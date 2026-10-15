import Foundation
import Crypto
import NIOCore
import NIOPosix
import NIOSSH
import Synchronization
import PatchNodeCore

public struct SSHEndpoint: Sendable, Hashable {
    public let host: String
    public let port: Int
    public let username: String

    public init(host: String, port: Int, username: String) {
        self.host = host
        self.port = port
        self.username = username
    }

    /// Host names and addresses only: no spaces, no scheme, no user part.
    public static func isValidHost(_ host: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:[]%_"))
        return !host.isEmpty && host.count <= 253 && host.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }
    }

    public static func isValidUsername(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-$"))
        return !name.isEmpty && name.count <= 64 && name.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }
    }
}

/// How the server's host key is checked.
public enum SSHHostKeyPolicy: Sendable, Hashable {
    /// Only this fingerprint is accepted.
    case pinned(String)
    /// First contact: nothing is accepted, the fingerprint is reported
    /// (`SSHFailure.hostKeyUnknown`) so the user can check it.
    case discover
}

public struct SSHCredentials: Sendable {
    public let key: Curve25519.Signing.PrivateKey?
    public let password: String?

    public init(key: Curve25519.Signing.PrivateKey?, password: String? = nil) {
        self.key = key
        self.password = password
    }
}

/// One authenticated SSH connection (SwiftNIO SSH): interactive shells with a
/// PTY, and commands without one. Keep-alive through TCP; the app closes it
/// in the background.
public final class SSHConnection: Sendable {
    public static let connectTimeout: TimeAmount = .seconds(10)
    public static let authenticationTimeout: Duration = .seconds(20)

    private let channel: any Channel

    private init(channel: any Channel) {
        self.channel = channel
    }

    public static func connect(
        to endpoint: SSHEndpoint, credentials: SSHCredentials, hostKey: SSHHostKeyPolicy
    ) async throws -> SSHConnection {
        guard SSHEndpoint.isValidHost(endpoint.host), (1...65535).contains(endpoint.port),
              SSHEndpoint.isValidUsername(endpoint.username)
        else { throw SSHFailure.unreachable }
        let check = HostKeyCheck(policy: hostKey)
        let auth = UserAuth(username: endpoint.username, credentials: credentials)
        let bootstrap = ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connectTimeout(connectTimeout)
            .channelOption(.socketOption(.so_keepalive), value: 1)
            .channelOption(.socketOption(.tcp_nodelay), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let promise = channel.eventLoop.makePromise(of: Void.self)
                    let sync = channel.pipeline.syncOperations
                    try sync.addHandler(NIOSSHHandler(
                        role: .client(.init(userAuthDelegate: auth, serverAuthDelegate: check)),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    ))
                    try sync.addHandler(AuthenticationWatcher(promise: promise))
                }
            }
        let channel: any Channel
        do {
            channel = try await bootstrap.connect(host: endpoint.host, port: endpoint.port).get()
        } catch {
            throw SSHFailure.unreachable
        }
        // The watcher of the channel `connect` returned (Happy Eyeballs may
        // have initialized and dropped others).
        let authenticated: EventLoopFuture<Void>
        do {
            authenticated = try await channel.eventLoop.submit {
                try channel.pipeline.syncOperations.handler(type: AuthenticationWatcher.self).future
            }.get()
        } catch {
            channel.close(promise: nil)
            throw SSHFailure.unreachable
        }
        // `get()` ignores task cancellation: the deadline and a cancellation
        // close the channel, which fails the watcher's promise.
        let timedOut = Flag()
        let deadline = channel.eventLoop.scheduleTask(in: .seconds(Int64(authenticationTimeout.components.seconds))) {
            timedOut.set()
            channel.close(promise: nil)
        }
        defer { deadline.cancel() }
        do {
            try await withTaskCancellationHandler {
                try await authenticated.get()
            } onCancel: {
                channel.close(promise: nil)
            }
            try Task.checkCancellation()
            return SSHConnection(channel: channel)
        } catch {
            channel.close(promise: nil)
            // The most precise reason: the host key first, then authentication.
            if let failure = check.failure { throw failure }
            if let failure = auth.failure { throw failure }
            if Task.isCancelled { throw CancellationError() }
            if timedOut.isSet { throw SSHFailure.timedOut }
            throw SSHFailure.closed
        }
    }

    public func close() {
        channel.close(promise: nil)
    }

    /// A session channel: a PTY then a shell, or a command (with a PTY when
    /// `pty` is given, for `pct enter` or `cd … && exec $SHELL`).
    public func openSession(pty: TerminalSize?, command: String?) async throws -> SSHSession {
        let (events, continuation) = AsyncThrowingStream.makeStream(of: SSHSession.Event.self)
        let promise = channel.eventLoop.makePromise(of: (any Channel).self)
        let parent = channel
        channel.eventLoop.execute {
            do {
                let ssh = try parent.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                ssh.createChannel(promise, channelType: .session) { child, type in
                    guard type == .session else { return child.eventLoop.makeFailedFuture(SSHFailure.channelRefused) }
                    return child.eventLoop.makeCompletedFuture {
                        try child.pipeline.syncOperations.addHandler(SessionHandler(continuation: continuation))
                    }
                }
            } catch {
                promise.fail(error)
            }
        }
        let child: any Channel
        do {
            child = try await withTaskCancellationHandler {
                try await promise.futureResult.get()
            } onCancel: {
                parent.close(promise: nil)
            }
        } catch {
            throw Task.isCancelled ? CancellationError() : SSHFailure.channelRefused
        }
        do {
            try Task.checkCancellation()
            if let pty {
                try await child.triggerUserOutboundEvent(SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: false, term: "xterm-256color",
                    terminalCharacterWidth: pty.columns, terminalRowHeight: pty.rows,
                    terminalPixelWidth: 0, terminalPixelHeight: 0, terminalModes: SSHTerminalModes([:])
                )).get()
            }
            if let command {
                try await child.triggerUserOutboundEvent(SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)).get()
            } else {
                try await child.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true)).get()
            }
        } catch {
            child.close(promise: nil)
            throw SSHFailure.channelRefused
        }
        return SSHSession(channel: child, events: events)
    }

    /// Runs a command without a PTY, sends `input` on its stdin then EOF, and
    /// streams its output; the last event is its exit status.
    public func run(_ command: String, input: Data? = nil) async throws -> SSHSession {
        let session = try await openSession(pty: nil, command: command)
        if let input { await session.write(Array(input)) }
        await session.endInput()
        return session
    }

}

/// A flag set from an event loop, read after.
final class Flag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
}

/// One channel of a connection.
public final class SSHSession: Sendable {
    public enum Event: Sendable, Equatable {
        case output([UInt8])
        case errorOutput([UInt8])
        case exit(Int)
    }

    public let events: AsyncThrowingStream<Event, any Error>
    private let channel: any Channel

    init(channel: any Channel, events: AsyncThrowingStream<Event, any Error>) {
        self.channel = channel
        self.events = events
    }

    public func write(_ bytes: [UInt8]) async {
        guard !bytes.isEmpty else { return }
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        try? await channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer))).get()
    }

    public func resize(_ size: TerminalSize) async {
        try? await channel.triggerUserOutboundEvent(SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: size.columns, terminalRowHeight: size.rows,
            terminalPixelWidth: 0, terminalPixelHeight: 0
        )).get()
    }

    /// EOF on stdin (the command's input is complete).
    public func endInput() async {
        try? await channel.close(mode: .output).get()
    }

    public func close() {
        channel.close(promise: nil)
    }
}

// MARK: - NIO handlers and delegates

/// Accepts only the pinned key; on first contact reports the presented one.
final class HostKeyCheck: NIOSSHClientServerAuthenticationDelegate, Sendable {
    private let policy: SSHHostKeyPolicy
    private let state = Mutex<SSHFailure?>(nil)

    init(policy: SSHHostKeyPolicy) {
        self.policy = policy
    }

    var failure: SSHFailure? { state.withLock { $0 } }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = SSHHostKeyFingerprint.of(hostKey)
        switch policy {
        case .pinned(let pinned) where pinned == presented:
            validationCompletePromise.succeed(())
        case .pinned:
            state.withLock { $0 = .hostKeyChanged(presented: presented) }
            validationCompletePromise.fail(SSHFailure.hostKeyChanged(presented: presented))
        case .discover:
            let failure = SSHFailure.hostKeyUnknown(fingerprint: presented, algorithm: SSHHostKeyFingerprint.algorithm(of: hostKey))
            state.withLock { $0 = failure }
            validationCompletePromise.fail(failure)
        }
    }
}

/// The device key first, then the password if one was given; never anything
/// else, never twice.
final class UserAuth: NIOSSHClientUserAuthenticationDelegate, Sendable {
    private struct State {
        var triedKey = false
        var triedPassword = false
        var passwordAllowed = false
        var exhausted = false
    }

    private let username: String
    private let key: NIOSSHPrivateKey?
    private let password: String?
    private let state = Mutex(State())

    init(username: String, credentials: SSHCredentials) {
        self.username = username
        key = credentials.key.map { NIOSSHPrivateKey(ed25519Key: $0) }
        password = credentials.password
    }

    var failure: SSHFailure? {
        state.withLock { $0.exhausted ? .authenticationFailed(passwordAllowed: $0.passwordAllowed) : nil }
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        let offer: NIOSSHUserAuthenticationOffer.Offer? = state.withLock { state in
            // The server's latest list (the first call offers every method,
            // before the server answered).
            state.passwordAllowed = availableMethods.contains(.password)
            if let key, !state.triedKey, availableMethods.contains(.publicKey) {
                state.triedKey = true
                return .privateKey(.init(privateKey: key))
            }
            if let password, !state.triedPassword, availableMethods.contains(.password) {
                state.triedPassword = true
                return .password(.init(password: password))
            }
            state.exhausted = true
            return nil
        }
        if let offer {
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: offer))
        } else {
            nextChallengePromise.fail(SSHFailure.authenticationFailed(passwordAllowed: availableMethods.contains(.password)))
        }
    }
}

/// Completes once the server accepted the user, fails if the connection
/// errors or closes first.
final class AuthenticationWatcher: ChannelInboundHandler {
    typealias InboundIn = Any

    private var promise: EventLoopPromise<Void>?
    /// Succeeds once the user is authenticated.
    let future: EventLoopFuture<Void>

    init(promise: EventLoopPromise<Void>) {
        self.promise = promise
        future = promise.futureResult
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            promise?.succeed(())
            promise = nil
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        promise?.fail(error)
        promise = nil
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        promise?.fail(SSHFailure.closed)
        promise = nil
        context.fireChannelInactive()
    }

    /// A connection that never got as far as authentication.
    func handlerRemoved(context: ChannelHandlerContext) {
        promise?.fail(SSHFailure.closed)
        promise = nil
    }
}

/// Bytes and the exit status of a session channel, to an async stream.
final class SessionHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let continuation: AsyncThrowingStream<SSHSession.Event, any Error>.Continuation

    init(continuation: AsyncThrowingStream<SSHSession.Event, any Error>.Continuation) {
        self.continuation = continuation
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = message.data else { return }
        let bytes = Array(buffer.readableBytesView)
        switch message.type {
        case .channel: continuation.yield(.output(bytes))
        case .stdErr: continuation.yield(.errorOutput(bytes))
        default: break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let status as SSHChannelRequestEvent.ExitStatus:
            continuation.yield(.exit(status.exitStatus))
        case is ChannelFailureEvent:
            continuation.finish(throwing: SSHFailure.channelRefused)
            context.close(promise: nil)
        case let event as ChannelEvent where event == .inputClosed:
            // The remote side is done writing; the channel closes after the
            // exit status.
            break
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        continuation.finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        continuation.finish(throwing: SSHFailure.closed)
        context.close(promise: nil)
    }
}

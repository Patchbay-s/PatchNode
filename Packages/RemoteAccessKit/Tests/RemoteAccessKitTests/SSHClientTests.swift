import Foundation
import Testing
import Crypto
import NIOCore
import NIOPosix
import NIOSSH
import PatchNodeCore
@testable import RemoteAccessKit

/// A real SSH server (SwiftNIO SSH) on 127.0.0.1, in the test process: the
/// client's handshake, host key checks, authentication and channels run end
/// to end. Exec answers "ran:<command>" with exit status 3, and whatever
/// arrives on stdin before EOF; a shell echoes.
final class TestSSHServer: Sendable {
    let hostKey = Curve25519.Signing.PrivateKey()
    let channel: any Channel
    var port: Int { channel.localAddress?.port ?? 0 }

    var fingerprint: String {
        SSHHostKeyFingerprint.of(NIOSSHPrivateKey(ed25519Key: hostKey).publicKey)
    }

    init(allowedKey: Curve25519.Signing.PublicKey?, password: String?) async throws {
        let hostKey = self.hostKey
        let auth = ServerAuth(allowedKey: allowedKey, password: password)
        channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { child in
                child.eventLoop.makeCompletedFuture {
                    try child.pipeline.syncOperations.addHandler(NIOSSHHandler(
                        role: .server(.init(hostKeys: [NIOSSHPrivateKey(ed25519Key: hostKey)], userAuthDelegate: auth, globalRequestDelegate: nil)),
                        allocator: child.allocator,
                        inboundChildChannelInitializer: { session, _ in
                            session.eventLoop.makeCompletedFuture {
                                try session.pipeline.syncOperations.addHandler(ServerSession())
                            }
                        }
                    ))
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
    }

    func stop() { channel.close(promise: nil) }

    var endpoint: SSHEndpoint { SSHEndpoint(host: "127.0.0.1", port: port, username: "patchnode") }
}

private final class ServerAuth: NIOSSHServerUserAuthenticationDelegate, Sendable {
    let allowedKey: NIOSSHPublicKey?
    let password: String?

    init(allowedKey: Curve25519.Signing.PublicKey?, password: String?) {
        self.allowedKey = allowedKey?.nioKey
        self.password = password
    }

    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods {
        password == nil ? [.publicKey] : [.publicKey, .password]
    }

    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        switch request.request {
        case .publicKey(let key):
            responsePromise.succeed(key.publicKey == allowedKey ? .success : .failure)
        case .password(let given):
            responsePromise.succeed(given.password == password ? .success : .failure)
        default:
            responsePromise.succeed(.failure)
        }
    }
}

extension Curve25519.Signing.PublicKey {
    var nioKey: NIOSSHPublicKey {
        // The public half of an ed25519 key in OpenSSH wire form.
        var blob = Data()
        func put(_ data: Data) {
            var length = UInt32(data.count).bigEndian
            blob.append(Data(bytes: &length, count: 4))
            blob.append(data)
        }
        put(Data("ssh-ed25519".utf8))
        put(rawRepresentation)
        return try! NIOSSHPublicKey(openSSHPublicKey: "ssh-ed25519 " + blob.base64EncodedString())
    }
}

private final class ServerSession: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    private var command: String?
    private var stdin: [UInt8] = []
    private var shell = false

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let exec as SSHChannelRequestEvent.ExecRequest:
            command = exec.command
            if exec.wantReply { context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil) }
        case let request as SSHChannelRequestEvent.ShellRequest:
            shell = true
            if request.wantReply { context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil) }
            send(context, Array("$ ".utf8))
        case let event as ChannelEvent where event == .inputClosed:
            guard let command else { return }
            send(context, Array("ran:\(command)\n".utf8) + stdin)
            context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: 3), promise: nil)
            context.close(promise: nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .byteBuffer(let buffer) = unwrapInboundIn(data).data else { return }
        let bytes = Array(buffer.readableBytesView)
        if shell { send(context, bytes) } else { stdin += bytes }
    }

    private func send(_ context: ChannelHandlerContext, _ bytes: [UInt8]) {
        var buffer = context.channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        context.writeAndFlush(NIOAny(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: nil)
    }
}

@Suite("SSH client against an in-process server", .serialized)
struct SSHClientTests {
    let clientKey = Curve25519.Signing.PrivateKey()

    @Test func firstContactReportsTheFingerprintWithoutAuthenticating() async throws {
        let server = try await TestSSHServer(allowedKey: clientKey.publicKey, password: nil)
        defer { server.stop() }
        let discovered = try await SSHAccess.discoverHostKey(of: server.endpoint)
        #expect(discovered.fingerprint == server.fingerprint)
        #expect(discovered.algorithm == "ssh-ed25519")
        #expect(discovered.fingerprint.hasPrefix("SHA256:"))
        #expect(!discovered.fingerprint.hasSuffix("="))
    }

    @Test func aChangedHostKeyIsRefused() async throws {
        let server = try await TestSSHServer(allowedKey: clientKey.publicKey, password: nil)
        defer { server.stop() }
        await #expect(throws: SSHFailure.hostKeyChanged(presented: server.fingerprint)) {
            _ = try await SSHConnection.connect(to: server.endpoint, credentials: SSHCredentials(key: clientKey), hostKey: .pinned("SHA256:someOtherKey"))
        }
    }

    @Test func noPinnedKeyMeansNoConnection() async throws {
        await #expect(throws: SSHFailure.self) {
            _ = try await SSHAccess.connect(endpoint: SSHEndpoint(host: "127.0.0.1", port: 22, username: "x"), pinnedHostKey: "", key: clientKey, askPassword: { nil })
        }
    }

    @Test func theDeviceKeyAuthenticatesAndACommandReturnsItsExitStatus() async throws {
        let server = try await TestSSHServer(allowedKey: clientKey.publicKey, password: nil)
        defer { server.stop() }
        let connection = try await SSHAccess.connect(endpoint: server.endpoint, pinnedHostKey: server.fingerprint, key: clientKey, askPassword: { nil })
        defer { connection.close() }
        let session = try await connection.run("echo 'hi'", input: Data("stdin-data".utf8))
        var output: [UInt8] = []
        var exit: Int?
        for try await event in session.events {
            switch event {
            case .output(let bytes): output += bytes
            case .errorOutput: break
            case .exit(let status): exit = status
            }
        }
        #expect(String(decoding: output, as: UTF8.self) == "ran:echo 'hi'\nstdin-data")
        #expect(exit == 3)
    }

    @Test func aRefusedKeyFallsBackToTheAskedPassword() async throws {
        let server = try await TestSSHServer(allowedKey: nil, password: "correct horse")
        defer { server.stop() }
        let asked = AskCounter()
        let connection = try await SSHAccess.connect(
            endpoint: server.endpoint, pinnedHostKey: server.fingerprint, key: clientKey,
            askPassword: { await asked.ask("correct horse") }
        )
        connection.close()
        #expect(await asked.count == 1)
    }

    @Test func aWrongPasswordFailsWithoutRetrying() async throws {
        let server = try await TestSSHServer(allowedKey: nil, password: "correct horse")
        defer { server.stop() }
        let asked = AskCounter()
        await #expect(throws: SSHFailure.authenticationFailed(passwordAllowed: true)) {
            _ = try await SSHAccess.connect(
                endpoint: server.endpoint, pinnedHostKey: server.fingerprint, key: clientKey,
                askPassword: { await asked.ask("wrong") }
            )
        }
        #expect(await asked.count == 1)
    }

    @Test func cancellingThePasswordPromptCancels() async throws {
        let server = try await TestSSHServer(allowedKey: nil, password: "pw")
        defer { server.stop() }
        await #expect(throws: SSHFailure.cancelled) {
            _ = try await SSHAccess.connect(endpoint: server.endpoint, pinnedHostKey: server.fingerprint, key: clientKey, askPassword: { nil })
        }
    }

    @Test func aKeyOnlyServerNeverAsksForAPassword() async throws {
        let server = try await TestSSHServer(allowedKey: Curve25519.Signing.PrivateKey().publicKey, password: nil)
        defer { server.stop() }
        let asked = AskCounter()
        await #expect(throws: SSHFailure.authenticationFailed(passwordAllowed: false)) {
            _ = try await SSHAccess.connect(endpoint: server.endpoint, pinnedHostKey: server.fingerprint, key: clientKey, askPassword: { await asked.ask("x") })
        }
        #expect(await asked.count == 0)
    }

    @Test func anInteractiveShellEchoesThroughTheTerminalChannel() async throws {
        let server = try await TestSSHServer(allowedKey: clientKey.publicKey, password: nil)
        defer { server.stop() }
        let connector = SSHTerminalConnector(
            endpoint: server.endpoint, pinnedHostKey: server.fingerprint,
            key: { [clientKey] in clientKey }, askPassword: { nil }
        )
        let channel = try await connector.open(size: TerminalSize(columns: 100, rows: 30))
        await channel.send(Array("hello".utf8))
        var text = ""
        for try await chunk in channel.output {
            text += String(decoding: chunk, as: UTF8.self)
            if text.contains("hello") { break }
        }
        #expect(text == "$ hello")
        await channel.close()
    }

    @Test func unreachableHostsAndInvalidInputsFailCleanly() async {
        await #expect(throws: SSHFailure.unreachable) {
            _ = try await SSHConnection.connect(to: SSHEndpoint(host: "127.0.0.1", port: 1, username: "x"), credentials: SSHCredentials(key: nil), hostKey: .discover)
        }
        await #expect(throws: SSHFailure.unreachable) {
            _ = try await SSHConnection.connect(to: SSHEndpoint(host: "host; rm -rf /", port: 22, username: "x"), credentials: SSHCredentials(key: nil), hostKey: .discover)
        }
        await #expect(throws: SSHFailure.unreachable) {
            _ = try await SSHConnection.connect(to: SSHEndpoint(host: "nas", port: 22, username: "-oProxyCommand=x"), credentials: SSHCredentials(key: nil), hostKey: .discover)
        }
    }
}

private actor AskCounter {
    private(set) var count = 0
    func ask(_ answer: String) -> String {
        count += 1
        return answer
    }
}

@Suite("Device key")
struct SSHDeviceKeyTests {
    @Test func createdOnceThenReloaded() async throws {
        let store = InMemorySecretStore()
        #expect(try await SSHDeviceKey.load(from: store) == nil)
        let created = try await SSHDeviceKey.loadOrCreate(in: store)
        let again = try await SSHDeviceKey.loadOrCreate(in: store)
        #expect(created.privateKey.rawRepresentation == again.privateKey.rawRepresentation)
        try await SSHDeviceKey.delete(from: store)
        #expect(try await SSHDeviceKey.load(from: store) == nil)
    }

    @Test func publicKeyLineIsOpenSSHAndCarriesNoSecret() async throws {
        let key = try await SSHDeviceKey.loadOrCreate(in: InMemorySecretStore())
        let line = key.openSSHPublicKey(comment: "PatchNode-iPhone 2026; rm")
        #expect(line.hasPrefix("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5"))
        #expect(line.hasSuffix(" PatchNode-iPhone2026rm"))
        #expect(!line.contains(key.privateKey.rawRepresentation.base64EncodedString()))
        #expect(key.fingerprint.hasPrefix("SHA256:"))
    }

    @Test func authorizedKeysLineOptions() throws {
        let key = "ssh-ed25519 AAAA PatchNode"
        #expect(try AuthorizedKeysLine.make(publicKey: key, from: nil, restricted: false) == key)
        #expect(try AuthorizedKeysLine.make(publicKey: key, from: "100.64.0.0/10,192.0.2.*", restricted: true)
                == "from=\"100.64.0.0/10,192.0.2.*\",restrict,pty ssh-ed25519 AAAA PatchNode")
        #expect(throws: AuthorizedKeysLine.Failure.invalidSource) {
            try AuthorizedKeysLine.make(publicKey: key, from: "192.0.2.5\",command=\"reboot", restricted: false)
        }
    }

    @Test func fingerprintMatchesOpenSSHFormat() {
        // ssh-keygen -lf of an all-zero ed25519 public key.
        var blob = Data()
        func put(_ data: Data) {
            var length = UInt32(data.count).bigEndian
            blob.append(Data(bytes: &length, count: 4))
            blob.append(data)
        }
        put(Data("ssh-ed25519".utf8))
        put(Data(repeating: 0, count: 32))
        let fingerprint = SSHHostKeyFingerprint.of(wireBlob: blob)
        let expected = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        #expect(fingerprint == "SHA256:" + expected)
        #expect(fingerprint.count == 7 + 43)
    }
}

/// Accepts TCP and never says a word (sshd overwhelmed, tarpit).
final class SilentServer: Sendable {
    let channel: any Channel
    init() async throws {
        channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { $0.eventLoop.makeSucceededVoidFuture() }
            .bind(host: "127.0.0.1", port: 0).get()
    }
    var endpoint: SSHEndpoint { SSHEndpoint(host: "127.0.0.1", port: channel.localAddress?.port ?? 0, username: "x") }
    func stop() { channel.close(promise: nil) }
}

@Suite("SSH against a silent server", .serialized)
struct SSHSilentServerTests {
    @Test func cancellingAStuckConnectionReturnsAtOnce() async throws {
        let server = try await SilentServer()
        defer { server.stop() }
        let task = Task {
            try await SSHConnection.connect(to: server.endpoint, credentials: SSHCredentials(key: nil), hostKey: .discover)
        }
        try await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}

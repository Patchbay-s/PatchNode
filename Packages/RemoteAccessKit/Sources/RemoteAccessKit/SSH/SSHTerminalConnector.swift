import Foundation
import Crypto
import PatchNodeCore

/// An SSH shell in the shared terminal. Every `open` connects again: the
/// device key first, then — if the host also accepts passwords and refused
/// the key — the password asked from the user (never stored).
public struct SSHTerminalConnector: TerminalConnector {
    public let kind: TerminalKind = .ssh
    private let endpoint: SSHEndpoint
    private let pinnedHostKey: String
    /// Run with a PTY instead of the login shell (`pct enter 101`, `cd … &&
    /// exec "$SHELL" -l`), built with `ShellQuoting`.
    private let command: String?
    private let key: @Sendable () async throws -> Curve25519.Signing.PrivateKey?
    private let askPassword: @Sendable () async -> String?

    public init(
        endpoint: SSHEndpoint, pinnedHostKey: String, command: String? = nil,
        key: @escaping @Sendable () async throws -> Curve25519.Signing.PrivateKey?,
        askPassword: @escaping @Sendable () async -> String?
    ) {
        self.endpoint = endpoint
        self.pinnedHostKey = pinnedHostKey
        self.command = command
        self.key = key
        self.askPassword = askPassword
    }

    public func open(size: TerminalSize) async throws -> any TerminalChannel {
        let connection = try await SSHAccess.connect(
            endpoint: endpoint, pinnedHostKey: pinnedHostKey, key: try await key(), askPassword: askPassword
        )
        do {
            let session = try await connection.openSession(pty: size, command: command)
            return SSHTerminalChannel(connection: connection, session: session)
        } catch {
            connection.close()
            throw error
        }
    }
}

/// Connecting with the key, then the password if needed. Shared by terminals
/// and compose commands.
public enum SSHAccess {
    public static func connect(
        endpoint: SSHEndpoint, pinnedHostKey: String,
        key: Curve25519.Signing.PrivateKey?, askPassword: @Sendable () async -> String?
    ) async throws -> SSHConnection {
        guard !pinnedHostKey.isEmpty else { throw SSHFailure.hostKeyUnknown(fingerprint: "", algorithm: "") }
        do {
            return try await SSHConnection.connect(
                to: endpoint, credentials: SSHCredentials(key: key), hostKey: .pinned(pinnedHostKey)
            )
        } catch SSHFailure.authenticationFailed(let passwordAllowed) where passwordAllowed {
            try Task.checkCancellation()
            guard let password = await askPassword() else { throw SSHFailure.cancelled }
            // Closed while the prompt was shown: never authenticate for nothing.
            try Task.checkCancellation()
            return try await SSHConnection.connect(
                to: endpoint, credentials: SSHCredentials(key: key, password: password), hostKey: .pinned(pinnedHostKey)
            )
        }
    }

    /// First contact: the presented host key, without authenticating.
    public static func discoverHostKey(of endpoint: SSHEndpoint) async throws -> (fingerprint: String, algorithm: String) {
        do {
            let connection = try await SSHConnection.connect(to: endpoint, credentials: SSHCredentials(key: nil), hostKey: .discover)
            connection.close()
            throw SSHFailure.closed
        } catch SSHFailure.hostKeyUnknown(let fingerprint, let algorithm) {
            return (fingerprint, algorithm)
        }
    }
}

final class SSHTerminalChannel: TerminalChannel {
    let output: AsyncThrowingStream<[UInt8], any Error>
    private let connection: SSHConnection
    private let session: SSHSession
    private let tasks = TaskBag()

    init(connection: SSHConnection, session: SSHSession) {
        self.connection = connection
        self.session = session
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [UInt8].self)
        output = stream
        let reader = Task {
            do {
                for try await event in session.events {
                    switch event {
                    case .output(let bytes), .errorOutput(let bytes): continuation.yield(bytes)
                    case .exit: break
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            connection.close()
        }
        tasks.add(reader)
        continuation.onTermination = { [tasks] _ in tasks.cancelAll() }
    }

    func send(_ bytes: [UInt8]) async {
        await session.write(bytes)
    }

    func resize(_ size: TerminalSize) async {
        await session.resize(size)
    }

    func close() async {
        tasks.cancelAll()
        session.close()
        connection.close()
    }
}

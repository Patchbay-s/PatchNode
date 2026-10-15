import Foundation
import PatchNodeCore

/// A compose project worked on over one SSH connection: read and save its
/// files (validated, backed up), run its actions with the output streamed.
/// Nothing here keeps or logs a file's content.
public final class ComposeRemote: Sendable {
    public static let maxFileBytes = 1_048_576
    static let maxOutputBytes = 2_097_152

    public enum SaveResult: Sendable, Equatable {
        case saved
        /// `docker compose config` refused it; the file was left unchanged.
        case invalid(output: String)
    }

    public enum Event: Sendable, Equatable {
        case output(String)
        case exit(Int)
    }

    public enum Failure: Error, Equatable {
        case tooLarge
        case notText
        case commandFailed(status: Int, output: String)
    }

    public let commands: ComposeCommands
    private let connection: SSHConnection

    public init(connection: SSHConnection, commands: ComposeCommands) {
        self.connection = connection
        self.commands = commands
    }

    public func close() { connection.close() }

    /// The file's text, nil if it doesn't exist (a project without `.env`).
    public func read(_ path: String) async throws -> String? {
        let (status, output) = try await execute(try commands.read(path), limit: Self.maxFileBytes + 1)
        if status == 3 { return nil }
        guard status == 0 else { throw Failure.commandFailed(status: status ?? -1, output: String(decoding: output.prefix(4096), as: UTF8.self)) }
        guard output.count <= Self.maxFileBytes else { throw Failure.tooLarge }
        guard let text = String(bytes: output, encoding: .utf8) else { throw Failure.notText }
        return text
    }

    /// A compose file: staged, validated with `docker compose config` in place
    /// of the current one, then written over it after a timestamped backup.
    /// A `.env`: backed up and written, then the project validated; if it
    /// fails, the previous `.env` is put back.
    /// `existed`: the file was there when read (a new `.env` refused by
    /// validation is removed rather than restored).
    public func save(_ path: String, content: String, existed: Bool = true, now: Date = .now) async throws -> SaveResult {
        guard content.utf8.count <= Self.maxFileBytes else { throw Failure.tooLarge }
        try await expectSuccess(try commands.stage(path), input: Data(content.utf8))
        let stamp = ComposeCommands.stamp(now)
        if commands.project.configFiles.contains(path) {
            let (status, output) = try await execute(try commands.validateStaged(path))
            guard status == 0 else {
                _ = try? await execute(try commands.discardStaged(path))
                return .invalid(output: Self.text(output))
            }
            try await expectSuccess(try commands.commit(path, stamp: stamp))
            return .saved
        }
        try await expectSuccess(try commands.commit(path, stamp: stamp))
        let (status, output) = try await execute(try commands.validate())
        guard status == 0 else {
            try await expectSuccess(existed ? try commands.restoreBackup(path, stamp: stamp) : try commands.removeEnvFile())
            return .invalid(output: Self.text(output))
        }
        return .saved
    }

    /// `docker compose config --quiet` on the project as it is.
    public func validate() async throws -> (valid: Bool, output: String) {
        let (status, output) = try await execute(try commands.validate())
        return (status == 0, Self.text(output))
    }

    /// The action's output as it comes (stdout and stderr), then its exit
    /// status. Run once: never retried.
    public func run(_ action: ComposeAction) async throws -> AsyncThrowingStream<Event, any Error> {
        let session = try await connection.run(try commands.run(action))
        return AsyncThrowingStream { continuation in
            let task = Task {
                var received = 0
                // Whole lines only: a chunk may end inside a UTF-8 character.
                var pending: [UInt8] = []
                do {
                    for try await event in session.events {
                        switch event {
                        case .output(let bytes), .errorOutput(let bytes):
                            received += bytes.count
                            guard received <= Self.maxOutputBytes else { continue }
                            pending += bytes
                            if let lastNewline = pending.lastIndex(of: 0x0A) {
                                continuation.yield(.output(String(decoding: pending[...lastNewline], as: UTF8.self)))
                                pending.removeSubrange(...lastNewline)
                            }
                        case .exit(let status):
                            if !pending.isEmpty {
                                continuation.yield(.output(String(decoding: pending, as: UTF8.self)))
                                pending = []
                            }
                            continuation.yield(.exit(status))
                        }
                    }
                    if !pending.isEmpty { continuation.yield(.output(String(decoding: pending, as: UTF8.self))) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                session.close()
            }
        }
    }

    // MARK: - Plumbing

    private func expectSuccess(_ command: String, input: Data? = nil) async throws {
        let (status, output) = try await execute(command, input: input)
        guard status == 0 else { throw Failure.commandFailed(status: status ?? -1, output: Self.text(output.prefix(4096))) }
    }

    /// Runs a command without PTY: exit status and stdout+stderr (capped).
    func execute(_ command: String, input: Data? = nil, limit: Int = maxOutputBytes) async throws -> (Int?, [UInt8]) {
        let session = try await connection.run(command, input: input)
        defer { session.close() }
        var output: [UInt8] = []
        var status: Int?
        for try await event in session.events {
            switch event {
            case .output(let bytes), .errorOutput(let bytes):
                if output.count < limit { output += bytes.prefix(limit - output.count) }
            case .exit(let code):
                status = code
            }
        }
        try Task.checkCancellation()
        return (status, output)
    }

    private static func text(_ bytes: some Collection<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}

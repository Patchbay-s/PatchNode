import Foundation
import DockerKit
import PatchNodeCore
import RemoteAccessKit

/// A file the editor can open: a compose file, the project's `.env` (SSH),
/// or the file of a Portainer stack.
struct ComposeFile: Sendable, Hashable, Identifiable {
    let path: String
    let isEnv: Bool
    let title: String

    var id: String { path }
}

/// Where a project's files and actions go: SSH (folder on the host),
/// Portainer's API (stacks it owns), or the demo.
protocol ComposeBackend: Sendable {
    var files: [ComposeFile] { get }
    /// "SSH · nas", "Portainer"; shown on the screen and in the action log.
    var channel: String { get }
    func read(_ file: ComposeFile) async throws -> String?
    func save(_ file: ComposeFile, content: String, existed: Bool) async throws -> ComposeRemote.SaveResult
    func run(_ action: ComposeAction) async throws -> AsyncThrowingStream<ComposeRemote.Event, any Error>
    func close()
}

struct SSHComposeBackend: ComposeBackend {
    let remote: ComposeRemote
    let hostName: String

    var channel: String { "SSH · \(hostName)" }

    var files: [ComposeFile] {
        let project = remote.commands.project
        var files = project.configFiles.map { ComposeFile(path: $0, isEnv: false, title: ($0 as NSString).lastPathComponent) }
        if let env = project.envFile { files.append(ComposeFile(path: env, isEnv: true, title: ".env")) }
        return files
    }

    func read(_ file: ComposeFile) async throws -> String? { try await remote.read(file.path) }

    func save(_ file: ComposeFile, content: String, existed: Bool) async throws -> ComposeRemote.SaveResult {
        try await remote.save(file.path, content: content, existed: existed)
    }

    func run(_ action: ComposeAction) async throws -> AsyncThrowingStream<ComposeRemote.Event, any Error> {
        try await remote.run(action)
    }

    func close() { remote.close() }
}

/// A stack Portainer deployed: its file through the API (Portainer validates
/// it when redeploying), its environment sent back unchanged. Git stacks are
/// read-only. No `docker compose` output: the API answers once done.
struct PortainerComposeBackend: ComposeBackend {
    static let filePath = "portainer://stack"
    let client: DockerClient
    let stack: PortainerStack

    var channel: String { "Portainer" }

    var files: [ComposeFile] {
        [ComposeFile(path: Self.filePath, isEnv: false, title: "docker-compose.yml")]
    }

    func details() async throws -> PortainerStackDetails {
        try await client.stackDetails(id: stack.id)
    }

    func read(_ file: ComposeFile) async throws -> String? {
        try await client.stackFile(id: stack.id)
    }

    func save(_ file: ComposeFile, content: String, existed: Bool) async throws -> ComposeRemote.SaveResult {
        let details = try await details()
        guard !details.isGitBased else { throw PortainerComposeFailure.gitStack }
        do {
            try await client.updateStack(details, content: content, pullImage: false)
            return .saved
        } catch ServiceProviderError.unexpectedStatus(let status) where status == 400 || status == 500 {
            // Portainer refused the file (invalid compose) without changing it.
            return .invalid(output: "Portainer: HTTP \(status)")
        }
    }

    func run(_ action: ComposeAction) async throws -> AsyncThrowingStream<ComposeRemote.Event, any Error> {
        let details = try await details()
        let client = self.client
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch action {
                    case .up, .update:
                        guard !details.isGitBased else { throw PortainerComposeFailure.gitStack }
                        let content = try await client.stackFile(id: details.id)
                        continuation.yield(.output(action == .update ? "Portainer: pull and redeploy…\n" : "Portainer: redeploy…\n"))
                        try await client.updateStack(details, content: content, pullImage: action == .update)
                    case .stop:
                        continuation.yield(.output("Portainer: stop…\n"))
                        try await client.setStack(details, running: false)
                    case .restart:
                        continuation.yield(.output("Portainer: stop…\n"))
                        try await client.setStack(details, running: false)
                        continuation.yield(.output("Portainer: start…\n"))
                        try await client.setStack(details, running: true)
                    }
                    continuation.yield(.output("Portainer: done.\n"))
                    continuation.yield(.exit(0))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func close() {}
}

enum PortainerComposeFailure: Error { case gitStack }

/// The demo: a sample file, simulated validation and output.
struct DemoComposeBackend: ComposeBackend {
    let project: ComposeProject

    var channel: String { "SSH · demo" }

    var files: [ComposeFile] {
        let folder = project.workingDirectory ?? "/opt/stacks/\(project.name)"
        return [
            ComposeFile(path: folder + "/compose.yaml", isEnv: false, title: "compose.yaml"),
            ComposeFile(path: folder + "/.env", isEnv: true, title: ".env"),
        ]
    }

    func read(_ file: ComposeFile) async throws -> String? {
        if file.isEnv { return "TZ=Europe/Paris\nDB_PASSWORD=demo-not-a-secret\n" }
        let services = project.services.isEmpty ? ["app"] : project.services
        return "services:\n" + services.map { "  \($0):\n    image: example/\($0):latest\n    restart: unless-stopped\n" }.joined()
    }

    func save(_ file: ComposeFile, content: String, existed: Bool) async throws -> ComposeRemote.SaveResult {
        try await Task.sleep(for: .milliseconds(400))
        return content.contains("invalid") ? .invalid(output: "yaml: line 2: mapping values are not allowed in this context (simulated)") : .saved
    }

    func run(_ action: ComposeAction) async throws -> AsyncThrowingStream<ComposeRemote.Event, any Error> {
        let services = project.services.isEmpty ? ["app"] : project.services
        return AsyncThrowingStream { continuation in
            let task = Task {
                if action == .update {
                    for service in services {
                        try? await Task.sleep(for: .milliseconds(350))
                        continuation.yield(.output(" \(service) Pulled (simulated)\n"))
                    }
                }
                for service in services {
                    try? await Task.sleep(for: .milliseconds(350))
                    let verb = switch action { case .stop: "Stopped"; case .restart: "Restarted"; case .up, .update: "Started" }
                    continuation.yield(.output(" Container \(project.name)-\(service)-1  \(verb) (simulated)\n"))
                }
                continuation.yield(.exit(0))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func close() {}
}

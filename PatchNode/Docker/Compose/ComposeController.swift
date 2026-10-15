import SwiftUI
import DockerKit
import PatchNodeCore
import RemoteAccessKit

/// One compose project on screen: connects its backend once (SSH key or
/// password, Portainer or demo), then validates and runs actions after a
/// confirmation and Face ID, one at a time, never retried.
@Observable
@MainActor
final class ComposeController {
    enum Source: Equatable {
        case ssh(SSHHostSnapshot)
        case portainer(PortainerStack, serviceID: UUID)
        case demo
        /// Neither an SSH host linked to this Docker host nor a Portainer stack.
        case unavailable
    }

    struct Run: Identifiable {
        /// Lines kept on screen (the oldest go beyond this).
        static let maxLines = 2000

        let id = UUID()
        let action: ComposeAction
        /// Complete lines, then the line being written.
        var lines: [String] = []
        var exitStatus: Int?

        init(action: ComposeAction, output: String = "", failure: String? = nil) {
            self.action = action
            self.failure = failure
            append(output)
        }

        mutating func append(_ text: String) {
            guard !text.isEmpty else { return }
            var parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if let last = lines.popLast() { parts[0] = last + parts[0] }
            lines += parts
            if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        }
        var failure: String?
        var isRunning: Bool { exitStatus == nil && failure == nil }
    }

    let project: ComposeProject
    let hostName: String
    let source: Source
    private(set) var backend: (any ComposeBackend)?
    private(set) var isConnecting = false
    var errorMessage: String?
    var run: Run?

    @ObservationIgnored private let lock: AppLockController
    @ObservationIgnored private let log: ActionLog
    @ObservationIgnored private let ssh: SSHLauncher
    @ObservationIgnored private let docker: DockerStore
    @ObservationIgnored private let claimKey: String

    init(project: ComposeProject, hostItemID: String, hostName: String, source: Source,
         lock: AppLockController, log: ActionLog, ssh: SSHLauncher, docker: DockerStore) {
        self.project = project
        self.hostName = hostName
        self.source = source
        self.lock = lock
        self.log = log
        self.ssh = ssh
        self.docker = docker
        claimKey = "compose|\(hostItemID)|\(project.name)"
    }

    /// The project screen went away: its connection closes with it.
    isolated deinit {
        backend?.close()
    }

    var isBusy: Bool { log.inFlightTargets.contains(claimKey) }

    /// Connects once (SSH: the pinned host key only; a password asked if the
    /// key is refused). Nil with `errorMessage` set if it can't.
    func connect() async -> (any ComposeBackend)? {
        if let backend { return backend }
        guard !isConnecting else { return nil }
        isConnecting = true
        defer { isConnecting = false }
        do {
            switch source {
            case .demo:
                backend = DemoComposeBackend(project: project)
            case .portainer(let stack, let serviceID):
                guard let client = await docker.client(for: serviceID) else {
                    errorMessage = String(localized: "Portainer is paused or its token is missing. Pull to refresh the Docker screen, then try again.")
                    return nil
                }
                backend = PortainerComposeBackend(client: client, stack: stack)
            case .ssh(let host):
                guard SSHPinConfirmations.isConfirmed(host) else {
                    errorMessage = String(localized: "The host key of \(host.name) hasn't been checked yet. Open a terminal here once (or connect from Settings › SSH) to check it.")
                    return nil
                }
                // The device key opens a shell on the host: Face ID first (within
                // the 5-minute window an action just opened, no second prompt).
                guard await lock.authenticateForAction(reason: String(localized: "Open the project \(project.name) on \(host.name)")) else { return nil }
                let connection = try await SSHAccess.connect(
                    endpoint: host.endpoint, pinnedHostKey: host.pinnedHostKey,
                    key: try await SSHDeviceKey.loadOrCreate(in: SSHDeviceKey.keychain()).privateKey,
                    askPassword: { [ssh] in await ssh.askPassword(hostName: host.address, username: host.username) }
                )
                backend = SSHComposeBackend(remote: ComposeRemote(connection: connection, commands: try ComposeCommands(project: project)), hostName: host.name)
            case .unavailable:
                return nil
            }
        } catch {
            errorMessage = TerminalFailureText.message(for: error)
        }
        return backend
    }

    /// `.env` values are secrets: Face ID every time before showing them.
    func authorizeReveal(_ file: ComposeFile) async -> Bool {
        await lock.authenticateForAction(reason: String(localized: "Show the values of \(file.title)"), alwaysAsk: true)
    }

    func disconnect() {
        backend?.close()
        backend = nil
    }

    // MARK: - Actions

    /// After the confirmation: Face ID, validation (SSH), then the action with
    /// its output streamed into `run`.
    func perform(_ action: ComposeAction) async {
        guard log.claim(claimKey) else { return }
        defer { log.release(claimKey) }
        guard await lock.authenticateForAction(reason: Self.reason(action, project: project.name), alwaysAsk: true) else { return }
        guard let backend = await connect() else { return }
        let entry = log.begin(service: hostName, target: project.name, action: Self.logTitle(action))
        if let ssh = backend as? SSHComposeBackend {
            do {
                let (valid, output) = try await ssh.remote.validate()
                guard valid else {
                    run = Run(action: action, output: output, failure: String(localized: "docker compose config refused the project: nothing was run."))
                    log.finish(entry, .failed(String(localized: "Invalid configuration")))
                    return
                }
            } catch {
                errorMessage = TerminalFailureText.message(for: error)
                log.finish(entry, .failed(String(localized: "Connection lost.")))
                disconnect()
                return
            }
        }
        run = Run(action: action)
        do {
            // Published about ten times a second, not for every chunk.
            var buffer = ""
            var lastFlush = ContinuousClock.now
            for try await event in try await backend.run(action) {
                switch event {
                case .output(let text):
                    buffer += text
                    if ContinuousClock.now - lastFlush > .milliseconds(100) {
                        run?.append(buffer)
                        buffer = ""
                        lastFlush = .now
                    }
                case .exit(let status):
                    run?.append(buffer)
                    buffer = ""
                    run?.exitStatus = status
                }
            }
            run?.append(buffer)
            if run?.exitStatus == nil { run?.exitStatus = -1 }
            let status = run?.exitStatus ?? -1
            log.finish(entry, status == 0 ? .succeeded(String(localized: "Done")) : .failed("exit \(status)"))
            await docker.refresh(force: true)
        } catch {
            let message = Self.message(for: error)
            run?.failure = message
            log.finish(entry, .failed(Self.logMessage(for: error)))
            if backend is SSHComposeBackend { disconnect() }
        }
    }

    /// Save after the diff preview: Face ID, then validated save.
    func save(_ file: ComposeFile, content: String, existed: Bool) async -> ComposeRemote.SaveResult? {
        guard log.claim(claimKey) else { return nil }
        defer { log.release(claimKey) }
        guard await lock.authenticateForAction(reason: String(localized: "Save \(file.title) of \(project.name)"), alwaysAsk: true) else { return nil }
        guard let backend = await connect() else { return nil }
        let entry = log.begin(service: hostName, target: project.name, action: String(localized: "Save \(file.title)"))
        do {
            let result = try await backend.save(file, content: content, existed: existed)
            switch result {
            case .saved: log.finish(entry, .succeeded(String(localized: "Saved, previous version backed up")))
            case .invalid: log.finish(entry, .failed(String(localized: "Invalid configuration")))
            }
            return result
        } catch {
            errorMessage = Self.message(for: error)
            log.finish(entry, .failed(Self.logMessage(for: error)))
            if backend is SSHComposeBackend { disconnect() }
            return nil
        }
    }

    /// For the action log, which never holds remote output (a compose error
    /// can quote a value).
    static func logMessage(for error: any Error) -> String {
        if case ComposeRemote.Failure.commandFailed(let status, _) = error { return "exit \(status)" }
        return message(for: error)
    }

    static func message(for error: any Error) -> String {
        switch error {
        case PortainerComposeFailure.gitStack:
            String(localized: "This stack is deployed from Git: change it in its repository, or redeploy it from Portainer.")
        case ComposeRemote.Failure.tooLarge:
            String(localized: "The file is larger than 1 MB.")
        case ComposeRemote.Failure.notText:
            String(localized: "The file isn't UTF-8 text.")
        case ComposeRemote.Failure.commandFailed(let status, let output):
            String(localized: "The command failed (exit \(status)): \(output)")
        case ServiceProviderError.forbidden:
            String(localized: "Portainer refused the action (403): the token's user can't manage this stack.")
        default:
            TerminalFailureText.message(for: error)
        }
    }

    static func title(_ action: ComposeAction) -> String {
        switch action {
        case .up: String(localized: "Start (up -d)")
        case .stop: String(localized: "Stop")
        case .restart: String(localized: "Restart")
        case .update: String(localized: "Update (pull + up -d)")
        }
    }

    static func logTitle(_ action: ComposeAction) -> String {
        switch action {
        case .up: "compose up -d"
        case .stop: "compose stop"
        case .restart: "compose restart"
        case .update: "compose pull + up -d"
        }
    }

    static func reason(_ action: ComposeAction, project: String) -> String {
        String(localized: "\(title(action)): \(project)")
    }
}

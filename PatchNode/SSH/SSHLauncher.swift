import SwiftUI
import SwiftData
import PatchNodeCore
import RemoteAccessKit
import TerminalKit

/// SSH is off until the user turns it on (Settings › SSH).
enum SSHSettings {
    static let enabledKey = "ssh.enabled"
}

/// Host keys checked on this device. A pin can arrive through iCloud sync
/// (with the address): it is trusted only once confirmed here, for that
/// address — like a token bound to its server. Local, not synced.
enum SSHPinConfirmations {
    static let key = "ssh.confirmedHostKeys"

    static func entry(hostname: String, port: Int, fingerprint: String) -> String {
        "\(hostname.lowercased()):\(port)|\(fingerprint)"
    }

    static func isConfirmed(_ host: SSHHostSnapshot, defaults: UserDefaults = .standard) -> Bool {
        !host.pinnedHostKey.isEmpty
            && (defaults.dictionary(forKey: key)?[host.id.uuidString] as? String)
                == entry(hostname: host.hostname, port: host.port, fingerprint: host.pinnedHostKey)
    }

    static func confirm(id: UUID, hostname: String, port: Int, fingerprint: String, defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        all[id.uuidString] = entry(hostname: hostname, port: port, fingerprint: fingerprint)
        defaults.set(all, forKey: key)
    }
}

/// What a session needs from an `SSHHost` (the SwiftData model stays on the
/// main actor).
struct SSHHostSnapshot: Sendable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let hostname: String
    let port: Int
    let username: String
    let pinnedHostKey: String

    init(_ host: SSHHost) {
        id = host.id
        name = host.name.isEmpty ? host.hostname : host.name
        hostname = host.hostname
        port = host.port
        username = host.username
        pinnedHostKey = host.pinnedHostKey
    }

    var endpoint: SSHEndpoint { SSHEndpoint(host: hostname, port: port, username: username) }

    /// The real address, shown wherever a password is asked.
    var address: String { port == 22 ? hostname : "\(hostname):\(port)" }
}

/// Opens SSH sessions: Face ID every time; on first contact the host key is
/// shown to be checked and pinned; a password is asked only if the host
/// refuses the device key, and never stored.
@Observable
@MainActor
final class SSHLauncher {
    struct HostKeyConfirmation: Identifiable {
        let id = UUID()
        let host: SSHHostSnapshot
        let fingerprint: String
        let algorithm: String
        let command: String?
        let title: String
        /// A pin was there (synced from another device) but never confirmed here.
        let fromSync: Bool
    }

    struct PasswordRequest: Identifiable {
        let id = UUID()
        let hostName: String
        let username: String
    }

    private(set) var launching: Set<UUID> = []
    var hostKeyConfirmation: HostKeyConfirmation?
    var errorMessage: String?
    private(set) var passwordRequest: PasswordRequest?

    @ObservationIgnored private let terminals: TerminalSessionStore
    @ObservationIgnored private let lock: AppLockController
    @ObservationIgnored private var passwordContinuation: CheckedContinuation<String?, Never>?

    init(terminals: TerminalSessionStore, lock: AppLockController) {
        self.terminals = terminals
        self.lock = lock
    }

    /// `command` runs with a PTY instead of the login shell (built with
    /// `ShellQuoting`).
    func connect(_ host: SSHHostSnapshot, command: String? = nil, title: String? = nil) async {
        guard !launching.contains(host.id) else { return }
        guard terminals.canOpenMore else {
            errorMessage = String(localized: "Close a session first: up to \(TerminalSessionStore.maxSessions) can be open.")
            return
        }
        launching.insert(host.id)
        defer { launching.remove(host.id) }
        guard await lock.authenticateForAction(reason: String(localized: "Open an SSH session on \(host.name)"), alwaysAsk: true) else { return }
        let title = title ?? host.name
        if DemoMode.isOn {
            openDemo(title: title, hostname: host.hostname)
            return
        }
        guard SSHPinConfirmations.isConfirmed(host) else {
            do {
                let found = try await SSHAccess.discoverHostKey(of: host.endpoint)
                hostKeyConfirmation = HostKeyConfirmation(
                    host: host, fingerprint: found.fingerprint, algorithm: found.algorithm, command: command, title: title,
                    fromSync: !host.pinnedHostKey.isEmpty
                )
            } catch {
                errorMessage = TerminalFailureText.message(for: error)
            }
            return
        }
        openSession(host, pinnedHostKey: host.pinnedHostKey, command: command, title: title)
    }

    /// The user checked the fingerprint (the view pinned it in the store).
    func hostKeyAccepted(_ confirmation: HostKeyConfirmation) {
        hostKeyConfirmation = nil
        openSession(confirmation.host, pinnedHostKey: confirmation.fingerprint, command: confirmation.command, title: confirmation.title)
    }

    /// A shell in the demo: simulated, nothing is contacted.
    func openDemo(title: String, hostname: String) {
        terminals.open(
            title: title, subtitle: "SSH · \(hostname)",
            connector: DemoTerminalConnector(
                hostname: hostname.split(separator: ".").first.map(String.init) ?? "demo",
                banner: String(localized: "Demo SSH session: simulated, no server is contacted.")
            ),
            logLabel: nil
        )
    }

    private func openSession(_ host: SSHHostSnapshot, pinnedHostKey: String, command: String?, title: String) {
        let connector = SSHTerminalConnector(
            endpoint: host.endpoint, pinnedHostKey: pinnedHostKey, command: command,
            key: { try await SSHDeviceKey.loadOrCreate(in: SSHDeviceKey.keychain()).privateKey },
            askPassword: { [weak self] in await self?.askPassword(hostName: host.address, username: host.username) }
        )
        terminals.open(
            title: title, subtitle: "SSH · \(host.name)", connector: connector,
            logLabel: RequestLog.Label(serviceID: host.id, serviceName: host.name)
        )
    }

    // MARK: - Password

    /// Shown over whatever is on screen; nil if dismissed, or if the session
    /// asking is closed meanwhile (the alert goes away). Never stored.
    func askPassword(hostName: String, username: String) async -> String? {
        guard passwordContinuation == nil, !Task.isCancelled else { return nil }
        let request = PasswordRequest(hostName: hostName, username: username)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                passwordContinuation = continuation
                passwordRequest = request
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelPassword(request.id) }
        }
    }

    private func cancelPassword(_ id: UUID) {
        guard passwordRequest?.id == id else { return }
        answerPassword(nil)
    }

    func answerPassword(_ password: String?) {
        passwordRequest = nil
        let continuation = passwordContinuation
        passwordContinuation = nil
        continuation?.resume(returning: password.flatMap { $0.isEmpty ? nil : $0 })
    }
}

/// The password alert, over the workspace when it is shown, else over the
/// app (a fullScreenCover hides the alerts of the views below it).
struct SSHPasswordPrompt: ViewModifier {
    @Environment(SSHLauncher.self) private var launcher
    let isActive: Bool
    @State private var password = ""

    func body(content: Content) -> some View {
        content.alert(
            Text("Password for \(launcher.passwordRequest?.username ?? "")@\(launcher.passwordRequest?.hostName ?? "")"),
            isPresented: Binding(
                get: { isActive && launcher.passwordRequest != nil },
                set: { if !$0, launcher.passwordRequest != nil { launcher.answerPassword(nil) } }
            )
        ) {
            SecureField("Password", text: $password)
                .textContentType(.password)
            Button("Connect") {
                let typed = password
                password = ""
                launcher.answerPassword(typed)
            }
            Button("Cancel", role: .cancel) {
                password = ""
                launcher.answerPassword(nil)
            }
        } message: {
            Text("The server refused this device's key. The password is used for this connection only and never stored.")
        }
    }
}

/// First contact: the fingerprint to compare with the server's own
/// (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`), then pinned.
struct SSHHostKeySheet: View {
    let confirmation: SSHLauncher.HostKeyConfirmation
    @Environment(SSHLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if confirmation.fromSync {
                        Text("This host was set up on another device. Check its fingerprint on this one before trusting it.")
                    }
                    Text("First connection to \(confirmation.host.name). Check that this fingerprint is the server's before trusting it: PatchNode will then refuse any other key for this host.")
                }
                Section {
                    LabeledContent("Type") { Text(verbatim: confirmation.algorithm).font(.footnote.monospaced()) }
                    Text(verbatim: confirmation.fingerprint)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Fingerprint")
                } footer: {
                    Text("On the server: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
                        .font(.footnote.monospaced())
                }
                Section {
                    Button("Trust and connect", systemImage: "checkmark.shield") { trust() }
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .navigationTitle(Text(verbatim: "\(confirmation.host.username)@\(confirmation.host.hostname)"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .privacyCover()
    }

    private func trust() {
        let id = confirmation.host.id
        let hosts = (try? modelContext.fetch(FetchDescriptor<SSHHost>(predicate: #Predicate { $0.id == id }))) ?? []
        // Every copy (an iCloud sync can store one twice).
        hosts.forEach { $0.pinnedHostKey = confirmation.fingerprint }
        try? modelContext.save()
        SSHPinConfirmations.confirm(
            id: id, hostname: confirmation.host.hostname, port: confirmation.host.port, fingerprint: confirmation.fingerprint
        )
        dismiss()
        launcher.hostKeyAccepted(confirmation)
    }
}

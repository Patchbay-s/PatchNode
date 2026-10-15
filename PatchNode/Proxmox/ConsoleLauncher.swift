import SwiftUI
import PatchNodeCore
import ProxmoxKit
import RemoteAccessKit
import TerminalKit

/// Opens Proxmox consoles: Face ID every time, the privilege checked first
/// (`/access/permissions`, so a missing role shows the commands to grant it
/// instead of a refused request), then a terminal (node, CT, VM with a serial
/// port) or the graphical console (VM without one).
@Observable
@MainActor
final class ConsoleLauncher {
    /// Shown when the token lacks the console privilege.
    struct AccessHelp: Identifiable {
        let id = UUID()
        let targetName: String
        let privilege: String
        let commands: [String]
    }

    private(set) var launching: Set<ProxmoxConsoleTarget> = []
    var accessHelp: AccessHelp?
    var errorMessage: String?

    @ObservationIgnored private let proxmox: ProxmoxStore
    @ObservationIgnored private let terminals: TerminalSessionStore
    @ObservationIgnored private let lock: AppLockController

    init(proxmox: ProxmoxStore, terminals: TerminalSessionStore, lock: AppLockController) {
        self.proxmox = proxmox
        self.terminals = terminals
        self.lock = lock
    }

    func open(_ target: ProxmoxConsoleTarget, name: String, serviceID: UUID, serviceName: String) async {
        guard !launching.contains(target) else { return }
        guard terminals.canOpenMore else {
            errorMessage = String(localized: "Close a session first: up to \(TerminalSessionStore.maxSessions) can be open.")
            return
        }
        launching.insert(target)
        defer { launching.remove(target) }
        guard await lock.authenticateForAction(reason: String(localized: "Open the console of \(name)"), alwaysAsk: true) else { return }
        let label = RequestLog.Label(serviceID: serviceID, serviceName: serviceName)
        let subtitle = "Proxmox · \(serviceName)"

        if DemoMode.isOn {
            openDemo(target, name: name, subtitle: subtitle, label: label)
            return
        }
        guard let client = await proxmox.client(for: serviceID) else {
            errorMessage = String(localized: "\(serviceName) is paused or its token is missing. Pull to refresh the Proxmox screen, then try again.")
            return
        }
        do {
            let privileges = try await client.privileges(on: target.permissionPath)
            guard privileges.contains(target.requiredPrivilege) else {
                // The ACL on the target replaces what the token inherits there:
                // keep its power actions if it has them now.
                let commands = client.consoleAccessCommands(for: target, keepingPower: privileges.contains("VM.PowerMgmt"))
                accessHelp = AccessHelp(targetName: name, privilege: target.requiredPrivilege, commands: commands)
                return
            }
            switch try await client.consoleKind(for: target) {
            case .terminal(let serial):
                terminals.open(
                    title: name, subtitle: subtitle,
                    connector: ProxmoxTerminalConnector(client: client, target: target, serial: serial),
                    logLabel: label
                )
            case .graphical:
                terminals.openGraphical(
                    title: name, subtitle: subtitle,
                    link: { try await ProxmoxVNCConnection.open(client: client, target: target) },
                    logLabel: label
                )
            }
        } catch {
            errorMessage = TerminalFailureText.message(for: ConsoleFailureMapping.map(error))
        }
    }

    /// Simulated: a shell for nodes and containers, a login screen for VMs.
    private func openDemo(_ target: ProxmoxConsoleTarget, name: String, subtitle: String, label: RequestLog.Label) {
        switch target {
        case .guest(_, .qemu, _):
            terminals.openGraphical(title: name, subtitle: subtitle, link: nil, logLabel: label)
        case .guest, .node:
            terminals.open(
                title: name, subtitle: subtitle,
                connector: DemoTerminalConnector(
                    hostname: name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.first ?? "demo",
                    banner: String(localized: "Demo console: simulated, no server is contacted.")
                ),
                logLabel: label
            )
        }
    }
}

/// HTTP errors of the checks before a console, as console failures.
enum ConsoleFailureMapping {
    static func map(_ error: any Error) -> any Error {
        switch error {
        case ServiceProviderError.forbidden: ConsoleFailure.missingPrivilege
        case ServiceProviderError.unauthorized: ConsoleFailure.tokenRefused
        case ServiceProviderError.unreachable, is TimeoutError: ConsoleFailure.unreachable
        case ServiceProviderError.unexpectedStatus(let status): ConsoleFailure.server(status)
        default: error
        }
    }
}

/// The commands that grant the console, to copy (they name the token's
/// identity, never its secret).
struct ConsoleAccessSheet: View {
    let help: ConsoleLauncher.AccessHelp
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The Proxmox token can't open the console of \(help.targetName): it lacks the \(help.privilege) privilege. Run these commands in the shell of a node, then try again.")
                }
                Section {
                    Text(verbatim: help.commands.joined(separator: "\n"))
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy the commands", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.setItems(
                            [[UIPasteboard.typeAutomatic: help.commands.joined(separator: "\n")]],
                            options: [.localOnly: true]
                        )
                        copied = true
                    }
                } footer: {
                    Text("A guest's console needs VM.Console (PatchNodeConsole role), a node's shell Sys.Console (PatchNodeNodeConsole role), granted on this target only. Below /, Proxmox replaces the inherited roles with those of the path: PVEAuditor (and PatchNodePower if the token has it) is granted again here, otherwise PatchNode could no longer read this target. The last command shows the token's rights on the path. Consoles with an API token need Proxmox VE 9.1 or later. These lines assume a user dedicated to PatchNode: on your own account, they would replace its other roles on this path.")
                }
            }
            .navigationTitle("Console access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .privacyCover()
    }
}

/// "Console" in a guest's or node's screen.
struct ConsoleButton: View {
    let target: ProxmoxConsoleTarget
    let name: String
    let serviceID: UUID
    let serviceName: String
    var isAvailable = true
    @Environment(ConsoleLauncher.self) private var launcher

    var body: some View {
        Button {
            Task { await launcher.open(target, name: name, serviceID: serviceID, serviceName: serviceName) }
        } label: {
            HStack {
                Label("Console", systemImage: "terminal")
                Spacer()
                if launcher.launching.contains(target) { ProgressView() }
            }
        }
        .disabled(!isAvailable || launcher.launching.contains(target))
    }
}

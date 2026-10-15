import SwiftUI
import SwiftData
import DockerKit
import PatchNodeCore
import RemoteAccessKit

/// Route to a compose project of a Docker host.
struct ComposeRoute: Hashable {
    let hostItemID: String
    let project: String
}

/// A compose project: where it lives, its files, a terminal in its folder,
/// and its actions (validated first, confirmed, Face ID, live output).
struct ComposeProjectView: View {
    let route: ComposeRoute
    @Environment(DockerStore.self) private var store
    @Environment(AppLockController.self) private var lock
    @Environment(ActionLog.self) private var actionLog
    @Environment(SSHLauncher.self) private var ssh
    @Query private var sshHosts: [SSHHost]
    @AppStorage(SSHSettings.enabledKey) private var sshEnabled = false
    @AppStorage(DemoMode.key) private var demoMode = false
    @State private var controller: ComposeController?
    /// What the controller was built for: pushing the editor and coming back
    /// keeps it (and its SSH connection).
    @State private var controllerKey: String?
    @State private var pendingAction: ComposeAction?

    private var hostItem: DockerInventory.HostItem? {
        store.inventory.hosts.first { $0.id == route.hostItemID }
    }

    private var project: ComposeProject? {
        let containers = store.inventory.containers.filter { "\($0.serviceID.uuidString)|\($0.host.id)" == route.hostItemID }.map(\.container)
        return ComposeDiscovery.projects(in: containers).first { $0.name == route.project }
    }

    var body: some View {
        Group {
            if let project, let hostItem, let controller {
                content(project: project, host: hostItem, controller: controller)
            } else if project == nil || hostItem == nil {
                ContentUnavailableView("Project not found", systemImage: "square.stack.3d.up.slash")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(verbatim: route.project))
        .task(id: sourceKey) {
            guard controllerKey != sourceKey else { return }
            controllerKey = sourceKey
            makeController()
        }
    }

    /// Rebuilds the controller when what it depends on changes.
    private var sourceKey: String {
        "\(route.hostItemID)|\(route.project)|\(sshHostForDocker?.id.uuidString ?? "")|\(sshHostForDocker?.pinnedHostKey ?? "")|\(demoMode)|\(sshEnabled)"
    }

    private var sshHostForDocker: SSHHost? {
        guard let hostItem else { return nil }
        return SSHHostLookup.host(in: sshHosts, link: .dockerHost, serviceID: hostItem.serviceID, target: hostItem.host.id)
    }

    private func makeController() {
        guard let project, let hostItem else { return }
        controller?.disconnect()
        let source: ComposeController.Source
        if demoMode {
            source = .demo
        } else if let stack = store.inventory.portainerStack(named: project.name, on: hostItem) {
            source = .portainer(stack, serviceID: hostItem.serviceID)
        } else if sshEnabled, let host = sshHostForDocker, project.isManageable {
            source = .ssh(SSHHostSnapshot(host))
        } else {
            source = .unavailable
        }
        controller = ComposeController(
            project: project, hostItemID: route.hostItemID, hostName: hostItem.host.name, source: source,
            lock: lock, log: actionLog, ssh: ssh, docker: store
        )
    }

    @ViewBuilder
    private func content(project: ComposeProject, host: DockerInventory.HostItem, controller: ComposeController) -> some View {
        @Bindable var controller = controller
        List {
            Section {
                LabeledContent("Host") { Text(verbatim: host.host.name) }
                if let folder = project.workingDirectory {
                    LabeledContent("Folder") { Text(verbatim: folder).font(.footnote.monospaced()).textSelection(.enabled) }
                }
                LabeledContent("Services") { Text(verbatim: project.services.joined(separator: ", ")) }
                LabeledContent("Running") { Text(verbatim: "\(project.runningCount)/\(project.containerCount)") }
                LabeledContent("Managed through") { Text(verbatim: sourceTitle(controller.source)) }
            }
            if controller.source == .unavailable {
                Section {
                    if sshEnabled, sshHostForDocker != nil, !project.isManageable {
                        Text("PatchNode only manages .yml or .yaml files inside the project's folder, and never a system folder. This project's labels point elsewhere.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("To edit this project and run its actions, turn on Settings › SSH and add an SSH host linked to the Docker host \(host.host.name). Projects deployed by Portainer are managed through its API.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                if case .ssh(let sshHost) = controller.source {
                    Section {
                        Button("Open a terminal here", systemImage: "terminal") {
                            guard let command = try? ComposeCommands(project: project).terminalHere() else { return }
                            Task { await ssh.connect(sshHost, command: command, title: "\(project.name) (\(sshHost.name))") }
                        }
                    } footer: {
                        Text(verbatim: project.workingDirectory ?? "")
                    }
                } else if controller.source == .demo {
                    Section {
                        Button("Open a terminal here", systemImage: "terminal") {
                            ssh.openDemo(title: project.name, hostname: host.host.name)
                        }
                    }
                }
                Section("Files") {
                    ForEach(files(project: project, controller: controller)) { file in
                        NavigationLink {
                            ComposeEditorView(file: file, controller: controller)
                        } label: {
                            Label(file.title, systemImage: file.isEnv ? "key" : "doc.text")
                        }
                    }
                }
                Section {
                    ForEach(ComposeAction.allCases, id: \.self) { action in
                        Button(ComposeController.title(action), systemImage: icon(action), role: action == .stop ? .destructive : nil) {
                            pendingAction = action
                        }
                        .disabled(controller.isBusy || controller.isConnecting)
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    Text("The project is validated with docker compose config before any action. Face ID is asked each time; nothing is retried automatically.")
                }
            }
        }
        .readableWidth()
        .confirmationDialog(
            Text(confirmationTitle(project: project, host: host)),
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(ComposeController.title(action), role: action == .stop ? .destructive : nil) {
                Task { await controller.perform(action) }
            }
        } message: { _ in
            Text("Services: \(project.services.joined(separator: ", "))")
        }
        .sheet(item: $controller.run) { _ in
            ComposeRunSheet(controller: controller)
        }
        .alert("Compose", isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: controller.errorMessage ?? "")
        }
    }

    private func files(project: ComposeProject, controller: ComposeController) -> [ComposeFile] {
        switch controller.source {
        case .portainer:
            [ComposeFile(path: PortainerComposeBackend.filePath, isEnv: false, title: "docker-compose.yml")]
        case .demo:
            DemoComposeBackend(project: project).files
        case .ssh:
            project.configFiles.map { ComposeFile(path: $0, isEnv: false, title: ($0 as NSString).lastPathComponent) }
                + (project.envFile.map { [ComposeFile(path: $0, isEnv: true, title: ".env")] } ?? [])
        case .unavailable:
            []
        }
    }

    private func confirmationTitle(project: ComposeProject, host: DockerInventory.HostItem) -> String {
        guard let pendingAction else { return "" }
        return String(localized: "\(ComposeController.title(pendingAction)) — \(project.name) on \(host.host.name)?")
    }

    private func sourceTitle(_ source: ComposeController.Source) -> String {
        switch source {
        case .ssh(let host): "SSH · \(host.name)"
        case .portainer: "Portainer"
        case .demo: String(localized: "Demo")
        case .unavailable: String(localized: "Not available")
        }
    }

    private func icon(_ action: ComposeAction) -> String {
        switch action {
        case .up: "play"
        case .stop: "stop"
        case .restart: "arrow.clockwise"
        case .update: "arrow.down.circle"
        }
    }
}

/// The action's output, live, then its exit status.
struct ComposeRunSheet: View {
    let controller: ComposeController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // One row per line, built lazily: an output of thousands of
                    // lines stays smooth.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array((controller.run?.lines ?? []).enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line.isEmpty ? " " : line)
                                .font(.footnote.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .padding()
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: controller.run?.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { status }
            .navigationTitle(Text(verbatim: controller.run.map { ComposeController.title($0.action) } ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(controller.run?.isRunning == true ? "Hide" : "Done") { dismiss() }
                }
            }
        }
        .privacyCover()
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 8) {
            if let run = controller.run {
                if run.isRunning {
                    ProgressView()
                    Text("Running…")
                } else if let failure = run.failure {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text(verbatim: failure).lineLimit(3)
                } else if run.exitStatus == 0 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Finished")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Finished with exit status \(run.exitStatus ?? -1)")
                }
            }
            Spacer()
        }
        .font(.subheadline)
        .padding(12)
        .background(.bar)
    }
}

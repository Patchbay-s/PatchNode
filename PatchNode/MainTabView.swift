import SwiftUI
import SwiftData
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit
import TailscaleKit
import SecurityKit
import HomeServicesKit

enum AppTab: Hashable {
    case screen(AppScreen)
    case settings
}

struct MainTabView: View {
    @Query(sort: \ServiceConfig.name) private var services: [ServiceConfig]
    @Environment(ProxmoxStore.self) private var proxmoxStore
    @Environment(DockerStore.self) private var dockerStore
    @Environment(ObservabilityStore.self) private var observabilityStore
    @Environment(BackupStore.self) private var backupStore
    @Environment(TailscaleStore.self) private var tailscaleStore
    @Environment(SecurityStore.self) private var securityStore
    @Environment(HomeStore.self) private var homeStore
    @AppStorage(TabSelection.storageKey) private var storedTabs = ""
    @AppStorage(DemoMode.key) private var demoMode = false
    @AppStorage(OnboardingView.doneKey) private var onboardingDone = false
    @Environment(\.modelContext) private var modelContext
    @Environment(AppLockController.self) private var lockController
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .screen(.dashboard)

    /// Screens chosen in Settings > Tabs (at most 4) that still have a service;
    /// Settings always comes last, so iOS never shows "More".
    private var tabs: [AppScreen] {
        TabSelection.resolve(
            stored: TabSelection.decode(storedTabs),
            available: AppScreen.available(for: allDescriptors.map(\.kind))
        )
    }

    var body: some View {
        let tabs = tabs
        TabView(selection: $selection) {
            // In its own typed function: inline, the type checker gives up.
            screenTabs(tabs)
            Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                SettingsView()
                    .modifier(demoBannerInset)
            }
        }
        // iPad and Mac: a sidebar the user can show; iPhone keeps the tab bar.
        .tabViewStyle(.sidebarAdaptable)
        // ⌘N: Settings, whose form opens (SettingsView clears the request).
        .onChange(of: model.addServiceRequested) { _, requested in
            if requested { selection = .settings }
        }
        // Terminal sessions and consoles, above everything.
        .modifier(RemoteAccessPresentation())
        // First launch without any service: the introduction.
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingDone && services.isEmpty && !demoMode },
            set: { if !$0 { onboardingDone = true } }
        )) {
            OnboardingView()
                .appEnvironment(model)
        }
        // A tab switched off, or whose services were all deleted, goes away.
        .onChange(of: tabs) { _, tabs in
            if case .screen(let screen) = selection, !tabs.contains(screen) {
                selection = .screen(.dashboard)
            }
        }
        .onChange(of: proxmoxDescriptors, initial: true) { _, descriptors in
            proxmoxStore.configure(descriptors)
        }
        .onChange(of: observabilityDescriptors, initial: true) { _, descriptors in
            observabilityStore.configure(descriptors)
        }
        .onChange(of: dockerDescriptors, initial: true) { _, descriptors in
            dockerStore.configure(descriptors)
        }
        .onChange(of: securityDescriptors, initial: true) { _, descriptors in
            securityStore.configure(descriptors)
        }
        .onChange(of: backupDescriptors, initial: true) { _, descriptors in
            backupStore.configure(descriptors)
        }
        .onChange(of: tailscaleDescriptors, initial: true) { _, descriptors in
            tailscaleStore.configure(descriptors)
        }
        .onChange(of: homeDescriptors, initial: true) { _, descriptors in
            homeStore.configure(descriptors)
        }
    }

    @TabContentBuilder<AppTab>
    private func screenTabs(_ tabs: [AppScreen]) -> some TabContent<AppTab> {
        ForEach(tabs) { screen in
            Tab(screen.title, systemImage: screen.systemImage, value: AppTab.screen(screen)) {
                tabContent(screen, tabs: tabs)
                    .modifier(demoBannerInset)
            }
            .badge(badgeCount(for: screen))
        }
    }

    @ViewBuilder
    private func tabContent(_ screen: AppScreen, tabs: [AppScreen]) -> some View {
        if screen == .dashboard {
            DashboardView(selection: $selection, tabs: tabs)
        } else {
            NavigationStack {
                ScreenView(screen: screen)
            }
        }
    }

    private func badgeCount(for screen: AppScreen) -> Int {
        screen == .observability ? observabilityStore.inventory.overview.activeAlerts : 0
    }

    private var proxmoxDescriptors: [ServiceDescriptor] {
        descriptors { $0 == .proxmoxVE }
    }

    private var dockerDescriptors: [ServiceDescriptor] {
        descriptors { $0.isDocker }
    }

    private var observabilityDescriptors: [ServiceDescriptor] {
        descriptors { $0.isObservability }
    }

    private var securityDescriptors: [ServiceDescriptor] {
        descriptors { $0.isSecurity }
    }

    private var backupDescriptors: [ServiceDescriptor] {
        descriptors { $0 == .proxmoxBackupServer }
    }

    private var tailscaleDescriptors: [ServiceDescriptor] {
        descriptors { $0 == .tailscale }
    }

    private var homeDescriptors: [ServiceDescriptor] {
        descriptors { $0.isHomeService }
    }

    /// The user's services, or the demo ones while the demo runs.
    private var allDescriptors: [ServiceDescriptor] {
        if demoMode { return DemoMode.descriptors }
        // One per ID: an iCloud sync can store a service twice.
        return services.uniqued(by: \.id).compactMap { config in
            config.url.map { ServiceDescriptor(id: config.id, kind: config.kind, name: config.name, url: $0) }
        }
    }

    private func descriptors(where matches: (ServiceKind) -> Bool) -> [ServiceDescriptor] {
        allDescriptors.filter { matches($0.kind) }
    }

    /// Back to the user's services; a demo opened without a passcode locks again.
    /// Demo mode: labelled on every screen, left in one tap. Applied to each tab's
    /// content, outside its navigation stack: on the TabView, the inset does not
    /// reach the navigation bars and inline titles slide under the banner.
    private var demoBannerInset: DemoBannerInset {
        DemoBannerInset(isOn: demoMode) { exitDemo() }
    }

    private func exitDemo() {
        selection = .screen(.dashboard)
        DemoMode.exit(context: modelContext, lock: lockController)
    }
}

/// A service screen, without its navigation stack: a tab wraps it in one, the
/// dashboard pushes it onto its own.
struct ScreenView: View {
    let screen: AppScreen

    var body: some View {
        switch screen {
        case .dashboard: EmptyView()
        case .proxmox: ProxmoxView()
        case .backups: BackupsView()
        case .docker: DockerView()
        case .observability: ObservabilityView()
        case .security: SecurityView()
        case .tailscale: TailscaleView()
        case .homeAssistant: HomeAssistantView()
        case .glances: GlancesView()
        }
    }
}

extension AppScreen {
    var title: String {
        switch self {
        case .dashboard: String(localized: "Dashboard")
        case .proxmox: "Proxmox"
        case .backups: String(localized: "Backups")
        case .docker: "Docker"
        case .observability: String(localized: "Observability")
        case .security: String(localized: "Security")
        case .tailscale: "Tailscale"
        case .homeAssistant: "Home Assistant"
        case .glances: "Glances"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .proxmox: "server.rack"
        case .backups: "externaldrive.badge.timemachine"
        case .docker: "shippingbox"
        case .observability: "waveform.path.ecg"
        case .security: "shield.lefthalf.filled"
        case .tailscale: "network"
        case .homeAssistant: "house"
        case .glances: "gauge.with.dots.needle.33percent"
        }
    }
}

/// The terminal workspace (tabs on iPad and Mac), its return button, and
/// the console launcher's sheet and alert.
private struct RemoteAccessPresentation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(TerminalSessionStore.self) private var terminals
    @Environment(ConsoleLauncher.self) private var consoles
    @Environment(SSHLauncher.self) private var ssh

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: Binding(
                get: { terminals.isPresented },
                set: { terminals.isPresented = $0 }
            )) {
                TerminalWorkspaceView()
                    .appEnvironment(model)
            }
            .overlay(alignment: .bottomTrailing) { TerminalReturnButton() }
            // A console the token can't open: the commands that grant it.
            .sheet(item: Binding(get: { consoles.accessHelp }, set: { consoles.accessHelp = $0 })) { help in
                ConsoleAccessSheet(help: help)
                    .appEnvironment(model)
            }
            .alert("Console unavailable", isPresented: Binding(
                get: { consoles.errorMessage != nil },
                set: { if !$0 { consoles.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: consoles.errorMessage ?? "")
            }
            // SSH: first contact (fingerprint to check), errors, password.
            .sheet(item: Binding(get: { ssh.hostKeyConfirmation }, set: { ssh.hostKeyConfirmation = $0 })) { confirmation in
                SSHHostKeySheet(confirmation: confirmation)
                    .appEnvironment(model)
            }
            .alert("SSH connection failed", isPresented: Binding(
                get: { ssh.errorMessage != nil },
                set: { if !$0 { ssh.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: ssh.errorMessage ?? "")
            }
            .modifier(SSHPasswordPrompt(isActive: !terminals.isPresented))
    }
}

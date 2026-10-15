import SwiftUI
import SwiftData
import TipKit
import PatchNodeCore
import DockerKit
import ObservabilityKit
import ProxmoxKit
import TailscaleKit
import SecurityKit
import HomeServicesKit

/// Dashboard cards, in the order the user chose.
enum DashboardCard: String, CaseIterable, Identifiable, Hashable {
    case proxmox, backups, docker, observability, tailscale
    case crowdSec, nginxProxyManager, adGuardHome, homeAssistant, glances

    var id: String { rawValue }

    /// Product names, shown as-is in every language.
    var title: String {
        switch self {
        case .proxmox: "Proxmox"
        case .backups: "Proxmox Backup Server"
        case .docker: "Docker"
        case .observability: String(localized: "Observability")
        case .tailscale: "Tailscale"
        case .crowdSec: "CrowdSec"
        case .nginxProxyManager: "Nginx Proxy Manager"
        case .adGuardHome: "AdGuard Home"
        case .homeAssistant: "Home Assistant"
        case .glances: "Glances"
        }
    }

    /// Stored order (comma-separated raw values), completed with cards added later.
    static func ordered(_ stored: String) -> [DashboardCard] {
        var result: [DashboardCard] = []
        for raw in stored.split(separator: ",") {
            if let card = DashboardCard(rawValue: String(raw)), !result.contains(card) { result.append(card) }
        }
        return result + allCases.filter { !result.contains($0) }
    }

    static let orderKey = "dashboardCardOrder"

    /// The screen the card opens.
    var screen: AppScreen {
        switch self {
        case .proxmox: .proxmox
        case .backups: .backups
        case .docker: .docker
        case .observability: .observability
        case .tailscale: .tailscale
        case .crowdSec, .nginxProxyManager, .adGuardHome: .security
        case .homeAssistant: .homeAssistant
        case .glances: .glances
        }
    }
}

struct DashboardView: View {
    @Binding var selection: AppTab
    /// Screens in the tab bar: their card switches tab, the others push.
    let tabs: [AppScreen]
    @Environment(ProxmoxStore.self) private var proxmoxStore
    @Environment(BackupStore.self) private var backupStore
    @Environment(DockerStore.self) private var dockerStore
    @Environment(ObservabilityStore.self) private var observabilityStore
    @Environment(TailscaleStore.self) private var tailscaleStore
    @Environment(SecurityStore.self) private var securityStore
    @Environment(HomeStore.self) private var homeStore
    @Query(sort: \HomeAssistantPin.sortOrder) private var pins: [HomeAssistantPin]
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval
    @AppStorage(DashboardCard.orderKey) private var storedOrder = ""
    @Environment(\.modelContext) private var modelContext
    @State private var isEditingOrder = false

    private var stores: [any ManagedStore] {
        [proxmoxStore, backupStore, dockerStore, observabilityStore, tailscaleStore, securityStore, homeStore]
    }

    /// Cards of the configured services only.
    private var visibleCards: [DashboardCard] {
        DashboardCard.ordered(storedOrder).filter(isConfigured)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if visibleCards.isEmpty {
                        ContentUnavailableView {
                            Label("No services configured yet.", systemImage: "server.rack")
                        } description: {
                            Text("Add a service in Settings.")
                        } actions: {
                            Button("Open Settings") { selection = .settings }
                            Button("Try the demo") { DemoMode.enter(context: modelContext) }
                        }
                    } else {
                        // One banner for the whole app instead of an error per card.
                        if aggregateConnectivity(from: stores.flatMap { $0.healthStatuses }) == .allUnreachable {
                            PrivateNetworkBanner()
                        }
                        CertificatesBanner(
                            services: stores.flatMap { $0.services },
                            refreshStamp: stores.map { $0.lastUpdated }
                        )
                        TipView(WidgetTip())
                        // One column on iPhone, two or three on iPad and Mac.
                        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 16) {
                            ForEach(visibleCards) { card in
                                cardView(card)
                            }
                        }
                    }
                }
                .padding()
            }
            .tabBarClearance()
            // On the scroll view, not the stack: pushing a detail screen stops
            // the dashboard's polling (the detail screen polls its own store).
            .refreshable {
                await withTaskGroup(of: Void.self) { group in
                    for store in stores where !store.services.isEmpty {
                        group.addTask { await store.refresh(force: true) }
                    }
                }
            }
            .polling(every: refreshInterval) {
                let maxAge = max(refreshInterval - 5, 5)
                await withTaskGroup(of: Void.self) { group in
                    for store in stores where !store.services.isEmpty {
                        group.addTask { await store.refresh(ifOlderThan: maxAge) }
                    }
                }
            }
            .navigationTitle("Dashboard")
            .navigationDestination(for: AppScreen.self) { screen in
                ScreenView(screen: screen)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if visibleCards.count > 1 {
                        Button("Reorder cards", systemImage: "arrow.up.arrow.down") {
                            DashboardOrderTip().invalidate(reason: .actionPerformed)
                            isEditingOrder = true
                        }
                        .popoverTip(DashboardOrderTip())
                    }
                }
            }
            .onChange(of: visibleCards.count, initial: true) { _, count in DashboardOrderTip.cardCount = count }
            .task(id: stores.contains { $0.lastUpdated != nil }) {
                // A tip for widgets only after the dashboard was seen with data.
                if stores.contains(where: { $0.lastUpdated != nil }) { await WidgetTip.dashboardSeen.donate() }
            }
            .sheet(isPresented: $isEditingOrder) {
                DashboardOrderView(storedOrder: $storedOrder, visible: Set(visibleCards))
            }
        }
    }

    private static let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    private func isConfigured(_ card: DashboardCard) -> Bool {
        switch card {
        case .proxmox: !proxmoxStore.services.isEmpty
        case .backups: !backupStore.services.isEmpty
        case .docker: !dockerStore.services.isEmpty
        case .observability: !observabilityStore.services.isEmpty
        case .tailscale: !tailscaleStore.services.isEmpty
        case .crowdSec: !securityStore.services(of: .crowdSec).isEmpty
        case .nginxProxyManager: !securityStore.services(of: .nginxProxyManager).isEmpty
        case .adGuardHome: !securityStore.services(of: .adGuardHome).isEmpty
        case .homeAssistant: !homeStore.services(of: .homeAssistant).isEmpty
        case .glances: !homeStore.services(of: .glances).isEmpty
        }
    }

    @ViewBuilder
    private func cardView(_ card: DashboardCard) -> some View {
        let screen = card.screen
        if tabs.contains(screen) {
            Button { selection = .screen(screen) } label: { cardContent(card) }
                .buttonStyle(.plain)
                .contentShape(.hoverEffect, .rect(cornerRadius: 16))
                .hoverEffect(.highlight)
        } else {
            NavigationLink(value: screen) { cardContent(card) }
                .buttonStyle(.plain)
                .contentShape(.hoverEffect, .rect(cornerRadius: 16))
                .hoverEffect(.highlight)
        }
    }

    @ViewBuilder
    private func cardContent(_ card: DashboardCard) -> some View {
        switch card {
        case .proxmox: ProxmoxCard(store: proxmoxStore)
        case .docker: DockerCard(store: dockerStore)
        case .observability: ObservabilityCard(store: observabilityStore)
        case .crowdSec: CrowdSecCard(store: securityStore)
        case .nginxProxyManager: ProxyManagerCard(store: securityStore)
        case .adGuardHome: AdGuardCard(store: securityStore)
        case .backups: BackupsCard(store: backupStore)
        case .tailscale: TailscaleCard(store: tailscaleStore)
        case .homeAssistant: HomeAssistantCard(store: homeStore, pins: pins)
        case .glances: GlancesCard(store: homeStore)
        }
    }
}

/// Drag to reorder the dashboard cards.
struct DashboardOrderView: View {
    @Binding var storedOrder: String
    let visible: Set<DashboardCard>
    @Environment(\.dismiss) private var dismiss
    @State private var order: [DashboardCard] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(order.filter { visible.contains($0) }) { card in
                    Text(verbatim: card.title)
                }
                .onMove(perform: move)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { order = DashboardCard.ordered(storedOrder) }
        }
    }

    /// Moves within the visible cards; hidden ones keep their relative place.
    private func move(from source: IndexSet, to destination: Int) {
        var shown = order.filter { visible.contains($0) }
        shown.move(fromOffsets: source, toOffset: destination)
        var iterator = shown.makeIterator()
        order = order.map { visible.contains($0) ? (iterator.next() ?? $0) : $0 }
        storedOrder = order.map(\.rawValue).joined(separator: ",")
    }
}

/// Single banner shown instead of one error per card when nothing answers.
struct PrivateNetworkBanner: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Private network / VPN unreachable")
                    .font(.headline)
                Text("None of your services answered. Turn on your VPN and pull to refresh.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 16))
    }
}

struct ProxmoxCard: View {
    let store: ProxmoxStore

    var body: some View {
        let overview = store.inventory.overview
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Proxmox", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                if let level = store.level {
                    HealthIndicator(level: level)
                } else {
                    ProgressView()
                }
            }
            if store.hasLoadedOnce {
                Text("\(overview.nodesOnline)/\(overview.nodesTotal) nodes online")
                Text("\(overview.vmsRunning)/\(overview.vmsTotal) VMs running")
                Text("\(overview.containersRunning)/\(overview.containersTotal) containers running")
                ForEach(overview.storagesAboveThreshold) { item in
                    Label(
                        "Storage \(item.resource.displayName) at \(Format.percent(item.resource.diskUsage))",
                        systemImage: "externaldrive.badge.exclamationmark"
                    )
                    .foregroundStyle(.orange)
                }
                if overview.recentFailedTasks > 0 {
                    Label("\(overview.recentFailedTasks) failed tasks in the last 24 h", systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                }
                ForEach(store.services) { service in
                    if store.states[service.id]?.message != nil {
                        Label("\(service.name): \(store.stateText(for: service.id))", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                if let lastUpdated = store.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the Proxmox screen")
    }
}

struct HealthIndicator: View {
    let level: HealthLevel

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch level {
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private var label: Text {
        switch level {
        case .ok: Text("OK")
        case .warning: Text("Warning")
        case .critical: Text("Critical")
        }
    }
}

struct DockerCard: View {
    let store: DockerStore

    var body: some View {
        let overview = store.inventory.overview
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(verbatim: "Docker")
                } icon: {
                    Image(systemName: "shippingbox")
                }
                .font(.headline)
                Spacer()
                if let level = store.level {
                    HealthIndicator(level: level)
                } else {
                    ProgressView()
                }
            }
            if store.hasLoadedOnce {
                Text("\(overview.running)/\(overview.total) containers running")
                if overview.stopped > 0 {
                    Text("\(overview.stopped) stopped")
                }
                if overview.unhealthy > 0 {
                    Label("\(overview.unhealthy) unhealthy", systemImage: "heart.slash")
                        .foregroundStyle(.red)
                }
                if overview.exitedWithError > 0 {
                    Label("\(overview.exitedWithError) exited with an error", systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                }
                if overview.restarting > 0 {
                    Label("\(overview.restarting) restarting", systemImage: "arrow.clockwise")
                        .foregroundStyle(.orange)
                }
                if overview.hostsUnreachable > 0 {
                    Label("\(overview.hostsUnreachable) hosts unreachable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                ForEach(store.services) { service in
                    if store.states[service.id]?.message != nil {
                        Label("\(service.name): \(store.stateText(for: service.id))", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                if let lastUpdated = store.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the Docker screen")
    }
}

struct ObservabilityCard: View {
    let store: ObservabilityStore

    var body: some View {
        let overview = store.inventory.overview
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Observability", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                if let level = store.level {
                    HealthIndicator(level: level)
                } else {
                    ProgressView()
                }
            }
            if store.hasLoadedOnce {
                if overview.activeAlerts == 0 {
                    Label("No active alerts", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                } else {
                    Text("\(overview.activeAlerts) active alerts")
                        .font(.title3.bold())
                    if overview.critical > 0 {
                        Label("\(overview.critical) critical", systemImage: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    if overview.warning > 0 {
                        Label("\(overview.warning) warnings", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    ForEach(store.inventory.alerts.prefix(3)) { item in
                        Text(verbatim: "• \(item.alert.name)")
                            .lineLimit(1)
                    }
                }
                if overview.targetsDown > 0 {
                    Label("\(overview.targetsDown) Prometheus targets down", systemImage: "xmark.circle")
                        .foregroundStyle(.orange)
                }
                ForEach(store.services) { service in
                    if store.states[service.id]?.message != nil {
                        Label("\(service.name): \(store.stateText(for: service.id))", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                if let lastUpdated = store.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the Observability screen")
    }
}

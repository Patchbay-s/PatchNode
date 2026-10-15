import SwiftUI
import SwiftData
import ProxmoxKit
import PatchNodeCore
import DockerKit
import RemoteAccessKit

enum GuestTypeFilter: Hashable, CaseIterable {
    case all, vm, container

    var title: LocalizedStringKey {
        switch self {
        case .all: "All types"
        case .vm: "VMs"
        case .container: "Containers"
        }
    }

    func matches(_ type: ProxmoxGuestType?) -> Bool {
        switch self {
        case .all: true
        case .vm: type == .qemu
        case .container: type == .lxc
        }
    }
}

enum GuestStateFilter: Hashable, CaseIterable {
    case all, running, stopped

    var title: LocalizedStringKey {
        switch self {
        case .all: "All states"
        case .running: "Running"
        case .stopped: "Not running"
        }
    }

    func matches(_ resource: ProxmoxResource) -> Bool {
        switch self {
        case .all: true
        case .running: resource.isRunning
        case .stopped: !resource.isRunning
        }
    }
}

struct ProxmoxView: View {
    @Environment(SSHLauncher.self) private var ssh
    @Query private var sshHosts: [SSHHost]
    @AppStorage(SSHSettings.enabledKey) private var sshEnabled = false
    @AppStorage(DemoMode.key) private var demoMode = false
    @Environment(ProxmoxStore.self) private var store
    @Environment(BackupStore.self) private var backupStore
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval
    @State private var searchText = ""
    @State private var typeFilter: GuestTypeFilter = .all
    @State private var stateFilter: GuestStateFilter = .all
    /// nil = all nodes. A node of one service: two services may both have a "pve".
    @State private var nodeFilter: ProxmoxInventory.NodeKey?

    var body: some View {
        List {
            serviceErrors
            nodesSection
            tasksSection
            Section {
                NavigationLink {
                    ProxmoxBackupsView()
                } label: {
                    Label("Backups (Proxmox VE)", systemImage: "externaldrive.badge.clock")
                }
                NavigationLink {
                    ProxmoxDisksView()
                } label: {
                    Label("Disk health", systemImage: "internaldrive")
                }
                if !backupStore.services.isEmpty {
                    NavigationLink {
                        BackupsView()
                    } label: {
                        Label("Backups (Proxmox Backup Server)", systemImage: "externaldrive.badge.timemachine")
                    }
                }
            }
            guestsSection
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle(Text(verbatim: "Proxmox"))
        .navigationDestination(for: ProxmoxInventory.Item.self) { item in
            GuestDetailView(item: item)
        }
        .searchable(text: $searchText, prompt: Text("Search by name or ID"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { filterMenu }
        }
        .overlay {
            if !store.hasLoadedOnce && store.isRefreshing {
                ProgressView("Loading…")
            }
        }
        .tabBarClearance()
        .refreshable { await store.refresh(force: true) }
        .polling(every: refreshInterval) { await store.refresh(ifOlderThan: max(refreshInterval - 5, 5)) }
    }

    // MARK: Sections

    @ViewBuilder
    private var serviceErrors: some View {
        let failing = store.services.filter { store.states[$0.id]?.isFailure ?? false }
        if !failing.isEmpty {
            Section {
                if store.connectivity == .allUnreachable {
                    PrivateNetworkBanner()
                        .listRowInsets(EdgeInsets())
                } else {
                    ForEach(failing) { service in
                        Label {
                            VStack(alignment: .leading) {
                                Text(service.name).font(.headline)
                                store.stateText(for: service.id)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                GuideHelpButton(kind: service.kind, state: store.states[service.id])
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private var nodesSection: some View {
        Section("Nodes") {
            if store.inventory.nodes.isEmpty {
                Group {
                    if store.hasLoadedOnce { Text("No nodes.") } else { Text("Not loaded yet.") }
                }
                .foregroundStyle(.secondary)
            }
            ForEach(store.inventory.nodes) { item in
                NodeRow(item: item, storages: storages(of: item))
                    .contextMenu { nodeConsoleButton(item) }
                    .swipeActions(edge: .leading) { nodeConsoleButton(item).tint(.accentColor) }
            }
        }
    }

    /// The node's shell (Sys.Console), from the row's menu or a swipe; SSH
    /// when a host is linked to the node.
    @ViewBuilder
    private func nodeConsoleButton(_ item: ProxmoxInventory.Item) -> some View {
        if let node = item.resource.node, item.resource.isOnline {
            ConsoleButton(
                target: .node(node), name: node,
                serviceID: item.serviceID, serviceName: item.serviceName
            )
            if sshEnabled || demoMode {
                if let host = SSHHostLookup.host(in: sshHosts, link: .proxmoxNode, serviceID: item.serviceID, target: node) {
                    Button("SSH", systemImage: "terminal.fill") {
                        Task { await ssh.connect(SSHHostSnapshot(host)) }
                    }
                } else if demoMode {
                    Button("SSH", systemImage: "terminal.fill") { ssh.openDemo(title: node, hostname: node) }
                }
            }
        }
    }

    private var tasksSection: some View {
        Section {
            NavigationLink {
                TasksView()
            } label: {
                HStack {
                    Label("Recent tasks", systemImage: "list.bullet.rectangle")
                    Spacer()
                    let failed = store.inventory.overview.recentFailedTasks
                    if failed > 0 {
                        Text("\(failed) failed")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.red, in: .capsule)
                    }
                }
            }
        }
    }

    private var guestsSection: some View {
        Section {
            let guests = filteredGuests
            if guests.isEmpty {
                Group {
                    if store.inventory.guests.isEmpty {
                        Text("No VMs or containers.")
                    } else {
                        Text("No match for these filters.")
                    }
                }
                .foregroundStyle(.secondary)
            }
            ForEach(guests) { item in
                NavigationLink(value: item) {
                    GuestRow(item: item)
                }
            }
        } header: {
            Text("VMs and containers")
        } footer: {
            if isFiltering {
                Button("Clear filters") { clearFilters() }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $typeFilter) {
                ForEach(GuestTypeFilter.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("State", selection: $stateFilter) {
                ForEach(GuestStateFilter.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Node", selection: $nodeFilter) {
                Text("All nodes").tag(ProxmoxInventory.NodeKey?.none)
                ForEach(store.inventory.nodes) { node in
                    if let key = node.nodeKey {
                        Text(verbatim: [NodeRow.title(of: node), NodeRow.subtitle(of: node)].compactMap { $0 }.joined(separator: " · "))
                            .tag(ProxmoxInventory.NodeKey?.some(key))
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltering
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: Filtering

    private var isFiltering: Bool {
        typeFilter != .all || stateFilter != .all || nodeFilter != nil
    }

    private func clearFilters() {
        typeFilter = .all
        stateFilter = .all
        nodeFilter = nil
    }

    private var filteredGuests: [ProxmoxInventory.Item] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return store.inventory.guests.filter { item in
            let resource = item.resource
            guard typeFilter.matches(resource.guestType), stateFilter.matches(resource) else { return false }
            if let nodeFilter, item.nodeKey != nodeFilter { return false }
            guard !query.isEmpty else { return true }
            return resource.displayName.localizedStandardContains(query)
                || resource.vmid.map { String($0).contains(query) } ?? false
        }
    }

    private func storages(of node: ProxmoxInventory.Item) -> [ProxmoxInventory.Item] {
        store.inventory.storages.filter {
            $0.serviceID == node.serviceID && $0.resource.node == node.resource.node
        }
    }
}

struct NodeRow: View {
    let item: ProxmoxInventory.Item
    let storages: [ProxmoxInventory.Item]

    var body: some View {
        let node = item.resource
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: node.isOnline ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(node.isOnline ? .green : .red)
                    .accessibilityLabel(node.isOnline ? Text("Node online") : Text("Node offline"))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: Self.title(of: item)).font(.headline)
                    if let subtitle = Self.subtitle(of: item) {
                        Text(verbatim: subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if node.isOnline {
                    Text("Up \(Format.uptime(node.uptime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Offline").font(.caption).foregroundStyle(.red)
                }
            }
            if node.isOnline {
                UsageBar(title: Text("CPU"), fraction: node.cpu, detail: Format.percent(node.cpu))
                UsageBar(title: Text("RAM"), fraction: node.memoryUsage, detail: Format.usage(node.memory, of: node.maxMemory))
                // The node's root disk; not repeated when a storage shows the same figures
                // (the "local" storage usually lives on it).
                if !storages.contains(where: { $0.resource.disk == node.disk && $0.resource.maxDisk == node.maxDisk }) {
                    UsageBar(title: Text("Root disk"), fraction: node.diskUsage, detail: Format.usage(node.disk, of: node.maxDisk))
                }
                ForEach(storages) { storage in
                    UsageBar(
                        title: Text(verbatim: storage.resource.displayName),
                        fraction: storage.resource.diskUsage,
                        detail: Format.usage(storage.resource.disk, of: storage.resource.maxDisk)
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The configured service name as title (two services may both have a node
    /// called "pve"), the node name second.
    static func title(of item: ProxmoxInventory.Item) -> String {
        item.serviceName.isEmpty ? (item.resource.node ?? item.resource.displayName) : item.serviceName
    }

    static func subtitle(of item: ProxmoxInventory.Item) -> String? {
        guard let node = item.resource.node, node != title(of: item) else { return nil }
        return node
    }
}

struct UsageBar: View {
    let title: Text
    let fraction: Double?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                title
                Spacer()
                Text(detail).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: min(max(fraction ?? 0, 0), 1))
                .tint(tint)
        }
    }

    private var tint: Color {
        guard let fraction else { return .gray }
        if fraction > ProxmoxInventory.storageAlertThreshold { return .red }
        if fraction > 0.7 { return .orange }
        return .accentColor
    }
}

struct GuestRow: View {
    let item: ProxmoxInventory.Item

    private var resource: ProxmoxResource { item.resource }

    var body: some View {
        HStack(spacing: 12) {
            GuestStatusIcon(status: resource.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.displayName).font(.body)
                    // Same separator inset on every row, whatever the row contains.
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Text(Self.subtitle(of: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if resource.isRunning {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("CPU \(Format.percent(resource.cpu))")
                    Text("RAM \(Format.percent(resource.memoryUsage))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    /// "CT 100 · Demo cluster · node-b": the service first, the node second.
    static func subtitle(of item: ProxmoxInventory.Item) -> String {
        let resource = item.resource
        let type = resource.guestType == .lxc ? String(localized: "CT") : String(localized: "VM")
        let vmid = resource.vmid.map(String.init) ?? "?"
        let node = resource.node ?? "?"
        let place = item.serviceName.isEmpty || item.serviceName == node ? node : "\(item.serviceName) · \(node)"
        return "\(type) \(vmid) · \(place)"
    }
}

struct GuestStatusIcon: View {
    let status: String?

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(Text(verbatim: status ?? "unknown"))
    }

    private var symbol: String {
        switch status {
        case "running": "play.circle.fill"
        case "paused", "suspended": "pause.circle.fill"
        case "stopped": "stop.circle.fill"
        default: "questionmark.circle"
        }
    }

    private var color: Color {
        switch status {
        case "running": .green
        case "paused", "suspended": .orange
        default: .secondary
        }
    }
}

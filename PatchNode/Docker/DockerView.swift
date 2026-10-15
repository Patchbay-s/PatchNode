import SwiftUI
import DockerKit
import PatchNodeCore
import ProxmoxKit

enum ContainerStateFilter: Hashable, CaseIterable {
    case all, running, stopped, problems

    var title: LocalizedStringKey {
        switch self {
        case .all: "All containers"
        case .running: "Running"
        case .stopped: "Not running"
        case .problems: "Problems"
        }
    }

    func matches(_ container: DockerContainer) -> Bool {
        switch self {
        case .all: true
        case .running: container.isRunning
        case .stopped: !container.isRunning
        case .problems:
            container.health == .unhealthy || container.state == .restarting || container.exitedWithError
        }
    }
}

struct DockerView: View {
    @Environment(DockerStore.self) private var store
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval
    @State private var statsLoader = DockerStatsLoader()
    @State private var searchText = ""
    @State private var stateFilter: ContainerStateFilter = .all
    @State private var collapsedGroups: Set<String> = []

    var body: some View {
        List {
            serviceErrors
            if store.inventory.hosts.isEmpty {
                Section {
                    Group {
                        if store.hasLoadedOnce { Text("No Docker hosts.") } else { Text("Not loaded yet.") }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            ForEach(store.inventory.hosts) { host in
                hostSection(host)
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle(Text(verbatim: "Docker"))
        .navigationDestination(for: DockerInventory.ContainerItem.self) { item in
            ContainerDetailView(item: item)
        }
        .navigationDestination(for: ComposeRoute.self) { route in
            ComposeProjectView(route: route)
        }
        .searchable(text: $searchText, prompt: Text("Search by name or image"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("State", selection: $stateFilter) {
                        ForEach(ContainerStateFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("Filter", systemImage: stateFilter == .all
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .overlay {
            if !store.hasLoadedOnce && store.isRefreshing {
                ProgressView("Loading…")
            }
        }
        .tabBarClearance()
        .refreshable {
            await store.refresh(force: true)
            statsLoader.start(for: store.inventory.containers, store: store, maxAge: maxAge, force: true)
        }
        .polling(every: refreshInterval) {
            await store.refresh(ifOlderThan: maxAge)
            guard !Task.isCancelled else { return }
            statsLoader.start(for: store.inventory.containers, store: store, maxAge: maxAge)
        }
        .onDisappear { statsLoader.cancel() }
    }

    private var maxAge: Int { max(refreshInterval - 5, 5) }

    // MARK: Sections

    @ViewBuilder
    private var serviceErrors: some View {
        let failing = store.services.filter { store.states[$0.id]?.isFailure ?? false }
        if !failing.isEmpty {
            Section {
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

    private func hostSection(_ host: DockerInventory.HostItem) -> some View {
        Section {
            if let error = host.error {
                Label(ServiceLoadState(error: error).message ?? "", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if host.host.status == .down {
                Label("This environment is down in Portainer.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            let groups = filteredGroups(for: host)
            if groups.isEmpty && host.error == nil {
                Group {
                    if host.totalCount == 0 { Text("No containers.") } else { Text("No match for these filters.") }
                }
                .foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                DisclosureGroup(isExpanded: expansionBinding(for: group.id)) {
                    if let project = group.name {
                        NavigationLink(value: ComposeRoute(hostItemID: host.id, project: project)) {
                            Label("Manage the project", systemImage: "square.stack.3d.up")
                        }
                    }
                    ForEach(group.containers) { item in
                        NavigationLink(value: item) {
                            ContainerRow(container: item.container, stats: statsLoader.stats[item.id])
                        }
                    }
                } label: {
                    StackHeader(group: group)
                }
            }
        } header: {
            HStack {
                Text(verbatim: host.host.name)
                Spacer()
                Text("\(host.runningCount)/\(host.totalCount) running")
            }
        } footer: {
            if store.services.count > 1 {
                Text(verbatim: host.serviceName)
            }
        }
    }

    // MARK: Filtering

    private func filteredGroups(for host: DockerInventory.HostItem) -> [DockerInventory.StackGroup] {
        let groups = store.inventory.groupsByHost[host.id] ?? []
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard stateFilter != .all || !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let stackMatches = !query.isEmpty && (group.name?.localizedStandardContains(query) ?? false)
            let members = group.containers.filter { item in
                let container = item.container
                guard stateFilter.matches(container) else { return false }
                guard !query.isEmpty, !stackMatches else { return true }
                return container.name.localizedStandardContains(query) || container.image.localizedStandardContains(query)
            }
            guard !members.isEmpty else { return nil }
            return DockerInventory.StackGroup(name: group.name, hostItemID: group.hostItemID, containers: members)
        }
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(id) },
            set: { expanded in
                if expanded { collapsedGroups.remove(id) } else { collapsedGroups.insert(id) }
            }
        )
    }
}

struct StackHeader: View {
    let group: DockerInventory.StackGroup

    var body: some View {
        HStack {
            Image(systemName: group.name == nil ? "shippingbox" : "square.stack.3d.up")
                .foregroundStyle(.secondary)
            if let name = group.name {
                Text(verbatim: name).font(.headline)
            } else {
                Text("Standalone containers").font(.headline)
            }
            Spacer()
            Text("\(group.runningCount)/\(group.containers.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct ContainerRow: View {
    let container: DockerContainer
    let stats: DockerStats?

    var body: some View {
        HStack(spacing: 12) {
            ContainerStatusIcon(container: container)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: container.name)
                Text(verbatim: container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: container.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if container.isRunning, let stats {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("CPU \(Format.percent(stats.cpuPercent.map { $0 / 100 }))")
                    Text("RAM \(Format.bytes(stats.memoryUsed ?? 0))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct ContainerStatusIcon: View {
    let container: DockerContainer

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        if container.health == .unhealthy { return "heart.slash.fill" }
        switch container.state {
        case .running: return container.health == .starting ? "heart.circle" : "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .restarting: return "arrow.clockwise.circle.fill"
        case .exited, .dead: return "stop.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var color: Color {
        if container.health == .unhealthy { return .red }
        switch container.state {
        case .running: return container.health == .starting ? .orange : .green
        case .paused, .restarting: return .orange
        case .exited, .dead: return container.exitedWithError ? .red : .secondary
        default: return .secondary
        }
    }

    private var label: Text {
        switch container.health {
        case .unhealthy: Text("Unhealthy")
        case .healthy: Text("Healthy")
        case .starting: Text("Health check starting")
        case .none: Text(verbatim: container.status)
        }
    }
}

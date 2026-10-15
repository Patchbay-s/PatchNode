import SwiftUI
import PatchNodeCore
import SecurityKit

/// Security tab: CrowdSec bans, Nginx Proxy Manager hosts, AdGuard Home stats. Read-only.
struct SecurityView: View {
    @Environment(SecurityStore.self) private var store
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval

    /// Bans listed on this screen; the full list is one tap away.
    static let previewCount = 20

    var body: some View {
        List {
            ServiceErrorsSection(services: store.services, states: store.states, pauses: store.pauses)
            if !store.services(of: .crowdSec).isEmpty { crowdSecSection }
            if !store.services(of: .nginxProxyManager).isEmpty { npmSection }
            ForEach(store.inventory.adGuards) { item in
                AdGuardSection(item: item)
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle("Security")
        .overlay {
            if !store.hasLoadedOnce && store.isRefreshing {
                ProgressView("Loading…")
            }
        }
        .tabBarClearance()
        .refreshable { await store.refresh(force: true) }
        .polling(every: refreshInterval) { await store.refresh(ifOlderThan: max(refreshInterval - 5, 5)) }
    }

    private var crowdSecSection: some View {
        Section {
            if store.hasLoadedOnce && store.inventory.decisions.isEmpty {
                Label("No active bans.", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.inventory.decisions.prefix(Self.previewCount)) { item in
                DecisionRow(item: item, showsService: store.services(of: .crowdSec).count > 1)
            }
            if store.inventory.decisions.count > Self.previewCount {
                NavigationLink {
                    DecisionsView()
                } label: {
                    Text("All \(store.inventory.decisions.count) bans")
                }
            }
        } header: {
            Text(verbatim: "CrowdSec")
        } footer: {
            Text("Local detections and manual bans. Community blocklists are not listed.")
        }
    }

    private var npmSection: some View {
        Section {
            if store.hasLoadedOnce && store.inventory.hosts.isEmpty {
                Text("No proxy hosts.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.inventory.hosts) { item in
                ProxyHostRow(host: item.host)
            }
        } header: {
            Text(verbatim: "Nginx Proxy Manager")
        }
    }
}

struct DecisionsView: View {
    @Environment(SecurityStore.self) private var store
    @State private var searchText = ""

    var body: some View {
        List(filtered) { item in
            DecisionRow(item: item, showsService: store.services(of: .crowdSec).count > 1)
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle(Text(verbatim: "CrowdSec"))
        .searchable(text: $searchText, prompt: Text("Search by IP or scenario"))
        .refreshable { await store.refresh(force: true) }
    }

    private var filtered: [SecurityInventory.DecisionItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.inventory.decisions }
        return store.inventory.decisions.filter {
            $0.decision.value.localizedStandardContains(query) || ($0.decision.scenario?.localizedStandardContains(query) ?? false)
        }
    }
}

struct DecisionRow: View {
    let item: SecurityInventory.DecisionItem
    let showsService: Bool

    var body: some View {
        let decision = item.decision
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: decision.value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                if let country = decision.country {
                    Text(verbatim: country)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(verbatim: decision.type)
                    .font(.caption.bold())
                    .foregroundStyle(decision.simulated ? Color.secondary : Color.red)
            }
            if let scenario = decision.scenario {
                Text(verbatim: scenario)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if let expiresAt = decision.expiresAt {
                    Text("Expires \(expiresAt, format: .relative(presentation: .named))")
                }
                if decision.simulated {
                    Text("Simulation")
                }
                if showsService {
                    Text(verbatim: "· \(item.serviceName)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct ProxyHostRow: View {
    let host: NPMProxyHost

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(verbatim: host.title)
                if host.domainNames.count > 1 {
                    Text(verbatim: "+\(host.domainNames.count - 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if host.hasCertificate {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("HTTPS"))
                }
            }
            if let destination = host.destination {
                Text(verbatim: "→ \(destination)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if !host.enabled {
                Text("Disabled").font(.caption).foregroundStyle(.secondary)
            } else if let error = host.nginxError, host.isFailing {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private var icon: String {
        if !host.enabled { return "pause.circle" }
        return host.isFailing ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    private var color: Color {
        if !host.enabled { return .secondary }
        return host.isFailing ? .red : .green
    }
}

struct AdGuardSection: View {
    let item: SecurityInventory.AdGuardItem

    var body: some View {
        let summary = item.summary
        Section {
            LabeledContent("Protection") {
                if summary.protectionEnabled {
                    Label("On", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                } else {
                    Label("Off", systemImage: "shield.slash").foregroundStyle(.orange)
                }
            }
            LabeledContent("DNS queries", value: summary.dnsQueries.formatted())
            LabeledContent("Blocked") {
                Text("\(summary.blocked.formatted()) (\(Format.percent(summary.blockedRatio)))")
            }
            if let average = summary.averageProcessingTime {
                LabeledContent("Average processing time") {
                    Text(verbatim: "\(Int((average * 1000).rounded())) ms")
                }
            }
            if !summary.topBlocked.isEmpty {
                DisclosureGroup("Top blocked domains") {
                    ForEach(summary.topBlocked) { entry in
                        LabeledContent {
                            Text(entry.count.formatted())
                        } label: {
                            Text(verbatim: entry.domain).lineLimit(1)
                        }
                    }
                }
            }
            if !summary.topQueried.isEmpty {
                DisclosureGroup("Top queried domains") {
                    ForEach(summary.topQueried) { entry in
                        LabeledContent {
                            Text(entry.count.formatted())
                        } label: {
                            Text(verbatim: entry.domain).lineLimit(1)
                        }
                    }
                }
            }
        } header: {
            Text(verbatim: "AdGuard Home · \(item.serviceName)")
        } footer: {
            Text("Statistics over the period configured in AdGuard Home (24 h by default).")
        }
    }
}

// MARK: - Dashboard cards

struct CrowdSecCard: View {
    let store: SecurityStore

    var body: some View {
        let decisions = SecurityInventory.Scoped(inventory: store.inventory, serviceIDs: Set(store.services(of: .crowdSec).map(\.id))).decisions
        DashboardCardShell(
            title: Text(verbatim: "CrowdSec"),
            systemImage: "shield.lefthalf.filled",
            level: store.level(of: .crowdSec),
            hasLoadedOnce: store.hasLoadedOnce,
            failures: store.failures(kind: .crowdSec),
            lastUpdated: store.lastUpdated
        ) {
            let active = decisions.count { !$0.decision.simulated }
            if active == 0 {
                Label("No active bans", systemImage: "checkmark.shield")
                    .foregroundStyle(.green)
            } else {
                Text("\(active) active bans")
                    .font(.title3.bold())
                ForEach(decisions.prefix(3)) { item in
                    Text(verbatim: "• \(item.decision.value)  \(item.decision.scenario ?? "")")
                        .lineLimit(1)
                }
            }
        }
    }
}

struct ProxyManagerCard: View {
    let store: SecurityStore

    var body: some View {
        let hosts = SecurityInventory.Scoped(inventory: store.inventory, serviceIDs: Set(store.services(of: .nginxProxyManager).map(\.id))).hosts
        DashboardCardShell(
            title: Text(verbatim: "Nginx Proxy Manager"),
            systemImage: "arrow.left.arrow.right.circle",
            level: store.level(of: .nginxProxyManager),
            hasLoadedOnce: store.hasLoadedOnce,
            failures: store.failures(kind: .nginxProxyManager),
            lastUpdated: store.lastUpdated
        ) {
            let enabled = hosts.count { $0.host.enabled }
            Text("\(enabled)/\(hosts.count) hosts enabled")
            let failing = hosts.filter { $0.host.isFailing }
            if !failing.isEmpty {
                Label("\(failing.count) hosts refused by nginx", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            }
        }
    }
}

struct AdGuardCard: View {
    let store: SecurityStore

    var body: some View {
        let items = SecurityInventory.Scoped(inventory: store.inventory, serviceIDs: Set(store.services(of: .adGuardHome).map(\.id))).adGuards
        DashboardCardShell(
            title: Text(verbatim: "AdGuard Home"),
            systemImage: "shield.checkered",
            level: store.level(of: .adGuardHome),
            hasLoadedOnce: store.hasLoadedOnce,
            failures: store.failures(kind: .adGuardHome),
            lastUpdated: store.lastUpdated
        ) {
            ForEach(items) { item in
                let summary = item.summary
                if items.count > 1 {
                    Text(verbatim: item.serviceName).font(.subheadline.bold())
                }
                if summary.protectionEnabled {
                    Text("\(summary.dnsQueries.formatted()) queries, \(Format.percent(summary.blockedRatio)) blocked")
                } else {
                    Label("Protection is off", systemImage: "shield.slash")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

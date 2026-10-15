import SwiftUI
import PatchNodeCore
import TailscaleKit

/// Tailnet devices: online state, last seen, key expiry. Read-only.
struct TailscaleView: View {
    @Environment(TailscaleStore.self) private var store
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval
    @State private var searchText = ""

    var body: some View {
        List {
            ServiceErrorsSection(services: store.services, states: store.states, pauses: store.pauses)
            Section {
                if store.hasLoadedOnce && filtered.isEmpty {
                    Text("No devices.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { item in
                    TailscaleDeviceRow(item: item, showsService: store.services.count > 1)
                }
            } footer: {
                Text("Flagged: offline for more than 24 h, or key expiring within 14 days.")
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle(Text(verbatim: "Tailscale"))
        .tabBarClearance()
        .searchable(text: $searchText, prompt: Text("Search devices"))
        .overlay {
            if !store.hasLoadedOnce && store.isRefreshing {
                ProgressView("Loading…")
            }
        }
        .refreshable { await store.refresh(force: true) }
        .polling(every: refreshInterval) { await store.refresh(ifOlderThan: max(refreshInterval - 5, 5)) }
    }

    private var filtered: [TailscaleInventory.Item] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.inventory.devices }
        return store.inventory.devices.filter { item in
            item.device.name.localizedStandardContains(query)
                || item.device.addresses.contains { $0.contains(query) }
                || (item.device.os?.localizedStandardContains(query) ?? false)
        }
    }
}

struct TailscaleDeviceRow: View {
    let item: TailscaleInventory.Item
    let showsService: Bool

    var body: some View {
        let device = item.device
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(item.isOnline ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(item.isOnline ? Text("Online") : Text("Offline"))
                Text(verbatim: device.shortName).font(.headline)
                Spacer()
                if let os = device.os {
                    Text(verbatim: os)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let address = device.addresses.first {
                Text(verbatim: address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 6) {
                if item.isOnline {
                    Text("Connected")
                } else if let lastSeen = device.lastSeen {
                    Text("Last seen \(lastSeen, format: .relative(presentation: .named))")
                }
                if showsService {
                    Text(verbatim: "· \(item.serviceName)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(item.issues, id: \.self) { issue in
                issueLabel(issue)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func issueLabel(_ issue: TailscaleDeviceIssue) -> some View {
        switch issue {
        case .offline:
            Label("Offline for more than 24 h", systemImage: "wifi.slash")
                .foregroundStyle(.orange)
        case .keyExpiringSoon(let date):
            Label("Key expires \(date, format: .relative(presentation: .named))", systemImage: "key")
                .foregroundStyle(.orange)
        case .keyExpired(let date):
            Label("Key expired \(date, format: .relative(presentation: .named))", systemImage: "key.slash")
                .foregroundStyle(.red)
        case .notAuthorized:
            Label("Waiting for approval", systemImage: "person.badge.clock")
                .foregroundStyle(.orange)
        }
    }
}

struct TailscaleCard: View {
    let store: TailscaleStore

    var body: some View {
        let overview = store.inventory.overview
        DashboardCardShell(
            title: Text(verbatim: "Tailscale"),
            systemImage: "network",
            level: store.level,
            hasLoadedOnce: store.hasLoadedOnce,
            failures: store.failures(),
            lastUpdated: store.lastUpdated
        ) {
            Text("\(overview.online)/\(overview.total) devices online")
            if overview.offlineOver24h > 0 {
                Label("\(overview.offlineOver24h) offline for more than 24 h", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            }
            if overview.keysExpiringSoon > 0 {
                Label("\(overview.keysExpiringSoon) keys expiring within 14 days", systemImage: "key")
                    .foregroundStyle(.orange)
            }
            if overview.keysExpired > 0 {
                Label("\(overview.keysExpired) expired keys", systemImage: "key.slash")
                    .foregroundStyle(.red)
            }
        }
    }
}

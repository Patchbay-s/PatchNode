import SwiftUI
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit

struct ObservabilityView: View {
    @Environment(ObservabilityStore.self) private var store
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval

    var body: some View {
        List {
            serviceErrors
            alertsSection
            targetsSection
            ForEach(store.inventory.pages) { item in
                UptimeKumaSection(item: item)
            }
            moreSection
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle("Observability")
        .overlay {
            if !store.hasLoadedOnce && store.isRefreshing {
                ProgressView("Loading…")
            }
        }
        .tabBarClearance()
        .refreshable { await store.refresh(force: true) }
        .polling(every: refreshInterval) { await store.refresh(ifOlderThan: max(refreshInterval - 5, 5)) }
    }

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

    private var alertsSection: some View {
        Section {
            if store.inventory.alerts.isEmpty {
                Group {
                    if store.hasLoadedOnce {
                        Label("No active alerts.", systemImage: "checkmark.seal")
                    } else {
                        Text("Not loaded yet.")
                    }
                }
                .foregroundStyle(.secondary)
            }
            ForEach(store.inventory.alerts) { item in
                AlertRow(item: item, showsService: store.services.count > 1)
            }
        } header: {
            Text("Active alerts")
        }
    }

    @ViewBuilder
    private var targetsSection: some View {
        let overview = store.inventory.overview
        if overview.targetsTotal > 0 {
            Section {
                ForEach(store.inventory.downTargets) { item in
                    TargetRow(target: item.target)
                }
                NavigationLink {
                    TargetsView()
                } label: {
                    Text("\(overview.targetsTotal - overview.targetsDown)/\(overview.targetsTotal) targets up")
                }
            } header: {
                Text("Prometheus targets")
            }
        }
    }

    private var moreSection: some View {
        Section {
            if !store.prometheusServices.isEmpty {
                NavigationLink {
                    PromQLFavoritesView()
                } label: {
                    Label("PromQL charts", systemImage: "chart.xyaxis.line")
                }
            }
            if !store.inventory.dashboards.isEmpty {
                NavigationLink {
                    GrafanaDashboardsView()
                } label: {
                    Label("Grafana dashboards", systemImage: "square.grid.3x3")
                }
            }
        }
    }
}

struct AlertRow: View {
    let item: ObservabilityInventory.AlertItem
    let showsService: Bool

    var body: some View {
        let alert = item.alert
        HStack(alignment: .top, spacing: 12) {
            SeverityIcon(severity: alert.severity)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: alert.name).font(.headline)
                if let summary = alert.summary, !summary.isEmpty {
                    Text(verbatim: summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 6) {
                    Text(verbatim: sourceName(alert.source))
                    if showsService {
                        Text(verbatim: "· \(item.serviceName)")
                    }
                    if let since = alert.since {
                        Text("since \(since, style: .relative)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sourceName(_ source: ObservabilityAlert.Source) -> String {
        switch source {
        case .alertmanager: "Alertmanager"
        case .grafana: "Grafana"
        case .prometheus: "Prometheus"
        case .uptimeKuma: "Uptime Kuma"
        }
    }
}

struct SeverityIcon: View {
    let severity: ObservabilityAlert.Severity

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch severity {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var color: Color {
        switch severity {
        case .critical: .red
        case .warning: .orange
        case .info: .blue
        }
    }

    private var label: Text {
        switch severity {
        case .critical: Text("Critical")
        case .warning: Text("Warning")
        case .info: Text("Information")
        }
    }
}

struct TargetRow: View {
    let target: PrometheusTarget

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: target.health == .up ? "checkmark.circle.fill" : target.health == .down ? "xmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(target.health == .up ? Color.green : target.health == .down ? Color.red : Color.secondary)
                .accessibilityLabel(target.health == .up ? Text("Target up") : target.health == .down ? Text("Target down") : Text("Target state unknown"))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: target.instance)
                Text(verbatim: target.job)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = target.lastError {
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        }
    }
}

struct TargetsView: View {
    @Environment(ObservabilityStore.self) private var store

    var body: some View {
        List(store.inventory.targets) { item in
            TargetRow(target: item.target)
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle("Prometheus targets")
        .refreshable { await store.refresh(force: true) }
    }
}

struct UptimeKumaSection: View {
    let item: ObservabilityInventory.PageItem

    var body: some View {
        Section {
            if item.page.monitors.isEmpty {
                Text("No monitors on this status page.")
                    .foregroundStyle(.secondary)
            }
            ForEach(item.page.monitors) { monitor in
                MonitorRow(monitor: monitor)
            }
        } header: {
            Text(verbatim: item.page.title)
        }
    }
}

struct MonitorRow: View {
    let monitor: UptimeKumaPage.Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(Self.color(monitor.status))
                    .frame(width: 10, height: 10)
                Text(verbatim: monitor.name)
                Spacer()
                if let uptime = monitor.uptime24h {
                    Text("\(Format.percent(uptime)) (24 h)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !monitor.recentStatuses.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(monitor.recentStatuses.enumerated()), id: \.offset) { _, status in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Self.color(status))
                            .frame(width: 5, height: 14)
                    }
                }
                .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                if let ping = monitor.lastPing {
                    Text(verbatim: "\(Int(ping.rounded())) ms")
                }
                if let beat = monitor.lastBeat {
                    Text(beat, style: .relative)
                }
                if monitor.status == .down, let message = monitor.lastMessage {
                    Text(verbatim: message).foregroundStyle(.red).lineLimit(2)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    static func color(_ status: UptimeKumaPage.Monitor.Status?) -> Color {
        switch status {
        case .up: .green
        case .down: .red
        case .pending: .orange
        case .maintenance: .blue
        case nil: .gray
        }
    }
}

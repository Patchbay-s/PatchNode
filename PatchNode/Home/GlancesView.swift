import SwiftUI
import PatchNodeCore
import HomeServicesKit

/// Glances hosts: CPU, memory, load, file systems, temperatures.
struct GlancesView: View {
    @Environment(HomeStore.self) private var store
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval

    var body: some View {
        List {
            ServiceErrorsSection(services: store.services(of: .glances), states: store.states, pauses: store.pauses)
            ForEach(store.inventory.glances) { item in
                GlancesHostSections(item: item)
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle(Text(verbatim: "Glances"))
        .tabBarClearance()
        .overlay {
            if !store.hasLoadedOnce && store.isRefreshing {
                ProgressView("Loading…")
            }
        }
        .refreshable { await store.refresh(force: true) }
        .polling(every: refreshInterval) { await store.refresh(ifOlderThan: max(refreshInterval - 5, 5)) }
    }
}

private struct GlancesHostSections: View {
    let item: HomeServicesInventory.GlancesItem

    var body: some View {
        let summary = item.summary
        Section {
            if let system = summary.system {
                LabeledContent("System") { Text(verbatim: system) }
            }
            if let uptime = summary.uptime {
                LabeledContent("Uptime") { Text(verbatim: uptime) }
            }
            GaugeRow(title: Text("CPU"), percent: summary.cpuPercent, alert: 90)
            GaugeRow(title: Text("Memory"), percent: summary.memoryPercent, alert: GlancesSummary.memoryAlertPercent)
            if summary.memoryTotal != nil {
                LabeledContent("Memory used", value: Format.usage(summary.memoryUsed, of: summary.memoryTotal))
            }
            if summary.swapPercent != nil {
                GaugeRow(title: Text("Swap"), percent: summary.swapPercent, alert: 80)
            }
            if let load1 = summary.load1 {
                LabeledContent("Load") {
                    Text(verbatim: [load1, summary.load5, summary.load15]
                        .compactMap { $0?.formatted(.number.precision(.fractionLength(2))) }
                        .joined(separator: " · "))
                        .monospacedDigit()
                }
            }
        } header: {
            Text(verbatim: summary.hostname.map { "\(item.serviceName) · \($0)" } ?? item.serviceName)
        }
        if !summary.fileSystems.isEmpty {
            Section("File systems") {
                ForEach(summary.fileSystems) { fileSystem in
                    VStack(alignment: .leading, spacing: 4) {
                        GaugeRow(title: Text(verbatim: fileSystem.mountPoint), percent: fileSystem.percent, alert: GlancesSummary.diskAlertPercent)
                        Text(Format.usage(fileSystem.used, of: fileSystem.size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !summary.temperatures.isEmpty {
            Section("Temperatures") {
                ForEach(summary.temperatures) { sensor in
                    LabeledContent {
                        Text(verbatim: "\(Int(sensor.value.rounded())) °\(sensor.unit ?? "C")")
                            .monospacedDigit()
                    } label: {
                        Text(verbatim: sensor.label)
                    }
                }
            }
        }
    }
}

/// A label, its percentage and a bar that turns orange above `alert`.
private struct GaugeRow: View {
    let title: Text
    /// 0…100.
    let percent: Double?
    let alert: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                title
                Spacer()
                Text(Format.percent(percent.map { $0 / 100 }))
                    .monospacedDigit()
                    .foregroundStyle((percent ?? 0) >= alert ? Color.orange : Color.secondary)
            }
            if let percent {
                ProgressView(value: min(max(percent / 100, 0), 1))
                    .tint(percent >= alert ? Color.orange : Color.accentColor)
            }
        }
    }
}

struct GlancesCard: View {
    let store: HomeStore

    var body: some View {
        DashboardCardShell(
            title: Text(verbatim: "Glances"),
            systemImage: "gauge.with.dots.needle.33percent",
            level: store.level(of: .glances),
            hasLoadedOnce: store.hasLoadedOnce,
            failures: store.failures(kind: .glances),
            lastUpdated: store.lastUpdated
        ) {
            ForEach(store.inventory.glances) { item in
                let summary = item.summary
                HStack {
                    Text(verbatim: summary.hostname ?? item.serviceName).lineLimit(1)
                    Spacer()
                    Text("CPU \(Format.percent(summary.cpuPercent.map { $0 / 100 })) · RAM \(Format.percent(summary.memoryPercent.map { $0 / 100 }))")
                        .monospacedDigit()
                }
                ForEach(summary.fullFileSystems) { fileSystem in
                    Label("\(fileSystem.mountPoint) at \(Format.percent(fileSystem.percent.map { $0 / 100 }))", systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

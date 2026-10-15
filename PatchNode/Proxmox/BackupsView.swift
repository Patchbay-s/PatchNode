import SwiftUI
import PatchNodeCore
import ProxmoxKit

/// Proxmox Backup Server: datastores, latest backup per guest, recent tasks.
struct BackupsView: View {
    @Environment(BackupStore.self) private var store
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval

    var body: some View {
        List {
            ServiceErrorsSection(services: store.services, states: store.states, pauses: store.pauses)
            datastoresSection
            backupsSection
            tasksSection
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle(Text(verbatim: "Proxmox Backup Server"))
        .navigationBarTitleDisplayMode(.inline)
        .tabBarClearance()
        .overlay {
            if !store.hasLoadedOnce && store.isRefreshing {
                ProgressView("Loading…")
            }
        }
        .refreshable { await store.refresh(force: true) }
        .polling(every: refreshInterval) { await store.refresh(ifOlderThan: max(refreshInterval - 5, 5)) }
    }

    private var datastoresSection: some View {
        Section("Datastores") {
            if store.inventory.datastores.isEmpty {
                (store.hasLoadedOnce ? Text("No datastores.") : Text("Not loaded yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(store.inventory.datastores) { item in
                let datastore = item.datastore
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(verbatim: datastore.name).font(.headline)
                        Spacer()
                        Text(Format.percent(datastore.usage))
                            .monospacedDigit()
                            .foregroundStyle((datastore.usage ?? 0) >= PBSInventory.storageAlertThreshold ? Color.orange : Color.secondary)
                    }
                    if let usage = datastore.usage {
                        ProgressView(value: usage)
                            .tint((datastore.usage ?? 0) >= PBSInventory.storageAlertThreshold ? Color.orange : Color.accentColor)
                    }
                    Text(Format.usage(datastore.used, of: datastore.total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if store.services.count > 1 {
                        Text(verbatim: item.serviceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var backupsSection: some View {
        Section {
            if store.hasLoadedOnce && store.inventory.lastBackups.isEmpty {
                Text("No backups found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.inventory.lastBackups) { backup in
                let stale = backup.type != .host && Date.now.timeIntervalSince(backup.date) > PBSInventory.staleBackupAge
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(label(for: backup.type)) \(backup.backupID)")
                        Text(verbatim: backup.datastore)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(backup.date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(stale ? Color.orange : Color.secondary)
                }
            }
        } header: {
            Text("Latest backup per guest")
        } footer: {
            Text("Shown in orange when the latest backup is older than 2 days.")
        }
    }

    private var tasksSection: some View {
        Section("Recent tasks") {
            ForEach(store.inventory.tasks.prefix(50)) { item in
                let task = item.task
                HStack(alignment: .top) {
                    TaskStateIcon(task: task)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: task.targetID.map { "\(task.type) · \($0)" } ?? task.type)
                        if case .failed(let message) = task.state {
                            Text(verbatim: message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                    Spacer()
                    if let start = task.startTime {
                        Text(start, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func label(for type: PBSBackupGroup.BackupType) -> String {
        switch type {
        case .vm: "VM"
        case .ct: "CT"
        case .host: String(localized: "Host")
        }
    }
}

private struct TaskStateIcon: View {
    let task: ProxmoxTask

    var body: some View {
        switch task.state {
        case .running:
            Image(systemName: "hourglass").foregroundStyle(.blue)
                .accessibilityLabel(Text("Task running"))
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel(Text("Task succeeded"))
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .accessibilityLabel(Text("Task finished with warnings"))
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                .accessibilityLabel(Text("Task failed"))
        }
    }
}

struct BackupsCard: View {
    let store: BackupStore

    var body: some View {
        let overview = store.inventory.overview
        DashboardCardShell(
            title: Text(verbatim: "Proxmox Backup Server"),
            systemImage: "externaldrive.badge.timemachine",
            level: store.level,
            hasLoadedOnce: store.hasLoadedOnce,
            failures: store.failures(),
            lastUpdated: store.lastUpdated
        ) {
            Text("\(overview.guestsBackedUp) guests backed up")
            if let latest = overview.latestBackup {
                Text("Latest backup \(latest, format: .relative(presentation: .named))")
            }
            if overview.succeededBackups24h > 0 {
                Text("\(overview.succeededBackups24h) backups in the last 24 h")
            }
            if overview.failedTasks24h > 0 {
                Label("\(overview.failedTasks24h) failed tasks in the last 24 h", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            }
            if overview.staleBackups > 0 {
                Label("\(overview.staleBackups) guests without a backup for 2 days", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            if overview.datastoresAboveThreshold > 0 {
                Label("\(overview.datastoresAboveThreshold) datastores above 85 %", systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
        }
    }
}

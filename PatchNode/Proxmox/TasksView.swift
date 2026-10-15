import SwiftUI
import ProxmoxKit
import PatchNodeCore
import DockerKit

struct TasksView: View {
    @Environment(ProxmoxStore.self) private var store
    @State private var failuresOnly = false

    /// Enough for "recent" without building a huge list.
    static let displayLimit = 200

    var body: some View {
        List {
            Toggle("Failures only", isOn: $failuresOnly)
            // Secondary endpoint: its failure leaves the service up.
            ForEach(store.services.filter { store.inventory.tasksUnavailableServiceIDs.contains($0.id) }) { service in
                Label("\(service.name): task list unavailable at the last refresh.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            let tasks = visibleTasks
            if tasks.isEmpty {
                Text("No recent tasks.")
                    .foregroundStyle(.secondary)
            }
            ForEach(tasks) { item in
                TaskRow(task: item.task, serviceName: store.services.count > 1 ? item.serviceName : "")
                    .listRowBackground(item.task.isFailed ? Color.red.opacity(0.12) : nil)
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle("Recent tasks")
        .refreshable { await store.refresh(force: true) }
    }

    private var visibleTasks: [ProxmoxInventory.TaskItem] {
        let tasks = failuresOnly ? store.inventory.tasks.filter(\.task.isFailed) : store.inventory.tasks
        return Array(tasks.prefix(Self.displayLimit))
    }
}

struct TaskRow: View {
    let task: ProxmoxTask
    /// Shown when several Proxmox services are configured (homonymous nodes).
    var serviceName: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            stateIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                switch task.state {
                case .failed(let message), .warning(let message):
                    Text(verbatim: message)
                        .font(.caption)
                        .foregroundStyle(task.isFailed ? Color.red : Color.orange)
                default:
                    EmptyView()
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let start = task.startTime {
                    Text(start, style: .relative)
                }
                Text(Format.duration(task.duration()))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        let name = Self.friendlyName(for: task.type)
        guard let target = task.targetID else { return name }
        return "\(name) · \(target)"
    }

    private var subtitle: String {
        [serviceName.isEmpty ? nil : serviceName, task.node, task.user].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch task.state {
        case .running:
            ProgressView()
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

    /// Common Proxmox task types; anything else is shown as-is.
    static func friendlyName(for type: String) -> String {
        switch type {
        case "vzdump": String(localized: "Backup")
        case "qmstart", "vzstart": String(localized: "Start")
        case "qmstop", "vzstop": String(localized: "Stop")
        case "qmshutdown", "vzshutdown": String(localized: "Shutdown")
        case "qmreboot", "vzreboot": String(localized: "Reboot")
        case "qmigrate", "vzmigrate": String(localized: "Migration")
        case "qmclone", "vzclone": String(localized: "Clone")
        case "qmsnapshot", "vzsnapshot": String(localized: "Snapshot")
        case "aptupdate": String(localized: "Package update check")
        default: type
        }
    }
}

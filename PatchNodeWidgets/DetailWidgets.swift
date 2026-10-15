import WidgetKit
import SwiftUI
import PatchNodeCore

/// CPU and memory of the Proxmox nodes (home screen only).
struct ProxmoxNodesWidget: Widget {
    let kind = "PatchNodeProxmoxNodes"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            ProxmoxNodesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Proxmox nodes")
        .description("CPU and memory of each node.")
        .supportedFamilies([.systemMedium])
    }
}

struct ProxmoxNodesView: View {
    let entry: SnapshotEntry
    static let maxRows = 4

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(verbatim: "Proxmox")
                } icon: {
                    Image(systemName: "server.rack")
                }
                .font(.caption.bold())
                .widgetAccentable()
                if snapshot.nodes.isEmpty {
                    Text("No Proxmox node.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.nodes.prefix(Self.maxRows)) { node in
                    NodeLoadRow(node: node)
                }
                Spacer(minLength: 0)
                DataAgeFooter(entry: entry)
            }
        } else {
            NoDataView()
        }
    }
}

private struct NodeLoadRow: View {
    let node: SharedSnapshot.NodeLoad

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(node.isOnline ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(verbatim: node.title)
                .font(.caption)
                .lineLimit(1)
                .privacySensitive()
            Spacer(minLength: 4)
            if node.isOnline {
                LoadBar(title: "CPU", value: node.cpu)
                LoadBar(title: "RAM", value: node.memory)
            } else {
                Text("Offline").font(.caption2).foregroundStyle(.red)
            }
        }
    }
}

private struct LoadBar: View {
    let title: String
    /// 0…1.
    let value: Double?

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            ProgressView(value: min(max(value ?? 0, 0), 1))
                .frame(width: 36)
                .tint((value ?? 0) > 0.85 ? Color.red : (value ?? 0) > 0.7 ? Color.orange : Color.accentColor)
            Text(verbatim: value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                .font(.system(size: 9).monospacedDigit())
                .frame(width: 28, alignment: .trailing)
        }
    }
}

/// Stopped, exited or unhealthy containers (home screen only).
struct ContainerIssuesWidget: Widget {
    let kind = "PatchNodeContainerIssues"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            ContainerIssuesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Containers to check")
        .description("Stopped, exited or unhealthy Docker containers.")
        .supportedFamilies([.systemMedium])
    }
}

struct ContainerIssuesView: View {
    let entry: SnapshotEntry
    static let maxRows = 5

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(verbatim: "Docker")
                } icon: {
                    Image(systemName: "shippingbox")
                }
                .font(.caption.bold())
                .widgetAccentable()
                if snapshot.containerIssues.isEmpty {
                    Label("All containers are running.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                ForEach(snapshot.containerIssues.prefix(Self.maxRows)) { issue in
                    HStack(spacing: 6) {
                        Image(systemName: Self.symbol(issue.kind))
                            .foregroundStyle(Self.color(issue.kind))
                            .font(.caption)
                        Text(verbatim: issue.name)
                            .font(.caption)
                            .lineLimit(1)
                            .privacySensitive()
                        Spacer(minLength: 4)
                        Text(verbatim: issue.host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
                if snapshot.containerIssues.count > Self.maxRows {
                    Text("+\(snapshot.containerIssues.count - Self.maxRows) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                DataAgeFooter(entry: entry)
            }
        } else {
            NoDataView()
        }
    }

    static func symbol(_ kind: SharedSnapshot.ContainerIssue.Kind) -> String {
        switch kind {
        case .unhealthy: "heart.slash.fill"
        case .exitedWithError: "xmark.octagon.fill"
        case .restarting: "arrow.clockwise.circle.fill"
        case .stopped: "stop.circle"
        }
    }

    static func color(_ kind: SharedSnapshot.ContainerIssue.Kind) -> Color {
        switch kind {
        case .unhealthy, .exitedWithError: .red
        case .restarting: .orange
        case .stopped: .secondary
        }
    }
}

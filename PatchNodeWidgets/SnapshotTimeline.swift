import WidgetKit
import SwiftUI
import PatchNodeCore

// nonisolated: the target defaults to MainActor isolation, but WidgetKit calls
// the timeline provider off the main actor.

/// One moment of a widget: the snapshot the app last wrote (nil before the first
/// refresh, or while the App Group isn't enabled).
nonisolated struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?

    var isStale: Bool { snapshot?.isStale(at: date) ?? false }
}

/// Widgets never call the network: they read the file the app (or its background
/// refresh) wrote in the App Group container.
nonisolated struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = SharedSnapshotStore.appGroup()?.read()
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? (snapshot ?? .placeholder) : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let snapshot = SharedSnapshotStore.appGroup()?.read()
        var entries = [SnapshotEntry(date: now, snapshot: snapshot)]
        // A second entry flips the widget to "old data" when the hour is up.
        if let snapshot {
            let staleAt = snapshot.generatedAt.addingTimeInterval(SharedSnapshot.staleAge + 1)
            if staleAt > now { entries.append(SnapshotEntry(date: staleAt, snapshot: snapshot)) }
        }
        // The app reloads the timelines when the data changes; this is a slow fallback.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 60 * 60))))
    }
}

extension SharedSnapshot {
    /// Widget gallery preview: made-up figures, no real host.
    nonisolated static var placeholder: SharedSnapshot {
        SharedSnapshot(
            generatedAt: .now,
            families: [
                Family(id: "proxmox", title: "Proxmox", level: .ok, headline: "2/2"),
                Family(id: "docker", title: "Docker", level: .warning, headline: "18/20"),
                Family(id: "observability", title: "Observability", level: .ok, headline: "0"),
            ],
            nodes: [
                NodeLoad(id: "1", title: "Demo · node-a", isOnline: true, cpu: 0.18, memory: 0.52),
                NodeLoad(id: "2", title: "Demo · node-b", isOnline: true, cpu: 0.07, memory: 0.34),
            ],
            containerIssues: [
                ContainerIssue(id: "1", name: "service-01", host: "docker", kind: .unhealthy),
                ContainerIssue(id: "2", name: "service-02", host: "docker", kind: .exitedWithError),
            ]
        )
    }
}

// MARK: - Shared pieces

extension SharedSnapshot.Family.Level {
    var color: Color {
        switch self {
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        case .unknown: .gray
        }
    }

    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

/// "Updated 14:32", or "Old data · 14:32" in orange after an hour.
struct DataAgeFooter: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            HStack(spacing: 4) {
                if entry.isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text("Old data · \(snapshot.generatedAt, style: .time)")
                } else {
                    Text("Updated \(snapshot.generatedAt, style: .time)")
                }
            }
            .font(.caption2)
            .foregroundStyle(entry.isStale ? Color.orange : Color.secondary)
        }
    }
}

/// Nothing written by the app yet (never opened, or no App Group): a centered
/// icon and "Open PatchNode", sized for each family, never a large empty area.
struct NoDataView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Open PatchNode", systemImage: "server.rack")
        case .accessoryCircular:
            Image(systemName: "server.rack")
                .font(.title3)
                .accessibilityLabel(Text("Open PatchNode"))
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                Text("Open PatchNode")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            VStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Open PatchNode")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

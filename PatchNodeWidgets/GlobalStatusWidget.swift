import WidgetKit
import SwiftUI
import PatchNodeCore

/// Global state: the only widget offered on the lock screen, where it shows
/// counts only (no service, host or container name).
struct GlobalStatusWidget: Widget {
    let kind = "PatchNodeGlobalStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            GlobalStatusView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HomeLab status")
        .description("Services OK and in alert, with the time of the last data.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct GlobalStatusView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.families.isEmpty {
            switch family {
            case .accessoryCircular: circular(snapshot)
            case .accessoryRectangular: rectangular(snapshot)
            case .accessoryInline: inline(snapshot)
            default: small(snapshot)
            }
        } else {
            // Adapts to every family, lock screen included.
            NoDataView()
        }
    }

    private func small(_ snapshot: SharedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: snapshot.globalLevel.symbol)
                    .foregroundStyle(snapshot.globalLevel.color)
                    .font(.title2)
                    .widgetAccentable()
                Spacer()
                Text(verbatim: "PatchNode")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Text("\(snapshot.okCount) OK")
                .font(.title3.bold())
            if snapshot.alertCount > 0 {
                Text("\(snapshot.alertCount) in alert")
                    .font(.subheadline.bold())
                    .foregroundStyle(snapshot.globalLevel.color)
            }
            ForEach(snapshot.families.filter { $0.level == .warning || $0.level == .critical }.prefix(2)) { family in
                Text(verbatim: "• \(family.title)")
                    .font(.caption)
                    .lineLimit(1)
                    .privacySensitive()
            }
            Spacer(minLength: 0)
            DataAgeFooter(entry: entry)
        }
    }

    private func circular(_ snapshot: SharedSnapshot) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: snapshot.globalLevel.symbol)
                Text(verbatim: snapshot.alertCount > 0 ? "\(snapshot.alertCount)" : "OK")
                    .font(.caption.bold())
            }
        }
        .widgetAccentable()
    }

    private func rectangular(_ snapshot: SharedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(verbatim: "PatchNode")
            } icon: {
                Image(systemName: snapshot.globalLevel.symbol)
            }
            .font(.headline)
            .widgetAccentable()
            Text("\(snapshot.okCount) OK · \(snapshot.alertCount) in alert")
            if entry.isStale {
                Text("Old data · \(snapshot.generatedAt, style: .time)")
            } else {
                Text("Updated \(snapshot.generatedAt, style: .time)")
            }
        }
        .font(.caption)
    }

    private func inline(_ snapshot: SharedSnapshot) -> some View {
        Text("PatchNode: \(snapshot.okCount) OK · \(snapshot.alertCount) in alert")
    }
}

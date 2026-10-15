import SwiftUI
import MetricKit
import PatchNodeCore

/// Receives what iOS delivers through MetricKit (crashes, hangs, resource
/// exceptions, daily performance) and keeps it in `SystemReportArchive`, on this
/// device only. Nothing is sent anywhere.
final class MetricKitReceiver: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitReceiver()

    /// Once, at launch. Past payloads iOS still holds are read again; the
    /// archive drops the ones it already has.
    func start() {
        MXMetricManager.shared.add(self)
        // Off the main thread: the payloads (call stacks) are read and
        // converted after launch, and stored in one write at most.
        Task.detached(priority: .utility) {
            let manager = MXMetricManager.shared
            let diagnostics = manager.pastDiagnosticPayloads.map { $0.jsonRepresentation() }
            let metrics = manager.pastPayloads.map { $0.jsonRepresentation() }
            await SystemReportArchive.shared.add(diagnosticsJSONs: diagnostics, metricsJSONs: metrics)
        }
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let jsons = payloads.map { $0.jsonRepresentation() }
        Task.detached(priority: .utility) {
            for json in jsons { await SystemReportArchive.shared.add(metricsJSON: json) }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let jsons = payloads.map { $0.jsonRepresentation() }
        Task.detached(priority: .utility) {
            for json in jsons { await SystemReportArchive.shared.add(diagnosticsJSON: json) }
        }
    }
}

/// Settings › Diagnostics › iOS reports: what MetricKit delivered, readable,
/// each one shareable by the user.
struct SystemReportsView: View {
    @State private var reports: [SystemReport] = []
    @State private var confirmsDeletion = false

    var body: some View {
        List {
            Section {
                if reports.isEmpty {
                    Text("No report yet. iOS delivers them at most once a day, for the day before.")
                        .foregroundStyle(.secondary)
                }
                ForEach(reports) { report in
                    NavigationLink {
                        SystemReportDetailView(report: report)
                    } label: {
                        SystemReportRow(report: report)
                    }
                }
            } footer: {
                Text("Crashes, hangs and performance figures iOS gives the app, kept on this iPhone for 30 days. Nothing is sent automatically: share a report yourself, or attach a summary of the crashes when you contact support.")
            }
            if !reports.isEmpty {
                Section {
                    Button("Delete all reports", systemImage: "trash", role: .destructive) {
                        confirmsDeletion = true
                    }
                }
            }
        }
        .readableWidth()
        .navigationTitle("iOS reports")
        .task { reports = await SystemReportArchive.shared.reports() }
        .refreshable { reports = await SystemReportArchive.shared.reports() }
        .confirmationDialog("Delete all iOS reports?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete all reports", role: .destructive) {
                Task {
                    await SystemReportArchive.shared.removeAll()
                    reports = await SystemReportArchive.shared.reports()
                }
            }
        }
    }
}

private struct SystemReportRow: View {
    let report: SystemReport

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(SystemReportsView.title(report.kind))
                Text(report.receivedAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let app = report.appVersion {
                    Text(verbatim: "PatchNode \(app)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: SystemReportsView.symbol(report.kind))
                .foregroundStyle(report.kind == .crash || report.kind == .hang ? .orange : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SystemReportDetailView: View {
    let report: SystemReport

    var body: some View {
        List {
            Section {
                LabeledContent("Received") {
                    Text(report.receivedAt, format: .dateTime.day().month().year().hour().minute())
                }
                if let app = report.appVersion {
                    LabeledContent("App") { Text(verbatim: app) }
                }
                if let os = report.osVersion {
                    LabeledContent("iOS") { Text(verbatim: os) }
                }
            }
            if !report.details.isEmpty {
                Section {
                    ForEach(report.details, id: \.self) { detail in
                        LabeledContent {
                            Text(verbatim: detail.value).textSelection(.enabled)
                        } label: {
                            Text(verbatim: detail.label)
                        }
                    }
                } footer: {
                    Text("Technical details as iOS reports them, in English.")
                }
            }
        }
        .readableWidth()
        .navigationTitle(SystemReportsView.title(report.kind))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: SystemReportText.shareText(report)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

extension SystemReportsView {
    static func title(_ kind: SystemReport.Kind) -> LocalizedStringKey {
        switch kind {
        case .crash: "Crash"
        case .hang: "Hang"
        case .cpuException: "High CPU use"
        case .diskWriteException: "Heavy disk writes"
        case .launch: "Slow launch"
        case .performance: "Daily performance"
        }
    }

    static func symbol(_ kind: SystemReport.Kind) -> String {
        switch kind {
        case .crash: "exclamationmark.octagon"
        case .hang: "hourglass"
        case .cpuException: "cpu"
        case .diskWriteException: "internaldrive"
        case .launch: "timer"
        case .performance: "chart.bar"
        }
    }
}

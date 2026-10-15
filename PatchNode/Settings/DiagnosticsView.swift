import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PatchNodeCore

/// Settings > Diagnostics: state of each service and the last 200 requests (kept
/// in memory only, no secret), to understand intermittent failures.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var entries: [RequestLog.Entry] = []
    @State private var loadedVersion: Int?
    @State private var sharedText = ""
    @State private var widgetCache: WidgetCacheStatus?
    @State private var serviceFilter: String?
    @State private var copied = false

    private let log = RequestLog.shared

    var body: some View {
        List {
            Section {
                ForEach(model.stores.flatMap { store in store.services.map { (store, $0) } }, id: \.1.id) { store, service in
                    ServiceDiagnosticRow(
                        service: service,
                        state: store.states[service.id],
                        pause: store.pause(for: service.id)
                    )
                }
            } header: {
                Text("Services")
            }

            Section {
                NavigationLink {
                    SystemReportsView()
                } label: {
                    Label("iOS reports", systemImage: "doc.text.magnifyingglass")
                }
            } footer: {
                Text("Crashes, hangs and performance figures from iOS, kept on this iPhone only.")
            }

            Section {
                WidgetCacheRow(status: widgetCache)
            } footer: {
                Text("The summary the widgets and Siri read, written by the app after each refresh.")
            }

            Section {
                if visibleEntries.isEmpty {
                    Text("No request yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(visibleEntries.reversed()) { entry in
                    RequestLogRow(entry: entry)
                }
            } header: {
                Text("Last requests (newest first)")
            } footer: {
                Text("Kept in memory only (last 200), lost when the app quits. No token, body, host or query value is recorded: the service name, method, API path, status, timing, connection details, content type and server software.")
            }
        }
        .readableWidth()
        .navigationTitle("Diagnostics")
        .onChange(of: serviceFilter) { sharedText = exportText }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Service", systemImage: "line.3.horizontal.decrease") {
                    Picker("Service", selection: $serviceFilter) {
                        Text("All services").tag(String?.none)
                        ForEach(serviceNames, id: \.self) { name in
                            Text(verbatim: name).tag(String?.some(name))
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button(copied ? "Copied" : "Copy", systemImage: "doc.on.doc") {
                        // This device only (no Universal Clipboard), gone after 2 min.
                        UIPasteboard.general.setItems(
                            [[UTType.plainText.identifier: exportText]],
                            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)]
                        )
                        copied = true
                    }
                    // Text rebuilt when the log changes, not on every render.
                    ShareLink(item: sharedText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button("Clear", systemImage: "trash", role: .destructive) {
                        log.clear()
                        entries = []
                        loadedVersion = log.version
                        sharedText = exportText
                    }
                }
            }
        }
        // Live while on screen; the list is rebuilt only when the log changed.
        .task {
            widgetCache = SharedSnapshotStore.currentStatus()
            while !Task.isCancelled {
                let version = log.version
                if version != loadedVersion {
                    loadedVersion = version
                    entries = log.entries()
                    sharedText = exportText
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var visibleEntries: [RequestLog.Entry] {
        guard let serviceFilter else { return entries }
        return entries.filter { $0.serviceName == serviceFilter || $0.serviceID == nil }
    }

    private var serviceNames: [String] {
        Array(Set(entries.compactMap { $0.serviceID == nil ? nil : $0.serviceName })).sorted()
    }

    /// Services' state, then the requests, oldest first.
    private var exportText: String {
        let now = Date.now
        let states = model.stores.flatMap { store in
            store.services.map { service -> String in
                var line = "[\(service.name)] \(service.kind.rawValue): \(store.states[service.id].map { "\($0)" } ?? "not loaded")"
                if service.kind.hasOwnCertificate, let expiry = CertificateRegistry.shared.expiry(for: service.url, now: now) {
                    // Days only: an exact expiry date could be looked up in the public
                    // Certificate Transparency logs and reveal the user's domain.
                    line += ", certificate expires in \(expiry.daysRemaining(now: now)) d"
                }
                if let pause = store.pause(for: service.id) {
                    let until = pause.resumeAt.map { "resumes in \(Int(max($0.timeIntervalSince(now), 0))) s" } ?? "until pull to refresh"
                    line += ", paused (\(pause.reason.rawValue), strike \(pause.strikes)), \(until)"
                }
                return line
            }
        }
        let cache: String = switch widgetCache {
        case nil: "Widgets cache: not read"
        case .appGroupMissing: "Widgets cache: App Group missing"
        case .empty: "Widgets cache: not written"
        case let .written(date, families, nodes, guests, containers):
            "Widgets cache: written \(date.formatted(.iso8601)), \(families) cards, \(nodes) nodes, \(guests) guests, \(containers) containers"
        }
        return (["PatchNode diagnostics \(now.formatted(.iso8601))", cache] + states + [""] + visibleEntries.map(\.logLine))
            .joined(separator: "\n")
    }
}

/// "Widgets cache": when the app last wrote the widgets' summary and what it holds.
private struct WidgetCacheRow: View {
    let status: WidgetCacheStatus?

    var body: some View {
        LabeledContent {
            switch status {
            case nil:
                ProgressView()
            case .appGroupMissing:
                Text("App Group missing").foregroundStyle(.red)
            case .empty:
                Text("Not written yet").foregroundStyle(.secondary)
            case let .written(date, families, nodes, guests, containers):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(date, format: .relative(presentation: .named))
                    Text("\(families) cards · \(nodes) nodes · \(guests) VMs/CTs · \(containers) containers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Widgets cache", systemImage: "square.stack.3d.up")
        }
    }
}

private struct ServiceDiagnosticRow: View {
    let service: ServiceDescriptor
    let state: ServiceLoadState?
    let pause: ServicePauses.Pause?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: service.name).font(.headline)
                Spacer()
                Text(verbatim: state.map { "\($0)" } ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(state?.isFailure == true ? .red : .secondary)
            }
            CertificateDiagnosticLine(service: service)
            if let pause {
                if let resumeAt = pause.resumeAt, resumeAt > .now {
                    Text("Paused (\(pause.reason.rawValue), \(pause.strikes)×), resumes in \(Text(timerInterval: Date.now...resumeAt, countsDown: true))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if pause.resumeAt != nil {
                    Text("Pause over: asked again at the next refresh")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Paused (\(pause.reason.rawValue)) until a pull to refresh")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

private struct RequestLogRow: View {
    let entry: RequestLog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(verbatim: entry.serviceName)
                    .font(.caption.bold())
                Spacer()
                badge
            }
            switch entry.kind {
            case .request(let request):
                Text(verbatim: "\(request.method) \(request.path)")
                    .font(.caption.monospaced())
                    .lineLimit(2)
                Text(verbatim: details(request))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            case .event:
                Text(verbatim: entry.logLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        switch entry.kind {
        case .request(let request):
            Text(verbatim: request.statusCode.map(String.init) ?? request.outcome.rawValue)
                .font(.caption.monospaced().bold())
                .foregroundStyle(color(request.outcome))
        case .event(let event):
            switch event {
            case .paused: Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            case .resumed: Image(systemName: "play.circle.fill").foregroundStyle(.green)
            case .sessionsReset: Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
            case .terminalOpened: Image(systemName: "terminal").foregroundStyle(.blue)
            case .guestsNoLongerListed: Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
            case .terminalEnded(_, _, let reason):
                if case .failed = reason {
                    Image(systemName: "terminal").foregroundStyle(.red)
                } else {
                    Image(systemName: "terminal").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func details(_ r: RequestLog.Request) -> String {
        var parts = [r.outcome.rawValue, "#\(r.attempt)", "\(Int((r.duration * 1000).rounded())) ms"]
        if let proto = r.networkProtocol { parts.append(proto) }
        if let reused = r.reusedConnection { parts.append(reused ? "reused" : "new-conn") }
        if let port = r.localPort { parts.append("lport \(port)") }
        if r.freshConnection { parts.append("fresh-session") }
        if case .resumeProbe(let attempt) = r.context { parts.append("resume-probe #\(attempt)") }
        if let server = r.server { parts.append("server \(server)") }
        if let type = r.contentType { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    private func color(_ outcome: RequestLog.Outcome) -> Color {
        switch outcome {
        case .ok: .green
        case .cancelled: .secondary
        case .misdirected, .httpStatus, .timedOut, .connectionLost: .orange
        default: .red
        }
    }
}

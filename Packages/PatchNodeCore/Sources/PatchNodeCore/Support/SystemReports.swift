import Foundation

/// A report iOS delivered through MetricKit (crash, hang, resource exception,
/// launch or daily performance), kept on this device only. Nothing is ever sent
/// automatically: the user can read it, share it, or attach a summary of the
/// crashes to a support e-mail they write themselves.
public struct SystemReport: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case crash
        case hang
        case cpuException
        case diskWriteException
        case launch
        case performance
    }

    /// One readable line of the report: a technical label and a short value,
    /// already cleaned by `SystemReportText.clean`.
    public struct Detail: Sendable, Hashable, Codable {
        public let label: String
        public let value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public let id: UUID
    public let kind: Kind
    public let receivedAt: Date
    /// The period iOS covers (a day for performance reports).
    public let periodStart: Date?
    public let periodEnd: Date?
    public let appVersion: String?
    public let osVersion: String?
    public let details: [Detail]
    /// The JSON iOS produced for this entry (call stacks, metadata), capped, for
    /// a user who shares the full report. Never part of the support summary.
    public let rawJSON: Data?
    /// Identifies the same diagnostic delivered twice (MetricKit's past
    /// payloads, read again at each launch). Computed once, on the full JSON.
    public let fingerprint: String

    public init(
        id: UUID = UUID(), kind: Kind, receivedAt: Date, periodStart: Date?, periodEnd: Date?,
        appVersion: String?, osVersion: String?, details: [Detail], rawJSON: Data?, contentHash: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.receivedAt = receivedAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.details = details
        self.rawJSON = rawJSON
        fingerprint = "\(kind.rawValue)|\(periodStart?.timeIntervalSince1970 ?? 0)|\(periodEnd?.timeIntervalSince1970 ?? 0)|\(contentHash)"
    }
}

/// Turns MetricKit's JSON (`MXDiagnosticPayload` / `MXMetricPayload`
/// `jsonRepresentation()`) into reports. Lenient: unknown or missing keys are
/// skipped, a broken payload gives no report.
public enum SystemReportParser {
    /// Per entry, at most this much of the original JSON is kept.
    public static let maxRawBytes = 64 * 1024

    public static func diagnostics(from json: Data, receivedAt: Date) -> [SystemReport] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [] }
        let start = date(root["timeStampBegin"])
        let end = date(root["timeStampEnd"])
        let sections: [(String, SystemReport.Kind)] = [
            ("crashDiagnostics", .crash),
            ("hangDiagnostics", .hang),
            ("cpuExceptionDiagnostics", .cpuException),
            ("diskWriteExceptionDiagnostics", .diskWriteException),
            ("appLaunchDiagnostics", .launch),
        ]
        var reports: [SystemReport] = []
        for (key, kind) in sections {
            for entry in root[key] as? [[String: Any]] ?? [] {
                let meta = entry["diagnosticMetaData"] as? [String: Any] ?? [:]
                var details: [SystemReport.Detail] = []
                for (label, metaKey) in [
                    ("Exception type", "exceptionType"), ("Exception code", "exceptionCode"), ("Signal", "signal"),
                    ("Termination reason", "terminationReason"), ("Hang duration", "hangDuration"),
                    ("CPU time", "totalCPUTime"), ("Sampled time", "totalSampledTime"),
                    ("Writes caused", "writesCaused"), ("Launch duration", "launchDuration"),
                    ("Device", "deviceType"), ("Architecture", "platformArchitecture"),
                ] {
                    if let value = text(meta[metaKey]) {
                        details.append(.init(label, SystemReportText.clean(value)))
                    }
                }
                let (rawJSON, hash) = raw(entry)
                reports.append(SystemReport(
                    kind: kind, receivedAt: receivedAt, periodStart: start, periodEnd: end,
                    appVersion: appVersion(meta), osVersion: text(meta["osVersion"]).map { SystemReportText.clean($0) },
                    details: details, rawJSON: rawJSON, contentHash: hash
                ))
            }
        }
        return reports
    }

    /// One performance report per payload, with the few figures worth reading.
    public static func metrics(from json: Data, receivedAt: Date) -> SystemReport? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let meta = root["metaData"] as? [String: Any] ?? [:]
        var details: [SystemReport.Detail] = []
        let paths: [(String, [String])] = [
            ("Peak memory", ["memoryMetrics", "peakMemoryUsage"]),
            ("CPU time", ["cpuMetrics", "cumulativeCPUTime"]),
            ("Foreground time", ["applicationTimeMetrics", "cumulativeForegroundTime"]),
            ("Background time", ["applicationTimeMetrics", "cumulativeBackgroundTime"]),
            ("Cellular data", ["networkTransferMetrics", "cumulativeCellularDownload"]),
            ("Wi-Fi data", ["networkTransferMetrics", "cumulativeWifiDownload"]),
            ("Disk writes", ["diskIOMetrics", "cumulativeLogicalWrites"]),
        ]
        for (label, path) in paths {
            var node: Any? = root
            for key in path { node = (node as? [String: Any])?[key] }
            if let value = text(node) { details.append(.init(label, SystemReportText.clean(value))) }
        }
        guard !details.isEmpty || !meta.isEmpty else { return nil }
        let (rawJSON, hash) = raw(root)
        return SystemReport(
            kind: .performance, receivedAt: receivedAt, periodStart: date(root["timeStampBegin"]), periodEnd: date(root["timeStampEnd"]),
            appVersion: appVersion(meta), osVersion: text(meta["osVersion"]).map { SystemReportText.clean($0) },
            details: details, rawJSON: rawJSON, contentHash: hash
        )
    }

    private static func appVersion(_ meta: [String: Any]) -> String? {
        let version = text(meta["appVersion"]).map { SystemReportText.clean($0) }
        let build = text(meta["appBuildVersion"]).map { SystemReportText.clean($0) }
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        case let (nil, build?): return "(\(build))"
        default: return nil
        }
    }

    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: string.isEmpty ? nil : string
        case let number as NSNumber: number.stringValue
        case let object as [String: Any]:
            // MetricKit measurements: {"value": 12, "unit": "MB"}…
            if let value = object["value"] { [text(value), object["unit"] as? String].compactMap(\.self).joined(separator: " ") } else { nil }
        default: nil
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        for format in ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return ISO8601DateFormatter().date(from: string)
    }

    /// The JSON kept (nil beyond `maxRawBytes`) and the hash of the full JSON,
    /// so two big distinct reports never look alike.
    private static func raw(_ object: [String: Any]) -> (Data?, String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return (nil, "") }
        return (data.count <= maxRawBytes ? data : nil, SHA256.hex(String(decoding: data, as: UTF8.self)))
    }
}

/// The reports kept on this device: the last 30 days, 50 at most, no duplicate.
public struct SystemReportStore: Sendable, Equatable, Codable {
    public static let retention: TimeInterval = 30 * 86_400
    public static let maxReports = 50

    public private(set) var reports: [SystemReport]
    /// "Delete all reports": what iOS delivers again for a period before this
    /// (its past payloads, read at each launch) stays deleted.
    public private(set) var clearedAt: Date?

    public init(reports: [SystemReport] = [], clearedAt: Date? = nil) {
        self.reports = reports
        self.clearedAt = clearedAt
    }

    /// Adds what's new, newest first, then drops what's too old or too many.
    /// Returns how many reports were new.
    @discardableResult
    public mutating func add(_ incoming: [SystemReport], now: Date = .now) -> Int {
        var seen = Set(reports.map(\.fingerprint))
        var added = 0
        for report in incoming where !isCleared(report) && seen.insert(report.fingerprint).inserted {
            reports.append(report)
            added += 1
        }
        prune(now: now)
        return added
    }

    public mutating func prune(now: Date = .now) {
        reports = reports
            .filter { now.timeIntervalSince($0.receivedAt) < Self.retention }
            .sorted { $0.receivedAt > $1.receivedAt }
        if reports.count > Self.maxReports { reports = Array(reports.prefix(Self.maxReports)) }
    }

    public mutating func removeAll(now: Date = .now) {
        reports = []
        clearedAt = now
    }

    private func isCleared(_ report: SystemReport) -> Bool {
        guard let clearedAt, let period = report.periodEnd ?? report.periodStart else { return false }
        return period <= clearedAt
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decoded(from data: Data?) -> SystemReportStore {
        data.flatMap { try? JSONDecoder().decode(SystemReportStore.self, from: $0) } ?? SystemReportStore()
    }
}

/// Text built from the reports.
public enum SystemReportText {
    /// Keeps a value short and free of anything that could point at the user's
    /// network or a secret: URLs, host names, IP and e-mail addresses become
    /// "[removed]", as does any `forbidden` word (service names, hosts…).
    public static func clean(_ value: String, forbidden: [String] = []) -> String {
        var text = String(value.prefix(300))
        let patterns = [
            #"[A-Za-z][A-Za-z0-9+.-]*://\S+"#,                          // URLs
            #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+"#,                        // e-mail
            #"\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b"#,                    // IPv4
            #"\b(?:[0-9A-Fa-f]{1,4}:){2,7}[0-9A-Fa-f]{1,4}\b"#,          // IPv6
            #"(?:[0-9A-Fa-f]{1,4})?(?::[0-9A-Fa-f]{1,4})*::(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?"#, // IPv6 with ::
            #"\b(?:[A-Za-z0-9-]+\.)+(?:[A-Za-z]{2,})(?::\d+)?\b"#,       // host names
            #"(?:[\p{L}\p{N}-]+\.)+[\p{L}\p{N}-]*[\p{L}][\p{L}\p{N}-]*(?::\d+)?"#, // other host names (accents, digits)
            #"/(?:Users|home|var/mobile|private/var)/\S+"#,               // file paths
            #"(?i)\b(?:bearer|token|x-api-key|api[-_]?key)\b\s*[:=]?\s*\S+"#,
            #"(?i)(?:token|secret|password|authorization|apikey|api_key)\S*\s*[=:]\s*\S+"#,
            #"[A-Za-z0-9_\-]{28,}"#,                                     // long opaque values
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: "[removed]", options: .regularExpression)
        }
        for word in forbidden where word.count >= 3 {
            text = text.replacingOccurrences(of: word, with: "[removed]", options: .caseInsensitive)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-,()[]:/+#"))
        return String(String(text.unicodeScalars.filter { allowed.contains($0) }).prefix(120))
    }

    /// The optional summary for a support e-mail: crashes and hangs only, with
    /// date, versions and exception details, every value cleaned again with the
    /// user's service names and hosts. Never the call stacks or the raw JSON.
    public static func supportSummary(_ reports: [SystemReport], forbidden: [String], limit: Int = 10) -> String {
        let relevant = reports.filter { $0.kind == .crash || $0.kind == .hang }.prefix(limit)
        var lines = ["iOS crash and hang reports (last 30 days): \(relevant.count)"]
        let day = Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: "en_US_POSIX"))
        for report in relevant {
            var parts = [report.kind.rawValue, report.receivedAt.formatted(day)]
            if let app = report.appVersion { parts.append("app " + clean(app, forbidden: forbidden)) }
            if let os = report.osVersion { parts.append(clean(os, forbidden: forbidden)) }
            for detail in report.details where ["Exception type", "Exception code", "Signal", "Termination reason", "Hang duration"].contains(detail.label) {
                parts.append("\(detail.label.lowercased()) \(clean(detail.value, forbidden: forbidden))")
            }
            lines.append("  " + parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    /// What "Share" sends for one report: the readable lines, then iOS's JSON.
    public static func shareText(_ report: SystemReport) -> String {
        var lines = ["PatchNode – iOS \(report.kind.rawValue) report", "Received: \(report.receivedAt.formatted(.iso8601))"]
        if let app = report.appVersion { lines.append("App: \(app)") }
        if let os = report.osVersion { lines.append("iOS: \(os)") }
        lines += report.details.map { "\($0.label): \($0.value)" }
        if let raw = report.rawJSON {
            lines += ["", String(decoding: raw, as: UTF8.self)]
        }
        return lines.joined(separator: "\n")
    }
}

/// The reports file, in the app's Application Support (excluded from nothing,
/// part of the device backups like the settings). One writer at a time.
public actor SystemReportArchive {
    public static let shared = SystemReportArchive()

    private let url: URL?
    private var store: SystemReportStore?

    public init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first) {
        url = directory?.appending(path: "system-reports.json")
    }

    /// Reports older than 30 days leave the file too, not only the list.
    public func reports(now: Date = .now) -> [SystemReport] {
        var current = load()
        let before = current.reports.count
        current.prune(now: now)
        if current.reports.count != before { write(current) }
        return current.reports
    }

    public func add(diagnosticsJSON json: Data, now: Date = .now) {
        add(diagnosticsJSONs: [json], metricsJSONs: [], now: now)
    }

    public func add(metricsJSON json: Data, now: Date = .now) {
        add(diagnosticsJSONs: [], metricsJSONs: [json], now: now)
    }

    /// Several payloads at once (MetricKit's past payloads at launch): one write
    /// at most, none if everything was already there.
    public func add(diagnosticsJSONs: [Data], metricsJSONs: [Data], now: Date = .now) {
        let reports = diagnosticsJSONs.flatMap { SystemReportParser.diagnostics(from: $0, receivedAt: now) }
            + metricsJSONs.compactMap { SystemReportParser.metrics(from: $0, receivedAt: now) }
        save(adding: reports, now: now)
    }

    public func removeAll(now: Date = .now) {
        var current = load()
        current.removeAll(now: now)
        write(current)
    }

    private func save(adding reports: [SystemReport], now: Date) {
        guard !reports.isEmpty else { return }
        var current = load()
        guard current.add(reports, now: now) > 0 else { return }
        write(current)
    }

    private func load() -> SystemReportStore {
        if let store { return store }
        let loaded = SystemReportStore.decoded(from: url.flatMap { try? Data(contentsOf: $0) })
        store = loaded
        return loaded
    }

    private func write(_ updated: SystemReportStore) {
        store = updated
        guard let url, let data = updated.encoded() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: .atomic)
        #endif
    }
}

import Foundation

/// What the user can choose to attach to a support e-mail. Built only from
/// values that can't identify a server or a person: versions, device model,
/// language, service TYPES, demo flag, and the classification and HTTP code of
/// the latest errors per service type. Never a URL, host name, address, service
/// name, token, identifier, path or body: the inputs below don't even carry them.
public struct SupportReport: Sendable, Equatable {
    public struct RecentError: Sendable, Equatable {
        public let kind: ServiceKind
        public let outcome: RequestLog.Outcome
        public let statusCode: Int?
        public let date: Date
    }

    public let appVersion: String
    public let systemVersion: String
    public let deviceModel: String
    public let language: String
    /// Number of configured services per type.
    public let serviceTypes: [ServiceKind: Int]
    public let demoMode: Bool
    /// Latest error per service type, most recent first.
    public let recentErrors: [RecentError]

    /// `services`: IDs and types of the configured services, only to map the log's
    /// entries to a type (the IDs never reach the report).
    public init(
        appVersion: String, systemVersion: String, deviceModel: String, language: String,
        services: [(id: UUID, kind: ServiceKind)], demoMode: Bool, log: [RequestLog.Entry]
    ) {
        self.appVersion = Self.clean(appVersion)
        self.systemVersion = Self.clean(systemVersion)
        self.deviceModel = Self.clean(deviceModel)
        self.language = Self.clean(language)
        self.demoMode = demoMode
        var counts: [ServiceKind: Int] = [:]
        var kinds: [UUID: ServiceKind] = [:]
        for service in services {
            counts[service.kind, default: 0] += 1
            kinds[service.id] = service.kind
        }
        serviceTypes = counts
        var latest: [ServiceKind: RecentError] = [:]
        for entry in log {
            guard case .request(let request) = entry.kind,
                  Self.isError(request.outcome),
                  let id = entry.serviceID, let kind = kinds[id]
            else { continue }
            if let known = latest[kind], known.date > entry.date { continue }
            latest[kind] = RecentError(kind: kind, outcome: request.outcome, statusCode: request.statusCode, date: entry.date)
        }
        recentErrors = latest.values.sorted { $0.date > $1.date }
    }

    static func isError(_ outcome: RequestLog.Outcome) -> Bool {
        switch outcome {
        case .ok, .cancelled: false
        default: true
        }
    }

    /// Versions and model come from the system; still keep only harmless
    /// characters and a short length.
    static func clean(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-,()"))
        return String(String(value.unicodeScalars.filter { allowed.contains($0) }).prefix(40))
    }

    /// The exact text attached to the e-mail, shown in full before sending.
    /// Technical English, like a log.
    public func text(now: Date = .now) -> String {
        var lines = [
            "PatchNode diagnostic report",
            "App: \(appVersion)",
            "iOS: \(systemVersion)",
            "Device: \(deviceModel)",
            "Language: \(language)",
            "Demo mode: \(demoMode ? "yes" : "no")",
            "Service types: " + (serviceTypes.isEmpty
                ? "none"
                : serviceTypes.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) ×\($0.value)" }.joined(separator: ", ")),
            "Latest errors (per service type):",
        ]
        if recentErrors.isEmpty {
            lines.append("  none")
        }
        for error in recentErrors {
            let age = Int(max(0, now.timeIntervalSince(error.date)) / 60)
            let code = error.statusCode.map { "HTTP \($0)" } ?? "no response"
            lines.append("  \(error.kind.rawValue): \(error.outcome.rawValue), \(code), \(age) min ago")
        }
        return lines.joined(separator: "\n")
    }
}

/// A support e-mail: subject and body, from the form.
public enum SupportMessage {
    public enum Category: String, Sendable, CaseIterable, Identifiable {
        case bug
        case setupHelp
        case suggestion

        public var id: String { rawValue }
    }

    public static func subject(category: Category, kind: ServiceKind?) -> String {
        let label = switch category {
        case .bug: "Bug"
        case .setupHelp: "Setup help"
        case .suggestion: "Suggestion"
        }
        return "PatchNode – \(label)" + (kind.map { " – \($0.rawValue)" } ?? "")
    }

    /// The user's description, then the report and the crash summary
    /// (`SystemReportText.supportSummary`) if they chose to attach them.
    public static func body(description: String, report: SupportReport?, crashSummary: String? = nil, now: Date = .now) -> String {
        var body = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let report {
            body += "\n\n---\n" + report.text(now: now)
        }
        if let crashSummary {
            body += "\n\n---\n" + crashSummary
        }
        return body
    }

    /// `mailto:` link for when Mail isn't set up, or nil if the address is invalid.
    public static func mailtoURL(to address: String, subject: String, body: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_+@")
        guard trimmed.filter({ $0 == "@" }).count == 1,
              trimmed.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        // Only unreserved characters stay as they are: '&', '=', '+', '%' in the
        // user's text can't add a recipient or a header.
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encode(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        }
        return URL(string: "mailto:\(trimmed)?subject=\(encode(subject))&body=\(encode(body))")
    }
}

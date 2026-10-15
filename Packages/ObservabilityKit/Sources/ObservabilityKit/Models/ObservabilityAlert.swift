import Foundation
import PatchNodeCore

/// An alert from any source, normalized for the Observability tab and dashboard.
public struct ObservabilityAlert: Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable, Hashable, CaseIterable {
        case alertmanager
        case grafana
        case prometheus
        case uptimeKuma
    }

    public enum Severity: Int, Sendable, Hashable, Comparable, CaseIterable {
        case info = 0
        case warning = 1
        case critical = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        /// From the conventional `severity` label; unknown or missing → warning
        /// (the alert is firing, so it deserves attention).
        public init(label: String?) {
            switch label?.lowercased() {
            case "critical", "page", "error", "high", "disaster": self = .critical
            case "info", "information", "informational", "low", "none": self = .info
            default: self = .warning
            }
        }
    }

    public let id: String
    public let source: Source
    public let severity: Severity
    public let name: String
    public let summary: String?
    public let since: Date?
    public let labels: [String: String]

    public init(
        id: String, source: Source, severity: Severity, name: String,
        summary: String? = nil, since: Date? = nil, labels: [String: String] = [:]
    ) {
        self.id = id; self.source = source; self.severity = severity; self.name = name
        self.summary = summary; self.since = since; self.labels = labels
    }
}

extension [ObservabilityAlert] {
    /// Most severe first, then oldest first (the longest-running problem on top).
    public func sortedBySeverity() -> [ObservabilityAlert] {
        sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return ($0.since ?? .distantFuture) < ($1.since ?? .distantFuture)
        }
    }
}

/// Alertmanager v2 alert (`GET /api/v2/alerts`), also served by Grafana under
/// `/api/alertmanager/grafana/api/v2/alerts`.
struct AlertmanagerAlert: Decodable {
    let fingerprint: String?
    let labels: [String: String]
    let annotations: [String: String]
    let startsAt: String?
    let state: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        fingerprint = c.lenientString(AnyCodingKey("fingerprint"))
        labels = (try? c.decodeIfPresent([String: String].self, forKey: AnyCodingKey("labels"))) ?? [:]
        annotations = (try? c.decodeIfPresent([String: String].self, forKey: AnyCodingKey("annotations"))) ?? [:]
        startsAt = c.lenientString(AnyCodingKey("startsAt"))
        let status = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("status"))
        state = status?.lenientString(AnyCodingKey("state"))
    }

    func normalized(source: ObservabilityAlert.Source) -> ObservabilityAlert {
        let name = labels["alertname"] ?? labels["__alert_rule_title__"] ?? "Alert"
        let id = fingerprint ?? ([name] + labels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }).joined(separator: ",")
        return ObservabilityAlert(
            id: "\(source.rawValue)|\(id)",
            source: source,
            severity: ObservabilityAlert.Severity(label: labels["severity"]),
            name: name,
            summary: annotations["summary"] ?? annotations["description"] ?? annotations["message"],
            since: startsAt.flatMap(RFC3339Timestamp.parse),
            labels: labels
        )
    }
}

import Foundation
import PatchNodeCore

/// Shared request building for the observability services.
struct ObservabilityRequests: Sendable {
    enum Auth: Sendable {
        case none
        /// `user:password`, sent only when not empty.
        case basic(String)
        case bearer(String)
    }

    let baseURL: URL
    let auth: Auth

    func spec(_ segments: [String], query: [URLQueryItem] = []) -> HTTPRequestSpec {
        var url = baseURL
        for segment in segments {
            url = url.appending(component: segment)
        }
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            // "+" is left as-is by URLComponents but decoded as a space by
            // Prometheus: `a + b` would become `a   b`.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
            url = components.url ?? url
        }
        return HTTPRequestSpec(method: .get, url: url, headers: headers)
    }

    private var headers: [String: String] {
        switch auth {
        case .none:
            return [:]
        case .basic(let credential):
            guard !credential.isEmpty else { return [:] }
            return ["Authorization": "Basic \(Data(credential.utf8).base64EncodedString())"]
        case .bearer(let token):
            guard !token.isEmpty else { return [:] }
            return ["Authorization": "Bearer \(token)"]
        }
    }
}

// MARK: - Prometheus

public enum PrometheusQueryError: Error, Sendable, Hashable {
    /// Prometheus refused the query (syntax error, unknown function…), with its message.
    case rejected(String)
}

public struct PrometheusClient: Sendable {
    private let requests: ObservabilityRequests
    private let httpClient: any HTTPClientProtocol

    /// `credential`: optional `user:password` for a reverse proxy doing Basic auth.
    public init(baseURL: URL, credential: String = "", httpClient: any HTTPClientProtocol = HTTPClient()) {
        requests = ObservabilityRequests(baseURL: baseURL, auth: .basic(credential))
        self.httpClient = httpClient
    }

    public func checkConnection() async throws {
        _ = try await httpClient.fetchOK(requests.spec(["api", "v1", "status", "buildinfo"]))
    }

    public func query(_ promQL: String, at time: Date? = nil) async throws -> PrometheusResult {
        var items = [URLQueryItem(name: "query", value: promQL)]
        if let time { items.append(URLQueryItem(name: "time", value: Self.format(time))) }
        return try await run(requests.spec(["api", "v1", "query"], query: items))
    }

    /// `step` is clamped so a range never asks for more than `maxPoints` samples.
    public static let maxPoints = 500

    public func queryRange(_ promQL: String, start: Date, end: Date, step: TimeInterval? = nil) async throws -> PrometheusResult {
        let span = max(end.timeIntervalSince(start), 1)
        let minimumStep = (span / Double(Self.maxPoints)).rounded(.up)
        let effectiveStep = max(step ?? minimumStep, minimumStep, 1)
        return try await run(requests.spec(["api", "v1", "query_range"], query: [
            URLQueryItem(name: "query", value: promQL),
            URLQueryItem(name: "start", value: Self.format(start)),
            URLQueryItem(name: "end", value: Self.format(end)),
            URLQueryItem(name: "step", value: Self.format(effectiveStep)),
        ]))
    }

    public func targets() async throws -> [PrometheusTarget] {
        struct Payload: Decodable {
            let data: TargetsData
            struct TargetsData: Decodable { let activeTargets: LossyArray<PrometheusTarget>? }
        }
        let payload: Payload = try await httpClient.fetchJSON(
            requests.spec(["api", "v1", "targets"], query: [URLQueryItem(name: "state", value: "active")])
        )
        return payload.data.activeTargets?.elements ?? []
    }

    private struct Envelope: Decodable {
        let status: String?
        let data: PrometheusResult?
        let error: String?
    }

    /// Prometheus answers a bad query with 400/422 and `{"status":"error","error":…}`.
    private func run(_ spec: HTTPRequestSpec) async throws -> PrometheusResult {
        let (data, response) = try await httpClient.fetchResponse(spec)
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        if response.statusCode == 200 {
            guard let result = envelope?.data, envelope?.status == "success" else {
                throw ServiceProviderError.decodingFailed
            }
            return result
        }
        if [400, 422].contains(response.statusCode), let message = envelope?.error {
            throw PrometheusQueryError.rejected(String(message.prefix(500)))
        }
        throw ServiceProviderError.unexpectedStatus(response.statusCode)
    }

    static func format(_ date: Date) -> String { format(date.timeIntervalSince1970) }

    static func format(_ seconds: Double) -> String {
        String(format: "%.3f", seconds)
    }
}

// MARK: - Alertmanager

public struct AlertmanagerClient: Sendable {
    private let requests: ObservabilityRequests
    private let httpClient: any HTTPClientProtocol

    public init(baseURL: URL, credential: String = "", httpClient: any HTTPClientProtocol = HTTPClient()) {
        requests = ObservabilityRequests(baseURL: baseURL, auth: .basic(credential))
        self.httpClient = httpClient
    }

    public func checkConnection() async throws {
        _ = try await httpClient.fetchOK(requests.spec(["api", "v2", "status"]))
    }

    /// Active alerts only: silenced and inhibited ones are excluded by default.
    public func alerts(includeSilenced: Bool = false) async throws -> [ObservabilityAlert] {
        let list: LossyArray<AlertmanagerAlert> = try await httpClient.fetchJSON(requests.spec(
            ["api", "v2", "alerts"],
            query: [
                URLQueryItem(name: "active", value: "true"),
                URLQueryItem(name: "silenced", value: includeSilenced ? "true" : "false"),
                URLQueryItem(name: "inhibited", value: includeSilenced ? "true" : "false"),
            ]
        ))
        return list.elements
            .filter { includeSilenced || $0.state == nil || $0.state == "active" }
            .map { $0.normalized(source: .alertmanager) }
    }
}

// MARK: - Grafana

public struct GrafanaClient: Sendable {
    public let baseURL: URL
    private let requests: ObservabilityRequests
    private let httpClient: any HTTPClientProtocol

    /// `token`: a service account token (Viewer role).
    public init(baseURL: URL, token: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.baseURL = baseURL
        requests = ObservabilityRequests(baseURL: baseURL, auth: .bearer(token))
        self.httpClient = httpClient
    }

    /// `/api/health` doesn't check the token, so the search endpoint is used.
    public func checkConnection() async throws {
        _ = try await httpClient.fetchOK(requests.spec(["api", "search"], query: [URLQueryItem(name: "limit", value: "1")]))
    }

    public func dashboards() async throws -> [GrafanaDashboard] {
        let list: LossyArray<GrafanaDashboard> = try await httpClient.fetchJSON(requests.spec(
            ["api", "search"],
            query: [URLQueryItem(name: "type", value: "dash-db"), URLQueryItem(name: "limit", value: "500")]
        ))
        return list.elements
    }

    /// Grafana-managed alerts. Grafana without unified alerting answers 404: no alerts.
    public func alerts() async throws -> [ObservabilityAlert] {
        do {
            let list: LossyArray<AlertmanagerAlert> = try await httpClient.fetchJSON(requests.spec(
                ["api", "alertmanager", "grafana", "api", "v2", "alerts"],
                query: [
                    URLQueryItem(name: "active", value: "true"),
                    URLQueryItem(name: "silenced", value: "false"),
                    URLQueryItem(name: "inhibited", value: "false"),
                ]
            ))
            return list.elements
                .filter { $0.state == nil || $0.state == "active" }
                .map { $0.normalized(source: .grafana) }
        } catch ServiceProviderError.unexpectedStatus(404) {
            return []
        }
    }
}

// MARK: - Uptime Kuma

public struct UptimeKumaClient: Sendable {
    public let location: UptimeKumaLocation
    private let requests: ObservabilityRequests
    private let httpClient: any HTTPClientProtocol

    /// Public status pages need no credential.
    public init(location: UptimeKumaLocation, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.location = location
        requests = ObservabilityRequests(baseURL: location.baseURL, auth: .none)
        self.httpClient = httpClient
    }

    public func checkConnection() async throws {
        _ = try await httpClient.fetchOK(requests.spec(["api", "status-page", location.slug]))
    }

    public func page() async throws -> UptimeKumaPage {
        // Sequential: a failing page costs one request, not two.
        let info: StatusPagePayload = try await httpClient.fetchJSON(requests.spec(["api", "status-page", location.slug]))
        let beats: HeartbeatPayload = try await httpClient.fetchJSON(
            requests.spec(["api", "status-page", "heartbeat", location.slug])
        )
        var monitors: [UptimeKumaPage.Monitor] = []
        for group in info.groups {
            for monitor in group.monitors {
                let history = beats.heartbeats[String(monitor.id)] ?? []
                let last = history.last
                monitors.append(UptimeKumaPage.Monitor(
                    id: monitor.id,
                    name: monitor.name,
                    group: group.name,
                    status: last?.status,
                    lastMessage: (last?.message?.isEmpty ?? true) ? nil : last?.message,
                    lastPing: last?.ping,
                    lastBeat: last?.time,
                    uptime24h: beats.uptimes["\(monitor.id)_24"],
                    recentStatuses: history.suffix(30).compactMap(\.status)
                ))
            }
        }
        return UptimeKumaPage(slug: location.slug, title: info.title ?? location.slug, monitors: monitors)
    }

    private struct StatusPagePayload: Decodable {
        struct Group: Decodable {
            let name: String?
            let monitors: [MonitorRef]

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: AnyCodingKey.self)
                name = c.lenientString(AnyCodingKey("name"))
                monitors = (try? c.decodeIfPresent(LossyArray<MonitorRef>.self, forKey: AnyCodingKey("monitorList")))?.elements ?? []
            }
        }

        struct MonitorRef: Decodable {
            let id: Int
            let name: String

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: AnyCodingKey.self)
                guard let id = c.lenientInt(AnyCodingKey("id")) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
                }
                self.id = id
                name = c.lenientString(AnyCodingKey("name")) ?? "#\(id)"
            }
        }

        let title: String?
        let groups: [Group]

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyCodingKey.self)
            let config = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("config"))
            title = config?.lenientString(AnyCodingKey("title"))
            groups = (try? c.decodeIfPresent(LossyArray<Group>.self, forKey: AnyCodingKey("publicGroupList")))?.elements ?? []
        }
    }

    private struct HeartbeatPayload: Decodable {
        struct Beat: Decodable {
            let status: UptimeKumaPage.Monitor.Status?
            let time: Date?
            let message: String?
            let ping: Double?

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: AnyCodingKey.self)
                status = c.lenientInt(AnyCodingKey("status")).flatMap(UptimeKumaPage.Monitor.Status.init(rawValue:))
                time = c.lenientString(AnyCodingKey("time")).flatMap(UptimeKumaClient.parseTime)
                message = c.lenientString(AnyCodingKey("msg"))
                ping = c.lenientDouble(AnyCodingKey("ping"))
            }
        }

        let heartbeats: [String: [Beat]]
        let uptimes: [String: Double]

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyCodingKey.self)
            var heartbeats: [String: [Beat]] = [:]
            if let list = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("heartbeatList")) {
                for key in list.allKeys {
                    heartbeats[key.stringValue] = (try? list.decode(LossyArray<Beat>.self, forKey: key))?.elements ?? []
                }
            }
            self.heartbeats = heartbeats
            var uptimes: [String: Double] = [:]
            if let list = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("uptimeList")) {
                for key in list.allKeys {
                    if let value = list.lenientDouble(key) { uptimes[key.stringValue] = value }
                }
            }
            self.uptimes = uptimes
        }
    }

    /// Kuma writes "2024-05-01 10:00:00.123" in UTC.
    static func parseTime(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let date = RFC3339Timestamp.parse(trimmed) { return date }
        return RFC3339Timestamp.parse(trimmed.replacingOccurrences(of: " ", with: "T") + "Z")
    }
}

import Foundation
import PatchNodeCore

// MARK: - CrowdSec

/// An active CrowdSec decision (`GET /v1/decisions`), usually a ban.
public struct CrowdSecDecision: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    /// `ban`, `captcha`…
    public let type: String
    /// `Ip`, `Range`, `Country`, `AS`…
    public let scope: String
    /// The IP, range, country code… depending on `scope`.
    public let value: String
    public let scenario: String?
    /// `crowdsec`, `cscli`, `CAPI`, `lists`…
    public let origin: String?
    public let expiresAt: Date?
    public let simulated: Bool

    public init(
        id: String, type: String = "ban", scope: String = "Ip", value: String, scenario: String? = nil,
        origin: String? = nil, expiresAt: Date? = nil, simulated: Bool = false
    ) {
        self.id = id; self.type = type; self.scope = scope; self.value = value
        self.scenario = scenario; self.origin = origin; self.expiresAt = expiresAt; self.simulated = simulated
    }

    /// Decoded relative to `now`: `duration` is what remains ("3h59m50.3s").
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let value = c.lenientString(AnyCodingKey("value")), !value.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing value"))
        }
        self.value = value
        let rawID = c.lenientString(AnyCodingKey("id")) ?? c.lenientString(AnyCodingKey("uuid"))
        id = rawID ?? value
        type = c.lenientString(AnyCodingKey("type")) ?? "ban"
        scope = c.lenientString(AnyCodingKey("scope")) ?? "Ip"
        let scenario = c.lenientString(AnyCodingKey("scenario"))
        self.scenario = (scenario?.isEmpty ?? true) ? nil : scenario
        origin = c.lenientString(AnyCodingKey("origin"))
        simulated = c.lenientBool(AnyCodingKey("simulated")) ?? false
        let now = (decoder.userInfo[.decisionsReferenceDate] as? Date) ?? .now
        if let until = c.lenientString(AnyCodingKey("until")).flatMap(RFC3339Timestamp.parse) {
            expiresAt = until
        } else if let remaining = c.lenientString(AnyCodingKey("duration")).flatMap(GoDuration.seconds) {
            expiresAt = now.addingTimeInterval(remaining)
        } else {
            expiresAt = nil
        }
    }

    /// Country code for a `Country`-scoped decision. The bouncer API gives no
    /// country for IP decisions.
    public var country: String? {
        scope.lowercased() == "country" ? value.uppercased() : nil
    }
}

extension CodingUserInfoKey {
    static let decisionsReferenceDate = CodingUserInfoKey(rawValue: "decisionsReferenceDate")!
}

/// Go `time.Duration` strings as CrowdSec writes them: "3h59m50.304s", "-1m2s", "150ms".
public enum GoDuration {
    public static func seconds(_ text: String) -> TimeInterval? {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        guard !rest.isEmpty else { return nil }
        var sign = 1.0
        if rest.first == "-" { sign = -1; rest = rest.dropFirst() } else if rest.first == "+" { rest = rest.dropFirst() }
        if rest == "0" { return 0 }
        let units: [(String, Double)] = [("ns", 1e-9), ("us", 1e-6), ("µs", 1e-6), ("μs", 1e-6), ("ms", 1e-3), ("h", 3600), ("m", 60), ("s", 1)]
        var total = 0.0
        var parsedAny = false
        while !rest.isEmpty {
            let number = rest.prefix { $0.isNumber || $0 == "." }
            guard !number.isEmpty, let value = Double(number) else { return nil }
            rest = rest.dropFirst(number.count)
            guard let unit = units.first(where: { rest.hasPrefix($0.0) }) else { return nil }
            rest = rest.dropFirst(unit.0.count)
            total += value * unit.1
            parsedAny = true
        }
        return parsedAny && total.isFinite ? sign * total : nil
    }
}

// MARK: - Nginx Proxy Manager

/// A proxy host (`GET /api/nginx/proxy-hosts`).
public struct NPMProxyHost: Sendable, Hashable, Identifiable, Decodable {
    public let id: Int
    public let domainNames: [String]
    public let forwardScheme: String?
    public let forwardHost: String?
    public let forwardPort: Int?
    public let enabled: Bool
    public let hasCertificate: Bool
    public let sslForced: Bool
    /// nginx accepted the host's configuration (`meta.nginx_online`).
    public let nginxOnline: Bool?
    public let nginxError: String?

    public init(
        id: Int, domainNames: [String], forwardScheme: String? = nil, forwardHost: String? = nil, forwardPort: Int? = nil,
        enabled: Bool = true, hasCertificate: Bool = false, sslForced: Bool = false, nginxOnline: Bool? = nil, nginxError: String? = nil
    ) {
        self.id = id; self.domainNames = domainNames; self.forwardScheme = forwardScheme; self.forwardHost = forwardHost
        self.forwardPort = forwardPort; self.enabled = enabled; self.hasCertificate = hasCertificate
        self.sslForced = sslForced; self.nginxOnline = nginxOnline; self.nginxError = nginxError
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.lenientInt(AnyCodingKey("id")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        domainNames = (try? c.decodeIfPresent([String].self, forKey: AnyCodingKey("domain_names"))) ?? []
        forwardScheme = c.lenientString(AnyCodingKey("forward_scheme"))
        forwardHost = c.lenientString(AnyCodingKey("forward_host"))
        forwardPort = c.lenientInt(AnyCodingKey("forward_port"))
        enabled = c.lenientBool(AnyCodingKey("enabled")) ?? true
        hasCertificate = (c.lenientInt(AnyCodingKey("certificate_id")) ?? 0) > 0
        sslForced = c.lenientBool(AnyCodingKey("ssl_forced")) ?? false
        let meta = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("meta"))
        nginxOnline = meta?.lenientBool(AnyCodingKey("nginx_online"))
        let error = meta?.lenientString(AnyCodingKey("nginx_err"))
        nginxError = (error?.isEmpty ?? true) ? nil : error
    }

    public var title: String { domainNames.first ?? "#\(id)" }

    /// Where the traffic goes, e.g. `http://192.0.2.5:8080`.
    public var destination: String? {
        guard let forwardHost, !forwardHost.isEmpty else { return nil }
        let scheme = forwardScheme.map { "\($0)://" } ?? ""
        let port = forwardPort.map { ":\($0)" } ?? ""
        return "\(scheme)\(forwardHost)\(port)"
    }

    /// Enabled but refused by nginx.
    public var isFailing: Bool { enabled && nginxOnline == false }
}

// MARK: - AdGuard Home

/// `GET /control/status` + `GET /control/stats`.
public struct AdGuardSummary: Sendable, Hashable {
    public struct DomainCount: Sendable, Hashable, Identifiable {
        public let domain: String
        public let count: Int
        public var id: String { domain }

        public init(domain: String, count: Int) {
            self.domain = domain; self.count = count
        }
    }

    public let protectionEnabled: Bool
    public let running: Bool
    public let version: String?
    public let dnsQueries: Int
    public let blocked: Int
    /// Average processing time, in seconds.
    public let averageProcessingTime: Double?
    public let topQueried: [DomainCount]
    public let topBlocked: [DomainCount]

    public init(
        protectionEnabled: Bool, running: Bool = true, version: String? = nil, dnsQueries: Int = 0, blocked: Int = 0,
        averageProcessingTime: Double? = nil, topQueried: [DomainCount] = [], topBlocked: [DomainCount] = []
    ) {
        self.protectionEnabled = protectionEnabled; self.running = running; self.version = version
        self.dnsQueries = dnsQueries; self.blocked = blocked; self.averageProcessingTime = averageProcessingTime
        self.topQueried = topQueried; self.topBlocked = topBlocked
    }

    public var blockedRatio: Double? {
        dnsQueries > 0 ? min(Double(blocked) / Double(dnsQueries), 1) : nil
    }
}

struct AdGuardStatusPayload: Decodable {
    let protectionEnabled: Bool
    let running: Bool
    let version: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let protection = c.lenientBool(AnyCodingKey("protection_enabled")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing protection_enabled"))
        }
        protectionEnabled = protection
        running = c.lenientBool(AnyCodingKey("running")) ?? true
        version = c.lenientString(AnyCodingKey("version"))
    }
}

struct AdGuardStatsPayload: Decodable {
    let dnsQueries: Int
    let blocked: Int
    let averageProcessingTime: Double?
    let topQueried: [AdGuardSummary.DomainCount]
    let topBlocked: [AdGuardSummary.DomainCount]

    static let topCount = 10

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        dnsQueries = max(c.lenientInt(AnyCodingKey("num_dns_queries")) ?? 0, 0)
        // Safe browsing and parental control are blocks too.
        blocked = [
            "num_blocked_filtering", "num_replaced_safebrowsing", "num_replaced_parental",
        ].reduce(0) { $0 + max(c.lenientInt(AnyCodingKey($1)) ?? 0, 0) }
        averageProcessingTime = c.lenientDouble(AnyCodingKey("avg_processing_time"))
        topQueried = Self.domains(c, "top_queried_domains")
        topBlocked = Self.domains(c, "top_blocked_domains")
    }

    /// `[{"example.com": 42}, …]`, already sorted by AdGuard.
    private static func domains(_ c: KeyedDecodingContainer<AnyCodingKey>, _ key: String) -> [AdGuardSummary.DomainCount] {
        guard var list = try? c.nestedUnkeyedContainer(forKey: AnyCodingKey(key)) else { return [] }
        var result: [AdGuardSummary.DomainCount] = []
        while !list.isAtEnd, result.count < topCount {
            guard let entry = try? list.nestedContainer(keyedBy: AnyCodingKey.self) else {
                _ = try? list.decode(Discarded.self)
                continue
            }
            for key in entry.allKeys {
                if let count = entry.lenientInt(key) {
                    result.append(AdGuardSummary.DomainCount(domain: key.stringValue, count: count))
                }
            }
        }
        return Array(result.prefix(topCount))
    }

    private struct Discarded: Decodable {}
}

import Foundation
import PatchNodeCore

/// Demo CrowdSec Local API: a handful of bans from local scenarios and one
/// manual ban. Documentation IP ranges only.
public struct CrowdSecDemoResponder: DemoResponder {
    public init() {}

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        guard request.segments == ["v1", "decisions"] else { return .notFound }
        let bans: [(Int, String, String, String, String, String)] = [
            (4101, "Ip", "203.0.113.45", "crowdsecurity/http-probing", "3h41m12s", "crowdsec"),
            (4102, "Ip", "198.51.100.23", "crowdsecurity/ssh-bf", "2h05m40s", "crowdsec"),
            (4103, "Ip", "203.0.113.201", "crowdsecurity/http-crawl-non_statics", "58m03s", "crowdsec"),
            (4104, "Range", "192.0.2.0/24", "crowdsecurity/http-bad-user-agent", "23h10m00s", "crowdsec"),
            (4105, "Ip", "198.51.100.77", "LePresidente/http-generic-401-bf", "11h20m09s", "crowdsec"),
            (4106, "Ip", "203.0.113.9", "manual 'ban' from 'patchnode-demo'", "166h0m0s", "cscli"),
        ]
        return .json(object: bans.map { id, scope, value, scenario, duration, origin in
            ["id": id, "scope": scope, "value": value, "scenario": scenario, "duration": duration,
             "origin": origin, "type": "ban", "uuid": "00000000-demo-4000-8000-00000000\(id)"] as [String: Any]
        })
    }
}

/// Demo Nginx Proxy Manager: proxy hosts, one refused by nginx, one disabled.
public struct NPMDemoResponder: DemoResponder {
    public init() {}

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        switch (request.method, request.segments) {
        case ("POST", ["api", "tokens"]):
            return .json(object: ["token": "demo-npm-token", "expires": now.addingTimeInterval(86_400).formatted(.iso8601)])
        case ("GET", ["api", "nginx", "proxy-hosts"]):
            func host(_ id: Int, _ domain: String, _ target: String, _ port: Int, certificate: Bool = true,
                      enabled: Bool = true, error: String? = nil) -> [String: Any] {
                [
                    "id": id, "domain_names": [domain], "forward_host": target, "forward_port": port,
                    "forward_scheme": "http", "certificate_id": certificate ? 1 : 0, "ssl_forced": certificate ? 1 : 0,
                    "enabled": enabled ? 1 : 0,
                    "meta": ["nginx_online": error == nil, "nginx_err": error.map { $0 as Any } ?? NSNull()],
                ]
            }
            return .json(object: [
                host(1, "cloud.example.invalid", "192.0.2.20", 80),
                host(2, "media.example.invalid", "192.0.2.21", 8096),
                host(3, "home-assistant.example.invalid", "192.0.2.30", 8123),
                host(4, "proxmox.example.invalid", "192.0.2.11", 8006),
                host(5, "vault.example.invalid", "192.0.2.22", 8081),
                host(6, "old-wiki.example.invalid", "wiki.example.invalid", 3000, error: "nginx: [emerg] host not found in upstream \"wiki.example.invalid\""),
                host(7, "test.example.invalid", "192.0.2.99", 8080, certificate: false, enabled: false),
            ])
        default:
            return .notFound
        }
    }
}

/// Demo AdGuard Home: 24 h of statistics, protection on.
public struct AdGuardDemoResponder: DemoResponder {
    public init() {}

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        switch request.segments {
        case ["control", "status"]:
            return .json(object: ["protection_enabled": true, "running": true, "version": "v0.107.54", "dns_port": 53])
        case ["control", "stats"]:
            let hour = Calendar(identifier: .gregorian).component(.hour, from: now)
            let queries = 38_000 + hour * 410
            return .json(object: [
                "time_units": "hours",
                "num_dns_queries": queries, "num_blocked_filtering": queries * 14 / 100,
                "num_replaced_safebrowsing": 7, "num_replaced_safesearch": 0, "num_replaced_parental": 0,
                "avg_processing_time": 0.0187,
                "top_queried_domains": [
                    ["connectivitycheck.gstatic.com": 3_210], ["api.apple-cloudkit.com": 2_480], ["time.apple.com": 1_630],
                    ["github.com": 920], ["example.invalid": 870],
                ],
                "top_blocked_domains": [
                    ["doubleclick.net": 1_420], ["app-measurement.com": 980], ["telemetry.example": 610], ["ads.example": 402],
                ],
            ])
        default:
            return .notFound
        }
    }
}

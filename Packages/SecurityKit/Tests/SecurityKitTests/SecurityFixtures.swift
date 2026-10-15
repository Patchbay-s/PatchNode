import Foundation
@testable import SecurityKit

/// Realistic CrowdSec / Nginx Proxy Manager / AdGuard Home payloads. Every key,
/// token and password is obviously fake; hosts use `.example.invalid` and
/// documentation IP ranges.
enum SecurityFixtures {
    static let serviceID = UUID(uuidString: "5EC0417F-0000-4000-8000-00000000B001")!
    static let otherServiceID = UUID(uuidString: "5EC0417F-0000-4000-8000-00000000B002")!

    static var reference: Date { date(referenceEpoch) }

    // MARK: CrowdSec

    static let crowdSecURL = URL(string: "https://crowdsec.example.invalid:8080")!
    static let bouncerKey = "fake-bouncer-key-1234"
    static let decisionsPath = "/v1/decisions"

    /// - 1287: IP ban from a local scenario, 3h59m50.304318377s left.
    /// - 1288: range ban with an absolute `until` (wins over `duration`).
    /// - 1290: manual country ban (cscli), lowercase code, 167h left.
    /// - 1291: simulated ban, 12m left.
    /// - malformed entry without value: dropped.
    static let decisionsJSON = """
    [
      {
        "duration": "3h59m50.304318377s",
        "id": 1287,
        "origin": "crowdsec",
        "scenario": "crowdsecurity/http-probing",
        "scope": "Ip",
        "type": "ban",
        "uuid": "00000000-fake-4000-8000-000000001287",
        "value": "203.0.113.45"
      },
      {
        "duration": "1h",
        "until": "2024-05-02T10:00:00Z",
        "id": 1288,
        "origin": "crowdsec",
        "scenario": "crowdsecurity/ssh-bf",
        "scope": "Range",
        "type": "ban",
        "value": "198.51.100.0/24"
      },
      {
        "duration": "167h0m0s",
        "id": 1290,
        "origin": "cscli",
        "scenario": "manual 'ban' from 'fake-machine-id'",
        "scope": "Country",
        "type": "ban",
        "value": "zz"
      },
      {
        "duration": "12m0s",
        "id": 1291,
        "origin": "crowdsec",
        "scenario": "crowdsecurity/http-crawl-non_statics",
        "scope": "Ip",
        "type": "captcha",
        "value": "192.0.2.77",
        "simulated": true
      },
      { "id": 9999, "scope": "Ip", "type": "ban", "duration": "1h" }
    ]
    """

    static func decisionsJSON(count: Int) -> String {
        let items = (0..<count).map { index in
            #"{"id":\#(index),"duration":"1h","origin":"crowdsec","scope":"Ip","type":"ban","value":"203.0.113.\#(index % 256)"}"#
        }
        return "[" + items.joined(separator: ",") + "]"
    }

    // MARK: Nginx Proxy Manager

    static let npmURL = URL(string: "https://npm.example.invalid")!
    static let npmIdentity = "viewer@example.invalid"
    static let npmPassword = "fake:pass:1234"
    static let npmCredential = "\(npmIdentity):\(npmPassword)"
    static let npmToken = "fake-npm-jwt-token-1234"
    static let tokensPath = "/api/tokens"
    static let proxyHostsPath = "/api/nginx/proxy-hosts"

    static func npmTokenResponse(expires: String? = "2099-01-01T00:00:00.000Z") -> String {
        if let expires { return #"{"token":"\#(npmToken)","expires":"\#(expires)"}"# }
        return #"{"token":"\#(npmToken)"}"#
    }

    /// - 1: enabled (0/1), certificate, SSL forced, nginx online.
    /// - 2: enabled (bool), no certificate, refused by nginx → failing.
    /// - 3: disabled, refused by nginx → not failing.
    /// - 7: string id, no meta, no forward scheme.
    /// - malformed entry without id: dropped.
    static let proxyHostsJSON = """
    [
      {
        "id": 1,
        "created_on": "2024-01-10T09:00:00.000Z",
        "modified_on": "2024-04-01T09:00:00.000Z",
        "owner_user_id": 1,
        "domain_names": ["cloud.example.invalid", "www.cloud.example.invalid"],
        "forward_host": "192.0.2.10",
        "forward_port": 8080,
        "access_list_id": 0,
        "certificate_id": 3,
        "ssl_forced": 1,
        "caching_enabled": 0,
        "block_exploits": 1,
        "advanced_config": "",
        "meta": {"letsencrypt_agree": true, "dns_challenge": false, "nginx_online": true, "nginx_err": null},
        "allow_websocket_upgrade": 1,
        "http2_support": 1,
        "forward_scheme": "http",
        "enabled": 1,
        "locations": [],
        "hsts_enabled": 0,
        "hsts_subdomains": 0
      },
      {
        "id": 2,
        "domain_names": ["broken.example.invalid"],
        "forward_host": "gone.example.invalid",
        "forward_port": 443,
        "forward_scheme": "https",
        "certificate_id": 0,
        "ssl_forced": false,
        "enabled": true,
        "meta": {"nginx_online": false, "nginx_err": "nginx: [emerg] host not found in upstream \\"gone.example.invalid\\""}
      },
      {
        "id": 3,
        "domain_names": ["archive.example.invalid"],
        "forward_host": "192.0.2.30",
        "forward_port": 80,
        "forward_scheme": "http",
        "certificate_id": 0,
        "enabled": 0,
        "meta": {"nginx_online": false, "nginx_err": ""}
      },
      {
        "id": "7",
        "domain_names": ["app.example.invalid"],
        "forward_host": "192.0.2.70",
        "forward_port": "3000"
      },
      { "domain_names": ["no-id.example.invalid"], "enabled": 1 }
    ]
    """

    // MARK: AdGuard Home

    static let adGuardURL = URL(string: "https://adguard.example.invalid")!
    static let adGuardCredential = "viewer:fake-adguard-pass-1234"
    static let statusPath = "/control/status"
    static let statsPath = "/control/stats"

    static let statusJSON = """
    {
      "dns_addresses": ["192.0.2.53", "fe80::fake"],
      "dns_port": 53,
      "http_port": 443,
      "protection_enabled": true,
      "protection_disabled_duration": 0,
      "dhcp_available": true,
      "running": true,
      "version": "v0.107.52",
      "language": "en"
    }
    """

    static let statusDisabledJSON = #"{"protection_enabled":false,"running":true,"version":"v0.107.52"}"#

    static let statsJSON = """
    {
      "time_units": "hours",
      "top_queried_domains": [
        {"connectivity-check.example.invalid": 1520},
        {"api.example.invalid": 830},
        {"cdn.example.invalid": 412}
      ],
      "top_clients": [{"192.0.2.20": 9000}],
      "top_blocked_domains": [
        {"ads.example.invalid": 410},
        {"tracker.example.invalid": 120}
      ],
      "top_upstreams_responses": [{"https://dns.example.invalid/dns-query": 21000}],
      "top_upstreams_avg_time": [{"https://dns.example.invalid/dns-query": 0.018}],
      "dns_queries": [100, 200, 300],
      "blocked_filtering": [10, 20, 30],
      "replaced_safebrowsing": [0, 1, 0],
      "replaced_parental": [0, 0, 0],
      "num_dns_queries": 24567,
      "num_blocked_filtering": 3120,
      "num_replaced_safebrowsing": 12,
      "num_replaced_safesearch": 40,
      "num_replaced_parental": 3,
      "avg_processing_time": 0.0213
    }
    """

    static func statsJSON(topQueriedCount: Int) -> String {
        let entries = (0..<topQueriedCount).map { #"{"d\#($0).example.invalid": \#(1000 - $0)}"# }
        return #"{"num_dns_queries":10,"top_queried_domains":[\#(entries.joined(separator: ","))]}"#
    }
}

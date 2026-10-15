import Foundation
import PatchNodeCore

private func iso(_ date: Date) -> String {
    date.formatted(.iso8601)
}

/// Demo Prometheus: targets (one down), and any PromQL query answered with a
/// plausible series, so saved charts draw something.
public struct PrometheusDemoResponder: DemoResponder {
    public init() {}

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        switch request.segments {
        case ["api", "v1", "status", "buildinfo"]:
            return .json(object: ["status": "success", "data": ["version": "2.54.1", "revision": "demo", "branch": "HEAD"]])
        case ["api", "v1", "targets"]:
            func target(_ job: String, _ instance: String, health: String, error: String = "") -> [String: Any] {
                [
                    "labels": ["instance": instance, "job": job], "scrapePool": job,
                    "scrapeUrl": "http://\(instance)/metrics", "lastError": error,
                    "lastScrape": iso(now.addingTimeInterval(-7)), "lastScrapeDuration": 0.014, "health": health,
                    "scrapeInterval": "15s", "scrapeTimeout": "10s",
                ]
            }
            return .json(object: ["status": "success", "data": ["activeTargets": [
                target("node", "node-a:9100", health: "up"),
                target("node", "node-b:9100", health: "up"),
                target("node", "storage-node:9100", health: "down", error: "Get \"http://storage-node:9100/metrics\": context deadline exceeded"),
                target("cadvisor", "docker:8080", health: "up"),
                target("prometheus", "localhost:9090", health: "up"),
                target("blackbox", "https://service.example.invalid", health: "up"),
            ], "droppedTargets": [] as [Any]]])
        case ["api", "v1", "query"]:
            let value = String(format: "%.3f", 0.2 + 0.1 * sin(now.timeIntervalSince1970 / 600))
            return .json(object: ["status": "success", "data": ["resultType": "vector", "result": [
                ["metric": ["instance": "node-a:9100", "job": "node"], "value": [now.timeIntervalSince1970, value]],
            ]]])
        case ["api", "v1", "query_range"]:
            let start = Double(request.query["start"] ?? "") ?? now.timeIntervalSince1970 - 3_600
            let end = Double(request.query["end"] ?? "") ?? now.timeIntervalSince1970
            let step = max(Double(request.query["step"] ?? "") ?? 60, (end - start) / 240, 1)
            func series(_ instance: String, base: Double, amplitude: Double, phase: Double) -> [String: Any] {
                var values: [[Any]] = []
                var time = start
                while time <= end {
                    let x = time / 900 + phase
                    values.append([time, String(format: "%.4f", max(0, base + amplitude * sin(x) + amplitude / 3 * sin(x * 3.7)))])
                    time += step
                }
                return ["metric": ["instance": instance, "job": "node"], "values": values]
            }
            return .json(object: ["status": "success", "data": ["resultType": "matrix", "result": [
                series("node-a:9100", base: 22, amplitude: 9, phase: 0),
                series("node-b:9100", base: 35, amplitude: 12, phase: 2),
            ]]])
        default:
            return .notFound
        }
    }
}

/// Demo alerts, shared by Alertmanager and Grafana's unified alerting.
private func demoAlerts(now: Date, grafana: Bool) -> [[String: Any]] {
    func alert(_ name: String, severity: String, summary: String, startedAgo: Double, instance: String?) -> [String: Any] {
        var labels = ["alertname": name, "severity": severity]
        if let instance { labels["instance"] = instance }
        if grafana { labels["__alert_rule_title__"] = name; labels["grafana_folder"] = "Infra" }
        return [
            "labels": labels, "annotations": ["summary": summary],
            "startsAt": iso(now.addingTimeInterval(-startedAgo)), "endsAt": iso(now.addingTimeInterval(300)),
            "updatedAt": iso(now.addingTimeInterval(-30)), "fingerprint": String(format: "%016x", abs(name.hashValue) & 0xFFFF_FFFF),
            "receivers": [["name": "default"]], "status": ["state": "active", "inhibitedBy": [] as [String], "silencedBy": [] as [String]],
        ]
    }
    if grafana {
        return [alert("High CPU on node-b", severity: "warning", summary: "CPU above 85% for 10 minutes", startedAgo: 1_500, instance: "node-b")]
    }
    return [
        alert("InstanceDown", severity: "critical", summary: "storage-node:9100 has been unreachable for 5 minutes", startedAgo: 1_140, instance: "storage-node:9100"),
        alert("DiskAlmostFull", severity: "warning", summary: "local-lvm on node-b is 89% full", startedAgo: 7_200, instance: "node-b:9100"),
        alert("CertificateExpiringSoon", severity: "info", summary: "Certificate for the proxy expires in 12 days", startedAgo: 86_400, instance: nil),
    ]
}

public struct AlertmanagerDemoResponder: DemoResponder {
    public init() {}

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        switch request.segments {
        case ["api", "v2", "status"]:
            return .json(object: ["versionInfo": ["version": "0.27.0"], "cluster": ["status": "ready"]])
        case ["api", "v2", "alerts"]:
            return .json(object: demoAlerts(now: now, grafana: false))
        default:
            return .notFound
        }
    }
}

/// Demo Grafana: dashboards and one alert. Dashboards themselves are web pages,
/// which the app doesn't open in demo mode.
public struct GrafanaDemoResponder: DemoResponder {
    public init() {}

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        switch request.segments {
        case ["api", "search"]:
            let dashboards: [(String, String, String, [String], Bool)] = [
                ("node-exporter", "Node Exporter Full", "Infrastructure", ["linux", "prometheus"], true),
                ("proxmox", "Proxmox VE", "Infrastructure", ["proxmox"], false),
                ("docker", "Docker containers", "Infrastructure", ["docker"], false),
                ("home", "Home energy", "Home", ["home-assistant"], true),
                ("network", "Network metrics", "Network", ["dns", "gateway"], false),
            ]
            let limit = Int(request.query["limit"] ?? "") ?? dashboards.count
            return .json(object: dashboards.prefix(limit).enumerated().map { index, entry in
                [
                    "id": index + 1, "uid": entry.0, "title": entry.1, "url": "/d/\(entry.0)/\(entry.0)",
                    "type": "dash-db", "tags": entry.3, "isStarred": entry.4, "folderTitle": entry.2,
                ] as [String: Any]
            })
        case ["api", "alertmanager", "grafana", "api", "v2", "alerts"]:
            return .json(object: demoAlerts(now: now, grafana: true))
        default:
            return .notFound
        }
    }
}

/// Demo Uptime Kuma status page "homelab": monitors with heartbeats, one down.
public struct UptimeKumaDemoResponder: DemoResponder {
    public init() {}

    private static let monitors: [(Int, String, String)] = [
        (1, "Service A", "Services"), (2, "Service B", "Services"), (3, "Service C", "Services"),
        (4, "Service D", "Services"), (5, "Storage node", "Infrastructure"), (6, "Gateway", "Infrastructure"),
        (7, "Backup service", "Infrastructure"),
    ]

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        switch request.segments {
        case ["api", "status-page", "homelab"]:
            let groups = Dictionary(grouping: Self.monitors, by: \.2)
            let list = ["Services", "Infrastructure"].enumerated().map { index, name in
                [
                    "id": index + 1, "name": name, "weight": index + 1,
                    "monitorList": (groups[name] ?? []).map { ["id": $0.0, "name": $0.1, "type": "http"] as [String: Any] },
                ] as [String: Any]
            }
            return .json(object: ["config": ["slug": "homelab", "title": "HomeLab", "published": true], "incident": NSNull(),
                                  "publicGroupList": list, "maintenanceList": [] as [Any]])
        case ["api", "status-page", "heartbeat", "homelab"]:
            var beats: [String: Any] = [:]
            var uptimes: [String: Any] = [:]
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            for (id, _, _) in Self.monitors {
                let down = id == 7
                beats[String(id)] = (0..<30).map { index -> [String: Any] in
                    let failing = down && index >= 26
                    return [
                        "status": failing ? 0 : 1, "time": formatter.string(from: now.addingTimeInterval(Double(index - 29) * 60)),
                        "msg": failing ? "connect ETIMEDOUT" : "200 - OK", "ping": failing ? NSNull() : 20 + (id * 7 + index) % 40,
                    ]
                }
                uptimes["\(id)_24"] = down ? 0.962 : 0.9991 - Double(id % 3) / 1_000
            }
            return .json(object: ["heartbeatList": beats, "uptimeList": uptimes])
        default:
            return .notFound
        }
    }
}

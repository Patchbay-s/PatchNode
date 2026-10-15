import Foundation
import Synchronization
import PatchNodeCore

/// Demo Docker host (Engine API behind a socket proxy) or Portainer with two
/// environments, answered on the device. Start / stop / restart change the
/// container's state; logs and stats are generated.
public final class DockerDemoResponder: DemoResponder {
    struct Container {
        let id: String
        let name: String
        let image: String
        let project: String?
        var running: Bool
        var startedAt: Date
        var exitCode: Int
        let health: String?
        let ports: [(Int, Int?)]
        let restarts: Int
    }

    private let portainer: Bool
    private let containers: Mutex<[String: [Container]]>

    /// `portainer`: `/api/endpoints/{id}/docker/…` paths, stacks and a second,
    /// unreachable environment; otherwise the Engine API at the root.
    public init(portainer: Bool, now: Date = .now) {
        self.portainer = portainer
        let day = 86_400.0
        func c(_ name: String, _ image: String, _ project: String?, running: Bool = true, up: Double = 6 * day,
               exit: Int = 0, health: String? = nil, ports: [(Int, Int?)] = [], restarts: Int = 0) -> Container {
            let id = Self.containerID(name)
            return Container(id: id, name: name, image: image, project: project, running: running,
                             startedAt: now.addingTimeInterval(-up), exitCode: exit, health: health, ports: ports, restarts: restarts)
        }
        if portainer {
            containers = Mutex(["1": [
                c("service-01", "nginx:1.27", "stack-a", health: "healthy", ports: [(8080, 8080)]),
                c("service-02", "redis:7", "stack-a", ports: [(6379, 6379)]),
                c("service-03", "busybox:1.36", "stack-a", up: 2 * day, restarts: 3),
                c("service-04", "caddy:2.8", "stack-b", health: "healthy", ports: [(80, 8081)]),
                c("service-05", "nginx:1.27", "stack-c", health: "healthy", ports: [(8000, 8000)]),
                c("service-06", "redis:7", "stack-c"),
                c("service-07", "alpine:3.20", nil, running: false, up: 3 * day, exit: 0),
            ]])
        } else {
            containers = Mutex(["engine": [
                c("service-08", "nginx:1.27", "stack-d", health: "healthy", ports: [(8096, 8096)]),
                c("service-09", "nginx:1.27", "stack-d", ports: [(8989, 8989)]),
                c("service-10", "nginx:1.27", "stack-d", ports: [(7878, 7878)]),
                c("service-11", "nginx:1.27", "stack-d", ports: [(8080, 8090)]),
                c("service-12", "prom/prometheus:v2.54", "stack-e", ports: [(9090, 9090)]),
                c("service-13", "grafana/grafana:11.2", "stack-e", ports: [(3000, 3000)]),
                c("service-14", "prom/node-exporter:v1.8", "stack-e"),
                c("service-15", "nginx:1.27", nil, health: "unhealthy", ports: [(3001, 3001)], restarts: 1),
                c("service-16", "alpine:3.20", nil, running: false, up: 0.2 * day, exit: 1),
                c("service-17", "nginx:1.27", "stack-f", ports: [(80, 8443)]),
                c("service-18", "mariadb:11", "stack-f"),
            ]])
        }
    }

    static func containerID(_ name: String) -> String {
        // Stable 64 hex characters derived from the name.
        var value: UInt64 = 1_469_598_103_934_665_603
        for byte in name.utf8 { value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        let chunk = String(value, radix: 16)
        let padded = String(repeating: "0", count: max(0, 16 - chunk.count)) + chunk
        return String(repeating: padded, count: 4)
    }

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        var parts = request.segments
        var hostKey = "engine"
        if portainer {
            if request.method == "GET", parts == ["api", "endpoints"] { return endpoints() }
            if request.method == "GET", parts == ["api", "stacks"] { return stacks() }
            guard parts.count > 4, parts[0] == "api", parts[1] == "endpoints", parts[3] == "docker" else { return .notFound }
            hostKey = parts[2]
            parts.removeFirst(4)
            guard hostKey == "1" else { return .json(#"{"message":"environment unreachable"}"#, status: 502) }
        }
        switch (request.method, parts) {
        case ("GET", ["version"]):
            return .json(object: ["Version": "27.2.0", "ApiVersion": "1.47", "Os": "linux", "Arch": "amd64"])
        case ("GET", ["containers", "json"]):
            return .json(object: list(hostKey, now: now))
        case ("GET", let p) where p.count == 3 && p[0] == "containers" && p[2] == "json":
            guard let container = find(hostKey, p[1]) else { return .notFound }
            return .json(object: details(container))
        case ("GET", let p) where p.count == 3 && p[0] == "containers" && p[2] == "stats":
            guard let container = find(hostKey, p[1]) else { return .notFound }
            return .json(object: stats(container, now: now))
        case ("GET", let p) where p.count == 3 && p[0] == "containers" && p[2] == "logs":
            guard let container = find(hostKey, p[1]) else { return .notFound }
            let tail = Int(request.query["tail"] ?? "") ?? 200
            return DemoResponse(contentType: "application/vnd.docker.multiplexed-stream", body: logs(container, tail: tail, now: now))
        case ("POST", let p) where p.count == 3 && p[0] == "containers":
            guard let action = DockerContainerAction(rawValue: p[2]) else { return .notFound }
            return perform(action, hostKey: hostKey, id: p[1], now: now)
        default:
            return .notFound
        }
    }

    // MARK: - Portainer

    private func endpoints() -> DemoResponse {
        .json(object: [
            ["Id": 1, "Name": "server-a", "Type": 1, "URL": "unix:///var/run/docker.sock", "Status": 1],
            ["Id": 2, "Name": "server-b", "Type": 2, "URL": "tcp://server-b.\(DemoServer.domain):9001", "Status": 2],
        ])
    }

    private func stacks() -> DemoResponse {
        .json(object: [
            ["Id": 1, "Name": "stack-a", "Type": 2, "EndpointId": 1, "Status": 1],
            ["Id": 2, "Name": "stack-b", "Type": 2, "EndpointId": 1, "Status": 1],
            ["Id": 3, "Name": "stack-c", "Type": 2, "EndpointId": 1, "Status": 1],
        ])
    }

    // MARK: - Engine

    private func find(_ hostKey: String, _ id: String) -> Container? {
        containers.withLock { $0[hostKey]?.first { $0.id == id || $0.name == id } }
    }

    private func list(_ hostKey: String, now: Date) -> [[String: Any]] {
        containers.withLock { $0[hostKey] ?? [] }.map { container in
            var labels: [String: String] = [:]
            if let project = container.project {
                labels["com.docker.compose.project"] = project
                labels["com.docker.compose.service"] = container.name
                labels["com.docker.compose.project.working_dir"] = "/opt/stacks/\(project)"
                labels["com.docker.compose.project.config_files"] = "/opt/stacks/\(project)/compose.yaml"
            }
            return [
                "Id": container.id, "Names": ["/\(container.name)"], "Image": container.image,
                "Created": Int(container.startedAt.timeIntervalSince1970) - 3_600,
                "State": container.running ? "running" : "exited",
                "Status": status(container, now: now),
                "Labels": labels,
                "Ports": container.ports.map { port -> [String: Any] in
                    var item: [String: Any] = ["PrivatePort": port.0, "Type": "tcp"]
                    if let published = port.1 { item["PublicPort"] = published; item["IP"] = "0.0.0.0" }
                    return item
                },
            ]
        }
    }

    private func status(_ container: Container, now: Date) -> String {
        let elapsed = max(60, now.timeIntervalSince(container.startedAt))
        let span = elapsed >= 86_400 ? "\(Int(elapsed / 86_400)) days" : elapsed >= 3_600 ? "\(Int(elapsed / 3_600)) hours" : "\(Int(elapsed / 60)) minutes"
        guard container.running else { return "Exited (\(container.exitCode)) \(span) ago" }
        return container.health.map { "Up \(span) (\($0))" } ?? "Up \(span)"
    }

    private func details(_ container: Container) -> [String: Any] {
        let iso = container.startedAt.formatted(.iso8601)
        var state: [String: Any] = [
            "Status": container.running ? "running" : "exited", "Running": container.running,
            "Paused": false, "Restarting": false, "OOMKilled": false, "Dead": false,
            "ExitCode": container.running ? 0 : container.exitCode, "StartedAt": iso,
            "FinishedAt": container.running ? "0001-01-01T00:00:00Z" : iso,
        ]
        if let health = container.health {
            state["Health"] = ["Status": health, "FailingStreak": health == "unhealthy" ? 4 : 0, "Log": [
                ["Start": iso, "End": iso, "ExitCode": health == "unhealthy" ? 1 : 0,
                 "Output": health == "unhealthy" ? "curl: (7) Failed to connect to localhost port 3001" : "OK"],
            ]]
        }
        let network = container.project.map { "\($0)_default" } ?? "bridge"
        return [
            "Id": container.id, "Name": "/\(container.name)", "Created": iso, "RestartCount": container.restarts,
            "State": state,
            "Config": ["Image": container.image, "Hostname": String(container.id.prefix(12)), "Labels": [:] as [String: String]],
            "HostConfig": ["NetworkMode": network, "RestartPolicy": ["Name": "unless-stopped", "MaximumRetryCount": 0]],
            "Mounts": [
                ["Type": "bind", "Source": "/srv/\(container.name)/config", "Destination": "/config", "Mode": "rw", "RW": true],
                ["Type": "volume", "Name": "\(container.name)_data", "Source": "", "Destination": "/data", "Driver": "local", "RW": true],
            ],
            "NetworkSettings": ["Networks": [network: ["IPAddress": "172.18.0.\(abs(container.name.count * 7) % 200 + 2)"]]],
        ]
    }

    private func stats(_ container: Container, now: Date) -> [String: Any] {
        let seed = Double(container.name.count)
        let busy = container.running ? 0.02 + 0.15 * (1 + sin(now.timeIntervalSince1970 / 90 + seed)) / 2 : 0
        let system: Int64 = 400_000_000_000
        let delta: Int64 = 2_000_000_000
        let cpuDelta = Int64(Double(delta) * busy / 4 * 4)
        let memory = container.running ? Int64(80_000_000 + Int64(seed) * 21_000_000) : 0
        return [
            "read": now.formatted(.iso8601), "preread": now.addingTimeInterval(-1).formatted(.iso8601),
            "cpu_stats": ["cpu_usage": ["total_usage": 5_000_000_000 + cpuDelta], "system_cpu_usage": system + delta, "online_cpus": 4],
            "precpu_stats": ["cpu_usage": ["total_usage": 5_000_000_000], "system_cpu_usage": system, "online_cpus": 4],
            "memory_stats": ["usage": memory + 10_000_000, "stats": ["inactive_file": 10_000_000], "limit": 8_589_934_592],
            "name": "/\(container.name)", "id": container.id,
        ]
    }

    private func logs(_ container: Container, tail: Int, now: Date) -> Data {
        let messages: [(UInt8, String)] = [
            (1, "Starting \(container.name)…"),
            (1, "Loaded configuration from /config"),
            (1, "Listening on :\(container.ports.first?.0 ?? 8080)"),
            (1, "GET /health 200 1.2ms"),
            (2, "WARN slow request: GET /api/items took 1830ms"),
            (1, "Scheduled task finished in 412ms"),
            (1, "GET /health 200 0.9ms"),
        ]
        let count = min(tail, 60)
        var data = Data()
        for index in 0..<count {
            let date = now.addingTimeInterval(Double(index - count) * 37)
            let (stream, message) = container.health == "unhealthy" && index % 5 == 4
                ? (UInt8(2), "ERROR health check failed: connection refused")
                : messages[index % messages.count]
            let line = Array("\(date.formatted(.iso8601)) \(message)\n".utf8)
            let size = UInt32(line.count)
            data.append(contentsOf: [stream, 0, 0, 0, UInt8(size >> 24 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)])
            data.append(contentsOf: line)
        }
        return data
    }

    private func perform(_ action: DockerContainerAction, hostKey: String, id: String, now: Date) -> DemoResponse {
        let status = containers.withLock { all -> Int in
            guard var list = all[hostKey], let index = list.firstIndex(where: { $0.id == id }) else { return 404 }
            switch action {
            case .start:
                if list[index].running { return 304 }
                list[index].running = true
                list[index].startedAt = now
            case .stop:
                if !list[index].running { return 304 }
                list[index].running = false
                list[index].exitCode = 0
            case .restart:
                list[index].running = true
                list[index].startedAt = now
            }
            all[hostKey] = list
            return 204
        }
        return DemoResponse(status: status, body: Data())
    }
}

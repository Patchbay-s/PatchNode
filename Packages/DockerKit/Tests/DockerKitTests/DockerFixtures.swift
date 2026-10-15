import Foundation

/// Realistic Docker Engine API / Portainer 2.x responses. Every credential and host
/// is fake (`*.example.invalid`).
enum DockerFixtures {
    static let portainerURL = URL(string: "https://portainer.example.invalid")!
    static let engineURL = URL(string: "https://docker.example.invalid")!
    static let portainerKey = "ptr_FAKE0000000000000000000000000000"
    static let engineCredential = "monitor:fake-password"
    /// base64("monitor:fake-password")
    static let engineBasic = "Basic bW9uaXRvcjpmYWtlLXBhc3N3b3Jk"

    static let containerID = "8dfafdbc3a40c7b6e9b2a1f0d3e4c5b6a7980112233445566778899aabbccdd"

    /// GET /api/endpoints: Docker standalone (1, up), Docker agent (2, down),
    /// Edge agent (4), Azure (3), Kubernetes local (5), Kubernetes agent (6),
    /// Kubernetes edge agent (7).
    static let endpoints = """
    [
      {"Id": 1, "Name": "local", "Type": 1, "URL": "unix:///var/run/docker.sock", "Status": 1,
       "PublicURL": "", "GroupId": 1, "TagIds": [], "Snapshots": []},
      {"Id": 2, "Name": "storage-node", "Type": 2, "URL": "tcp://nas.example.invalid:9001", "Status": 2,
       "PublicURL": "", "GroupId": 1, "TagIds": [], "Snapshots": []},
      {"Id": 3, "Name": "azure-aci", "Type": 3, "URL": "https://management.example.invalid", "Status": 1},
      {"Id": 4, "Name": "server-b", "Type": 4, "URL": "", "Status": 1, "EdgeID": "fake-edge-id"},
      {"Id": 5, "Name": "k8s-local", "Type": 5, "URL": "https://kubernetes.default.svc", "Status": 1},
      {"Id": 6, "Name": "k8s-agent", "Type": 6, "URL": "tcp://k8s.example.invalid:9001", "Status": 1},
      {"Id": 7, "Name": "k8s-edge", "Type": 7, "URL": "", "Status": 1}
    ]
    """

    static func endpointsJSON(_ entries: [(id: Int, name: String, status: Int)]) -> String {
        "[" + entries.map { #"{"Id": \#($0.id), "Name": "\#($0.name)", "Type": 1, "Status": \#($0.status)}"# }
            .joined(separator: ",") + "]"
    }

    /// GET /containers/json?all=true
    static let containers = """
    [
      {
        "Id": "8dfafdbc3a40c7b6e9b2a1f0d3e4c5b6a7980112233445566778899aabbccdd",
        "Names": ["/traefik"],
        "Image": "traefik:v3.1",
        "ImageID": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        "Command": "/entrypoint.sh traefik",
        "Created": 1714557600,
        "Ports": [
          {"IP": "0.0.0.0", "PrivatePort": 443, "PublicPort": 443, "Type": "tcp"},
          {"IP": "::", "PrivatePort": 443, "PublicPort": 443, "Type": "tcp"},
          {"PrivatePort": 8080, "Type": "tcp"},
          {"IP": "0.0.0.0", "PrivatePort": 53, "PublicPort": 5353, "Type": "udp"}
        ],
        "Labels": {
          "com.docker.compose.project": "proxy",
          "com.docker.compose.service": "service-04",
          "com.docker.compose.version": "2.27.0"
        },
        "State": "running",
        "Status": "Up 3 hours (healthy)",
        "HostConfig": {"NetworkMode": "proxy_default"},
        "NetworkSettings": {"Networks": {"proxy_default": {"IPAddress": "192.0.2.1"}}},
        "Mounts": []
      },
      {
        "Names": ["/broken"],
        "Image": "busybox",
        "State": "running",
        "Status": "Up 1 minute"
      },
      {
        "Id": "0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9",
        "Names": ["/backup-job"],
        "Image": "restic/restic:0.16.4",
        "Created": "1714471200",
        "Ports": [],
        "Labels": {},
        "State": "exited",
        "Status": "Exited (137) 3 hours ago"
      },
      {
        "Id": "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100",
        "Names": [],
        "Image": "postgres:16",
        "Labels": null,
        "State": "restarting",
        "Status": "Restarting (1) 5 seconds ago"
      }
    ]
    """

    /// GET /containers/{id}/json (Config.Env holds a fake secret that must never surface).
    static let details = """
    {
      "Id": "8dfafdbc3a40c7b6e9b2a1f0d3e4c5b6a7980112233445566778899aabbccdd",
      "Created": "2024-05-01T09:59:58.000000000Z",
      "Path": "/entrypoint.sh",
      "Args": ["service-04"],
      "State": {
        "Status": "running",
        "Running": true,
        "Paused": false,
        "Restarting": false,
        "OOMKilled": false,
        "Dead": false,
        "Pid": 4242,
        "ExitCode": 0,
        "Error": "",
        "StartedAt": "2024-05-01T10:00:00.123456789Z",
        "FinishedAt": "0001-01-01T00:00:00Z",
        "Health": {
          "Status": "unhealthy",
          "FailingStreak": 3,
          "Log": [
            {"Start": "2024-05-01T10:05:00.1Z", "End": "2024-05-01T10:05:01.2Z", "ExitCode": 1, "Output": "curl: (7) Failed to connect"}
          ]
        }
      },
      "Image": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
      "Name": "/traefik",
      "RestartCount": 2,
      "HostConfig": {
        "Binds": ["/srv/traefik:/etc/traefik:ro"],
        "NetworkMode": "proxy_default",
        "RestartPolicy": {"Name": "unless-stopped", "MaximumRetryCount": 0}
      },
      "Mounts": [
        {"Type": "bind", "Source": "/srv/traefik", "Destination": "/etc/traefik", "Mode": "ro", "RW": false, "Propagation": "rprivate"},
        {"Type": "volume", "Name": "traefik_certs", "Source": "", "Destination": "/certs", "Driver": "local", "Mode": "z", "RW": true}
      ],
      "Config": {
        "Hostname": "8dfafdbc3a40",
        "Tty": true,
        "Env": [
          "POSTGRES_PASSWORD=fake-password-do-not-leak",
          "API_TOKEN=fake-token-1234",
          "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        ],
        "Image": "traefik:v3.1",
        "Labels": {"com.docker.compose.project": "proxy"}
      },
      "NetworkSettings": {
        "Networks": {
          "proxy_default": {"IPAddress": "192.0.2.1"},
          "bridge": {"IPAddress": "192.0.2.2"},
          "monitoring": {"IPAddress": "192.0.2.3"}
        }
      }
    }
    """

    /// GET /containers/{id}/stats?stream=false, cgroup v2.
    /// Δcpu = 250_000_000, Δsystem = 2_000_000_000, 4 CPUs → 50 %.
    static let stats = """
    {
      "read": "2024-05-01T10:00:01.000000000Z",
      "preread": "2024-05-01T10:00:00.000000000Z",
      "pids_stats": {"current": 12, "limit": 18446744073709551615},
      "num_procs": 0,
      "cpu_stats": {
        "cpu_usage": {"total_usage": 1250000000, "usage_in_kernelmode": 250000000, "usage_in_usermode": 1000000000},
        "system_cpu_usage": 400000000000,
        "online_cpus": 4,
        "throttling_data": {"periods": 0, "throttled_periods": 0, "throttled_time": 0}
      },
      "precpu_stats": {
        "cpu_usage": {"total_usage": 1000000000, "usage_in_kernelmode": 200000000, "usage_in_usermode": 800000000},
        "system_cpu_usage": 398000000000,
        "online_cpus": 4,
        "throttling_data": {"periods": 0, "throttled_periods": 0, "throttled_time": 0}
      },
      "memory_stats": {
        "usage": 157286400,
        "stats": {"active_anon": 90000000, "active_file": 10000000, "anon": 100000000, "file": 57286400, "inactive_file": 52428800},
        "limit": 1073741824
      },
      "name": "/traefik",
      "id": "8dfafdbc3a40c7b6e9b2a1f0d3e4c5b6a7980112233445566778899aabbccdd",
      "networks": {
        "eth0": {"rx_bytes": 1000, "rx_packets": 10, "rx_errors": 0, "rx_dropped": 0, "tx_bytes": 2000, "tx_packets": 20, "tx_errors": 0, "tx_dropped": 0},
        "eth1": {"rx_bytes": 500, "rx_packets": 5, "rx_errors": 0, "rx_dropped": 0, "tx_bytes": 250, "tx_packets": 2, "tx_errors": 0, "tx_dropped": 0}
      }
    }
    """

    /// GET /api/stacks
    static let stacks = """
    [
      {"Id": 1, "Name": "proxy", "Type": 2, "EndpointId": 1, "Status": 1, "EntryPoint": "docker-compose.yml",
       "Env": [{"name": "TRAEFIK_TOKEN", "value": "fake-token-1234"}]},
      {"Id": 2, "Name": "media", "Type": 2, "EndpointId": 1, "Status": 2},
      {"Name": "no-id"}
    ]
    """

    /// Builds one multiplexed log frame (stream, 3 zero bytes, big-endian size).
    static func frame(_ stream: UInt8, _ payload: String) -> [UInt8] {
        frame(stream, Array(payload.utf8))
    }

    static func frame(_ stream: UInt8, _ payload: [UInt8]) -> [UInt8] {
        let size = UInt32(payload.count)
        return [stream, 0, 0, 0,
                UInt8(size >> 24 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)]
            + payload
    }
}

import PatchNodeCore

/// Starting points offered when adding a favorite (node_exporter metrics).
public struct PromQLExample: Sendable, Hashable, Identifiable {
    public let id: String
    public let query: String
    public let unit: PromQLUnit

    public static let all: [PromQLExample] = [
        PromQLExample(
            id: "cpu",
            query: #"100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)"#,
            unit: .percent
        ),
        PromQLExample(
            id: "memory",
            query: "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100",
            unit: .percent
        ),
        PromQLExample(
            id: "disk",
            query: #"(1 - node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"}) * 100"#,
            unit: .percent
        ),
    ]
}

import Foundation
import PatchNodeCore

/// `GET /containers/{id}/stats?stream=false`, reduced to what the UI shows.
public struct DockerStats: Sendable, Hashable, Decodable {
    public let cpuTotal: Double?
    public let cpuSystem: Double?
    public let preCPUTotal: Double?
    public let preCPUSystem: Double?
    public let onlineCPUs: Int?
    public let memoryUsage: Double?
    public let memoryLimit: Double?
    /// Page cache that Docker's CLI subtracts from `usage` (cgroup v2
    /// `inactive_file`, v1 `total_inactive_file` or `cache`).
    public let memoryCache: Double?
    public let networkReceived: Double?
    public let networkSent: Double?

    public init(
        cpuTotal: Double?, cpuSystem: Double?, preCPUTotal: Double?, preCPUSystem: Double?,
        onlineCPUs: Int?, memoryUsage: Double?, memoryLimit: Double?, memoryCache: Double? = nil,
        networkReceived: Double? = nil, networkSent: Double? = nil
    ) {
        self.cpuTotal = cpuTotal; self.cpuSystem = cpuSystem; self.preCPUTotal = preCPUTotal
        self.preCPUSystem = preCPUSystem; self.onlineCPUs = onlineCPUs; self.memoryUsage = memoryUsage
        self.memoryLimit = memoryLimit; self.memoryCache = memoryCache
        self.networkReceived = networkReceived; self.networkSent = networkSent
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)

        func cpu(_ key: String) -> (total: Double?, system: Double?, online: Int?, perCPU: Int?) {
            guard let stats = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey(key)) else {
                return (nil, nil, nil, nil)
            }
            let usage = try? stats.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("cpu_usage"))
            let perCPU = (try? usage?.decodeIfPresent([Double].self, forKey: AnyCodingKey("percpu_usage")))??.count
            return (
                usage?.lenientDouble(AnyCodingKey("total_usage")),
                stats.lenientDouble(AnyCodingKey("system_cpu_usage")),
                stats.lenientInt(AnyCodingKey("online_cpus")),
                perCPU
            )
        }

        let current = cpu("cpu_stats")
        let previous = cpu("precpu_stats")
        cpuTotal = current.total
        cpuSystem = current.system
        preCPUTotal = previous.total
        preCPUSystem = previous.system
        onlineCPUs = current.online ?? current.perCPU

        let memory = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("memory_stats"))
        memoryUsage = memory?.lenientDouble(AnyCodingKey("usage"))
        memoryLimit = memory?.lenientDouble(AnyCodingKey("limit"))
        let memoryDetails = try? memory?.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("stats"))
        memoryCache = memoryDetails?.lenientDouble(AnyCodingKey("inactive_file"))
            ?? memoryDetails?.lenientDouble(AnyCodingKey("total_inactive_file"))
            ?? memoryDetails?.lenientDouble(AnyCodingKey("cache"))

        var received = 0.0
        var sent = 0.0
        var sawNetwork = false
        if let networks = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("networks")) {
            for key in networks.allKeys {
                guard let interface = try? networks.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else { continue }
                received += interface.lenientDouble(AnyCodingKey("rx_bytes")) ?? 0
                sent += interface.lenientDouble(AnyCodingKey("tx_bytes")) ?? 0
                sawNetwork = true
            }
        }
        networkReceived = sawNetwork ? received : nil
        networkSent = sawNetwork ? sent : nil
    }

    /// Docker's own formula: (Δ container CPU / Δ system CPU) × online CPUs × 100.
    /// nil when there's no previous sample (first read, stopped container).
    public var cpuPercent: Double? {
        guard let cpuTotal, let cpuSystem, let preCPUTotal, let preCPUSystem else { return nil }
        let cpuDelta = cpuTotal - preCPUTotal
        let systemDelta = cpuSystem - preCPUSystem
        guard systemDelta > 0, cpuDelta >= 0 else { return nil }
        let percent = cpuDelta / systemDelta * Double(max(onlineCPUs ?? 1, 1)) * 100
        return percent.isFinite ? percent : nil
    }

    /// Working set as shown by `docker stats`: usage minus page cache.
    public var memoryUsed: Double? {
        guard let memoryUsage else { return nil }
        let cache = memoryCache ?? 0
        return cache < memoryUsage ? memoryUsage - cache : memoryUsage
    }

    /// 0…1 fraction of the limit.
    public var memoryFraction: Double? {
        guard let memoryUsed, let memoryLimit, memoryLimit > 0 else { return nil }
        let fraction = memoryUsed / memoryLimit
        return fraction.isFinite ? fraction : nil
    }
}

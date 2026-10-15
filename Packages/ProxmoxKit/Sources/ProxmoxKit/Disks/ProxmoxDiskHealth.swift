import Foundation
import PatchNodeCore

/// A physical disk of a node (`GET /nodes/{node}/disks/list`, `Sys.Audit`).
public struct ProxmoxDisk: Sendable, Hashable, Identifiable, Codable {
    public enum Health: Sendable, Hashable {
        /// SMART overall assessment passed ("PASSED", or "OK" for SAS/NVMe).
        case passed
        case failed
        /// No SMART data (USB bridge, virtual disk, smartctl missing).
        case unknown
    }

    public let devpath: String
    public let model: String?
    public let serial: String?
    public let type: String?
    public let size: Int64?
    /// What uses it: "ZFS", "LVM", "partitions", "mounted"…
    public let usage: String?
    public let health: Health
    /// SSD/NVMe life left, in percent (100 = new). Proxmox's GUI shows 100 minus
    /// this value as "Wearout". nil for hard disks or when unknown.
    public let lifeLeft: Int?
    public var id: String { devpath }

    /// SSD/NVMe life left at or below this is flagged.
    public static let lowLifeLeft = 10

    public init(
        devpath: String, model: String? = nil, serial: String? = nil, type: String? = nil,
        size: Int64? = nil, usage: String? = nil, health: Health, lifeLeft: Int? = nil
    ) {
        self.devpath = devpath; self.model = model; self.serial = serial; self.type = type
        self.size = size; self.usage = usage; self.health = health; self.lifeLeft = lifeLeft
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let devpath = c.lenientString(AnyCodingKey("devpath")), !devpath.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing devpath"))
        }
        self.devpath = devpath
        model = c.lenientString(AnyCodingKey("model"))
        serial = c.lenientString(AnyCodingKey("serial"))
        type = c.lenientString(AnyCodingKey("type"))
        size = c.lenientDouble(AnyCodingKey("size")).map { Int64(max(0, min($0, Double(Int64.max)))) }
        usage = c.lenientString(AnyCodingKey("used"))
        health = switch c.lenientString(AnyCodingKey("health"))?.uppercased() {
        case "PASSED", "OK": .passed
        case "FAILED": .failed
        default: .unknown
        }
        // "N/A" (string) for disks without a wear indicator.
        lifeLeft = c.lenientInt(AnyCodingKey("wearout")).flatMap { (0...100).contains($0) ? $0 : nil }
    }

    /// In the shape Proxmox sends, so a stored reading decodes like the API.
    /// Never the serial number: shown nowhere, it would only end up in backups.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(devpath, forKey: AnyCodingKey("devpath"))
        try c.encodeIfPresent(model, forKey: AnyCodingKey("model"))
        try c.encodeIfPresent(type, forKey: AnyCodingKey("type"))
        try c.encodeIfPresent(size, forKey: AnyCodingKey("size"))
        try c.encodeIfPresent(usage, forKey: AnyCodingKey("used"))
        let health = switch health {
        case .passed: "PASSED"
        case .failed: "FAILED"
        case .unknown: "UNKNOWN"
        }
        try c.encode(health, forKey: AnyCodingKey("health"))
        try c.encodeIfPresent(lifeLeft, forKey: AnyCodingKey("wearout"))
    }

    public var level: HealthLevel {
        if health == .failed { return .critical }
        if let lifeLeft, lifeLeft <= Self.lowLifeLeft { return .warning }
        return .ok
    }
}

/// A ZFS pool of a node (`GET /nodes/{node}/disks/zfs`, `Sys.Audit`).
public struct ProxmoxZFSPool: Sendable, Hashable, Identifiable, Codable {
    public let name: String
    /// "ONLINE", "DEGRADED", "FAULTED", "OFFLINE", "UNAVAIL", "REMOVED", "SUSPENDED".
    public let health: String
    public let size: Int64?
    public let allocated: Int64?
    public let fragmentation: Int?
    public var id: String { name }

    /// Used share flagged from here (ZFS slows down when nearly full).
    public static let warningUsage = 0.8
    public static let criticalUsage = 0.9

    public init(name: String, health: String, size: Int64? = nil, allocated: Int64? = nil, fragmentation: Int? = nil) {
        self.name = name; self.health = health.uppercased(); self.size = size
        self.allocated = allocated; self.fragmentation = fragmentation
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let name = c.lenientString(AnyCodingKey("name")), !name.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing name"))
        }
        self.name = name
        health = (c.lenientString(AnyCodingKey("health")) ?? "UNKNOWN").uppercased()
        let bytes: (String) -> Int64? = { key in
            c.lenientDouble(AnyCodingKey(key)).map { Int64(max(0, min($0, Double(Int64.max)))) }
        }
        size = bytes("size")
        allocated = bytes("alloc")
        fragmentation = c.lenientInt(AnyCodingKey("frag"))
    }

    /// In the shape Proxmox sends, so a stored reading decodes like the API.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(name, forKey: AnyCodingKey("name"))
        try c.encode(health, forKey: AnyCodingKey("health"))
        try c.encodeIfPresent(size, forKey: AnyCodingKey("size"))
        try c.encodeIfPresent(allocated, forKey: AnyCodingKey("alloc"))
        try c.encodeIfPresent(fragmentation, forKey: AnyCodingKey("frag"))
    }

    /// Allocated share of the pool, nil if unknown.
    public var usage: Double? {
        guard let size, size > 0, let allocated else { return nil }
        return Double(allocated) / Double(size)
    }

    public var level: HealthLevel {
        switch health {
        case "ONLINE": break
        case "DEGRADED": return max(.warning, usageLevel)
        default: return .critical
        }
        return usageLevel
    }

    private var usageLevel: HealthLevel {
        guard let usage else { return .ok }
        if usage >= Self.criticalUsage { return .critical }
        if usage >= Self.warningUsage { return .warning }
        return .ok
    }
}

/// Disks and ZFS pools of every online node of one Proxmox VE service. Read
/// only through `DiskHealthAccess` (`disks/list` runs smartctl on the node),
/// then kept in `SMARTReadingStore`.
public struct ProxmoxDiskHealth: Sendable, Hashable, Codable {
    public struct Node: Sendable, Hashable, Identifiable, Codable {
        public let name: String
        /// Failed first, then by device path.
        public let disks: [ProxmoxDisk]
        public let pools: [ProxmoxZFSPool]
        /// Parts refused (missing Sys.Audit) or unreadable on this node.
        public let unavailable: Set<Part>
        public var id: String { name }

        public init(name: String, disks: [ProxmoxDisk], pools: [ProxmoxZFSPool], unavailable: Set<Part> = []) {
            self.name = name
            self.disks = disks.sorted { ($0.level, $1.devpath) > ($1.level, $0.devpath) }
            self.pools = pools.sorted { ($0.level, $1.name) > ($1.level, $0.name) }
            self.unavailable = unavailable
        }

        public var level: HealthLevel {
            (disks.map(\.level) + pools.map(\.level)).max() ?? .ok
        }
    }

    public enum Part: String, Sendable, Hashable, CaseIterable, Codable {
        case disks, zfs
    }

    /// Something to point out: a failed or worn disk, a pool not ONLINE or nearly full.
    public struct Issue: Sendable, Hashable, Identifiable {
        public enum Subject: Sendable, Hashable {
            case disk(devpath: String, model: String?)
            case pool(name: String)
        }

        public let node: String
        public let subject: Subject
        public let level: HealthLevel
        public var id: String {
            switch subject {
            case .disk(let devpath, _): "\(node)/disk\(devpath)"
            case .pool(let name): "\(node)/pool/\(name)"
            }
        }
    }

    public let nodes: [Node]

    public init(nodes: [Node]) {
        self.nodes = nodes.sorted { $0.name < $1.name }
    }

    public var level: HealthLevel {
        nodes.map(\.level).max() ?? .ok
    }

    /// Worst first.
    public var issues: [Issue] {
        nodes.flatMap { node in
            node.disks.filter { $0.level != .ok }.map {
                Issue(node: node.name, subject: .disk(devpath: $0.devpath, model: $0.model), level: $0.level)
            } + node.pools.filter { $0.level != .ok }.map {
                Issue(node: node.name, subject: .pool(name: $0.name), level: $0.level)
            }
        }
        .sorted { ($0.level, $1.id) > ($1.level, $0.id) }
    }

    public var hasUnavailableParts: Bool {
        nodes.contains { !$0.unavailable.isEmpty }
    }

    /// Online nodes of the service, then disks and pools node after node,
    /// sequentially: a refused part only empties that part; a revoked token, a
    /// proxy block or an unreachable service stops (one request, no burst).
    /// Runs smartctl on every disk (wakes disks in standby): only through
    /// `DiskHealthAccess`.
    static func load(client: ProxmoxClient, resources: [ProxmoxResource]) async throws -> ProxmoxDiskHealth {
        let nodeNames = resources
            .filter { $0.kind == .node && $0.isOnline }
            .compactMap(\.node)
        var nodes: [Node] = []
        for name in Set(nodeNames).sorted() {
            var unavailable = Set<Part>()
            func optional<T: Sendable>(_ part: Part, _ operation: () async throws -> [T]) async throws -> [T] {
                do {
                    return try await operation()
                } catch let error where ProxmoxNativeBackups.stopsLoading(error) {
                    throw error
                } catch {
                    unavailable.insert(part)
                    return []
                }
            }
            let disks = try await optional(.disks) { try await client.disks(node: name) }
            let pools = try await optional(.zfs) { try await client.zfsPools(node: name) }
            nodes.append(Node(name: name, disks: disks, pools: pools, unavailable: unavailable))
        }
        return ProxmoxDiskHealth(nodes: nodes)
    }
}

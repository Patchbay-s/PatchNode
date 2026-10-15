import Foundation
import PatchNodeCore

/// One entry of `GET /cluster/resources`.
public struct ProxmoxResource: Sendable, Hashable, Identifiable, Decodable {
    public enum Kind: Sendable, Hashable {
        case node
        case guest(ProxmoxGuestType)
        case storage
        case other(String)
    }

    /// Proxmox id, e.g. `node/pve`, `qemu/100`, `lxc/101`, `storage/pve/local`.
    public let id: String
    public let kind: Kind
    public let node: String?
    public let vmid: Int?
    public let name: String?
    public let status: String?
    /// Fraction of `maxCPU` in use (0…1).
    public let cpu: Double?
    public let maxCPU: Double?
    public let memory: Int?
    public let maxMemory: Int?
    public let disk: Int?
    public let maxDisk: Int?
    public let uptime: Int?
    public let storage: String?
    public let isShared: Bool
    public let isTemplate: Bool
    public let tags: [String]
    /// Storage only: content types it holds (`images`, `rootdir`, `backup`, `iso`…).
    public let content: [String]

    public init(
        id: String, kind: Kind, node: String? = nil, vmid: Int? = nil, name: String? = nil,
        status: String? = nil, cpu: Double? = nil, maxCPU: Double? = nil, memory: Int? = nil,
        maxMemory: Int? = nil, disk: Int? = nil, maxDisk: Int? = nil, uptime: Int? = nil,
        storage: String? = nil, isShared: Bool = false, isTemplate: Bool = false, tags: [String] = [],
        content: [String] = []
    ) {
        self.id = id; self.kind = kind; self.node = node; self.vmid = vmid; self.name = name
        self.status = status; self.cpu = cpu; self.maxCPU = maxCPU; self.memory = memory
        self.maxMemory = maxMemory; self.disk = disk; self.maxDisk = maxDisk; self.uptime = uptime
        self.storage = storage; self.isShared = isShared; self.isTemplate = isTemplate; self.tags = tags
        self.content = content
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let type = c.lenientString(AnyCodingKey("type")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing type"))
        }
        switch type {
        case "node": kind = .node
        case "qemu": kind = .guest(.qemu)
        case "lxc": kind = .guest(.lxc)
        case "storage": kind = .storage
        default: kind = .other(type)
        }
        node = c.lenientString(AnyCodingKey("node"))
        vmid = c.lenientInt(AnyCodingKey("vmid"))
        storage = c.lenientString(AnyCodingKey("storage"))
        let fallbackID = [type, node, vmid.map(String.init), storage].compactMap { $0 }.joined(separator: "/")
        id = c.lenientString(AnyCodingKey("id")) ?? fallbackID
        name = c.lenientString(AnyCodingKey("name"))
        status = c.lenientString(AnyCodingKey("status"))
        cpu = c.lenientDouble(AnyCodingKey("cpu"))
        maxCPU = c.lenientDouble(AnyCodingKey("maxcpu"))
        memory = c.lenientInt(AnyCodingKey("mem"))
        maxMemory = c.lenientInt(AnyCodingKey("maxmem"))
        disk = c.lenientInt(AnyCodingKey("disk"))
        maxDisk = c.lenientInt(AnyCodingKey("maxdisk"))
        uptime = c.lenientInt(AnyCodingKey("uptime"))
        isShared = c.lenientBool(AnyCodingKey("shared")) ?? false
        isTemplate = c.lenientBool(AnyCodingKey("template")) ?? false
        tags = (c.lenientString(AnyCodingKey("tags")) ?? "")
            .split(whereSeparator: { ";, ".contains($0) })
            .map(String.init)
        content = (c.lenientString(AnyCodingKey("content")) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A storage that can hold vzdump backups (local directory, NFS, PBS…).
    public var holdsBackups: Bool {
        kind == .storage && content.contains("backup")
    }

    public var guestType: ProxmoxGuestType? {
        if case .guest(let type) = kind { return type }
        return nil
    }

    /// Nodes report "online"/"offline", guests "running"/"stopped"/"paused",
    /// storages "available".
    public var isOnline: Bool { status == "online" }
    public var isRunning: Bool { status == "running" }

    public var memoryUsage: Double? { ratio(memory, maxMemory) }
    public var diskUsage: Double? { ratio(disk, maxDisk) }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let storage { return storage }
        if let vmid { return String(vmid) }
        return node ?? id
    }

    private func ratio(_ used: Int?, _ total: Int?) -> Double? {
        guard let used, let total, total > 0 else { return nil }
        return Double(used) / Double(total)
    }
}

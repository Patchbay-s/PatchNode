import Foundation
import PatchNodeCore

/// A Proxmox Backup Server datastore with its space usage (`/admin/datastore` +
/// `/admin/datastore/{store}/status`).
public struct PBSDatastore: Sendable, Hashable, Identifiable {
    public let name: String
    public let comment: String?
    public let total: Int?
    public let used: Int?
    public let available: Int?
    /// Latest backup of each guest or host in this datastore.
    public let groups: [PBSBackupGroup]

    public var id: String { name }

    public init(name: String, comment: String? = nil, total: Int? = nil, used: Int? = nil, available: Int? = nil, groups: [PBSBackupGroup] = []) {
        self.name = name; self.comment = comment
        self.total = total; self.used = used; self.available = available
        self.groups = groups
    }

    /// Used / total, nil when unknown.
    public var usage: Double? {
        guard let total, total > 0, let used else { return nil }
        return min(max(Double(used) / Double(total), 0), 1)
    }

    func with(total: Int?, used: Int?, available: Int?, groups: [PBSBackupGroup]) -> PBSDatastore {
        PBSDatastore(name: name, comment: comment, total: total, used: used, available: available, groups: groups)
    }
}

/// Entry of `/admin/datastore`.
struct PBSDatastoreEntry: Decodable {
    let name: String
    let comment: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let name = c.lenientString(AnyCodingKey("store")), !name.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing store"))
        }
        self.name = name
        let comment = c.lenientString(AnyCodingKey("comment"))
        self.comment = (comment?.isEmpty ?? true) ? nil : comment
    }
}

/// `/admin/datastore/{store}/status`.
struct PBSDatastoreStatus: Decodable {
    let total: Int?
    let used: Int?
    let available: Int?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        total = c.lenientInt(AnyCodingKey("total"))
        used = c.lenientInt(AnyCodingKey("used"))
        available = c.lenientInt(AnyCodingKey("avail"))
    }
}

/// Entry of `/admin/datastore/{store}/groups`: one guest (or host) and its latest backup.
public struct PBSBackupGroup: Sendable, Hashable, Identifiable, Decodable {
    public enum BackupType: String, Sendable, Hashable {
        case vm, ct, host
    }

    public let type: BackupType
    /// The VMID for `vm` / `ct`, a host name for `host`.
    public let backupID: String
    public let lastBackup: Date?
    public let count: Int?
    public let comment: String?

    public var id: String { "\(type.rawValue)/\(backupID)" }

    public init(type: BackupType, backupID: String, lastBackup: Date?, count: Int? = nil, comment: String? = nil) {
        self.type = type; self.backupID = backupID; self.lastBackup = lastBackup
        self.count = count; self.comment = comment
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let rawType = c.lenientString(AnyCodingKey("backup-type")), let type = BackupType(rawValue: rawType),
              let backupID = c.lenientString(AnyCodingKey("backup-id")), !backupID.isEmpty
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing group"))
        }
        self.type = type
        self.backupID = backupID
        lastBackup = c.lenientDouble(AnyCodingKey("last-backup")).map { Date(timeIntervalSince1970: $0) }
        count = c.lenientInt(AnyCodingKey("backup-count"))
        let comment = c.lenientString(AnyCodingKey("comment"))
        self.comment = (comment?.isEmpty ?? true) ? nil : comment
    }
}

/// Entry of `/nodes/localhost/tasks`, mapped onto `ProxmoxTask` (PBS names the
/// type `worker_type` and the target `worker_id`, e.g. `store:vm/100`).
struct PBSTaskEntry: Decodable {
    let task: ProxmoxTask

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let upid = c.lenientString(AnyCodingKey("upid")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing upid"))
        }
        let target = c.lenientString(AnyCodingKey("worker_id"))
        let status = c.lenientString(AnyCodingKey("status"))
        task = ProxmoxTask(
            id: upid,
            node: c.lenientString(AnyCodingKey("node")),
            type: c.lenientString(AnyCodingKey("worker_type")) ?? "unknown",
            targetID: (target?.isEmpty ?? true) ? nil : target,
            user: c.lenientString(AnyCodingKey("user")),
            startTime: c.lenientDouble(AnyCodingKey("starttime")).map { Date(timeIntervalSince1970: $0) },
            endTime: c.lenientDouble(AnyCodingKey("endtime")).map { Date(timeIntervalSince1970: $0) },
            rawStatus: (status?.isEmpty ?? true) ? nil : status
        )
    }
}

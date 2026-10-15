import Foundation
import PatchNodeCore

/// One scheduled vzdump job (`GET /cluster/backup`).
public struct ProxmoxBackupJob: Sendable, Hashable, Identifiable, Decodable {
    public enum Selection: Sendable, Hashable {
        case all(excluding: [Int])
        case guests([Int])
        /// Resource pool.
        case pool(String)
    }

    public let id: String
    public let isEnabled: Bool
    public let schedule: String?
    public let storage: String?
    public let selection: Selection
    /// Node the job is restricted to, if any.
    public let node: String?
    public let mode: String?
    public let comment: String?
    public let nextRun: Date?

    public init(
        id: String, isEnabled: Bool = true, schedule: String? = nil, storage: String? = nil,
        selection: Selection, node: String? = nil, mode: String? = nil, comment: String? = nil, nextRun: Date? = nil
    ) {
        self.id = id; self.isEnabled = isEnabled; self.schedule = schedule; self.storage = storage
        self.selection = selection; self.node = node; self.mode = mode; self.comment = comment; self.nextRun = nextRun
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.lenientString(AnyCodingKey("id")), !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        isEnabled = c.lenientBool(AnyCodingKey("enabled")) ?? true
        schedule = c.lenientString(AnyCodingKey("schedule"))
            ?? c.lenientString(AnyCodingKey("starttime")).map { time in
                (c.lenientString(AnyCodingKey("dow")).map { "\($0) " } ?? "") + time
            }
        storage = c.lenientString(AnyCodingKey("storage"))
        node = c.lenientString(AnyCodingKey("node"))
        mode = c.lenientString(AnyCodingKey("mode"))
        comment = c.lenientString(AnyCodingKey("comment"))
        nextRun = c.lenientDouble(AnyCodingKey("next-run")).map { Date(timeIntervalSince1970: $0) }
        let ids: (String?) -> [Int] = { list in
            (list ?? "").split(whereSeparator: { ", ".contains($0) }).compactMap { Int($0) }
        }
        if c.lenientBool(AnyCodingKey("all")) == true {
            selection = .all(excluding: ids(c.lenientString(AnyCodingKey("exclude"))))
        } else if let pool = c.lenientString(AnyCodingKey("pool")), !pool.isEmpty {
            selection = .pool(pool)
        } else {
            selection = .guests(ids(c.lenientString(AnyCodingKey("vmid"))))
        }
    }
}

/// A guest no enabled job covers (`GET /cluster/backup-info/not-backed-up`).
public struct ProxmoxUnprotectedGuest: Sendable, Hashable, Identifiable, Decodable {
    public let vmid: Int
    public let name: String?
    public let type: ProxmoxGuestType?
    public var id: Int { vmid }

    public init(vmid: Int, name: String? = nil, type: ProxmoxGuestType? = nil) {
        self.vmid = vmid; self.name = name; self.type = type
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let vmid = c.lenientInt(AnyCodingKey("vmid")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing vmid"))
        }
        self.vmid = vmid
        name = c.lenientString(AnyCodingKey("name"))
        type = c.lenientString(AnyCodingKey("type")).flatMap(ProxmoxGuestType.init(rawValue:))
    }
}

/// One backup archive in a storage (`…/storage/{storage}/content?content=backup`).
public struct ProxmoxBackupFile: Sendable, Hashable, Identifiable, Decodable {
    public let volid: String
    public let vmid: Int?
    public let created: Date?
    public let size: Int?
    public let format: String?
    public let notes: String?
    public let isProtected: Bool
    /// Filled in by the client: where the archive was listed.
    public let node: String?
    public let storage: String?
    public var id: String { volid }

    public init(
        volid: String, vmid: Int?, created: Date?, size: Int? = nil, format: String? = nil,
        notes: String? = nil, isProtected: Bool = false, node: String? = nil, storage: String? = nil
    ) {
        self.volid = volid; self.vmid = vmid; self.created = created; self.size = size; self.format = format
        self.notes = notes; self.isProtected = isProtected; self.node = node; self.storage = storage
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let volid = c.lenientString(AnyCodingKey("volid")), !volid.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing volid"))
        }
        self.volid = volid
        vmid = c.lenientInt(AnyCodingKey("vmid"))
        created = c.lenientDouble(AnyCodingKey("ctime")).map { Date(timeIntervalSince1970: $0) }
        size = c.lenientInt(AnyCodingKey("size"))
        format = c.lenientString(AnyCodingKey("format"))
        notes = c.lenientString(AnyCodingKey("notes"))
        isProtected = c.lenientBool(AnyCodingKey("protected")) ?? false
        node = nil
        storage = nil
    }

    func located(node: String, storage: String) -> ProxmoxBackupFile {
        ProxmoxBackupFile(
            volid: volid, vmid: vmid, created: created, size: size, format: format,
            notes: notes, isProtected: isProtected, node: node, storage: storage
        )
    }
}

/// Native Proxmox VE backups of one service: jobs, guests without a job, latest
/// archive per guest, failed backup tasks. Loaded on demand (its own screen),
/// never on the periodic refresh.
public struct ProxmoxNativeBackups: Sendable, Hashable {
    public struct GuestBackup: Sendable, Hashable, Identifiable {
        public let guest: ProxmoxResource
        /// nil: no archive found in the storages that could be read.
        public let latest: ProxmoxBackupFile?
        public let count: Int
        public var id: String { guest.id }
    }

    static let maxConcurrentStorages = 3

    /// Errors that end the whole load instead of emptying one part: a rejected
    /// token, a reverse-proxy block (more requests could get the IP banned) and
    /// an unreachable service (every other request would wait for its timeout
    /// too). A 403 from Proxmox itself is a missing right on that endpoint only.
    static func stopsLoading(_ error: any Error) -> Bool {
        switch error {
        case is CancellationError, is TimeoutError: true
        case ServiceProviderError.unauthorized, ServiceProviderError.blockedByProxy, ServiceProviderError.unreachable: true
        default: false
        }
    }

    /// Guests without a backup for this long are flagged (as for PBS).
    public static let staleAge: TimeInterval = PBSInventory.staleBackupAge

    public let jobs: [ProxmoxBackupJob]
    public let unprotected: [ProxmoxUnprotectedGuest]
    /// Every non-template guest, latest backup first-missing, then oldest first.
    public let guests: [GuestBackup]
    public let failedTasks: [ProxmoxTask]
    /// Parts refused or unreachable: the screen says which list may be incomplete.
    public let unavailable: Set<Part>

    public enum Part: String, Sendable, Hashable, CaseIterable {
        case jobs, unprotected, archives
    }

    public init(
        resources: [ProxmoxResource], jobs: [ProxmoxBackupJob], unprotected: [ProxmoxUnprotectedGuest],
        files: [ProxmoxBackupFile], tasks: [ProxmoxTask], unavailable: Set<Part> = [], now: Date = .now
    ) {
        self.jobs = jobs.sorted { $0.id < $1.id }
        self.unprotected = unprotected.sorted { $0.vmid < $1.vmid }
        self.unavailable = unavailable
        var byGuest: [Int: [ProxmoxBackupFile]] = [:]
        // The same archive seen through a shared storage from two nodes counts once.
        var seen = Set<String>()
        for file in files where seen.insert(file.volid).inserted {
            if let vmid = file.vmid { byGuest[vmid, default: []].append(file) }
        }
        guests = resources
            .filter { $0.guestType != nil && !$0.isTemplate && $0.vmid != nil }
            .map { guest in
                let archives = byGuest[guest.vmid!] ?? []
                return GuestBackup(guest: guest, latest: archives.max { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }, count: archives.count)
            }
            .sorted { lhs, rhs in
                switch (lhs.latest?.created, rhs.latest?.created) {
                case (nil, nil): return (lhs.guest.vmid ?? 0) < (rhs.guest.vmid ?? 0)
                case (nil, _): return true
                case (_, nil): return false
                case let (l?, r?): return l < r
                }
            }
        let dayAgo = now.addingTimeInterval(-86_400)
        failedTasks = tasks
            .filter { $0.type == "vzdump" && $0.isFailed && ($0.startTime ?? .distantPast) >= dayAgo }
            .sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
    }

    /// No archive, or the latest older than `staleAge`.
    public func isStale(_ backup: GuestBackup, now: Date = .now) -> Bool {
        guard let created = backup.latest?.created else { return true }
        return now.timeIntervalSince(created) > Self.staleAge
    }

    /// The storages to list: every storage that holds backups, once per shared
    /// storage (from its first online node), once per node otherwise.
    public static func storagesToList(_ resources: [ProxmoxResource]) -> [(node: String, storage: String)] {
        let onlineNodes = Set(resources.filter { $0.kind == .node && $0.isOnline }.compactMap(\.node))
        var result: [(node: String, storage: String)] = []
        var sharedSeen = Set<String>()
        for item in resources where item.holdsBackups && item.status != "unknown" {
            guard let node = item.node, onlineNodes.contains(node), let storage = item.storage else { continue }
            if item.isShared {
                guard sharedSeen.insert(storage).inserted else { continue }
            }
            result.append((node, storage))
        }
        return result
    }

    /// Everything the screen needs, sequentially (a refused part only empties that
    /// part; a 401 stops, a revoked token costs one request).
    public static func load(client: ProxmoxClient, resources: [ProxmoxResource], tasks: [ProxmoxTask], now: Date = .now) async throws -> ProxmoxNativeBackups {
        var unavailable = Set<Part>()
        func optional<T: Sendable>(_ part: Part, _ fallback: T, _ operation: () async throws -> T) async throws -> T {
            do {
                return try await operation()
            } catch let error where Self.stopsLoading(error) {
                throw error
            } catch {
                unavailable.insert(part)
                return fallback
            }
        }
        let jobs = try await optional(.jobs, []) { try await client.backupJobs() }
        let unprotected = try await optional(.unprotected, []) { try await client.guestsNotBackedUp() }
        // Storages at most three at a time: one slow NFS or CIFS share doesn't
        // hold the others up.
        var files: [ProxmoxBackupFile] = []
        let locations = storagesToList(resources)
        let listed = try await withThrowingTaskGroup(of: [ProxmoxBackupFile]?.self) { group in
            var results: [[ProxmoxBackupFile]?] = []
            var next = 0
            func addNext() {
                guard next < locations.count else { return }
                let location = locations[next]
                next += 1
                group.addTask {
                    do {
                        return try await client.backups(node: location.node, storage: location.storage)
                    } catch let error where Self.stopsLoading(error) {
                        throw error
                    } catch {
                        return nil
                    }
                }
            }
            for _ in 0..<Self.maxConcurrentStorages { addNext() }
            while let result = try await group.next() {
                results.append(result)
                addNext()
            }
            return results
        }
        for result in listed {
            if let result { files += result } else { unavailable.insert(.archives) }
        }
        return ProxmoxNativeBackups(
            resources: resources, jobs: jobs, unprotected: unprotected, files: files,
            tasks: tasks, unavailable: unavailable, now: now
        )
    }
}

extension ProxmoxInventory {
    /// Nodes, guests and storages shown for one service (none for a service that
    /// duplicates an earlier one's cluster).
    public func resources(of serviceID: UUID) -> [ProxmoxResource] {
        (nodes + guests + storages).filter { $0.serviceID == serviceID }.map(\.resource)
    }

    /// Recent tasks of one service.
    public func tasks(of serviceID: UUID) -> [ProxmoxTask] {
        tasks.filter { $0.serviceID == serviceID }.map(\.task)
    }
}

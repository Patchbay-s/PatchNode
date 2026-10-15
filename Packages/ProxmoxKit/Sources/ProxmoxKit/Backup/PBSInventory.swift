import Foundation
import PatchNodeCore

/// What one Proxmox Backup Server returned during a refresh.
public struct PBSServiceSnapshot: Sendable, Hashable {
    public let serviceID: UUID
    public let serviceName: String
    public let datastores: [PBSDatastore]
    public let tasks: [ProxmoxTask]
    public let fetchedAt: Date

    public init(serviceID: UUID, serviceName: String, datastores: [PBSDatastore], tasks: [ProxmoxTask] = [], fetchedAt: Date = .now) {
        self.serviceID = serviceID; self.serviceName = serviceName
        self.datastores = datastores; self.tasks = tasks; self.fetchedAt = fetchedAt
    }
}

/// Datastores, recent tasks and latest backup per guest across every configured PBS.
public struct PBSInventory: Sendable {
    public struct DatastoreItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let datastore: PBSDatastore
        public var id: String { "\(serviceID.uuidString)|\(datastore.name)" }
    }

    public struct TaskItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let task: ProxmoxTask
        public var id: String { "\(serviceID.uuidString)|\(task.id)" }
    }

    /// Latest backup of one guest, whatever the datastore or server.
    public struct LastBackup: Sendable, Hashable, Identifiable {
        public let type: PBSBackupGroup.BackupType
        public let backupID: String
        public let date: Date
        public let datastore: String
        public let serviceName: String
        public var id: String { "\(type.rawValue)/\(backupID)" }
    }

    public static let storageAlertThreshold = 0.85
    public static let failedTaskWindow: TimeInterval = 24 * 60 * 60
    /// A guest without a backup for longer than this is flagged.
    public static let staleBackupAge: TimeInterval = 48 * 60 * 60

    public let datastores: [DatastoreItem]
    /// Most recent first.
    public let tasks: [TaskItem]
    /// Sorted by type then numeric ID.
    public let lastBackups: [LastBackup]
    public let overview: PBSOverview

    private let lastBackupIndex: [String: LastBackup]

    public init(snapshots: [PBSServiceSnapshot], now: Date = .now) {
        var datastores: [DatastoreItem] = []
        var tasks: [TaskItem] = []
        var latest: [String: LastBackup] = [:]
        for snapshot in snapshots {
            for store in snapshot.datastores {
                datastores.append(DatastoreItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, datastore: store))
                for group in store.groups {
                    guard let date = group.lastBackup else { continue }
                    let candidate = LastBackup(type: group.type, backupID: group.backupID, date: date, datastore: store.name, serviceName: snapshot.serviceName)
                    if let existing = latest[candidate.id], existing.date >= date { continue }
                    latest[candidate.id] = candidate
                }
            }
            tasks += snapshot.tasks.map { TaskItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, task: $0) }
        }
        self.datastores = datastores
        self.tasks = tasks.sorted { ($0.task.startTime ?? .distantPast) > ($1.task.startTime ?? .distantPast) }
        self.lastBackupIndex = latest
        self.lastBackups = latest.values.sorted { lhs, rhs in
            if lhs.type != rhs.type { return lhs.type.rawValue < rhs.type.rawValue }
            if let l = Int(lhs.backupID), let r = Int(rhs.backupID), l != r { return l < r }
            return lhs.backupID.localizedStandardCompare(rhs.backupID) == .orderedAscending
        }
        self.overview = PBSOverview(datastores: datastores, tasks: self.tasks, lastBackups: self.lastBackups, now: now)
    }

    /// Latest backup of a Proxmox VE guest (`vm` for QEMU, `ct` for LXC), if any.
    public func lastBackup(vmid: Int, type: ProxmoxGuestType) -> LastBackup? {
        lastBackupIndex["\(type == .qemu ? "vm" : "ct")/\(vmid)"]
    }
}

public struct PBSOverview: Sendable, Hashable {
    public let datastoresTotal: Int
    public let datastoresAboveThreshold: Int
    public let failedTasks24h: Int
    public let succeededBackups24h: Int
    public let guestsBackedUp: Int
    public let staleBackups: Int
    public let latestBackup: Date?

    init(datastores: [PBSInventory.DatastoreItem], tasks: [PBSInventory.TaskItem], lastBackups: [PBSInventory.LastBackup], now: Date) {
        datastoresTotal = datastores.count
        datastoresAboveThreshold = datastores.count { ($0.datastore.usage ?? 0) >= PBSInventory.storageAlertThreshold }
        let recent = tasks.filter { ($0.task.startTime ?? .distantPast) >= now.addingTimeInterval(-PBSInventory.failedTaskWindow) }
        failedTasks24h = recent.count { $0.task.isFailed }
        succeededBackups24h = recent.count { $0.task.type == "backup" && $0.task.state == .ok }
        guestsBackedUp = lastBackups.count
        staleBackups = lastBackups.count { $0.type != .host && now.timeIntervalSince($0.date) > PBSInventory.staleBackupAge }
        latestBackup = lastBackups.map(\.date).max()
    }

    /// Critical: no server answered. Warning: a server failed, a task failed in the
    /// last 24 h, a datastore is above 85 % or a guest has no recent backup.
    public func level(failedServices: Int, totalServices: Int) -> HealthLevel {
        if totalServices > 0 && failedServices >= totalServices { return .critical }
        if failedServices > 0 || failedTasks24h > 0 || datastoresAboveThreshold > 0 || staleBackups > 0 { return .warning }
        return .ok
    }
}

/// Proxmox Backup Server (`Authorization: PBSAPIToken=…`).
public struct PBSProvider: ServiceProvider {
    public let id: UUID
    public let kind: ServiceKind = .proxmoxBackupServer
    public let displayName: String
    public let client: PBSClient

    public init(id: UUID, displayName: String, baseURL: URL, apiTokenValue: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.id = id
        self.displayName = displayName
        self.client = PBSClient(baseURL: baseURL, apiTokenValue: apiTokenValue, httpClient: httpClient)
    }

    public func healthCheck() async throws -> HealthStatus {
        do {
            try await client.checkConnection()
            return .ok
        } catch ServiceProviderError.blockedByProxy {
            // The reverse proxy refused (VPN off?): not a token problem.
            return .unreachable(ServiceProviderError.blockedByProxy)
        } catch ServiceProviderError.unauthorized, ServiceProviderError.forbidden {
            return .unauthorized
        } catch ServiceProviderError.unexpectedStatus(let code) {
            return .degraded("HTTP \(code)")
        } catch ServiceProviderError.invalidResponse, ServiceProviderError.decodingFailed {
            return .degraded("invalid response")
        } catch let error as CancellationError {
            throw error
        } catch {
            return .unreachable(ProxmoxProviderError.unreachable)
        }
    }

    public func summary() async throws -> ServiceSummary {
        let snapshot = try await Self.loadSnapshot(client: client, serviceID: id, serviceName: displayName)
        let overview = PBSInventory(snapshots: [snapshot]).overview
        return ServiceSummary(
            headline: String(overview.datastoresTotal),
            details: [
                "datastores": String(overview.datastoresTotal),
                "datastoresAboveThreshold": String(overview.datastoresAboveThreshold),
                "failedTasks24h": String(overview.failedTasks24h),
                "staleBackups": String(overview.staleBackups),
            ]
        )
    }

    /// Datastores first (validates the token), then tasks; a task list failure
    /// doesn't hide the datastores.
    public static func loadSnapshot(client: PBSClient, serviceID: UUID, serviceName: String) async throws -> PBSServiceSnapshot {
        let datastores = try await client.datastores()
        let tasks = try await PBSClient.optional { try await client.tasks() } ?? []
        return PBSServiceSnapshot(serviceID: serviceID, serviceName: serviceName, datastores: datastores, tasks: tasks)
    }
}

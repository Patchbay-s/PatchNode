import Foundation
import PatchNodeCore

/// What one configured Proxmox service returned during a refresh.
public struct ProxmoxServiceSnapshot: Sendable, Hashable {
    public let serviceID: UUID
    public let serviceName: String
    public let resources: [ProxmoxResource]
    public let tasks: [ProxmoxTask]
    /// `/cluster/tasks` failed (refused, timed out…): only the task list is
    /// unavailable, the service itself answered.
    public let tasksUnavailable: Bool
    public let fetchedAt: Date

    public init(
        serviceID: UUID, serviceName: String, resources: [ProxmoxResource], tasks: [ProxmoxTask] = [],
        tasksUnavailable: Bool = false, fetchedAt: Date = .now
    ) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.resources = resources
        self.tasks = tasks
        self.tasksUnavailable = tasksUnavailable
        self.fetchedAt = fetchedAt
    }

    /// Timeout of the secondary `/cluster/tasks` request, so a slow task list can't
    /// push the whole refresh over the store's per-service timeout.
    public static let tasksTimeout: Double = 6

    /// One refresh of a service. `/cluster/resources` is the primary endpoint: its
    /// error (refused token, proxy, timeout…) is the service's state and is thrown.
    /// `/cluster/tasks` is secondary: any error, a 403 included, only marks the
    /// task list unavailable. Sequential on purpose: a refused token costs one
    /// request, not two.
    public static func load(
        serviceID: UUID, serviceName: String, client: ProxmoxClient, tasksTimeout: Double = ProxmoxServiceSnapshot.tasksTimeout
    ) async throws -> ProxmoxServiceSnapshot {
        let resources = try await client.clusterResources()
        // Accepted token that sees nothing: say it instead of an empty list.
        if ProxmoxInventory.lacksPrivileges(resources) { throw ServiceProviderError.insufficientRights }
        let tasks: [ProxmoxTask]?
        do {
            tasks = try await withTimeout(seconds: tasksTimeout) { try await client.clusterTasks() }
        } catch {
            // Only this refresh being cancelled stops it; anything else, a
            // cancelled task list included, only costs the task list.
            if Task.isCancelled { throw CancellationError() }
            tasks = nil
        }
        return ProxmoxServiceSnapshot(
            serviceID: serviceID, serviceName: serviceName, resources: resources,
            tasks: tasks ?? [], tasksUnavailable: tasks == nil
        )
    }
}

extension ProxmoxServiceSnapshot {
    /// VMIDs of the guests `previous` listed that this snapshot no longer lists
    /// although their node answers (listed online). Deleted, migrated out of
    /// sight, or no longer visible to the token (an ACL on /vms/<id> without
    /// PVEAuditor replaces VM.Audit inherited from /): never assumed deleted.
    public func guestsNoLongerListed(since previous: ProxmoxServiceSnapshot) -> [Int] {
        let onlineNodes = Set(resources.filter { $0.kind == .node && $0.isOnline }.compactMap(\.node))
        let listed = Set(resources.filter { $0.guestType != nil }.compactMap(\.vmid))
        let gone = previous.resources.filter { resource in
            guard resource.guestType != nil, let vmid = resource.vmid, let node = resource.node else { return false }
            return !listed.contains(vmid) && onlineNodes.contains(node)
        }
        return Set(gone.compactMap(\.vmid)).sorted()
    }
}

/// Merges the snapshots of every configured Proxmox service into one view.
///
/// Every item carries the service it came from: a resource is identified by
/// (service, node, type, VMID), never by its node name alone. Two standalone hosts
/// both called "pve" (the default), even with identical hardware, stay two
/// distinct nodes with their own guests, and actions go to their own service.
///
/// The only merge: two members of one cluster, each added as its own service,
/// return the same cluster. A snapshot is skipped as such a duplicate when an
/// earlier snapshot has exactly the same nodes (at least two, same names, memory
/// and CPUs), whatever its guests (a VM may be migrating between the two reads). A
/// standalone host has one node and is never merged.
public struct ProxmoxInventory: Sendable {
    public struct Item: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        /// Name of the configured service, shown before the node name.
        public let serviceName: String
        public let resource: ProxmoxResource
        public var id: String { "\(serviceID.uuidString)|\(resource.id)" }
        /// The node, qualified by its service.
        public var nodeKey: NodeKey? { resource.node.map { NodeKey(serviceID: serviceID, node: $0) } }

        public init(serviceID: UUID, serviceName: String = "", resource: ProxmoxResource) {
            self.serviceID = serviceID
            self.serviceName = serviceName
            self.resource = resource
        }
    }

    /// A node of one service: two services may both have a node named "pve".
    public struct NodeKey: Sendable, Hashable {
        public let serviceID: UUID
        public let node: String

        public init(serviceID: UUID, node: String) {
            self.serviceID = serviceID
            self.node = node
        }
    }

    public struct TaskItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let task: ProxmoxTask
        public var id: String { "\(serviceID.uuidString)|\(task.id)" }

        public init(serviceID: UUID, serviceName: String = "", task: ProxmoxTask) {
            self.serviceID = serviceID
            self.serviceName = serviceName
            self.task = task
        }
    }

    public static let storageAlertThreshold = 0.85
    public static let failedTaskWindow: TimeInterval = 24 * 60 * 60

    public let nodes: [Item]
    /// VMs and containers, templates excluded, sorted by service, node then VMID.
    public let guests: [Item]
    public let storages: [Item]
    /// Most recent first.
    public let tasks: [TaskItem]
    public let overview: ProxmoxOverview
    /// Services skipped because they show the same cluster as an earlier one.
    public let duplicateServiceIDs: Set<UUID>
    /// Services whose task list couldn't be read at the last refresh.
    public let tasksUnavailableServiceIDs: Set<UUID>

    public init(snapshots: [ProxmoxServiceSnapshot], now: Date = .now) {
        var seenClusters = Set<Set<String>>()
        var duplicates = Set<UUID>()
        var nodes: [Item] = []
        var guests: [Item] = []
        var storages: [Item] = []
        var tasks: [TaskItem] = []

        for snapshot in snapshots {
            // Name, memory and CPUs of each node: two members of one cluster report
            // the same set, even while a VM migrates between the two reads.
            let nodeSignature = Set(snapshot.resources.filter { $0.kind == .node }.compactMap { node -> String? in
                node.node.map { "\($0)|\(node.maxMemory.map(String.init) ?? "?")|\(node.maxCPU.map { String($0) } ?? "?")" }
            })
            if nodeSignature.count >= 2 {
                guard seenClusters.insert(nodeSignature).inserted else {
                    duplicates.insert(snapshot.serviceID)
                    continue
                }
            }

            var seenResourceIDs = Set<String>()
            for resource in snapshot.resources {
                guard seenResourceIDs.insert(resource.id).inserted else { continue }
                let item = Item(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, resource: resource)
                switch resource.kind {
                case .node where resource.node != nil:
                    nodes.append(item)
                case .guest where !resource.isTemplate:
                    guests.append(item)
                case .storage:
                    storages.append(item)
                default:
                    break
                }
            }

            var seenTaskIDs = Set<String>()
            for task in snapshot.tasks where seenTaskIDs.insert(task.id).inserted {
                tasks.append(TaskItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, task: task))
            }
        }

        // Service order first, so each service's resources stay together.
        let order = Dictionary(snapshots.enumerated().map { ($1.serviceID, $0) }, uniquingKeysWith: { first, _ in first })
        func rank(_ item: Item) -> Int { order[item.serviceID] ?? 0 }
        guests.sort {
            (rank($0), $0.resource.node ?? "", $0.resource.vmid ?? 0) < (rank($1), $1.resource.node ?? "", $1.resource.vmid ?? 0)
        }
        nodes.sort { (rank($0), $0.resource.node ?? "") < (rank($1), $1.resource.node ?? "") }
        tasks.sort { ($0.task.startTime ?? .distantPast) > ($1.task.startTime ?? .distantPast) }

        self.nodes = nodes
        self.guests = guests
        self.storages = storages
        self.tasks = tasks
        self.duplicateServiceIDs = duplicates
        self.tasksUnavailableServiceIDs = Set(snapshots.filter(\.tasksUnavailable).map(\.serviceID))
        self.overview = ProxmoxOverview(nodes: nodes, guests: guests, storages: storages, tasks: tasks, now: now)
    }

    /// What `/cluster/resources` returns to a token that is accepted but has no
    /// permission (Privilege Separation without an ACL): nodes without CPU or
    /// memory figures, and no guest or storage at all.
    public static func lacksPrivileges(_ resources: [ProxmoxResource]) -> Bool {
        let nodes = resources.filter { $0.kind == .node }
        guard !nodes.isEmpty else { return false }
        let bare = nodes.allSatisfy { $0.maxCPU == nil && $0.maxMemory == nil }
        let others = resources.contains { $0.guestType != nil || $0.kind == .storage }
        return bare && !others
    }

    /// Guests running on one node of one service.
    public func guests(on key: NodeKey) -> [Item] {
        guests.filter { $0.nodeKey == key }
    }
}

/// Where a power action goes: the service the resource came from, its node, type
/// and VMID. Built from an inventory item, so an action can't reach a homonymous
/// node of another service.
public struct ProxmoxActionTarget: Sendable, Hashable {
    public let serviceID: UUID
    public let node: String
    public let type: ProxmoxGuestType
    public let vmid: Int

    public init?(item: ProxmoxInventory.Item) {
        guard let node = item.resource.node, let type = item.resource.guestType, let vmid = item.resource.vmid else { return nil }
        self.serviceID = item.serviceID
        self.node = node
        self.type = type
        self.vmid = vmid
    }

    public init(serviceID: UUID, node: String, type: ProxmoxGuestType, vmid: Int) {
        self.serviceID = serviceID
        self.node = node
        self.type = type
        self.vmid = vmid
    }

    /// Stable key for "one action at a time on this target".
    public var key: String { "\(serviceID.uuidString)|\(node)|\(type.rawValue)|\(vmid)" }

    /// Sends `action` with the client of the target's own service; nil when that
    /// service has no usable client (token refused, service removed).
    public func perform(
        _ action: ProxmoxGuestAction,
        clients: @Sendable (UUID) async -> ProxmoxClient?
    ) async throws -> (client: ProxmoxClient, upid: String)? {
        guard let client = await clients(serviceID) else { return nil }
        let upid = try await client.perform(action, node: node, type: type, vmid: vmid)
        return (client, upid)
    }
}

public struct ProxmoxOverview: Sendable, Hashable {
    public let nodesOnline: Int
    public let nodesTotal: Int
    public let vmsRunning: Int
    public let vmsTotal: Int
    public let containersRunning: Int
    public let containersTotal: Int
    /// Storages above `ProxmoxInventory.storageAlertThreshold`; a shared storage
    /// seen from several nodes of one cluster is listed once.
    public let storagesAboveThreshold: [ProxmoxInventory.Item]
    /// Failed tasks started within `ProxmoxInventory.failedTaskWindow`.
    public let recentFailedTasks: Int

    init(
        nodes: [ProxmoxInventory.Item], guests: [ProxmoxInventory.Item],
        storages: [ProxmoxInventory.Item], tasks: [ProxmoxInventory.TaskItem], now: Date
    ) {
        nodesOnline = nodes.count { $0.resource.isOnline }
        nodesTotal = nodes.count
        let vms = guests.filter { $0.resource.guestType == .qemu }
        let containers = guests.filter { $0.resource.guestType == .lxc }
        vmsRunning = vms.count { $0.resource.isRunning }
        vmsTotal = vms.count
        containersRunning = containers.count { $0.resource.isRunning }
        containersTotal = containers.count

        var seenShared = Set<String>()
        storagesAboveThreshold = storages.filter { item in
            guard let usage = item.resource.diskUsage, usage > ProxmoxInventory.storageAlertThreshold else { return false }
            // Shared storages repeat once per node of the same cluster (same service).
            if item.resource.isShared, let name = item.resource.storage {
                return seenShared.insert("\(item.serviceID.uuidString)|\(name)").inserted
            }
            return true
        }

        let windowStart = now.addingTimeInterval(-ProxmoxInventory.failedTaskWindow)
        recentFailedTasks = tasks.count { item in
            item.task.isFailed && (item.task.startTime ?? .distantPast) >= windowStart
        }
    }

    /// Dashboard colour. Critical: no service answered, or every node is offline.
    /// Warning: a service failed, a node is offline, a storage is above 85 %, or a
    /// task failed in the last 24 h.
    public func level(failedServices: Int, totalServices: Int) -> HealthLevel {
        if totalServices > 0 && failedServices >= totalServices { return .critical }
        if nodesTotal > 0 && nodesOnline == 0 { return .critical }
        if failedServices > 0 || nodesOnline < nodesTotal || !storagesAboveThreshold.isEmpty || recentFailedTasks > 0 {
            return .warning
        }
        return .ok
    }
}

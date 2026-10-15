import Foundation
import PatchNodeCore

public struct DockerHostSnapshot: Sendable, Hashable {
    public let host: DockerHost
    public let containers: [DockerContainer]
    /// Set when this host's containers couldn't be listed (Portainer environment
    /// down) while the service itself answered.
    public let error: ServiceProviderError?

    public init(host: DockerHost, containers: [DockerContainer], error: ServiceProviderError? = nil) {
        self.host = host
        self.containers = containers
        self.error = error
    }
}

/// What one configured Docker service (Portainer or engine) returned.
public struct DockerServiceSnapshot: Sendable, Hashable {
    public let serviceID: UUID
    public let serviceName: String
    public let hosts: [DockerHostSnapshot]
    public let stacks: [PortainerStack]
    public let fetchedAt: Date

    public init(serviceID: UUID, serviceName: String, hosts: [DockerHostSnapshot], stacks: [PortainerStack] = [], fetchedAt: Date = .now) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.hosts = hosts
        self.stacks = stacks
        self.fetchedAt = fetchedAt
    }
}

/// Every Docker host and container across the configured services, with
/// containers grouped by compose project (`com.docker.compose.project`).
public struct DockerInventory: Sendable {
    public struct HostItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let host: DockerHost
        public let error: ServiceProviderError?
        public let runningCount: Int
        public let totalCount: Int
        public var id: String { "\(serviceID.uuidString)|\(host.id)" }

        public var isReachable: Bool { error == nil && host.status != .down }
    }

    public struct ContainerItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let host: DockerHost
        public let container: DockerContainer
        public var id: String { "\(serviceID.uuidString)|\(host.id)|\(container.id)" }

        public init(serviceID: UUID, host: DockerHost, container: DockerContainer) {
            self.serviceID = serviceID
            self.host = host
            self.container = container
        }
    }

    public struct StackGroup: Sendable, Hashable, Identifiable {
        /// Compose project, or nil for standalone containers.
        public let name: String?
        public let hostItemID: String
        public let containers: [ContainerItem]
        public var id: String { "\(hostItemID)|\(name ?? "")" }

        public init(name: String?, hostItemID: String, containers: [ContainerItem]) {
            self.name = name
            self.hostItemID = hostItemID
            self.containers = containers
        }

        public var runningCount: Int { containers.count { $0.container.isRunning } }
    }

    public let hosts: [HostItem]
    public let containers: [ContainerItem]
    /// Stack groups per `HostItem.id`: named stacks alphabetically, standalone last;
    /// containers by name.
    public let groupsByHost: [String: [StackGroup]]
    public let overview: DockerOverview
    /// Portainer stacks per service (compose projects Portainer manages).
    public let stacksByService: [UUID: [PortainerStack]]

    /// The Portainer stack deploying `project` on `host`, if Portainer owns it
    /// (same name, same environment).
    public func portainerStack(named project: String, on host: HostItem) -> PortainerStack? {
        guard let endpoint = host.host.portainerEndpointID else { return nil }
        return stacksByService[host.serviceID]?.first { $0.name.lowercased() == project.lowercased() && $0.endpointID == endpoint }
    }

    public init(snapshots: [DockerServiceSnapshot]) {
        var hosts: [HostItem] = []
        var containers: [ContainerItem] = []
        var groupsByHost: [String: [StackGroup]] = [:]
        var stacksByService: [UUID: [PortainerStack]] = [:]

        for snapshot in snapshots {
            stacksByService[snapshot.serviceID] = snapshot.stacks
            for hostSnapshot in snapshot.hosts {
                let items = hostSnapshot.containers.map {
                    ContainerItem(serviceID: snapshot.serviceID, host: hostSnapshot.host, container: $0)
                }
                let hostItem = HostItem(
                    serviceID: snapshot.serviceID,
                    serviceName: snapshot.serviceName,
                    host: hostSnapshot.host,
                    error: hostSnapshot.error,
                    runningCount: items.count { $0.container.isRunning },
                    totalCount: items.count
                )
                hosts.append(hostItem)
                containers.append(contentsOf: items)

                let grouped = Dictionary(grouping: items) { $0.container.composeProject }
                groupsByHost[hostItem.id] = grouped
                    .map { name, members in
                        StackGroup(
                            name: name,
                            hostItemID: hostItem.id,
                            containers: members.sorted {
                                $0.container.name.localizedStandardCompare($1.container.name) == .orderedAscending
                            }
                        )
                    }
                    .sorted { lhs, rhs in
                        switch (lhs.name, rhs.name) {
                        case (nil, _): return false
                        case (_, nil): return true
                        case let (l?, r?): return l.localizedStandardCompare(r) == .orderedAscending
                        }
                    }
            }
        }

        self.hosts = hosts
        self.containers = containers
        self.groupsByHost = groupsByHost
        self.stacksByService = stacksByService
        self.overview = DockerOverview(hosts: hosts, containers: containers)
    }
}

public struct DockerOverview: Sendable, Hashable {
    public let running: Int
    public let stopped: Int
    public let total: Int
    public let unhealthy: Int
    public let restarting: Int
    /// Exited with a non-zero code.
    public let exitedWithError: Int
    public let hostsTotal: Int
    public let hostsUnreachable: Int

    init(hosts: [DockerInventory.HostItem], containers: [DockerInventory.ContainerItem]) {
        running = containers.count { $0.container.isRunning }
        total = containers.count
        stopped = total - running
        unhealthy = containers.count { $0.container.health == .unhealthy }
        restarting = containers.count { $0.container.state == .restarting }
        exitedWithError = containers.count { $0.container.exitedWithError }
        hostsTotal = hosts.count
        hostsUnreachable = hosts.count { !$0.isReachable }
    }

    /// Critical: no service answered, or no host is reachable. Warning: a service
    /// or host failed, or a container is unhealthy, restarting or exited in error.
    public func level(failedServices: Int, totalServices: Int) -> HealthLevel {
        if totalServices > 0 && failedServices >= totalServices { return .critical }
        if hostsTotal > 0 && hostsUnreachable == hostsTotal { return .critical }
        if failedServices > 0 || hostsUnreachable > 0 || unhealthy > 0 || restarting > 0 || exitedWithError > 0 {
            return .warning
        }
        return .ok
    }
}

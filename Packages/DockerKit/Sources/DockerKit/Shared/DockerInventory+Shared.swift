import Foundation
import PatchNodeCore

extension DockerInventory {
    /// Containers needing attention for the medium widget: unhealthy, exited with
    /// an error, restarting, then other stopped ones.
    public func sharedContainerIssues() -> [SharedSnapshot.ContainerIssue] {
        func rank(_ kind: SharedSnapshot.ContainerIssue.Kind) -> Int {
            switch kind {
            case .unhealthy: 0
            case .exitedWithError: 1
            case .restarting: 2
            case .stopped: 3
            }
        }
        return containers.compactMap { item -> SharedSnapshot.ContainerIssue? in
            let container = item.container
            let kind: SharedSnapshot.ContainerIssue.Kind
            if container.health == .unhealthy {
                kind = .unhealthy
            } else if container.exitedWithError {
                kind = .exitedWithError
            } else if container.state == .restarting {
                kind = .restarting
            } else if !container.isRunning {
                kind = .stopped
            } else {
                return nil
            }
            return SharedSnapshot.ContainerIssue(id: item.id, name: container.name, host: item.host.name, kind: kind)
        }
        .sorted { lhs, rhs in
            if rank(lhs.kind) != rank(rhs.kind) { return rank(lhs.kind) < rank(rhs.kind) }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Containers an App Intent may restart, by name.
    public func sharedContainerTargets() -> [SharedSnapshot.ContainerTarget] {
        let serviceNames = Dictionary(hosts.map { ($0.serviceID, $0.serviceName) }, uniquingKeysWith: { first, _ in first })
        return containers.map { item in
            SharedSnapshot.ContainerTarget(
                id: item.id,
                serviceID: item.serviceID,
                serviceName: serviceNames[item.serviceID] ?? "",
                endpointID: item.host.portainerEndpointID,
                containerID: item.container.id,
                name: item.container.name,
                host: item.host.name
            )
        }
    }
}

extension DockerHost {
    /// The host of a container an App Intent picked from the shared snapshot.
    public init(shared target: SharedSnapshot.ContainerTarget) {
        if let endpointID = target.endpointID {
            self.init(id: "portainer-\(endpointID)", name: target.host, status: .up, portainerEndpointID: endpointID)
        } else {
            self = .engine(name: target.host)
        }
    }
}

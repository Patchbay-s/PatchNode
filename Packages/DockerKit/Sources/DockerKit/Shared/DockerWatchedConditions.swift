import Foundation
import PatchNodeCore

extension DockerInventory {
    /// Containers whose healthcheck reports unhealthy.
    public func watchedConditions() -> Set<WatchedCondition> {
        Set(containers.filter { $0.container.health == .unhealthy }.map {
            WatchedCondition(kind: .containerUnhealthy, scope: $0.serviceID.uuidString, key: "\($0.host.id)|\($0.container.id)")
        })
    }
}

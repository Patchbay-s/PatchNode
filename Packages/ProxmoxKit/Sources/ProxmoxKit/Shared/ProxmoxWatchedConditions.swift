import Foundation
import PatchNodeCore

extension ProxmoxInventory {
    /// Failed vzdump backups of the last 24 hours, one per task.
    public func watchedConditions(now: Date = .now) -> Set<WatchedCondition> {
        let since = now.addingTimeInterval(-PBSInventory.failedTaskWindow)
        return Set(tasks.compactMap { item in
            guard item.task.type == "vzdump", item.task.isFailed, (item.task.startTime ?? .distantPast) >= since else { return nil }
            return WatchedCondition(kind: .backupFailed, scope: item.serviceID.uuidString, key: "pve|\(item.task.id)")
        })
    }
}

extension PBSInventory {
    /// Failed backup tasks of the last 24 hours on Proxmox Backup Server.
    public func watchedConditions(now: Date = .now) -> Set<WatchedCondition> {
        let since = now.addingTimeInterval(-Self.failedTaskWindow)
        return Set(tasks.compactMap { item in
            guard item.task.type == "backup", item.task.isFailed, (item.task.startTime ?? .distantPast) >= since else { return nil }
            return WatchedCondition(kind: .backupFailed, scope: item.serviceID.uuidString, key: "pbs|\(item.task.id)")
        })
    }
}

extension ProxmoxDiskHealth {
    /// One condition per disk or pool problem; the level is part of the key, so a
    /// pool going from DEGRADED to FAULTED is announced again.
    public func watchedConditions(serviceID: UUID) -> Set<WatchedCondition> {
        Set(issues.map { issue in
            WatchedCondition(kind: .diskProblem, scope: serviceID.uuidString, key: "\(issue.id)|\(issue.level.rawValue)")
        })
    }
}

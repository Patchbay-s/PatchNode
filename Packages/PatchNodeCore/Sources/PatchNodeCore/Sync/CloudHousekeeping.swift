#if canImport(SwiftData)
import Foundation
import SwiftData

extension HomeAssistantPin {
    /// What makes two pins the same entity, whatever their IDs.
    public var pinKey: String { "\(serviceID.uuidString)|\(entityID)" }
}

extension ModelContext {
    /// Every stored copy of a service (see `Sequence.uniqued(by:)`).
    public func serviceRecords(id: UUID) throws -> [ServiceConfig] {
        try fetch(FetchDescriptor<ServiceConfig>(predicate: #Predicate { $0.id == id }))
    }

    /// Deletes every copy of a PromQL chart. Doesn't save.
    public func deleteFavorite(id: UUID) throws {
        for favorite in try fetch(FetchDescriptor<PromQLFavorite>(predicate: #Predicate { $0.id == id })) {
            delete(favorite)
        }
    }

    /// Deletes every copy of a pinned Home Assistant entity. Doesn't save.
    public func deletePin(serviceID: UUID, entityID: String) throws {
        let pins = try fetch(FetchDescriptor<HomeAssistantPin>(
            predicate: #Predicate { $0.serviceID == serviceID && $0.entityID == entityID }
        ))
        for pin in pins { delete(pin) }
    }
}

/// Keeps the synced settings (tabs, dashboard order) and UserDefaults in line.
public enum CloudHousekeeping {
    /// `changedLocally` are the keys this device just changed (its value is
    /// published); for the others, a different synced value is adopted. Records
    /// older than their key's winner are deleted. Saves only if something changed.
    /// Returns the values adopted, so the caller doesn't take the UserDefaults
    /// change they cause for a local edit (it would republish an older value over
    /// a newer one arriving meanwhile).
    @discardableResult
    public static func reconcileSettings(
        in context: ModelContext, defaults: UserDefaults = .standard, changedLocally: Set<String> = [], now: Date = .now
    ) throws -> [String: String] {
        var adopted: [String: String] = [:]
        let records = try context.fetch(FetchDescriptor<SyncedSetting>())
        let snapshots = records.map(\.snapshot)
        let winners = CloudReconciliation.winners(snapshots)
        var changed = false
        for index in CloudReconciliation.redundantSettings(snapshots) {
            context.delete(records[index])
            changed = true
        }
        for key in CloudReconciliation.syncedKeys {
            let local = defaults.string(forKey: key) ?? ""
            switch CloudReconciliation.action(local: local, synced: winners[key], localChanged: changedLocally.contains(key)) {
            case .adopt(let value):
                defaults.set(value, forKey: key)
                adopted[key] = value
            case .publish:
                // A new record rather than an edit: an edit of a record another
                // device edits at the same time would be lost in the merge. It
                // becomes the winner, so this key's other records go now (one
                // save, one CloudKit export).
                context.insert(SyncedSetting(key: key, value: local, updatedAt: max(now, (winners[key]?.updatedAt ?? .distantPast) + 0.001)))
                for record in records where record.key == key {
                    context.delete(record)
                }
                changed = true
            case .none:
                break
            }
        }
        if changed { try context.save() }
        return adopted
    }
}
#endif

import Foundation

/// iCloud sync of the configuration (SwiftData + CloudKit, the user's private
/// database). Off by default; read once when the store opens, so a change applies
/// at the next launch.
public enum CloudSyncSettings {
    public static let key = "iCloudSyncConfiguration"

    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}

/// Tokens in iCloud Keychain (`kSecAttrSynchronizable`) instead of this device
/// only. Off by default, changed only along with `KeychainSecretStore.moveAll(toSynchronized:)`.
public enum TokenSyncSettings {
    public static let key = "iCloudSyncTokens"

    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}

/// Whether the secrets saved by 1.0 (without a server) have been bound to their
/// service's address. Until then an unbound secret is still used, as in 1.0.
public enum CredentialBinding {
    public static let key = "credentialOriginsBound"

    public static func isDone(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    public static func markDone(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }

    /// An unbound secret is used only before binding and never once iCloud sync
    /// is on: a synced address could then point anywhere.
    public static func acceptsUnbound(_ defaults: UserDefaults = .standard) -> Bool {
        !isDone(defaults) && !CloudSyncSettings.isEnabled(defaults)
    }
}

/// A setting kept in UserDefaults and mirrored in the store so it follows the
/// configuration to the user's other devices.
public struct SyncedSettingValue: Sendable, Hashable {
    public let key: String
    public let value: String
    public let updatedAt: Date

    public init(key: String, value: String, updatedAt: Date) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

/// How synced settings and duplicated records are reconciled. CloudKit has no
/// unique constraint: two devices can each hold a record for the same thing, and
/// both end up everywhere.
public enum CloudReconciliation {
    /// The settings that sync: tabs and dashboard order (the same as the export
    /// file). The rest (refresh interval, notifications, lock) is per device.
    public static let syncedKeys = [TabSelection.storageKey, "dashboardCardOrder"]

    /// Longer synced values are ignored (a setting is a short list of names).
    public static let maxValueLength = 1_024

    /// Latest write wins for each key; at the same date, the greater value, so
    /// every device picks the same one.
    public static func winners(_ records: [SyncedSettingValue]) -> [String: SyncedSettingValue] {
        var winners: [String: SyncedSettingValue] = [:]
        for record in records where record.value.count <= maxValueLength {
            guard let current = winners[record.key] else {
                winners[record.key] = record
                continue
            }
            if (record.updatedAt, record.value) > (current.updatedAt, current.value) {
                winners[record.key] = record
            }
        }
        return winners
    }

    /// Indices of the records older than their key's winner, in ascending order:
    /// safe to delete on every device. Copies equal to the winner stay: two
    /// devices could each delete a different copy and lose them all.
    public static func redundantSettings(_ records: [SyncedSettingValue]) -> [Int] {
        let winners = winners(records)
        return records.indices.filter { records[$0] != winners[records[$0].key] }
    }

    /// What this device should do with one setting: adopt the synced value,
    /// publish its own, or nothing (same value: no write, so two devices never
    /// keep overwriting each other).
    public enum SettingAction: Sendable, Hashable {
        case adopt(String)
        case publish
        case none
    }

    public static func action(local: String, synced: SyncedSettingValue?, localChanged: Bool) -> SettingAction {
        guard let synced else { return local.isEmpty ? .none : .publish }
        if synced.value == local { return .none }
        if localChanged { return local.count <= maxValueLength ? .publish : .none }
        return .adopt(synced.value)
    }

}

extension Sequence {
    /// The first element of each key, in order. CloudKit has no unique constraint:
    /// after a sync, the same service, chart or entity can be stored twice (a
    /// backup restored on a second device, one file imported on both). The screens
    /// show one; deleting removes every copy. Copies are never deleted
    /// automatically: two devices could each delete a different one and lose both.
    public func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}

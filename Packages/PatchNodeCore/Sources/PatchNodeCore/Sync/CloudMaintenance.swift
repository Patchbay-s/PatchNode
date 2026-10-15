import Foundation

/// Tokens left on this device by services deleted on another one (iCloud sync
/// of the configuration). A service that disappears is purged only if it is
/// still missing after `grace`, so a store briefly incomplete during an iCloud
/// import never costs a token. When every service is gone (iCloud account
/// changed, zone deleted elsewhere…), nothing is purged automatically.
public struct OrphanTokenTracker: Sendable, Equatable, Codable {
    public static let storageKey = "orphanTokenTracker"
    public static let grace: TimeInterval = 3_600

    /// Services this device has seen.
    public private(set) var known: Set<UUID>
    /// Services seen before, missing since.
    public private(set) var missingSince: [UUID: Date]

    public init(known: Set<UUID> = [], missingSince: [UUID: Date] = [:]) {
        self.known = known
        self.missingSince = missingSince
    }

    /// Takes the current services; returns the IDs whose token should go now.
    /// They stay tracked until `markPurged` confirms the deletion (a locked
    /// Keychain must not make a token forgotten). `purging` false (sync off,
    /// demo): only remembers what exists, purges nothing (a local deletion
    /// removes its token itself).
    public mutating func update(current: Set<UUID>, purging: Bool, now: Date = .now) -> Set<UUID> {
        defer { known.formUnion(current) }
        for id in current { missingSince[id] = nil }
        guard purging, !current.isEmpty else {
            if !purging {
                known = current
                missingSince = [:]
            }
            return []
        }
        let wait = Self.grace
        var purge = Set<UUID>()
        for id in known.subtracting(current) {
            let since = missingSince[id] ?? now
            missingSince[id] = since
            if now.timeIntervalSince(since) >= wait { purge.insert(id) }
        }
        return purge
    }

    /// Their tokens are gone: stop tracking them.
    public mutating func markPurged(_ ids: Set<UUID>) {
        known.subtract(ids)
        for id in ids { missingSince[id] = nil }
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decoded(from data: Data?) -> OrphanTokenTracker {
        data.flatMap { try? JSONDecoder().decode(OrphanTokenTracker.self, from: $0) } ?? OrphanTokenTracker()
    }
}

/// "Delete my iCloud data" (Settings › iCloud): what it does and when it can run.
public enum CloudDataDeletion {
    public enum Step: Sendable, Hashable {
        /// Bring this device's synced tokens back to it first, so it keeps them.
        case moveTokensToDevice
        /// Then delete what remains in iCloud Keychain (services this device
        /// doesn't know included).
        case deleteSyncedTokens
        /// Delete the CloudKit zone holding the synced configuration.
        case deleteConfigurationZone
        /// Turn both options off on this device.
        case turnSyncOff
    }

    public enum Availability: Sendable, Hashable {
        case available
        /// The store of this launch syncs: it would upload everything again.
        /// Turn sync off and reopen PatchNode first.
        case syncRunning
        case demo
    }

    public static func availability(syncRunning: Bool, demo: Bool) -> Availability {
        if demo { return .demo }
        return syncRunning ? .syncRunning : .available
    }

    /// Tokens first (they stay usable on this device), then the configuration.
    public static func steps(tokenSyncOn: Bool) -> [Step] {
        (tokenSyncOn ? [.moveTokensToDevice, .deleteSyncedTokens] : []) + [.deleteConfigurationZone, .turnSyncOff]
    }
}

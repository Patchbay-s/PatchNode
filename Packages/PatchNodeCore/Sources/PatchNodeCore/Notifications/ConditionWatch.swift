import Foundation

/// What a local notification can be about. One notification per kind and
/// refresh, with a count only: nothing identifying on the lock screen.
public enum WatchedKind: String, Sendable, Hashable, CaseIterable, Codable {
    case serviceUnreachable
    case backupFailed
    case containerUnhealthy
    case alertFiring
    case certificateExpiring
    case diskProblem
}

/// A problem currently seen. `scope` is the service it belongs to (its ID);
/// `key` identifies the problem within that service for as long as it lasts
/// (container, alert fingerprint, task…). Keys are hashed before being stored.
public struct WatchedCondition: Sendable, Hashable {
    public let kind: WatchedKind
    public let scope: String
    public let key: String

    public init(kind: WatchedKind, scope: String, key: String) {
        self.kind = kind
        self.scope = scope
        self.key = key
    }

    /// What is stored: kind, service ID and a SHA-256 of the key, so addresses,
    /// labels or names found in keys never land in the app's preferences.
    var storedID: String { "\(kind.rawValue)|\(scope)|\(SHA256.hex(key))" }
}

/// A kind of problem for one service that couldn't be evaluated this time
/// (service not loaded, disks not read yet): its problems keep their state
/// instead of counting as solved, so they aren't announced again later.
public struct WatchedScope: Sendable, Hashable {
    public let kind: WatchedKind
    public let scope: String

    public init(kind: WatchedKind, scope: String) {
        self.kind = kind
        self.scope = scope
    }
}

/// Decides which problems deserve a notification: only new ones, once.
///
/// - A problem is announced when it first appears, if its kind is enabled and
///   the app is in the background (in the foreground the user sees it on screen,
///   so it counts as announced).
/// - While it lasts, it is never announced again.
/// - If it clears and comes back within `cooldown`, it stays quiet (a flapping
///   service doesn't notify every refresh).
/// - Problems of a disabled kind are still tracked: enabling the kind later
///   doesn't announce problems that were already there.
public struct ConditionWatch: Sendable, Equatable, Codable {
    struct Record: Sendable, Equatable, Codable {
        let kind: WatchedKind
        let scope: String
        var isActive: Bool
        var lastSeen: Date
        var lastAnnounced: Date?
    }

    public static let cooldown: TimeInterval = 6 * 3_600
    /// Cleared problems are forgotten after this.
    public static let retention: TimeInterval = 7 * 86_400
    /// Upper bound on tracked problems (oldest cleared ones go first).
    public static let maxRecords = 2_000

    private(set) var records: [String: Record] = [:]

    public init() {}

    /// New problems to announce now, counted per kind; updates the state.
    /// `unevaluated`: kinds of problems of a service that couldn't be checked
    /// this time; their problems are neither announced nor cleared.
    public mutating func update(
        current: Set<WatchedCondition>, unevaluated: Set<WatchedScope> = [], enabled: Set<WatchedKind>,
        deliver: Bool, now: Date = .now
    ) -> [WatchedKind: Int] {
        var announced: [WatchedKind: Int] = [:]
        let byID = Dictionary(current.map { ($0.storedID, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, condition) in byID.sorted(by: { $0.key < $1.key }) {
            if var record = records[id], record.isActive {
                record.lastSeen = now
                records[id] = record
                continue
            }
            let previous = records[id]
            let quiet = previous?.lastAnnounced.map { now.timeIntervalSince($0) < Self.cooldown } ?? false
            var record = Record(kind: condition.kind, scope: condition.scope, isActive: true, lastSeen: now, lastAnnounced: previous?.lastAnnounced)
            if !quiet {
                if !deliver {
                    record.lastAnnounced = now
                } else if enabled.contains(condition.kind) {
                    record.lastAnnounced = now
                    announced[condition.kind, default: 0] += 1
                }
            }
            records[id] = record
        }
        for (id, record) in records where record.isActive && byID[id] == nil {
            if unevaluated.contains(WatchedScope(kind: record.kind, scope: record.scope)) {
                records[id]?.lastSeen = now
            } else {
                records[id]?.isActive = false
            }
        }
        records = records.filter { $0.value.isActive || now.timeIntervalSince($0.value.lastSeen) < Self.retention }
        if records.count > Self.maxRecords {
            let dropped = records.filter { !$0.value.isActive }
                .sorted { $0.value.lastSeen < $1.value.lastSeen }
                .prefix(records.count - Self.maxRecords)
            for (id, _) in dropped { records[id] = nil }
        }
        return announced
    }

    // MARK: - Storage (no secret: kinds, service IDs, hashed keys and dates)

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data?) -> ConditionWatch {
        guard let data, let watch = try? JSONDecoder().decode(ConditionWatch.self, from: data) else { return ConditionWatch() }
        return watch
    }
}

/// Which kinds the user enabled, stored as a comma-separated list.
public enum WatchedKindSettings {
    /// UserDefaults key of the enabled kinds (no secret).
    public static let storageKey = "notificationKinds"

    /// What the user enabled, read from the standard defaults.
    public static var enabled: Set<WatchedKind> {
        decode(UserDefaults.standard.string(forKey: storageKey) ?? "")
    }

    public static func decode(_ stored: String) -> Set<WatchedKind> {
        Set(stored.split(separator: ",").compactMap { WatchedKind(rawValue: String($0)) })
    }

    public static func encode(_ kinds: Set<WatchedKind>) -> String {
        WatchedKind.allCases.filter(kinds.contains).map(\.rawValue).joined(separator: ",")
    }
}

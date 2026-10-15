import Foundation
import PatchNodeCore
import Synchronization

/// How the disks of one Proxmox VE service are read. A read is complete (disk
/// list with SMART, then ZFS pools): Proxmox runs `smartctl` on every disk,
/// which wakes disks in standby. Never on the periodic refresh, in the
/// background refresh or for widgets; only as `SMARTPolicy` allows
/// (`DiskHealthAccess`).
public struct SMARTSetting: Sendable, Hashable, Codable {
    public enum Mode: String, Sendable, Hashable, Codable, CaseIterable {
        /// Never read: no request to `/nodes/{node}/disks/*` at all, no result
        /// kept, no disk notification.
        case disabled
        /// Only with "Read SMART status" in the Disk health screen (default).
        case onDemand
        /// Once a day from `hour:minute`: at the first opening of the app after
        /// it, or in the background if iOS runs the scheduled task first.
        case automatic
    }

    public static let defaultHour = 18
    public static let defaultMinute = 0

    public var mode: Mode
    public var hour: Int
    public var minute: Int

    public init(mode: Mode = .onDemand, hour: Int = SMARTSetting.defaultHour, minute: Int = SMARTSetting.defaultMinute) {
        self.mode = mode
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Unknown values (a later version, a damaged entry) fall back to the default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: (try? c.decode(Mode.self, forKey: .mode)) ?? .onDemand,
            hour: (try? c.decode(Int.self, forKey: .hour)) ?? Self.defaultHour,
            minute: (try? c.decode(Int.self, forKey: .minute)) ?? Self.defaultMinute
        )
    }
}

/// The SMART setting of every Proxmox VE service, in UserDefaults (no secret).
/// A service without an entry, including those configured before 1.1, reads
/// SMART on demand. Written from the main actor only (read-modify-write).
public enum SMARTSettingsStore {
    public static let key = "smartSettings"

    public static func all(_ defaults: UserDefaults = .standard) -> [UUID: SMARTSetting] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: SMARTSetting].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }

    public static func setting(for serviceID: UUID, _ defaults: UserDefaults = .standard) -> SMARTSetting {
        all(defaults)[serviceID] ?? SMARTSetting()
    }

    /// Turning a service off also forgets its last reading.
    public static func set(
        _ setting: SMARTSetting, for serviceID: UUID, _ defaults: UserDefaults = .standard, readings: SMARTReadingStore = .shared
    ) {
        var current = all(defaults)
        current[serviceID] = setting
        save(current, defaults)
        if setting.mode == .disabled { readings.remove(serviceID) }
    }

    /// Drops the settings of services that no longer exist (deleted on another
    /// device with iCloud sync): an orphan automatic setting would stay due.
    public static func retain(only serviceIDs: Set<UUID>, _ defaults: UserDefaults = .standard) {
        let current = all(defaults)
        let kept = current.filter { serviceIDs.contains($0.key) }
        if kept.count != current.count { save(kept, defaults) }
    }

    /// A deleted service: its setting and its last reading.
    public static func remove(_ serviceID: UUID, _ defaults: UserDefaults = .standard, readings: SMARTReadingStore = .shared) {
        readings.remove(serviceID)
        var current = all(defaults)
        guard current.removeValue(forKey: serviceID) != nil else { return }
        save(current, defaults)
    }

    private static func save(_ settings: [UUID: SMARTSetting], _ defaults: UserDefaults) {
        let stored = Dictionary(uniqueKeysWithValues: settings.map { ($0.key.uuidString, $0.value) })
        defaults.set(try? JSONEncoder().encode(stored), forKey: key)
    }
}

/// The last complete read of a service's disks: the disk list with SMART, then
/// the ZFS pools. The Disk health screen shows it and disk notifications come
/// from it until the next wanted read; nothing else reads the disks.
public struct SMARTReading: Sendable, Hashable, Codable {
    public let readAt: Date
    public let report: ProxmoxDiskHealth

    public init(readAt: Date, report: ProxmoxDiskHealth) {
        self.readAt = readAt
        self.report = report
    }
}

extension ProxmoxDiskHealth {
    /// Serial numbers are shown nowhere: never kept (they would end up in backups).
    var withoutSerials: ProxmoxDiskHealth {
        ProxmoxDiskHealth(nodes: nodes.map { node in
            Node(name: node.name, disks: node.disks.map {
                ProxmoxDisk(devpath: $0.devpath, model: $0.model, type: $0.type, size: $0.size, usage: $0.usage, health: $0.health, lifeLeft: $0.lifeLeft)
            }, pools: node.pools, unavailable: node.unavailable)
        })
    }

    /// A node whose disks or pools couldn't be read this time keeps what the
    /// previous reading knew of them (still marked unavailable).
    func keepingKnownParts(of previous: ProxmoxDiskHealth?) -> ProxmoxDiskHealth {
        guard let previous, hasUnavailableParts else { return self }
        return ProxmoxDiskHealth(nodes: nodes.map { node in
            guard !node.unavailable.isEmpty, let known = previous.nodes.first(where: { $0.name == node.name }) else { return node }
            return Node(
                name: node.name,
                disks: node.unavailable.contains(.disks) ? known.disks : node.disks,
                pools: node.unavailable.contains(.zfs) ? known.pools : node.pools,
                unavailable: node.unavailable
            )
        })
    }
}

/// The last reading of each service, in UserDefaults (disks, pools and the
/// date, no secret), so it survives a relaunch.
public final class SMARTReadingStore: Sendable {
    public static let shared = SMARTReadingStore(defaults: nil)
    static let key = "diskHealthReadings"
    /// Before the complete readings (development builds of 1.1): SMART only.
    static let legacyKey = "smartReadings"

    private struct State {
        /// Loaded on first use.
        var readings: [UUID: SMARTReading]?
        /// Bumped when a service's reading is forgotten (turned off, deleted):
        /// a read started before is then dropped (`record(...ifGeneration:)`).
        var generations: [UUID: Int] = [:]
    }

    private let state: Mutex<State>
    private let defaultsName: String?

    /// `defaults` nil: the standard UserDefaults.
    public init(defaults suiteName: String?) {
        defaultsName = suiteName
        state = Mutex(State())
    }

    private var defaults: UserDefaults {
        defaultsName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func reading(for serviceID: UUID) -> SMARTReading? {
        withReadings { readings, _ in readings[serviceID] }
    }

    public func lastRead(for serviceID: UUID) -> Date? {
        reading(for: serviceID)?.readAt
    }

    /// Taken before a read; `record` drops the read if it changed meanwhile.
    public func generation(for serviceID: UUID) -> Int {
        state.withLock { $0.generations[serviceID] ?? 0 }
    }

    /// Keeps the read, unless the service was turned off or deleted since
    /// `generation` was taken (checked and written under one lock): nil then.
    @discardableResult
    public func record(_ report: ProxmoxDiskHealth, for serviceID: UUID, at date: Date = .now, ifGeneration generation: Int) -> SMARTReading? {
        withReadings { readings, generations in
            guard (generations[serviceID] ?? 0) == generation else { return nil }
            let reading = SMARTReading(readAt: date, report: report.withoutSerials.keepingKnownParts(of: readings[serviceID]?.report))
            readings[serviceID] = reading
            return reading
        }
    }

    @discardableResult
    public func record(_ report: ProxmoxDiskHealth, for serviceID: UUID, at date: Date = .now) -> SMARTReading {
        withReadings { readings, _ in
            let reading = SMARTReading(readAt: date, report: report.withoutSerials.keepingKnownParts(of: readings[serviceID]?.report))
            readings[serviceID] = reading
            return reading
        }
    }

    public func remove(_ serviceID: UUID) {
        withReadings { readings, generations in
            readings.removeValue(forKey: serviceID)
            generations[serviceID, default: 0] += 1
        }
    }

    /// Drops the readings of services that no longer exist (deleted on another
    /// device with iCloud sync).
    public func retain(only serviceIDs: Set<UUID>) {
        withReadings { readings, generations in
            for id in readings.keys where !serviceIDs.contains(id) { generations[id, default: 0] += 1 }
            readings = readings.filter { serviceIDs.contains($0.key) }
        }
    }

    private func withReadings<T>(_ body: (inout [UUID: SMARTReading], inout [UUID: Int]) -> T) -> T {
        let defaults = defaults
        return state.withLock { state in
            var readings = state.readings ?? Self.load(defaults)
            let before = readings
            let result = body(&readings, &state.generations)
            state.readings = readings
            if readings != before {
                let stored = Dictionary(uniqueKeysWithValues: readings.map { ($0.key.uuidString, $0.value) })
                defaults.set(try? JSONEncoder().encode(stored), forKey: Self.key)
            }
            return result
        }
    }

    private static func load(_ defaults: UserDefaults) -> [UUID: SMARTReading] {
        defaults.removeObject(forKey: legacyKey)
        // The hourly disk check of the development builds, gone.
        defaults.removeObject(forKey: "diskCheckDates")
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: SMARTReading].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }
}

extension SMARTReadingStore {
    /// Disk notifications come only from the last wanted reading: a service
    /// turned off has none (its disk problems count as gone), a service never
    /// read is unknown.
    public func watchedConditions(
        serviceIDs: [UUID], settings: [UUID: SMARTSetting]
    ) -> (current: Set<WatchedCondition>, unevaluated: Set<WatchedScope>) {
        var current = Set<WatchedCondition>()
        var unevaluated = Set<WatchedScope>()
        for id in serviceIDs where (settings[id] ?? SMARTSetting()).mode != .disabled {
            if let reading = reading(for: id) {
                current.formUnion(reading.report.watchedConditions(serviceID: id))
            } else {
                unevaluated.insert(WatchedScope(kind: .diskProblem, scope: id.uuidString))
            }
        }
        return (current, unevaluated)
    }
}

/// The only way to `/nodes/{node}/disks/*` (list, SMART, ZFS): a complete read
/// when `SMARTPolicy` allows it at this moment for the service's mode, kept in
/// `SMARTReadingStore`. Every other path (screen opening, refreshes, background,
/// notifications, widgets, demo) only shows what is kept.
public enum DiskHealthAccess {
    /// nil when the mode doesn't allow a read now. A read finished after the
    /// service was turned off or deleted (even turned on again since) is dropped.
    public static func read(
        at moment: SMARTPolicy.Moment, serviceID: UUID, client: ProxmoxClient, resources: [ProxmoxResource],
        timeout: Double, now: Date = .now, defaults: UserDefaults = .standard, readings: SMARTReadingStore = .shared
    ) async throws -> SMARTReading? {
        let generation = readings.generation(for: serviceID)
        let setting = SMARTSettingsStore.setting(for: serviceID, defaults)
        guard SMARTPolicy.readsSMART(at: moment, setting: setting, lastRead: readings.lastRead(for: serviceID), now: now) else { return nil }
        let report = try await withTimeout(seconds: timeout) {
            try await ProxmoxDiskHealth.load(client: client, resources: resources)
        }
        // Turned off (even back on since) or deleted during the read: dropped.
        // `SMARTSettingsStore` stores the mode before forgetting the reading.
        return readings.record(report, for: serviceID, at: now, ifGeneration: generation)
    }
}

/// When the disks may be read (complete read, SMART included). At any other
/// moment, no request reaches `/nodes/{node}/disks/*`.
public enum SMARTPolicy {
    public enum Moment: Sendable, Hashable {
        /// The periodic refresh, on screen.
        case refresh
        /// An ordinary background refresh.
        case backgroundRefresh
        /// Widgets and Siri (they only read the shared snapshot anyway).
        case widget
        /// The app was opened (a refresh on screen finished).
        case appOpened
        /// The background task scheduled for the chosen time.
        case scheduledTask
        /// "Read SMART status" in the Disk health screen.
        case userRequest
    }

    public static func readsSMART(at moment: Moment, setting: SMARTSetting, lastRead: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch moment {
        case .refresh, .backgroundRefresh, .widget:
            return false
        case .userRequest:
            return setting.mode != .disabled
        case .appOpened, .scheduledTask:
            return setting.mode == .automatic && isDue(setting, lastRead: lastRead, now: now, calendar: calendar)
        }
    }

    /// Today's chosen time in `calendar`'s time zone (a time skipped by a DST
    /// change moves to the next valid one).
    public static func scheduledTime(on day: Date, setting: SMARTSetting, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    /// Automatic mode: due once the chosen time has passed today, unless SMART
    /// was already read today (on demand included). Days and times are those
    /// of the current time zone: after a trip, "today" is the local day.
    public static func isDue(_ setting: SMARTSetting, lastRead: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard setting.mode == .automatic, let scheduled = scheduledTime(on: now, setting: setting, calendar: calendar), now >= scheduled else { return false }
        guard let lastRead else { return true }
        return !calendar.isDate(lastRead, inSameDayAs: now) && lastRead < scheduled
    }

    /// When to ask iOS for the background read: the earliest next chosen time
    /// among the services in automatic mode (now if one is already due), nil
    /// if none is automatic.
    public static func nextBackgroundDate(
        _ services: [(setting: SMARTSetting, lastRead: Date?)], now: Date = .now, calendar: Calendar = .current
    ) -> Date? {
        services.compactMap { service -> Date? in
            guard service.setting.mode == .automatic else { return nil }
            if isDue(service.setting, lastRead: service.lastRead, now: now, calendar: calendar) { return now }
            guard let today = scheduledTime(on: now, setting: service.setting, calendar: calendar) else { return nil }
            let readToday = service.lastRead.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            if today > now && !readToday { return today }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            return scheduledTime(on: tomorrow, setting: service.setting, calendar: calendar)
        }.min()
    }
}

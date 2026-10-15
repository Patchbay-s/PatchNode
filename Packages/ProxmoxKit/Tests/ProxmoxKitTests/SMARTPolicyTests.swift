import Foundation
import Synchronization
import Testing
import PatchNodeCore
@testable import ProxmoxKit

struct SMARTPolicyTests {
    private func calendar(_ zone: String = "Europe/Paris") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// 2027-03-10 at `hour:minute` in `zone`.
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 10, zone: String = "Europe/Paris") -> Date {
        calendar(zone).date(from: DateComponents(year: 2027, month: 3, day: day, hour: hour, minute: minute))!
    }

    let automatic = SMARTSetting(mode: .automatic)

    @Test func defaultIsOnDemandAtSixPM() {
        let setting = SMARTSetting()
        #expect(setting.mode == .onDemand)
        #expect(setting.hour == 18 && setting.minute == 0)
        // A service configured before 1.1 has no entry: on demand too.
        let defaults = UserDefaults(suiteName: "PatchNode-smart-settings-\(UUID().uuidString)")!
        #expect(SMARTSettingsStore.setting(for: UUID(), defaults) == SMARTSetting())
    }

    @Test func settingsAreStoredPerService() throws {
        let name = "PatchNode-smart-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let readings = SMARTReadingStore(defaults: name)
        let a = UUID(), b = UUID()
        SMARTSettingsStore.set(SMARTSetting(mode: .automatic, hour: 21, minute: 30), for: a, defaults, readings: readings)
        SMARTSettingsStore.set(SMARTSetting(mode: .disabled), for: b, defaults, readings: readings)
        #expect(SMARTSettingsStore.setting(for: a, defaults) == SMARTSetting(mode: .automatic, hour: 21, minute: 30))
        #expect(SMARTSettingsStore.setting(for: b, defaults).mode == .disabled)
        SMARTSettingsStore.retain(only: [b], defaults)
        #expect(SMARTSettingsStore.setting(for: a, defaults) == SMARTSetting())
        #expect(SMARTSettingsStore.setting(for: b, defaults).mode == .disabled)
        SMARTSettingsStore.set(SMARTSetting(mode: .automatic, hour: 21, minute: 30), for: a, defaults, readings: readings)
        SMARTSettingsStore.remove(a, defaults, readings: readings)
        #expect(SMARTSettingsStore.setting(for: a, defaults) == SMARTSetting())
        // Damaged values fall back to defaults.
        let damaged = try JSONDecoder().decode(SMARTSetting.self, from: Data(#"{"mode":"hourly","hour":99}"#.utf8))
        #expect(damaged == SMARTSetting(mode: .onDemand, hour: 23, minute: 0))
    }

    /// The periodic refresh, ordinary background refreshes and widgets never
    /// read SMART, whatever the mode and the time.
    @Test func neverOnRefreshBackgroundOrWidgets() {
        for mode in SMARTSetting.Mode.allCases {
            let setting = SMARTSetting(mode: mode)
            for moment in [SMARTPolicy.Moment.refresh, .backgroundRefresh, .widget] {
                for now in [date(9), date(18, 30), date(23, 59)] {
                    #expect(!SMARTPolicy.readsSMART(at: moment, setting: setting, lastRead: nil, now: now, calendar: calendar()), "\(mode) \(moment)")
                }
            }
        }
    }

    @Test func onDemandAndDisabled() {
        let now = date(19)
        #expect(SMARTPolicy.readsSMART(at: .userRequest, setting: SMARTSetting(mode: .onDemand), lastRead: nil, now: now, calendar: calendar()))
        #expect(SMARTPolicy.readsSMART(at: .userRequest, setting: automatic, lastRead: now, now: now, calendar: calendar()))
        #expect(!SMARTPolicy.readsSMART(at: .userRequest, setting: SMARTSetting(mode: .disabled), lastRead: nil, now: now, calendar: calendar()))
        for moment in [SMARTPolicy.Moment.appOpened, .scheduledTask] {
            #expect(!SMARTPolicy.readsSMART(at: moment, setting: SMARTSetting(mode: .onDemand), lastRead: nil, now: now, calendar: calendar()))
            #expect(!SMARTPolicy.readsSMART(at: moment, setting: SMARTSetting(mode: .disabled), lastRead: nil, now: now, calendar: calendar()))
        }
    }

    @Test func automaticNotBeforeTheChosenTime() {
        #expect(!SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: nil, now: date(17, 59), calendar: calendar()))
        #expect(SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: nil, now: date(18), calendar: calendar()))
        #expect(SMARTPolicy.readsSMART(at: .scheduledTask, setting: automatic, lastRead: nil, now: date(18, 1), calendar: calendar()))
    }

    @Test func automaticOncePerDay() {
        // Read in the background at 18:05: the opening at 20:00 doesn't read again.
        let read = date(18, 5)
        #expect(!SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: read, now: date(20), calendar: calendar()))
        #expect(!SMARTPolicy.readsSMART(at: .scheduledTask, setting: automatic, lastRead: read, now: date(23), calendar: calendar()))
        // The next day, from the chosen time only.
        #expect(!SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: read, now: date(9, day: 11), calendar: calendar()))
        #expect(SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: read, now: date(18, day: 11), calendar: calendar()))
        // A read on demand earlier today counts as today's read.
        #expect(!SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: date(8), now: date(19), calendar: calendar()))
    }

    @Test func firstOpeningAfterTheTimeWhenTheBackgroundDidNotRun() {
        // Nothing read yesterday or today (iOS never ran the task): the first
        // opening after 18:00 reads, even late at night.
        let yesterday = date(18, 2, day: 9)
        #expect(SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: yesterday, now: date(23, 50), calendar: calendar()))
    }

    @Test func changedTimeStillMeansOncePerDay() {
        // Read at 18:05, then the time moved to 21:00: no second read today.
        let moved = SMARTSetting(mode: .automatic, hour: 21, minute: 0)
        #expect(!SMARTPolicy.readsSMART(at: .appOpened, setting: moved, lastRead: date(18, 5), now: date(21, 30), calendar: calendar()))
        // Moved earlier before today's read: due right away.
        let earlier = SMARTSetting(mode: .automatic, hour: 7, minute: 0)
        #expect(SMARTPolicy.readsSMART(at: .appOpened, setting: earlier, lastRead: date(18, day: 9), now: date(10), calendar: calendar()))
    }

    @Test func timeZoneChangeUsesTheLocalDay() {
        // Read at 18:30 in Paris, then a flight to New York: it's 12:30 there,
        // same local day, then 19:00 New York time: already read today.
        let read = date(18, 30)
        #expect(!SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: read, now: read + 7 * 3_600, calendar: calendar("America/New_York")))
        // Eastward to Tokyo: the read (02:30 on the 11th, Tokyo time) already
        // counts for the 11th there; the next read is on the 12th from 18:00.
        let tokyo = calendar("Asia/Tokyo")
        let tokyoEvening = tokyo.date(from: DateComponents(year: 2027, month: 3, day: 11, hour: 18, minute: 10))!
        #expect(!SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: read, now: tokyoEvening, calendar: tokyo))
        let nextMorning = tokyo.date(from: DateComponents(year: 2027, month: 3, day: 12, hour: 9))!
        #expect(!SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: read, now: nextMorning, calendar: tokyo))
        let nextEvening = tokyo.date(from: DateComponents(year: 2027, month: 3, day: 12, hour: 18, minute: 10))!
        #expect(SMARTPolicy.readsSMART(at: .appOpened, setting: automatic, lastRead: read, now: nextEvening, calendar: tokyo))
    }

    @Test func daylightSavingDayKeepsTheTime() {
        // 2027-03-28: Paris skips from 02:00 to 03:00. 02:30 moves to 03:00.
        let setting = SMARTSetting(mode: .automatic, hour: 2, minute: 30)
        let dstDay = calendar().date(from: DateComponents(year: 2027, month: 3, day: 28, hour: 12))!
        let scheduled = SMARTPolicy.scheduledTime(on: dstDay, setting: setting, calendar: calendar())
        #expect(scheduled.map { calendar().component(.hour, from: $0) } == 3)
    }

    @Test func nextBackgroundDate() {
        let now = date(10)
        #expect(SMARTPolicy.nextBackgroundDate([(SMARTSetting(mode: .onDemand), nil)], now: now, calendar: calendar()) == nil)
        // Later today.
        #expect(SMARTPolicy.nextBackgroundDate([(automatic, date(18, day: 9))], now: now, calendar: calendar()) == date(18))
        // Already read today: tomorrow.
        #expect(SMARTPolicy.nextBackgroundDate([(automatic, date(18, 5))], now: date(20), calendar: calendar()) == date(18, day: 11))
        // Due now (missed): now.
        #expect(SMARTPolicy.nextBackgroundDate([(automatic, nil)], now: date(19), calendar: calendar()) == date(19))
        // The earliest service wins.
        let early = SMARTSetting(mode: .automatic, hour: 12, minute: 0)
        #expect(SMARTPolicy.nextBackgroundDate([(automatic, nil), (early, nil)], now: now, calendar: calendar()) == date(12))
    }
}

/// Records every request to `/nodes/{node}/disks/*`; `onDisks` runs on the
/// first one (to change the mode during a read).
private final class RecordingDisks: DemoResponder {
    let inner = ProxmoxDemoResponder()
    let diskRequests = Mutex<[DemoRequest]>([])
    let onDisks: (@Sendable () -> Void)?

    init(onDisks: (@Sendable () -> Void)? = nil) {
        self.onDisks = onDisks
    }

    func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        if request.path.contains("/disks/") {
            let first = diskRequests.withLock { $0.append(request); return $0.count == 1 }
            if first { onDisks?() }
        }
        return inner.respond(to: request, now: now)
    }

    var count: Int { diskRequests.withLock { $0.count } }
}

/// 401 on every disk request, counted.
private final class RejectingDisks: DemoResponder {
    let inner = ProxmoxDemoResponder()
    let diskRequests = Mutex(0)
    func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        guard request.path.contains("/disks/") else { return inner.respond(to: request, now: now) }
        diskRequests.withLock { $0 += 1 }
        return .json(#"{"data":null}"#, status: 401)
    }
    var count: Int { diskRequests.withLock { $0 } }
}

@Suite(.serialized)
struct DiskHealthAccessTests {
    private func client(_ responder: some DemoResponder) -> ProxmoxClient {
        let host = "pve-smart-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        DemoServer.register(responder, host: host)
        return ProxmoxClient(baseURL: URL(string: "https://\(host):8006")!, apiTokenValue: "test-user@pam!test-token=0",
                             httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), backoff: 0, label: nil, log: nil))
    }

    private func stores() throws -> (UserDefaults, SMARTReadingStore) {
        let name = "PatchNode-disks-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), SMARTReadingStore(defaults: name))
    }

    /// Today at `hour` (local time, like `SMARTPolicy`).
    private func today(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
    }

    private let everyMoment: [SMARTPolicy.Moment] = [.refresh, .backgroundRefresh, .widget, .appOpened, .scheduledTask, .userRequest]

    /// Opening the screen, the refreshes (on screen and in the background),
    /// notifications, the dashboard card and the shared summary never read the
    /// disks: they only show the kept reading. The refresh itself (resources,
    /// tasks) never reaches `/disks/`.
    @Test(arguments: SMARTSetting.Mode.allCases)
    func ordinaryRefreshNeverReadsTheDisks(mode: SMARTSetting.Mode) async throws {
        let (defaults, readings) = try stores()
        let responder = RecordingDisks()
        let client = client(responder)
        let id = UUID()
        SMARTSettingsStore.set(SMARTSetting(mode: mode, hour: 0, minute: 0), for: id, defaults, readings: readings)
        let snapshot = try await ProxmoxServiceSnapshot.load(serviceID: id, serviceName: "node-1", client: client)
        for moment: SMARTPolicy.Moment in [.refresh, .backgroundRefresh, .widget] {
            let reading = try await DiskHealthAccess.read(
                at: moment, serviceID: id, client: client, resources: snapshot.resources, timeout: 10, defaults: defaults, readings: readings
            )
            #expect(reading == nil)
        }
        _ = readings.watchedConditions(serviceIDs: [id], settings: SMARTSettingsStore.all(defaults))
        #expect(responder.count == 0)
    }

    /// Off: no request at any moment, the button included.
    @Test func disabledNeverReadsTheDisks() async throws {
        let (defaults, readings) = try stores()
        let responder = RecordingDisks()
        let client = client(responder)
        let resources = try await client.clusterResources()
        let id = UUID()
        SMARTSettingsStore.set(SMARTSetting(mode: .disabled, hour: 0, minute: 0), for: id, defaults, readings: readings)
        for moment in everyMoment {
            #expect(try await DiskHealthAccess.read(at: moment, serviceID: id, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings) == nil)
        }
        #expect(responder.count == 0)
        #expect(readings.reading(for: id) == nil)
    }

    /// On demand (default, no entry): only the button, which reads everything
    /// (list with SMART, then pools) and keeps it.
    @Test func onDemandReadsOnlyWithTheButton() async throws {
        let (defaults, readings) = try stores()
        let responder = RecordingDisks()
        let client = client(responder)
        let resources = try await client.clusterResources()
        let id = UUID()
        for moment in everyMoment where moment != .userRequest {
            #expect(try await DiskHealthAccess.read(at: moment, serviceID: id, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings) == nil)
        }
        #expect(responder.count == 0)
        let reading = try #require(try await DiskHealthAccess.read(
            at: .userRequest, serviceID: id, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings
        ))
        let paths = responder.diskRequests.withLock { $0.map(\.path) }
        #expect(paths == ["/api2/json/nodes/node-a/disks/list", "/api2/json/nodes/node-a/disks/zfs", "/api2/json/nodes/node-b/disks/list", "/api2/json/nodes/node-b/disks/zfs"])
        #expect(responder.diskRequests.withLock { $0.allSatisfy { $0.query["skipsmart"] == nil } })
        #expect(reading.report.issues.map(\.id).contains("node-a/disk/dev/sdb"))
        #expect(reading.report.issues.map(\.id).contains("node-a/pool/data"))
        #expect(readings.reading(for: id) == reading)
    }

    /// Automatic: one complete read a day after the chosen time (opening or
    /// background task); before it and after it, like on demand.
    @Test func automaticReadsOnceADayAfterTheTime() async throws {
        let (defaults, readings) = try stores()
        let responder = RecordingDisks()
        let client = client(responder)
        let resources = try await client.clusterResources()
        let id = UUID()
        SMARTSettingsStore.set(SMARTSetting(mode: .automatic, hour: 12, minute: 0), for: id, defaults, readings: readings)
        func read(_ moment: SMARTPolicy.Moment, _ now: Date) async throws -> SMARTReading? {
            try await DiskHealthAccess.read(at: moment, serviceID: id, client: client, resources: resources, timeout: 10, now: now, defaults: defaults, readings: readings)
        }
        #expect(try await read(.appOpened, today(11)) == nil)
        #expect(try await read(.scheduledTask, today(11)) == nil)
        #expect(responder.count == 0)
        #expect(try await read(.appOpened, today(13)) != nil)
        let afterRead = responder.count
        #expect(afterRead == 4)
        #expect(try await read(.appOpened, today(14)) == nil)
        #expect(try await read(.scheduledTask, today(15)) == nil)
        #expect(try await read(.refresh, today(16)) == nil)
        #expect(responder.count == afterRead)
        // The button still reads.
        #expect(try await read(.userRequest, today(17)) != nil)
    }

    /// Turned off while a read runs: its result is dropped.
    @Test func turnedOffDuringAReadKeepsNothing() async throws {
        let name = "PatchNode-disks-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let readings = SMARTReadingStore(defaults: name)
        let id = UUID()
        // From the settings screen, same stored settings.
        let responder = RecordingDisks {
            SMARTSettingsStore.set(SMARTSetting(mode: .disabled), for: id, UserDefaults(suiteName: name)!, readings: readings)
        }
        let client = client(responder)
        let resources = try await client.clusterResources()
        #expect(try await DiskHealthAccess.read(at: .userRequest, serviceID: id, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings) == nil)
        #expect(readings.reading(for: id) == nil)
    }

    /// Off then on again during a read, or deleted during it: still dropped.
    @Test(arguments: [false, true])
    func offAndOnAgainOrDeletedDuringAReadKeepsNothing(deleted: Bool) async throws {
        let name = "PatchNode-disks-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let readings = SMARTReadingStore(defaults: name)
        let id = UUID()
        let responder = RecordingDisks {
            let settings = UserDefaults(suiteName: name)!
            if deleted {
                SMARTSettingsStore.remove(id, settings, readings: readings)
            } else {
                SMARTSettingsStore.set(SMARTSetting(mode: .disabled), for: id, settings, readings: readings)
                SMARTSettingsStore.set(SMARTSetting(mode: .onDemand), for: id, settings, readings: readings)
            }
        }
        let client = client(responder)
        let resources = try await client.clusterResources()
        #expect(try await DiskHealthAccess.read(at: .userRequest, serviceID: id, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings) == nil)
        #expect(readings.reading(for: id) == nil)
        // The next read is kept.
        #expect(try await DiskHealthAccess.read(at: .userRequest, serviceID: id, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings) != nil)
    }

    /// A revoked token: one request, no retry, the kept reading untouched.
    @Test func rejectedTokenCostsOneRequestAndKeepsTheReading() async throws {
        let (defaults, readings) = try stores()
        let id = UUID()
        let known = readings.record(ProxmoxDiskHealth(nodes: []), for: id, at: Date(timeIntervalSince1970: 1_800_000_000))
        let responder = RejectingDisks()
        let client = client(responder)
        let resources = try await client.clusterResources()
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await DiskHealthAccess.read(at: .userRequest, serviceID: id, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings)
        }
        #expect(responder.count == 1)
        #expect(readings.reading(for: id) == known)
    }

    /// Turning a service off forgets its reading; the others keep theirs.
    @Test func turningOffClearsTheKeptReading() async throws {
        let (defaults, readings) = try stores()
        let responder = RecordingDisks()
        let client = client(responder)
        let resources = try await client.clusterResources()
        let a = UUID(), b = UUID()
        for id in [a, b] {
            _ = try await DiskHealthAccess.read(at: .userRequest, serviceID: id, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings)
        }
        SMARTSettingsStore.set(SMARTSetting(mode: .automatic), for: a, defaults, readings: readings)
        #expect(readings.reading(for: a) != nil)
        SMARTSettingsStore.set(SMARTSetting(mode: .disabled), for: a, defaults, readings: readings)
        #expect(readings.reading(for: a) == nil)
        #expect(readings.reading(for: b) != nil)
        SMARTSettingsStore.remove(b, defaults, readings: readings)
        #expect(readings.reading(for: b) == nil)
    }

    /// Settings and readings survive a relaunch (new stores on the same
    /// defaults), per service.
    @Test func modeAndReadingArePersistedPerService() async throws {
        let name = "PatchNode-disks-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let readings = SMARTReadingStore(defaults: name)
        let responder = RecordingDisks()
        let client = client(responder)
        let resources = try await client.clusterResources()
        let off = UUID(), onDemand = UUID(), automatic = UUID()
        SMARTSettingsStore.set(SMARTSetting(mode: .disabled), for: off, defaults, readings: readings)
        SMARTSettingsStore.set(SMARTSetting(mode: .onDemand), for: onDemand, defaults, readings: readings)
        SMARTSettingsStore.set(SMARTSetting(mode: .automatic, hour: 6, minute: 45), for: automatic, defaults, readings: readings)
        let read = try #require(try await DiskHealthAccess.read(
            at: .userRequest, serviceID: onDemand, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings
        ))

        let relaunchedDefaults = try #require(UserDefaults(suiteName: name))
        let relaunchedReadings = SMARTReadingStore(defaults: name)
        #expect(SMARTSettingsStore.setting(for: off, relaunchedDefaults).mode == .disabled)
        #expect(SMARTSettingsStore.setting(for: onDemand, relaunchedDefaults).mode == .onDemand)
        #expect(SMARTSettingsStore.setting(for: automatic, relaunchedDefaults) == SMARTSetting(mode: .automatic, hour: 6, minute: 45))
        // Disks and pools with their date, as read.
        #expect(relaunchedReadings.reading(for: onDemand) == read)
        #expect(relaunchedReadings.reading(for: off) == nil)
    }

    /// Disk notifications: only from the kept reading; none for a service
    /// turned off; unknown for a service never read.
    @Test func notificationsComeOnlyFromTheKeptReading() async throws {
        let (defaults, readings) = try stores()
        let responder = RecordingDisks()
        let client = client(responder)
        let resources = try await client.clusterResources()
        let read = UUID(), never = UUID(), off = UUID()
        _ = try await DiskHealthAccess.read(at: .userRequest, serviceID: read, client: client, resources: resources, timeout: 10, defaults: defaults, readings: readings)
        SMARTSettingsStore.set(SMARTSetting(mode: .disabled), for: off, defaults, readings: readings)
        let requests = responder.count
        let (current, unevaluated) = readings.watchedConditions(serviceIDs: [read, never, off], settings: SMARTSettingsStore.all(defaults))
        #expect(current.contains { $0.scope == read.uuidString && $0.key.hasPrefix("node-a/disk/dev/sdb|") })
        #expect(current.allSatisfy { $0.scope == read.uuidString && $0.kind == .diskProblem })
        #expect(unevaluated == [WatchedScope(kind: .diskProblem, scope: never.uuidString)])
        #expect(responder.count == requests)
    }

    /// A node whose disk list failed keeps the disks the previous reading knew.
    @Test func partialReadKeepsWhatWasKnown() {
        let readings = SMARTReadingStore(defaults: "PatchNode-disks-\(UUID().uuidString)")
        let id = UUID()
        let failed = ProxmoxDisk(devpath: "/dev/sdb", health: .failed)
        readings.record(ProxmoxDiskHealth(nodes: [.init(name: "node-a", disks: [failed], pools: [])]), for: id)
        let partial = ProxmoxDiskHealth(nodes: [.init(name: "node-a", disks: [], pools: [ProxmoxZFSPool(name: "rpool", health: "ONLINE")], unavailable: [.disks])])
        let kept = readings.record(partial, for: id)
        #expect(kept.report.nodes[0].disks == [failed])
        #expect(kept.report.nodes[0].pools.map(\.name) == ["rpool"])
        #expect(kept.report.nodes[0].unavailable == [.disks])
    }

    /// The development format (SMART only) is dropped, not misread.
    @Test func legacyReadingsAreDropped() throws {
        let name = "PatchNode-disks-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(Data(#"{"x":1}"#.utf8), forKey: SMARTReadingStore.legacyKey)
        #expect(SMARTReadingStore(defaults: name).reading(for: UUID()) == nil)
        #expect(defaults.object(forKey: SMARTReadingStore.legacyKey) == nil)
    }

    /// Stored in the shape Proxmox sends: a reading decodes back unchanged.
    @Test func readingRoundTrips() throws {
        let report = ProxmoxDiskHealth(nodes: [.init(
            name: "node-a",
            disks: [ProxmoxDisk(devpath: "/dev/nvme0n1", model: "SSD", serial: "S1", type: "nvme", size: 1_000, usage: "ZFS", health: .passed, lifeLeft: 8),
                    ProxmoxDisk(devpath: "/dev/sdb", health: .failed), ProxmoxDisk(devpath: "/dev/sdc", health: .unknown)],
            pools: [ProxmoxZFSPool(name: "tank", health: "DEGRADED", size: 100, allocated: 90, fragmentation: 3)],
            unavailable: [.zfs]
        )])
        let reading = SMARTReading(readAt: Date(timeIntervalSince1970: 1_800_000_000), report: report)
        let data = try JSONEncoder().encode(reading)
        // The serial number is never stored.
        #expect(!String(decoding: data, as: UTF8.self).contains("serial"))
        let decoded = try JSONDecoder().decode(SMARTReading.self, from: data)
        #expect(decoded.report.nodes[0].disks.first { $0.devpath == "/dev/nvme0n1" }?.serial == nil)
        #expect(decoded.readAt == reading.readAt)
        #expect(decoded.report.nodes[0].pools == reading.report.nodes[0].pools)
        #expect(decoded.report.nodes[0].disks.map(\.health) == reading.report.nodes[0].disks.map(\.health))
        #expect(decoded.report.nodes[0].disks.map(\.lifeLeft) == reading.report.nodes[0].disks.map(\.lifeLeft))
        #expect(decoded.report.nodes[0].unavailable == [.zfs])
    }
}

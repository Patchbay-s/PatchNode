import Foundation
import Testing
@testable import PatchNodeCore

struct CloudSyncTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func setting(_ value: String, _ offset: TimeInterval, key: String = "tabSelection") -> SyncedSettingValue {
        SyncedSettingValue(key: key, value: value, updatedAt: t0 + offset)
    }

    @Test func latestWriteWinsPerKey() {
        let records = [setting("dashboard,proxmox", 0), setting("dashboard,docker", 60), setting("docker", 10, key: "dashboardCardOrder")]
        let winners = CloudReconciliation.winners(records)
        #expect(winners["tabSelection"]?.value == "dashboard,docker")
        #expect(winners["dashboardCardOrder"]?.value == "docker")
    }

    @Test func sameDateTieIsDecidedTheSameWayEverywhere() {
        let a = setting("a", 0), b = setting("b", 0)
        #expect(CloudReconciliation.winners([a, b])["tabSelection"] == b)
        #expect(CloudReconciliation.winners([b, a])["tabSelection"] == b)
    }

    @Test func oversizedValuesAreIgnored() {
        let huge = setting(String(repeating: "x", count: CloudReconciliation.maxValueLength + 1), 100)
        #expect(CloudReconciliation.winners([setting("dashboard", 0), huge])["tabSelection"]?.value == "dashboard")
    }

    @Test func redundantSettingsKeepOneWinnerPerKey() {
        let old = setting("dashboard", 0)
        let new = setting("dashboard,docker", 60)
        let copy = setting("dashboard,docker", 60)
        let order = setting("docker", 0, key: "dashboardCardOrder")
        let older = setting("docker,proxmox", -60, key: "dashboardCardOrder")
        // Only older records go; the winner's copies stay (deleted on two devices,
        // both copies could disappear).
        #expect(CloudReconciliation.redundantSettings([old, new, order, copy, older]) == [0, 4])
    }

    @Test func settingActions() {
        let synced = setting("dashboard,docker", 0)
        // Another device changed it: adopt.
        #expect(CloudReconciliation.action(local: "dashboard", synced: synced, localChanged: false) == .adopt("dashboard,docker"))
        // Changed here: publish.
        #expect(CloudReconciliation.action(local: "dashboard", synced: synced, localChanged: true) == .publish)
        // Same value, whoever wrote it: nothing (no ping-pong between devices).
        #expect(CloudReconciliation.action(local: "dashboard,docker", synced: synced, localChanged: true) == .none)
        // Nothing synced yet: publish what this device has, unless it's the default.
        #expect(CloudReconciliation.action(local: "dashboard", synced: nil, localChanged: false) == .publish)
        #expect(CloudReconciliation.action(local: "", synced: nil, localChanged: false) == .none)
    }

    @Test func duplicatesShowTheFirstCopy() {
        let a = UUID(), b = UUID()
        let records = [(a, "first"), (b, "b"), (a, "second"), (a, "third")]
        #expect(records.uniqued(by: \.0).map(\.1) == ["first", "b"])
        #expect([String]().uniqued(by: \.self).isEmpty)
    }

    @Test func syncedKeysMatchTheAppSettings() {
        #expect(CloudReconciliation.syncedKeys == [TabSelection.storageKey, "dashboardCardOrder"])
    }

    @Test func bothSyncOptionsAreOffByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "PatchNode-cloud-\(UUID().uuidString)"))
        #expect(!CloudSyncSettings.isEnabled(defaults))
        #expect(!TokenSyncSettings.isEnabled(defaults))
    }
}

struct CredentialOriginTests {
    @Test func originIsSchemeHostAndPort() {
        #expect(CredentialOrigin.of("https://PROXMOX.example.invalid:8006/api2/json") == "https://proxmox.example.invalid:8006")
        #expect(CredentialOrigin.of("https://ha.example.invalid") == "https://ha.example.invalid:443")
        #expect(CredentialOrigin.of("https://ha.example.invalid:443/") == CredentialOrigin.of("https://ha.example.invalid"))
        #expect(CredentialOrigin.of("https://a.example.invalid") != CredentialOrigin.of("https://b.example.invalid"))
        #expect(CredentialOrigin.of("https://a.example.invalid:8443") != CredentialOrigin.of("https://a.example.invalid"))
        #expect(CredentialOrigin.of("not a url") == nil)
    }

    @Test func inMemoryStoreChecksTheOrigin() async throws {
        let store = InMemorySecretStore()
        let id = UUID()
        try await store.save("fake-token", for: id, origin: "https://a.example.invalid:443")
        #expect(try await store.read(for: id, origin: "https://a.example.invalid:443") == "fake-token")
        #expect(try await store.read(for: id, origin: "https://b.example.invalid:443") == nil)
        try await store.deleteDeviceOnly(for: id)
        #expect(try await store.read(for: id) == nil)
    }

    @Test func unboundSecretsAreRefusedOnceSyncIsOn() throws {
        let defaults = try #require(UserDefaults(suiteName: "PatchNode-binding-\(UUID().uuidString)"))
        #expect(CredentialBinding.acceptsUnbound(defaults))
        defaults.set(true, forKey: CloudSyncSettings.key)
        #expect(!CredentialBinding.acceptsUnbound(defaults))
        defaults.set(false, forKey: CloudSyncSettings.key)
        CredentialBinding.markDone(defaults)
        #expect(!CredentialBinding.acceptsUnbound(defaults))
    }
}

struct CloudMaintenanceTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let a = UUID(), b = UUID()

    @Test func orphanIsPurgedOnlyAfterTheGrace() {
        var tracker = OrphanTokenTracker()
        #expect(tracker.update(current: [a, b], purging: true, now: t0).isEmpty)
        // b deleted on another device: not yet.
        #expect(tracker.update(current: [a], purging: true, now: t0 + 60).isEmpty)
        #expect(tracker.update(current: [a], purging: true, now: t0 + 60 + OrphanTokenTracker.grace) == [b])
        // Not deleted yet (Keychain locked): asked again next time.
        #expect(tracker.update(current: [a], purging: true, now: t0 + 120 + OrphanTokenTracker.grace) == [b])
        tracker.markPurged([b])
        #expect(!tracker.known.contains(b))
        #expect(tracker.update(current: [a], purging: true, now: t0 + 10 * OrphanTokenTracker.grace).isEmpty)
    }

    @Test func serviceBackInTimeIsKept() {
        var tracker = OrphanTokenTracker()
        _ = tracker.update(current: [a, b], purging: true, now: t0)
        _ = tracker.update(current: [a], purging: true, now: t0 + 60)
        // Back during an iCloud import: forgiven.
        #expect(tracker.update(current: [a, b], purging: true, now: t0 + 120).isEmpty)
        #expect(tracker.update(current: [a, b], purging: true, now: t0 + 2 * OrphanTokenTracker.grace).isEmpty)
    }

    @Test func emptyStoreNeverPurges() {
        var tracker = OrphanTokenTracker()
        _ = tracker.update(current: [a, b], purging: true, now: t0)
        // Every service gone (account changed, zone deleted elsewhere): kept.
        #expect(tracker.update(current: [], purging: true, now: t0 + OrphanTokenTracker.grace * 2).isEmpty)
        #expect(tracker.update(current: [], purging: true, now: t0 + 30 * 86_400).isEmpty)
        #expect(tracker.known == [a, b])
    }

    @Test func withoutSyncNothingIsPurged() {
        var tracker = OrphanTokenTracker()
        _ = tracker.update(current: [a, b], purging: false, now: t0)
        #expect(tracker.update(current: [a], purging: false, now: t0 + 86_400).isEmpty)
        // Deleted while sync was off: not counted against later.
        #expect(tracker.update(current: [a], purging: true, now: t0 + 2 * 86_400).isEmpty)
    }

    @Test func trackerStorageRoundTrips() {
        var tracker = OrphanTokenTracker()
        _ = tracker.update(current: [a, b], purging: true, now: t0)
        _ = tracker.update(current: [a], purging: true, now: t0 + 60)
        #expect(OrphanTokenTracker.decoded(from: tracker.encoded()) == tracker)
        #expect(OrphanTokenTracker.decoded(from: Data("garbage".utf8)) == OrphanTokenTracker())
    }

    @Test func deletionStepsAndAvailability() {
        #expect(CloudDataDeletion.steps(tokenSyncOn: false) == [.deleteConfigurationZone, .turnSyncOff])
        #expect(CloudDataDeletion.steps(tokenSyncOn: true)
            == [.moveTokensToDevice, .deleteSyncedTokens, .deleteConfigurationZone, .turnSyncOff])
        #expect(CloudDataDeletion.availability(syncRunning: true, demo: false) == .syncRunning)
        #expect(CloudDataDeletion.availability(syncRunning: false, demo: true) == .demo)
        #expect(CloudDataDeletion.availability(syncRunning: false, demo: false) == .available)
    }
}

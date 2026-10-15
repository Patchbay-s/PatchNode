import Foundation
import Testing
@testable import PatchNodeCore

struct ConditionWatchTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let all = Set(WatchedKind.allCases)
    let down = WatchedCondition(kind: .serviceUnreachable, scope: "svc-a", key: "unreachable")
    let unhealthy = WatchedCondition(kind: .containerUnhealthy, scope: "svc-b", key: "engine|abc")

    @Test func newProblemIsAnnouncedOnceWhileItLasts() {
        var watch = ConditionWatch()
        #expect(watch.update(current: [down], enabled: all, deliver: true, now: t0) == [.serviceUnreachable: 1])
        #expect(watch.update(current: [down], enabled: all, deliver: true, now: t0 + 600).isEmpty)
        #expect(watch.update(current: [down], enabled: all, deliver: true, now: t0 + 86_400).isEmpty)
    }

    @Test func countsPerKind() {
        var watch = ConditionWatch()
        let other = WatchedCondition(kind: .serviceUnreachable, scope: "svc-c", key: "unreachable")
        #expect(watch.update(current: [down, other, unhealthy], enabled: all, deliver: true, now: t0)
            == [.serviceUnreachable: 2, .containerUnhealthy: 1])
    }

    @Test func flappingProblemStaysQuietDuringCooldown() {
        var watch = ConditionWatch()
        _ = watch.update(current: [down], enabled: all, deliver: true, now: t0)
        _ = watch.update(current: [], enabled: all, deliver: true, now: t0 + 1_800)
        #expect(watch.update(current: [down], enabled: all, deliver: true, now: t0 + 3_600).isEmpty)
        _ = watch.update(current: [], enabled: all, deliver: true, now: t0 + 4_000)
        #expect(watch.update(current: [down], enabled: all, deliver: true, now: t0 + ConditionWatch.cooldown + 1)
            == [.serviceUnreachable: 1])
    }

    @Test func foregroundCountsAsSeen() {
        var watch = ConditionWatch()
        #expect(watch.update(current: [down], enabled: all, deliver: false, now: t0).isEmpty)
        // Still there in the background: already seen on screen.
        #expect(watch.update(current: [down], enabled: all, deliver: true, now: t0 + 3_600).isEmpty)
    }

    @Test func disabledKindIsTrackedButNotAnnounced() {
        var watch = ConditionWatch()
        #expect(watch.update(current: [down, unhealthy], enabled: [.containerUnhealthy], deliver: true, now: t0)
            == [.containerUnhealthy: 1])
        // Enabling it later doesn't announce the problem that was already there.
        #expect(watch.update(current: [down, unhealthy], enabled: all, deliver: true, now: t0 + 600).isEmpty)
        // A new one of that kind is announced.
        let another = WatchedCondition(kind: .serviceUnreachable, scope: "svc-z", key: "unreachable")
        #expect(watch.update(current: [down, unhealthy, another], enabled: all, deliver: true, now: t0 + 1_200)
            == [.serviceUnreachable: 1])
    }

    @Test func disabledKindProblemIsAnnouncedWhenItComesBackAfterEnabling() {
        var watch = ConditionWatch()
        _ = watch.update(current: [down], enabled: [], deliver: true, now: t0)
        _ = watch.update(current: [], enabled: all, deliver: true, now: t0 + 600)
        #expect(watch.update(current: [down], enabled: all, deliver: true, now: t0 + 1_200) == [.serviceUnreachable: 1])
    }

    @Test func clearedProblemsAreForgottenAfterRetention() {
        var watch = ConditionWatch()
        _ = watch.update(current: [down], enabled: all, deliver: true, now: t0)
        _ = watch.update(current: [], enabled: all, deliver: true, now: t0 + 60)
        #expect(watch.records.count == 1)
        _ = watch.update(current: [], enabled: all, deliver: true, now: t0 + ConditionWatch.retention + 61)
        #expect(watch.records.isEmpty)
    }

    @Test func recordsAreBounded() {
        var watch = ConditionWatch()
        let many = Set((0..<(ConditionWatch.maxRecords + 50)).map { WatchedCondition(kind: .alertFiring, scope: "svc", key: "a\($0)") })
        _ = watch.update(current: many, enabled: all, deliver: false, now: t0)
        _ = watch.update(current: [], enabled: all, deliver: false, now: t0 + 60)
        #expect(watch.records.count == ConditionWatch.maxRecords)
    }

    @Test func storageRoundTripsAndToleratesGarbage() {
        var watch = ConditionWatch()
        _ = watch.update(current: [down], enabled: all, deliver: true, now: t0)
        var restored = ConditionWatch.decoded(from: watch.encoded())
        #expect(restored == watch)
        #expect(restored.update(current: [down], enabled: all, deliver: true, now: t0 + 60).isEmpty)
        #expect(ConditionWatch.decoded(from: Data("garbage".utf8)) == ConditionWatch())
        #expect(ConditionWatch.decoded(from: nil) == ConditionWatch())
    }

    @Test func settingsEncoding() {
        let kinds: Set<WatchedKind> = [.diskProblem, .serviceUnreachable]
        #expect(WatchedKindSettings.encode(kinds) == "serviceUnreachable,diskProblem")
        #expect(WatchedKindSettings.decode("serviceUnreachable,retired,diskProblem") == kinds)
        #expect(WatchedKindSettings.decode("").isEmpty)
    }

    @Test func unevaluatedServiceKeepsItsProblems() {
        var watch = ConditionWatch()
        _ = watch.update(current: [unhealthy], enabled: all, deliver: true, now: t0)
        // The Docker host timed out once: its container isn't "fixed".
        let skipped: Set<WatchedScope> = [WatchedScope(kind: .containerUnhealthy, scope: "svc-b")]
        _ = watch.update(current: [], unevaluated: skipped, enabled: all, deliver: true, now: t0 + 8 * 3_600)
        // Back more than 6 hours after the first notification: still the same problem.
        #expect(watch.update(current: [unhealthy], enabled: all, deliver: true, now: t0 + 9 * 3_600).isEmpty)
        // Another kind of the same service isn't covered by that scope.
        _ = watch.update(current: [down], enabled: all, deliver: true, now: t0 + 10 * 3_600)
        _ = watch.update(current: [], unevaluated: skipped, enabled: all, deliver: true, now: t0 + 11 * 3_600)
        #expect(watch.update(current: [down], enabled: all, deliver: true, now: t0 + 18 * 3_600) == [.serviceUnreachable: 1])
    }

    @Test func storedStateHoldsHashesNotKeys() throws {
        var watch = ConditionWatch()
        let alert = WatchedCondition(kind: .alertFiring, scope: "svc", key: "instance=192.0.2.4:9100,url=https://storage.example.invalid")
        _ = watch.update(current: [alert], enabled: all, deliver: true, now: t0)
        let text = String(decoding: try #require(watch.encoded()), as: UTF8.self)
        #expect(!text.contains("192.0.2.4"))
        #expect(!text.contains("storage.example.invalid"))
        #expect(text.contains(SHA256.hex(alert.key)))
    }

    @Test func sha256MatchesKnownVectors() {
        #expect(SHA256.hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SHA256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        #expect(SHA256.hex(String(repeating: "a", count: 1_000)).count == 64)
    }
}

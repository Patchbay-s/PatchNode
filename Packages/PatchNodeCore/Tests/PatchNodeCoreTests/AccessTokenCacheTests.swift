import Foundation
import Testing
@testable import PatchNodeCore

// MARK: - Helpers

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let credentialA = "tskey-client-fake-1234:fake-secret-aaaa"
private let credentialB = "tskey-client-fake-5678:fake-secret-bbbb"

private struct FakeFetchError: Error, Equatable {}

/// Counts fetch calls and optionally holds them until released. No real delay:
/// each held fetch suspends on a continuation that the test resumes explicitly.
private actor FetchProbe {
    private(set) var calls = 0
    private var isOpen: Bool
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []

    init(open: Bool = true) {
        self.isOpen = open
    }

    /// Returns the 1-based index of this call once it is released.
    func enter() async -> Int {
        calls += 1
        let index = calls
        if !isOpen && !released.contains(index) {
            await withCheckedContinuation { waiters[index] = $0 }
        }
        return index
    }

    /// Releases every held fetch and the following ones.
    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for (_, waiter) in pending { waiter.resume() }
    }

    /// Releases only fetch number `index`.
    func release(_ index: Int) {
        released.insert(index)
        waiters.removeValue(forKey: index)?.resume()
    }
}

/// Polls `probe` from outside the actor so other tasks can make progress.
private func waitForCalls(_ probe: FetchProbe, _ count: Int) async throws {
    for _ in 0..<2_000 {
        if await probe.calls >= count { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for \(count) fetch calls")
}

/// A fetch closure returning `token-<n>` valid for `lifetime` seconds after `t0`.
private func fetcher(_ probe: FetchProbe, lifetime: TimeInterval = 3_600) -> @Sendable () async throws -> AccessToken {
    {
        let index = await probe.enter()
        return AccessToken(value: "fake-access-token-\(index)", expiresAt: t0.addingTimeInterval(lifetime))
    }
}

// MARK: - Reuse and expiry

@Suite("AccessTokenCache reuse and expiry")
struct AccessTokenCacheExpiryTests {
    @Test func secondCallBeforeExpiryReusesCachedTokenWithoutFetching() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let id = UUID()
        let first = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe))
        let second = try await cache.token(for: id, credential: credentialA, now: t0.addingTimeInterval(1_000), fetch: fetcher(probe))
        #expect(first == "fake-access-token-1")
        #expect(second == "fake-access-token-1")
        #expect(await probe.calls == 1)
        #expect(await cache.cachedCount == 1)
    }

    @Test func tokenInsideExpiryMarginIsRefetched() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let id = UUID()
        _ = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe, lifetime: 3_600))
        // 59 s left < 60 s margin: renewed before its stated expiry.
        let renewed = try await cache.token(for: id, credential: credentialA, now: t0.addingTimeInterval(3_541), fetch: fetcher(probe))
        #expect(renewed == "fake-access-token-2")
        #expect(await probe.calls == 2)
    }

    @Test func tokenWithExactlyMarginLeftIsRefetched() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let id = UUID()
        _ = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe, lifetime: 3_600))
        _ = try await cache.token(for: id, credential: credentialA, now: t0.addingTimeInterval(3_540), fetch: fetcher(probe))
        #expect(await probe.calls == 2)
    }

    @Test func tokenJustOutsideMarginIsReused() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let id = UUID()
        _ = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe, lifetime: 3_600))
        let reused = try await cache.token(for: id, credential: credentialA, now: t0.addingTimeInterval(3_539), fetch: fetcher(probe))
        #expect(reused == "fake-access-token-1")
        #expect(await probe.calls == 1)
    }

    @Test func expiredTokenIsRefetchedAndReplacesTheOldOne() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let id = UUID()
        _ = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe, lifetime: 600))
        let afterExpiry = t0.addingTimeInterval(7_200)
        let renewed = try await cache.token(for: id, credential: credentialA, now: afterExpiry, fetch: {
            let index = await probe.enter()
            return AccessToken(value: "fake-access-token-\(index)", expiresAt: afterExpiry.addingTimeInterval(3_600))
        })
        #expect(renewed == "fake-access-token-2")
        // The renewed token is now cached.
        let again = try await cache.token(for: id, credential: credentialA, now: afterExpiry.addingTimeInterval(10), fetch: fetcher(probe))
        #expect(again == "fake-access-token-2")
        #expect(await probe.calls == 2)
        #expect(await cache.cachedCount == 1)
    }

    @Test func differentCredentialForSameServiceTriggersRefetch() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let id = UUID()
        _ = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe))
        let withB = try await cache.token(for: id, credential: credentialB, now: t0, fetch: fetcher(probe))
        #expect(withB == "fake-access-token-2")
        #expect(await probe.calls == 2)
        // The token obtained with B replaced the one from A: going back to A refetches.
        let backToA = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe))
        #expect(backToA == "fake-access-token-3")
        #expect(await probe.calls == 3)
    }

    @Test func servicesAreCachedIndependently() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let first = UUID(), second = UUID()
        let a = try await cache.token(for: first, credential: credentialA, now: t0, fetch: fetcher(probe))
        let b = try await cache.token(for: second, credential: credentialA, now: t0, fetch: fetcher(probe))
        #expect(a != b)
        #expect(await probe.calls == 2)
        #expect(await cache.cachedCount == 2)
    }
}

// MARK: - Concurrency

@Suite("AccessTokenCache concurrent callers")
struct AccessTokenCacheConcurrencyTests {
    @Test func concurrentCallersForSameServiceShareOneFetch() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let id = UUID()
        // Already inside the margin when it arrives: a late caller couldn't hit
        // the cache and would start its own fetch, so one call proves the join.
        let fetch = fetcher(probe, lifetime: 10)

        let callers = (0..<5).map { _ in
            Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetch) }
        }
        try await waitForCalls(probe, 1)
        // Let every caller reach the actor and join the pending fetch.
        try await Task.sleep(for: .milliseconds(100))
        await probe.open()

        var values: [String] = []
        for caller in callers { values.append(try await caller.value) }
        #expect(values == Array(repeating: "fake-access-token-1", count: 5))
        #expect(await probe.calls == 1)
    }

    @Test func concurrentCallerWithDifferentCredentialDoesNotJoinPendingFetch() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let id = UUID()
        let callerA = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) }
        try await waitForCalls(probe, 1)
        let callerB = Task { try await cache.token(for: id, credential: credentialB, now: t0, fetch: fetcher(probe)) }
        try await waitForCalls(probe, 2)
        await probe.open()
        let a = try await callerA.value
        let b = try await callerB.value
        #expect(a != b)
        #expect(await probe.calls == 2)
    }

    @Test func concurrentCallersForDifferentServicesFetchSeparately() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let first = Task { try await cache.token(for: UUID(), credential: credentialA, now: t0, fetch: fetcher(probe)) }
        let second = Task { try await cache.token(for: UUID(), credential: credentialA, now: t0, fetch: fetcher(probe)) }
        try await waitForCalls(probe, 2)
        await probe.open()
        _ = try await first.value
        _ = try await second.value
        #expect(await probe.calls == 2)
        #expect(await cache.cachedCount == 2)
    }
}

// MARK: - Invalidation

@Suite("AccessTokenCache invalidation")
struct AccessTokenCacheInvalidationTests {
    @Test func invalidateDropsOnlyThatServiceAndForcesRefetch() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let invalidated = UUID(), kept = UUID()
        _ = try await cache.token(for: invalidated, credential: credentialA, now: t0, fetch: fetcher(probe))
        _ = try await cache.token(for: kept, credential: credentialA, now: t0, fetch: fetcher(probe))

        await cache.invalidate(invalidated)
        #expect(await cache.cachedCount == 1)

        let renewed = try await cache.token(for: invalidated, credential: credentialA, now: t0, fetch: fetcher(probe))
        let stillCached = try await cache.token(for: kept, credential: credentialA, now: t0, fetch: fetcher(probe))
        #expect(renewed == "fake-access-token-3")
        #expect(stillCached == "fake-access-token-2")
        #expect(await probe.calls == 3)
    }

    @Test func invalidateUnknownServiceIsHarmless() async throws {
        let cache = AccessTokenCache()
        let probe = FetchProbe()
        let id = UUID()
        _ = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe))
        await cache.invalidate(UUID())
        #expect(await cache.cachedCount == 1)
    }

    @Test func removeAllDropsEveryTokenAndForcesRefetch() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let first = UUID(), second = UUID()
        _ = try await cache.token(for: first, credential: credentialA, now: t0, fetch: fetcher(probe))
        _ = try await cache.token(for: second, credential: credentialB, now: t0, fetch: fetcher(probe))

        await cache.removeAll()
        #expect(await cache.cachedCount == 0)

        _ = try await cache.token(for: first, credential: credentialA, now: t0, fetch: fetcher(probe))
        _ = try await cache.token(for: second, credential: credentialB, now: t0, fetch: fetcher(probe))
        #expect(await probe.calls == 4)
    }

    @Test func fetchInFlightDuringRemoveAllDoesNotStoreItsToken() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let id = UUID()
        let caller = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) }
        try await waitForCalls(probe, 1)

        await cache.removeAll()
        await probe.open()
        // The fetch ignores cancellation and completes; the caller still gets its
        // value, but it must not be kept after the cache was cleared.
        _ = try? await caller.value
        #expect(await cache.cachedCount == 0)

        let next = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe))
        #expect(next == "fake-access-token-2")
        #expect(await probe.calls == 2)
    }

    @Test func removeAllCancelsTheInFlightFetchTask() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let id = UUID()
        let caller = Task {
            try await cache.token(for: id, credential: credentialA, now: t0, fetch: {
                _ = await probe.enter()
                try Task.checkCancellation()
                return AccessToken(value: "fake-access-token-never", expiresAt: t0.addingTimeInterval(3_600))
            })
        }
        try await waitForCalls(probe, 1)
        await cache.removeAll()
        await probe.open()
        await #expect(throws: CancellationError.self) {
            _ = try await caller.value
        }
        #expect(await cache.cachedCount == 0)
    }

    @Test func staleFetchFinishingAfterRemoveAllDoesNotDetachNewerPendingFetch() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let id = UUID()
        // Expires inside the margin: only a caller joining the pending fetch can
        // avoid starting a new one.
        let fetch = fetcher(probe, lifetime: 10)

        let stale = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetch) }
        try await waitForCalls(probe, 1)
        await cache.removeAll()

        let fresh = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetch) }
        try await waitForCalls(probe, 2)

        // The stale fetch finishes while the fresh one is still pending.
        await probe.release(1)
        _ = try? await stale.value
        #expect(await cache.cachedCount == 0)

        // A new caller must still join the fresh pending fetch.
        let joiner = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetch) }
        try await Task.sleep(for: .milliseconds(100))
        await probe.release(2)
        #expect(try await fresh.value == "fake-access-token-2")
        #expect(try await joiner.value == "fake-access-token-2")
        #expect(await probe.calls == 2)
    }
}

// MARK: - Errors

@Suite("AccessTokenCache fetch errors")
struct AccessTokenCacheErrorTests {
    @Test func fetchErrorPropagatesToCaller() async {
        let cache = AccessTokenCache()
        await #expect(throws: FakeFetchError()) {
            _ = try await cache.token(for: UUID(), credential: credentialA, now: t0, fetch: { throw FakeFetchError() })
        }
    }

    @Test func fetchErrorIsNotCachedAndNextCallFetchesAgain() async throws {
        let cache = AccessTokenCache()
        let probe = FetchProbe()
        let id = UUID()
        await #expect(throws: FakeFetchError()) {
            _ = try await cache.token(for: id, credential: credentialA, now: t0, fetch: {
                _ = await probe.enter()
                throw FakeFetchError()
            })
        }
        #expect(await cache.cachedCount == 0)

        let token = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe))
        #expect(token == "fake-access-token-2")
        #expect(await probe.calls == 2)
    }

    @Test func fetchErrorIsDeliveredToEveryJoinedCaller() async throws {
        let cache = AccessTokenCache()
        let probe = FetchProbe(open: false)
        let id = UUID()
        let failing: @Sendable () async throws -> AccessToken = {
            _ = await probe.enter()
            throw FakeFetchError()
        }
        let callers = (0..<3).map { _ in
            Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: failing) }
        }
        try await waitForCalls(probe, 1)
        try await Task.sleep(for: .milliseconds(100))
        await probe.open()
        for caller in callers {
            await #expect(throws: FakeFetchError()) { _ = try await caller.value }
        }
        #expect(await probe.calls == 1)
        #expect(await cache.cachedCount == 0)
    }

    @Test func failedRefreshKeepsNoStaleEntryUsable() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let id = UUID()
        _ = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe, lifetime: 600))
        // Expired: refresh fails, the error surfaces instead of the expired token.
        await #expect(throws: FakeFetchError()) {
            _ = try await cache.token(for: id, credential: credentialA, now: t0.addingTimeInterval(3_600), fetch: { throw FakeFetchError() })
        }
    }
}

// MARK: - Phase 6 review fixes

@Suite("AccessTokenCache after review")
struct AccessTokenCacheReviewTests {
    /// Pull to refresh cancels the first caller while a second one joins its fetch:
    /// the token obtained must still be cached (no extra login POST next time).
    @Test func tokenIsCachedEvenWhenTheStartingCallerWasCancelled() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let id = UUID()
        let first = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) }
        try await waitForCalls(probe, 1)
        first.cancel()
        let joiner = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) }
        try await Task.sleep(for: .milliseconds(20))
        await probe.open()
        _ = try? await first.value
        #expect(try await joiner.value == "fake-access-token-1")
        #expect(await cache.cachedCount == 1)
        #expect(try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) == "fake-access-token-1")
        #expect(await probe.calls == 1)
    }

    /// Background refresh expiring during a slow login POST: the caller returns at
    /// once instead of waiting for the POST, which still caches its token.
    @Test func cancelledCallerReturnsWithoutWaitingForTheFetch() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let id = UUID()
        let caller = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) }
        try await waitForCalls(probe, 1)
        caller.cancel()
        // The fetch is still held: only the caller's cancellation can end this.
        await #expect(throws: CancellationError.self) { _ = try await caller.value }
        await probe.open()
        for _ in 0..<2_000 where await cache.cachedCount == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) == "fake-access-token-1")
        #expect(await probe.calls == 1)
    }

    @Test func callerCancelledBeforeJoiningReturnsImmediately() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let id = UUID()
        let first = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) }
        try await waitForCalls(probe, 1)
        let joiner = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe))
        }
        await #expect(throws: CancellationError.self) { _ = try await joiner.value }
        await probe.open()
        #expect(try await first.value == "fake-access-token-1")
        #expect(await probe.calls == 1)
    }

    /// A late 401 with an old token must not drop the newer token cached meanwhile.
    @Test func invalidateWithAStaleTokenKeepsTheNewerOne() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe()
        let id = UUID()
        _ = try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe, lifetime: 30))
        // Inside the margin: refetched as token 2.
        #expect(try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) == "fake-access-token-2")
        await cache.invalidate(id, token: "fake-access-token-1")
        #expect(await cache.cachedCount == 1)
        await cache.invalidate(id, token: "fake-access-token-2")
        #expect(await cache.cachedCount == 0)
    }

    /// A fetch for an old credential finishing after a newer one must not overwrite it.
    @Test func staleCredentialFetchDoesNotOverwriteNewerEntry() async throws {
        let cache = AccessTokenCache(margin: 60)
        let probe = FetchProbe(open: false)
        let id = UUID()
        let old = Task { try await cache.token(for: id, credential: credentialA, now: t0, fetch: fetcher(probe)) }
        try await waitForCalls(probe, 1)
        let new = Task { try await cache.token(for: id, credential: credentialB, now: t0, fetch: fetcher(probe)) }
        try await waitForCalls(probe, 2)
        await probe.release(2)
        #expect(try await new.value == "fake-access-token-2")
        await probe.release(1)
        _ = try await old.value
        // The entry still belongs to credential B.
        #expect(try await cache.token(for: id, credential: credentialB, now: t0, fetch: fetcher(probe)) == "fake-access-token-2")
        #expect(await probe.calls == 2)
    }
}

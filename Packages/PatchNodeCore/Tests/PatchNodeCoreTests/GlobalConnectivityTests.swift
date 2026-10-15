import Foundation
import Testing
@testable import PatchNodeCore

struct GlobalConnectivityTests {
    private struct FakeNetworkError: Error, Sendable {}

    @Test func emptyStatusesAreUnknown() {
        #expect(aggregateConnectivity(from: []) == .unknown)
    }

    @Test func allUnreachableStatusesAreAllUnreachable() {
        let statuses: [HealthStatus] = [
            .unreachable(FakeNetworkError()),
            .unreachable(HTTPClientError.unreachable),
            .unreachable(URLError(.timedOut)),
        ]
        #expect(aggregateConnectivity(from: statuses) == .allUnreachable)
    }

    @Test func singleUnreachableStatusIsAllUnreachable() {
        #expect(aggregateConnectivity(from: [.unreachable(FakeNetworkError())]) == .allUnreachable)
    }

    @Test func mixedStatusesArePartiallyReachable() {
        let statuses: [HealthStatus] = [
            .unreachable(FakeNetworkError()),
            .ok,
            .unreachable(FakeNetworkError()),
        ]
        #expect(aggregateConnectivity(from: statuses) == .partiallyReachable)
    }

    @Test func noUnreachableStatusIsPartiallyReachable() {
        let statuses: [HealthStatus] = [.ok, .degraded("fake degraded reason"), .unauthorized]
        #expect(aggregateConnectivity(from: statuses) == .partiallyReachable)
    }
}

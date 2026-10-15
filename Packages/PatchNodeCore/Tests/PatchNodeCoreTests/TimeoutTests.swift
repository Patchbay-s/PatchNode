import Foundation
import Testing
@testable import PatchNodeCore

private actor CancellationProbe {
    private(set) var wasCancelled = false
    func markCancelled() { wasCancelled = true }
}

private struct OperationFailure: Error, Equatable {}

@Suite("withTimeout")
struct TimeoutTests {
    @Test func fastOperationReturnsItsValue() async throws {
        let value = try await withTimeout(seconds: 5) { 42 }
        #expect(value == 42)
    }

    @Test func fastAsyncOperationReturnsBeforeTimeout() async throws {
        let value = try await withTimeout(seconds: 5) {
            try await Task.sleep(for: .milliseconds(10))
            return "done"
        }
        #expect(value == "done")
    }

    @Test func slowOperationThrowsTimeoutErrorQuicklyAndIsCancelled() async throws {
        let probe = CancellationProbe()
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: TimeoutError.self) {
            _ = try await withTimeout(seconds: 0.05) {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch is CancellationError {
                    await probe.markCancelled()
                    throw CancellationError()
                }
                return 1
            }
        }
        let elapsed = clock.now - start
        #expect(elapsed < .seconds(2))
        // The task group awaits its children, so the probe is set once withTimeout returns.
        #expect(await probe.wasCancelled)
    }

    @Test func operationErrorPropagates() async {
        await #expect(throws: OperationFailure()) {
            _ = try await withTimeout(seconds: 5) { () async throws -> Int in
                throw OperationFailure()
            }
        }
    }

    @Test func operationErrorPropagatesInsteadOfTimeoutError() async {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: OperationFailure()) {
            _ = try await withTimeout(seconds: 5) { () async throws -> Int in
                try await Task.sleep(for: .milliseconds(10))
                throw OperationFailure()
            }
        }
        // Timer child is cancelled: no need to wait the 5 s.
        #expect(clock.now - start < .seconds(2))
    }
}

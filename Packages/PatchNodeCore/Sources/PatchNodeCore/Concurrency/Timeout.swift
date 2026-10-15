public struct TimeoutError: Error, Sendable, Equatable {
    public init() {}
}

/// Runs `operation`, cancelling it and throwing `TimeoutError` if it takes longer
/// than `seconds`. Used to bound each service's refresh independently.
public func withTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            // Suspending clock: time spent with the app suspended doesn't count,
            // so returning to the foreground doesn't instantly time everything out.
            try await Task.sleep(for: .seconds(seconds), tolerance: nil, clock: .suspending)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TimeoutError() }
        return result
    }
}

import Foundation
import Synchronization

/// A short-lived access token obtained from a long-lived credential (Tailscale
/// OAuth client, Nginx Proxy Manager login).
public struct AccessToken: Sendable, Equatable {
    public let value: String
    public let expiresAt: Date

    public init(value: String, expiresAt: Date) {
        self.value = value
        self.expiresAt = expiresAt
    }
}

/// In-memory cache of access tokens, one per service. A token is reused until
/// shortly before it expires, then fetched again; it is never written to disk.
///
/// Concurrent callers for the same service share one fetch, so a refresh and a
/// detail screen can't send two login POSTs at once.
public actor AccessTokenCache {
    private struct Entry {
        let token: AccessToken
        let fingerprint: Int
    }

    private var entries: [UUID: Entry] = [:]
    private var inFlight: [UUID: (fingerprint: Int, id: UUID, task: Task<AccessToken, any Error>)] = [:]
    /// Tokens are renewed this long before their stated expiry.
    private let margin: TimeInterval

    public init(margin: TimeInterval = 60) {
        self.margin = margin
    }

    /// Returns a valid cached token for `serviceID`, or runs `fetch` to get one.
    /// `credential` identifies the long-lived credential (and its server): a token
    /// obtained with another one is never reused. Only a hash of it is kept.
    public func token(
        for serviceID: UUID,
        credential: String,
        now: Date = .now,
        fetch: @escaping @Sendable () async throws -> AccessToken
    ) async throws -> String {
        let fingerprint = credential.hashValue
        if let entry = entries[serviceID], entry.fingerprint == fingerprint,
           entry.token.expiresAt.timeIntervalSince(now) > margin {
            return entry.token.value
        }
        if let pending = inFlight[serviceID], pending.fingerprint == fingerprint {
            return try await Self.wait(for: pending.task).value
        }
        // A caller already cancelled doesn't start a login nobody would wait for.
        try Task.checkCancellation()
        let fetchID = UUID()
        // The fetch stores its own result, so a token obtained for callers that
        // were cancelled meanwhile (pull to refresh) is not lost. It is stored only
        // if this fetch is still the current one: `removeAll()` or a newer fetch
        // for another credential make it stale.
        // The fetch also ends its own in-flight entry: a caller that stops waiting
        // (cancelled) must not let the next caller start a second login.
        let task = Task { () throws -> AccessToken in
            defer {
                if inFlight[serviceID]?.id == fetchID { inFlight[serviceID] = nil }
            }
            let token = try await fetch()
            if inFlight[serviceID]?.id == fetchID {
                entries[serviceID] = Entry(token: token, fingerprint: fingerprint)
            }
            return token
        }
        inFlight[serviceID] = (fingerprint, fetchID, task)
        return try await Self.wait(for: task).value
    }

    /// Waits for a shared fetch, but returns as soon as the caller is cancelled
    /// (background refresh expiring): the fetch itself goes on for the other
    /// callers and stores its token. Awaiting `task.value` directly would hold the
    /// caller until the login POST ends, up to 15 s.
    private static func wait(for task: Task<AccessToken, any Error>) async throws -> AccessToken {
        let waiter = Waiter()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard waiter.install(continuation) else { return }
                Task {
                    let result = await task.result
                    waiter.resume(with: result)
                }
            }
        } onCancel: {
            waiter.resume(with: .failure(CancellationError()))
        }
    }

    /// One caller's continuation, resumed exactly once: by the fetch's result or by
    /// the caller's cancellation, whichever comes first.
    private final class Waiter: Sendable {
        private let state = Mutex<(continuation: CheckedContinuation<AccessToken, any Error>?, finished: Bool)>((nil, false))

        /// False if the caller was already cancelled (the continuation is resumed).
        func install(_ continuation: CheckedContinuation<AccessToken, any Error>) -> Bool {
            let alreadyFinished = state.withLock { state -> Bool in
                if state.finished { return true }
                state.continuation = continuation
                return false
            }
            if alreadyFinished { continuation.resume(throwing: CancellationError()) }
            return !alreadyFinished
        }

        func resume(with result: Result<AccessToken, any Error>) {
            let continuation = state.withLock { state -> CheckedContinuation<AccessToken, any Error>? in
                defer { state.continuation = nil; state.finished = true }
                return state.continuation
            }
            continuation?.resume(with: result)
        }
    }

    /// Drops the token of one service after a 401 with it. With `token`, only if
    /// it is still the cached one: a newer token obtained meanwhile is kept.
    public func invalidate(_ serviceID: UUID, token: String? = nil) {
        guard let token else {
            entries[serviceID] = nil
            return
        }
        if entries[serviceID]?.token.value == token { entries[serviceID] = nil }
    }

    /// Drops every token (app sent to the background) and abandons fetches in flight.
    public func removeAll() {
        entries.removeAll()
        for (_, pending) in inFlight { pending.task.cancel() }
        inFlight.removeAll()
    }

    /// For tests.
    public var cachedCount: Int { entries.count }
}

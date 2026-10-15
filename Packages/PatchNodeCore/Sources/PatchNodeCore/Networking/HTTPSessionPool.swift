import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization

/// A URLSession that can be swapped for a new one, with its own connection pool.
/// Used when a connection turns out to be unusable: a 421 Misdirected Request
/// (an HTTP/2 connection coalesced with another host of the same reverse proxy),
/// or a connection that died with the network path (VPN toggled).
public final class RenewableSession: Sendable {
    private struct State {
        var session: URLSession
        /// Invalidated for good (service removed): no new task may start.
        var closed = false
        /// Requests started and not finished yet, per session: the current one,
        /// and sessions replaced after a 421 whose requests are still running.
        var inFlight: [ObjectIdentifier: (session: URLSession, count: Int)] = [:]

        func count(_ session: URLSession) -> Int {
            inFlight[ObjectIdentifier(session)]?.count ?? 0
        }
        /// The network path changed while idle: the next request starts on a
        /// new session (nothing to cancel, no session built for nothing).
        var stale = false
    }

    private let state: Mutex<State>
    private let make: @Sendable () -> URLSession

    public init(make: @escaping @Sendable () -> URLSession) {
        self.make = make
        self.state = Mutex(State(session: make()))
    }

    public var current: URLSession {
        state.withLock { $0.session }
    }

    /// Creates and starts a task on the current session under the lock, so no
    /// other request can invalidate that session in between (URLSession raises
    /// an exception for a task created on an invalidated session). Nil once
    /// closed. Returns the session used, for `renew(replacing:)`.
    /// `onLaunch` runs before `resume()`, so the caller knows the task and its
    /// session even when the completion comes back at once (session reset).
    /// Both run under the lock: `onLaunch` must never call back into this
    /// object (the Mutex isn't reentrant). The completion handler takes the
    /// lock, which is safe because URLSession never calls it synchronously
    /// from `resume()` (delegate queue: its own serial queue).
    func startTask(
        _ request: URLRequest, delegate: (any URLSessionTaskDelegate & Sendable)?,
        onLaunch: (URLSessionDataTask, URLSession) -> Void = { _, _ in },
        completion: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void
    ) -> (task: URLSessionDataTask, session: URLSession)? {
        let (launched, retired) = state.withLock { state -> ((task: URLSessionDataTask, session: URLSession)?, URLSession?) in
            guard !state.closed else { return (nil, nil) }
            var retired: URLSession?
            if state.stale {
                retired = state.session
                state.session = make()
                state.stale = false
            }
            let session = state.session
            let key = ObjectIdentifier(session)
            let task = session.dataTask(with: request) { [self] data, response, error in
                self.state.withLock { state in
                    guard let entry = state.inFlight[key] else { return }
                    state.inFlight[key] = entry.count > 1 ? (entry.session, entry.count - 1) : nil
                }
                completion(data, response, error)
            }
            #if !canImport(FoundationNetworking)
            task.delegate = delegate
            #endif
            state.inFlight[key] = (session, state.count(session) + 1)
            onLaunch(task, state.session)
            task.resume()
            return ((task, state.session), retired)
        }
        retired?.invalidateAndCancel()
        return launched
    }

    /// Replaces `used` with a new session, unless a concurrent request already
    /// did. Requests still running on `used` finish on it.
    public func renew(replacing used: URLSession) {
        let retired = state.withLock { state -> URLSession? in
            guard !state.closed, state.session === used else { return nil }
            state.session = make()
            return used
        }
        retired?.finishTasksAndInvalidate()
    }

    /// Drops the current session and cancels its requests (network path changed:
    /// its connections are dead or go through the old route).
    public func reset() {
        let retired = state.withLock { state -> URLSession? in
            guard !state.closed else { return nil }
            let old = state.session
            state.session = make()
            return old
        }
        retired?.invalidateAndCancel()
    }

    /// Network path changed: a session with requests in flight is reset now
    /// (they are cancelled, a GET is sent again on the new one); an idle one is
    /// only marked, and replaced by its next request.
    public func resetIfActive() {
        let retired = state.withLock { state -> [URLSession] in
            guard !state.closed else { return [] }
            // Sessions replaced after a 421 that still run requests: cancelled too
            // (their connections use the old route as well).
            var retired = state.inFlight.values.map(\.session).filter { $0 !== state.session }
            if state.count(state.session) > 0 {
                retired.append(state.session)
                state.session = make()
                state.stale = false
            } else {
                state.stale = true
            }
            return retired
        }
        for session in retired { session.invalidateAndCancel() }
    }

    var isStale: Bool {
        state.withLock { $0.stale }
    }

    /// Ends the session for good (service removed).
    func invalidate() {
        let retired = state.withLock { state -> URLSession? in
            guard !state.closed else { return nil }
            state.closed = true
            return state.session
        }
        retired?.finishTasksAndInvalidate()
    }

    var isClosed: Bool {
        state.withLock { $0.closed }
    }
}

/// One session per service: separate connection pools, so two hosts behind the
/// same reverse proxy (same IP, same wildcard certificate) never share an HTTP/2
/// connection, and one service's dead connection can't stall another.
public final class HTTPSessionPool: Sendable {
    public static let shared = HTTPSessionPool()

    private let sessions = Mutex<[UUID: RenewableSession]>([:])
    private let make: @Sendable () -> URLSession
    private let log: RequestLog?

    public init(log: RequestLog? = .shared, make: @escaping @Sendable () -> URLSession = HTTPClient.makeSession) {
        self.log = log
        self.make = make
    }

    public func session(for serviceID: UUID) -> RenewableSession {
        sessions.withLock { sessions in
            if let existing = sessions[serviceID] { return existing }
            let created = RenewableSession(make: make)
            sessions[serviceID] = created
            return created
        }
    }

    /// Client for one service: its own session, requests logged under its name.
    /// `baseURL`: the service's configured URL, whose path is left out of the log.
    public func client(for serviceID: UUID, name: String, baseURL: URL? = nil, maxAttempts: Int = 2) -> HTTPClient {
        HTTPClient(
            sessions: session(for: serviceID), maxAttempts: maxAttempts,
            label: RequestLog.Label(serviceID: serviceID, serviceName: name, baseURL: baseURL), log: log
        )
    }

    /// Network path changed: sessions with requests in flight are replaced (their
    /// requests cancelled); idle ones are replaced by their next request.
    public func resetAll() {
        let all = sessions.withLock { Array($0.values) }
        for session in all { session.resetIfActive() }
        log?.append(.event(.sessionsReset), label: nil)
    }

    /// Drops the sessions of services no longer configured (or reconfigured: a
    /// new URL starts on a new session).
    public func remove(_ ids: some Sequence<UUID>) {
        let removed = sessions.withLock { sessions in
            ids.compactMap { sessions.removeValue(forKey: $0) }
        }
        for session in removed { session.invalidate() }
    }
}

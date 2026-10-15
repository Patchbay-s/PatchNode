import Foundation

/// Why a service's requests are paused.
public enum PauseReason: String, Sendable, Hashable {
    /// 401 or a 403 from the service itself: the token is wrong or lacks rights.
    /// Only an explicit pull to refresh resumes (repeated refusals can get the
    /// user's IP banned by CrowdSec / fail2ban).
    case tokenRejected
    /// 403 HTML page from the reverse proxy (VPN off, Access List, ban page):
    /// resumes on its own after a capped backoff, or at once on a pull to refresh
    /// or a network change.
    case proxyBlocked

    /// The pause a failure calls for; nil when the service may be asked again at
    /// the next refresh (timeout, 5xx, 421, bad JSON…).
    public init?(error: any Error) {
        switch error {
        case ServiceProviderError.unauthorized, ServiceProviderError.forbidden: self = .tokenRejected
        case ServiceProviderError.blockedByProxy: self = .proxyBlocked
        default: return nil
        }
    }
}

/// Paused services and when each may be asked again. Pure value, driven by the
/// store with an explicit `now`, so the backoff is testable without waiting.
public struct ServicePauses: Sendable, Hashable {
    public struct Pause: Sendable, Hashable {
        public let reason: PauseReason
        /// Nil: until a pull to refresh.
        public let resumeAt: Date?
        /// Refusals in a row by the proxy (1 for the first).
        public let strikes: Int
    }

    /// Wait before asking again after the 1st, 2nd, 3rd… proxy refusal in a row.
    public static let proxyBackoff: [TimeInterval] = [30, 60, 120]

    public private(set) var pauses: [UUID: Pause] = [:]
    /// Proxy refusals since the service last answered: a timeout between two
    /// refusals doesn't bring the backoff back to 30 s.
    private var proxyStrikes: [UUID: Int] = [:]

    public init() {}

    public func pause(for id: UUID) -> Pause? {
        pauses[id]
    }

    /// True while no request may go to `id`.
    public func isPaused(_ id: UUID, at now: Date) -> Bool {
        guard let pause = pauses[id] else { return false }
        guard let resumeAt = pause.resumeAt else { return true }
        return now < resumeAt
    }

    /// The request about to go to `id` is the first after an automatic pause.
    public func isResumeProbe(_ id: UUID, at now: Date) -> Bool {
        guard let pause = pauses[id], let resumeAt = pause.resumeAt else { return false }
        return now >= resumeAt
    }

    /// Earliest automatic resume, to schedule a refresh then.
    public var nextResume: Date? {
        pauses.values.compactMap(\.resumeAt).min()
    }

    /// The service answered: any pause ends. Returns true if one did.
    @discardableResult
    public mutating func recordSuccess(_ id: UUID) -> Bool {
        proxyStrikes[id] = nil
        return pauses.removeValue(forKey: id) != nil
    }

    /// The service failed. A refusal pauses it (the proxy's with a growing
    /// delay); any other failure ends an automatic pause, since that request was
    /// not refused. Returns the new pause, if any.
    @discardableResult
    public mutating func recordFailure(_ id: UUID, error: any Error, at now: Date) -> Pause? {
        recordFailure(id, reason: PauseReason(error: error), at: now)
    }

    /// Same, with the failure already classified (nil: not a refusal).
    @discardableResult
    public mutating func recordFailure(_ id: UUID, reason: PauseReason?, at now: Date) -> Pause? {
        guard let reason else {
            if pauses[id]?.resumeAt != nil { pauses[id] = nil }
            return nil
        }
        let pause: Pause
        switch reason {
        case .tokenRejected:
            pause = Pause(reason: .tokenRejected, resumeAt: nil, strikes: (pauses[id]?.strikes ?? 0) + 1)
        case .proxyBlocked:
            let strikes = (proxyStrikes[id] ?? 0) + 1
            proxyStrikes[id] = strikes
            let delay = Self.proxyBackoff[min(strikes, Self.proxyBackoff.count) - 1]
            pause = Pause(reason: .proxyBlocked, resumeAt: now.addingTimeInterval(delay), strikes: strikes)
        }
        pauses[id] = pause
        return pause
    }

    /// Ends the pauses matching `reasons`; returns the services resumed.
    @discardableResult
    public mutating func resume(reasons: Set<PauseReason>) -> [UUID] {
        let resumed = pauses.filter { reasons.contains($0.value.reason) }.map(\.key)
        for id in resumed { pauses[id] = nil }
        return resumed
    }

    /// Forgets services no longer configured.
    public mutating func keep(only ids: Set<UUID>) {
        pauses = pauses.filter { ids.contains($0.key) }
        proxyStrikes = proxyStrikes.filter { ids.contains($0.key) }
    }
}

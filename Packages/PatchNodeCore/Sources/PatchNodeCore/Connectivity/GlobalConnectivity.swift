public enum GlobalConnectivity: Sendable, Equatable {
    case unknown
    case allUnreachable
    case partiallyReachable
}

/// If every configured service reports `.unreachable`, callers should show a single
/// "private network / VPN unreachable" banner instead of one error per service card.
public func aggregateConnectivity(from statuses: [HealthStatus]) -> GlobalConnectivity {
    guard !statuses.isEmpty else { return .unknown }
    let allUnreachable = statuses.allSatisfy {
        if case .unreachable = $0 { return true }
        return false
    }
    return allUnreachable ? .allUnreachable : .partiallyReachable
}

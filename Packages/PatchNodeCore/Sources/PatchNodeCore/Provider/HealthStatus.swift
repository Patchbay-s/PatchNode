public enum HealthStatus: Sendable {
    case ok
    case degraded(String)
    case unreachable(any Error & Sendable)
    case unauthorized
}

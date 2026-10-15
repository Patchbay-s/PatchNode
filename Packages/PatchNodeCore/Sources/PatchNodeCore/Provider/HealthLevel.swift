/// Traffic-light level of a dashboard card.
public enum HealthLevel: Int, Sendable, Comparable, CaseIterable {
    case ok
    case warning
    case critical

    public static func < (lhs: HealthLevel, rhs: HealthLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

import Foundation

/// How a PromQL favorite's values are displayed.
public enum PromQLUnit: String, Sendable, Hashable, CaseIterable, Codable {
    case none
    /// Values already in 0…100.
    case percent
    case bytes
    case bytesPerSecond
    case seconds
}

#if canImport(SwiftData)
import SwiftData

/// A saved PromQL query charted in the Observability tab. No secret: the
/// Prometheus credential stays in the Keychain under `serviceID`.
///
/// CloudKit-compatible (schema V2): default values, no unique attribute.
@Model
public final class PromQLFavorite {
    public var id: UUID = UUID()
    public var name: String = ""
    public var query: String = ""
    public var unitRawValue: String = PromQLUnit.none.rawValue
    /// Chart range in minutes (60 = last hour).
    public var rangeMinutes: Int = 60
    /// The Prometheus `ServiceConfig` to query.
    public var serviceID: UUID = UUID()
    public var createdAt: Date = Date.distantPast

    public var unit: PromQLUnit {
        get { PromQLUnit(rawValue: unitRawValue) ?? .none }
        set { unitRawValue = newValue.rawValue }
    }

    public init(id: UUID = UUID(), name: String, query: String, unit: PromQLUnit, rangeMinutes: Int, serviceID: UUID, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.query = query
        self.unitRawValue = unit.rawValue
        self.rangeMinutes = rangeMinutes
        self.serviceID = serviceID
        self.createdAt = createdAt
    }
}
#endif

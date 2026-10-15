#if canImport(SwiftData)
import Foundation
import SwiftData

/// A Home Assistant entity chosen for display (sensor, light…) or for one-tap
/// activation (scene, script). No secret: the token stays in the Keychain under
/// `serviceID`.
///
/// CloudKit-compatible (schema V2): default values, no unique attribute.
@Model
public final class HomeAssistantPin {
    public var id: UUID = UUID()
    /// The Home Assistant `ServiceConfig`.
    public var serviceID: UUID = UUID()
    /// `domain.object_id`.
    public var entityID: String = ""
    public var sortOrder: Int = 0

    public init(id: UUID = UUID(), serviceID: UUID, entityID: String, sortOrder: Int) {
        self.id = id
        self.serviceID = serviceID
        self.entityID = entityID
        self.sortOrder = sortOrder
    }
}
#endif

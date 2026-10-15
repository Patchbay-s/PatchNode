#if canImport(SwiftData)
import Foundation
import SwiftData

/// Non-secret service configuration. The API token lives only in the Keychain,
/// keyed by `id` — never add a secret field here (the store may sync to iCloud).
///
/// CloudKit-compatible (schema V2): default values, no unique attribute. Two
/// records with the same `id` can meet after a sync; `CloudHousekeeping` keeps one.
@Model
public final class ServiceConfig {
    public var id: UUID = UUID()
    public var kindRawValue: String = ServiceKind.proxmoxVE.rawValue
    public var name: String = ""
    public var urlString: String = ""

    public var kind: ServiceKind {
        get { ServiceKind(rawValue: kindRawValue) ?? .proxmoxVE }
        set { kindRawValue = newValue.rawValue }
    }

    public var url: URL? { URL(string: urlString) }

    public init(id: UUID = UUID(), kind: ServiceKind, name: String, urlString: String) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.name = name
        self.urlString = urlString
    }
}
#endif

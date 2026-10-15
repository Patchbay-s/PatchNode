import Foundation
import PatchNodeCore

/// Demo mode: a complete sample HomeLab answered on the device (no request leaves
/// the phone), for trying the app or App Review without servers. The user's own
/// services stay configured but hidden until the demo is left.
nonisolated enum DemoMode {
    /// UserDefaults key (a Bool, no secret).
    static let key = "demoMode"

    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    /// Fake credential of a demo service; nil for any other service (whose
    /// credential only ever comes from the Keychain).
    static func credential(for serviceID: UUID, url: URL) -> String? {
        guard DemoServer.isDemo(url) else { return nil }
        return DemoCatalog.service(id: serviceID)?.credential
    }
}

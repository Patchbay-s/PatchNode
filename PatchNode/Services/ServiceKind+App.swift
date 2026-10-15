import Foundation
import PatchNodeCore
import ObservabilityKit
import SecurityKit
import HomeServicesKit
import TailscaleKit

extension ServiceKind {
    /// Prometheus, Alertmanager and Glances accept an optional Basic credential;
    /// an Uptime Kuma status page is public. Everything else needs one.
    nonisolated var requiresCredential: Bool {
        switch self {
        case .prometheus, .alertmanager, .uptimeKuma, .glances: false
        default: true
        }
    }

    nonisolated var isObservability: Bool {
        ObservabilityProvider.supportedKinds.contains(self)
    }

    nonisolated var isSecurity: Bool {
        SecurityProvider.supportedKinds.contains(self)
    }

    nonisolated var isHomeService: Bool {
        HomeServicesProvider.supportedKinds.contains(self)
    }

    /// Services at a fixed public address: the user doesn't type a URL.
    nonisolated var fixedURL: URL? {
        self == .tailscale ? TailscaleClient.defaultBaseURL : nil
    }
}

import Foundation
import PatchNodeCore
import ProxmoxKit
import DockerKit

extension ServiceLoadState {
    /// User-facing explanation of a failed service, nil when there's nothing to say.
    var message: String? {
        switch self {
        case .loading, .loaded:
            nil
        case .unauthorized:
            String(localized: "The token was rejected. Requests are paused: fix the token, then pull to refresh.")
        case .forbidden:
            String(localized: "The token lacks the required rights (read-only role). Requests are paused: fix it, then pull to refresh.")
        case .unreachable:
            String(localized: "Unreachable. Check your VPN connection.")
        case .blockedByProxy:
            String(localized: "Access blocked by the reverse proxy (VPN off, Access List, or IP banned by CrowdSec/fail2ban).")
        case .insufficientRights:
            String(localized: "The token has no rights: untick Privilege Separation or add an API Token Permission PVEAuditor on /.")
        case .failed:
            String(localized: "The service returned an unexpected response.")
        }
    }
}

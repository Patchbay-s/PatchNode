public enum ServiceProviderError: Error, Sendable, Hashable {
    /// 401: token missing, expired or revoked.
    case unauthorized
    /// 403: token accepted but lacking the rights for this endpoint.
    case forbidden
    case unreachable
    case invalidResponse
    /// Any HTTP status other than 200, 401 and 403.
    case unexpectedStatus(Int)
    case decodingFailed
    /// 403 HTML page from a reverse proxy (VPN off, Access List), not the service:
    /// nothing is wrong with the token.
    case blockedByProxy
    /// The token is accepted but sees nothing (e.g. Proxmox Privilege Separation
    /// without a permission on /).
    case insufficientRights
}

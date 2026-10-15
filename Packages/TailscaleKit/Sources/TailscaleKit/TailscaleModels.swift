import Foundation
import PatchNodeCore

/// One device of the tailnet (`GET /tailnet/-/devices`).
public struct TailscaleDevice: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    /// Full MagicDNS name, for example a host name under the tailnet's DNS suffix.
    public let name: String
    public let hostname: String?
    public let os: String?
    public let addresses: [String]
    public let user: String?
    public let clientVersion: String?
    public let updateAvailable: Bool
    public let lastSeen: Date?
    /// Node key expiry; meaningless when `keyExpiryDisabled`.
    public let expires: Date?
    public let keyExpiryDisabled: Bool
    /// Present on recent API versions; otherwise `lastSeen` decides.
    public let connectedToControl: Bool?
    public let authorized: Bool

    public init(
        id: String, name: String, hostname: String? = nil, os: String? = nil, addresses: [String] = [],
        user: String? = nil, clientVersion: String? = nil, updateAvailable: Bool = false,
        lastSeen: Date? = nil, expires: Date? = nil, keyExpiryDisabled: Bool = false,
        connectedToControl: Bool? = nil, authorized: Bool = true
    ) {
        self.id = id; self.name = name; self.hostname = hostname; self.os = os; self.addresses = addresses
        self.user = user; self.clientVersion = clientVersion; self.updateAvailable = updateAvailable
        self.lastSeen = lastSeen; self.expires = expires; self.keyExpiryDisabled = keyExpiryDisabled
        self.connectedToControl = connectedToControl; self.authorized = authorized
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.lenientString(AnyCodingKey("nodeId")) ?? c.lenientString(AnyCodingKey("id")), !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        let hostname = c.lenientString(AnyCodingKey("hostname"))
        self.hostname = (hostname?.isEmpty ?? true) ? nil : hostname
        name = c.lenientString(AnyCodingKey("name")).flatMap { $0.isEmpty ? nil : $0 } ?? hostname ?? id
        os = c.lenientString(AnyCodingKey("os"))
        addresses = (try? c.decodeIfPresent([String].self, forKey: AnyCodingKey("addresses"))) ?? []
        user = c.lenientString(AnyCodingKey("user"))
        clientVersion = c.lenientString(AnyCodingKey("clientVersion"))
        updateAvailable = c.lenientBool(AnyCodingKey("updateAvailable")) ?? false
        lastSeen = c.lenientString(AnyCodingKey("lastSeen")).flatMap(Self.parseDate)
        expires = c.lenientString(AnyCodingKey("expires")).flatMap(Self.parseDate)
        keyExpiryDisabled = c.lenientBool(AnyCodingKey("keyExpiryDisabled")) ?? false
        connectedToControl = c.lenientBool(AnyCodingKey("connectedToControl"))
        authorized = c.lenientBool(AnyCodingKey("authorized")) ?? true
    }

    /// The API writes the zero date (`0001-01-01T00:00:00Z`) for "never".
    static func parseDate(_ text: String) -> Date? {
        guard let date = RFC3339Timestamp.parse(text), date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }

    /// A device not seen for this long without a control connection is offline.
    public static let onlineWindow: TimeInterval = 5 * 60

    public func isOnline(now: Date = .now) -> Bool {
        if let connectedToControl { return connectedToControl }
        guard let lastSeen else { return false }
        return now.timeIntervalSince(lastSeen) < Self.onlineWindow
    }

    /// Key expiry date, nil when expiry is disabled or unknown.
    public var keyExpiry: Date? {
        keyExpiryDisabled ? nil : expires
    }

    /// Short name: the first label of the MagicDNS name.
    public var shortName: String {
        hostname ?? String(name.split(separator: ".").first ?? Substring(name))
    }
}

/// A problem worth showing on a device.
public enum TailscaleDeviceIssue: Sendable, Hashable {
    /// Offline for more than 24 h.
    case offline(since: Date?)
    /// Key expires within 14 days.
    case keyExpiringSoon(Date)
    case keyExpired(Date)
    case notAuthorized
}

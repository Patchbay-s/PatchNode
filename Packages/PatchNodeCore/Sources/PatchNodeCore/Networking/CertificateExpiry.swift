import Foundation
import Synchronization

/// When a service's TLS certificate expires, read from the certificate the server
/// presented during a connection the app made anyway: no extra request.
public struct CertificateExpiry: Sendable, Hashable {
    public let notAfter: Date
    /// When the certificate was seen (handshake time).
    public let observedAt: Date

    /// Warning from this many days before expiry, critical from `criticalDays`.
    public static let warningDays = 14
    public static let criticalDays = 7

    public init(notAfter: Date, observedAt: Date) {
        self.notAfter = notAfter
        self.observedAt = observedAt
    }

    /// Whole days left (0 on the last day, negative once expired).
    public func daysRemaining(now: Date = .now) -> Int {
        Int((notAfter.timeIntervalSince(now) / 86_400).rounded(.down))
    }

    public func level(now: Date = .now) -> HealthLevel {
        let days = daysRemaining(now: now)
        if days < Self.criticalDays { return .critical }
        if days < Self.warningDays { return .warning }
        return .ok
    }

    /// Expires within `warningDays`.
    public func needsAttention(now: Date = .now) -> Bool {
        level(now: now) != .ok
    }
}

/// Certificates seen per origin (host and port), in memory only. Filled by the
/// session delegate after the system accepted the server's certificate; read by
/// the dashboard, Diagnostics and, later, notifications.
public final class CertificateRegistry: Sendable {
    public static let shared = CertificateRegistry()

    private struct Origin: Hashable {
        let host: String
        let port: Int
    }

    private let state = Mutex<[Origin: CertificateExpiry]>([:])

    public init() {}

    public func record(host: String, port: Int, notAfter: Date, at date: Date = .now) {
        let origin = Origin(host: host.lowercased(), port: port)
        state.withLock { $0[origin] = CertificateExpiry(notAfter: notAfter, observedAt: date) }
    }

    /// The certificate last seen for `url`'s origin. Demo services get a fixed,
    /// plausible expiry (one of them close to it) since the demo has no TLS.
    public func expiry(for url: URL, now: Date = .now) -> CertificateExpiry? {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return nil }
        if DemoServer.isDemo(url) { return Self.demoExpiry(host: host, now: now) }
        let origin = Origin(host: host, port: url.port ?? 443)
        return state.withLock { $0[origin] }
    }

    /// Items whose certificate expires within `CertificateExpiry.warningDays`,
    /// soonest first. Tailscale is skipped: its certificate is Tailscale's API, not
    /// the user's.
    public func attention<Item>(
        among items: [Item], now: Date = .now, kind: (Item) -> ServiceKind, url: (Item) -> URL
    ) -> [(item: Item, expiry: CertificateExpiry)] {
        items
            .compactMap { item -> (item: Item, expiry: CertificateExpiry)? in
                guard kind(item).hasOwnCertificate, let expiry = expiry(for: url(item), now: now),
                      expiry.needsAttention(now: now)
                else { return nil }
                return (item, expiry)
            }
            .sorted { $0.expiry.notAfter < $1.expiry.notAfter }
    }

    /// One condition per certificate expiring within 14 days; the level is part
    /// of the key, so the 7-day threshold is announced again.
    public func watchedConditions<Item>(
        among items: [Item], now: Date = .now, id: (Item) -> String, kind: (Item) -> ServiceKind, url: (Item) -> URL
    ) -> Set<WatchedCondition> {
        Set(attention(among: items, now: now, kind: kind, url: url).map { entry in
            WatchedCondition(
                kind: .certificateExpiring, scope: id(entry.item),
                key: "\(Int(entry.expiry.notAfter.timeIntervalSince1970))|\(entry.expiry.level(now: now).rawValue)"
            )
        })
    }

    /// Forgets `url`'s origin (service deleted).
    public func remove(for url: URL) {
        guard let host = url.host()?.lowercased() else { return }
        let origin = Origin(host: host, port: url.port ?? 443)
        state.withLock { _ = $0.removeValue(forKey: origin) }
    }

    public func removeAll() {
        state.withLock { $0.removeAll() }
    }

    /// Days left for each demo host; the Uptime Kuma status page ("status") is
    /// the one about to expire.
    static func demoExpiry(host: String, now: Date) -> CertificateExpiry {
        let label = host.split(separator: ".").first.map(String.init) ?? host
        let days: Double = switch label {
        case "status": 9.5
        case "grafana": 52.5
        default: 60.5 + Double(abs(label.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % 25)
        }
        return CertificateExpiry(notAfter: now.addingTimeInterval(days * 86_400), observedAt: now)
    }
}

/// Reads `notAfter` from a DER-encoded X.509 certificate (RFC 5280):
/// Certificate → tbsCertificate → [version], serialNumber, signature, issuer,
/// validity { notBefore, notAfter }. Nothing else is interpreted; nil on any
/// unexpected structure.
public enum X509Validity {
    public static func notAfter(der: Data) -> Date? {
        var reader = DERReader(bytes: [UInt8](der))
        guard let certificate = reader.read(tag: 0x30) else { return nil }
        var certReader = DERReader(bytes: certificate)
        guard let tbs = certReader.read(tag: 0x30) else { return nil }
        var tbsReader = DERReader(bytes: tbs)
        if tbsReader.peekTag == 0xA0 { _ = tbsReader.readAny() }  // [0] version
        guard tbsReader.read(tag: 0x02) != nil,                     // serialNumber
              tbsReader.read(tag: 0x30) != nil,                     // signature
              tbsReader.read(tag: 0x30) != nil,                     // issuer
              let validity = tbsReader.read(tag: 0x30)
        else { return nil }
        var validityReader = DERReader(bytes: validity)
        guard validityReader.readTime() != nil else { return nil }  // notBefore
        return validityReader.readTime()
    }
}

/// Minimal DER reader: definite lengths only, which DER requires.
struct DERReader {
    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    var peekTag: UInt8? { index < bytes.count ? bytes[index] : nil }

    /// Contents of the next element if its tag is `tag`.
    mutating func read(tag: UInt8) -> [UInt8]? {
        guard peekTag == tag else { return nil }
        return readAny()?.contents
    }

    mutating func readAny() -> (tag: UInt8, contents: [UInt8])? {
        guard index < bytes.count else { return nil }
        let tag = bytes[index]
        var cursor = index + 1
        guard cursor < bytes.count else { return nil }
        var length = Int(bytes[cursor])
        cursor += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard (1...4).contains(count), cursor + count <= bytes.count else { return nil }
            length = 0
            for byte in bytes[cursor..<(cursor + count)] { length = length << 8 | Int(byte) }
            cursor += count
        }
        guard length >= 0, cursor + length <= bytes.count else { return nil }
        index = cursor + length
        return (tag, Array(bytes[cursor..<(cursor + length)]))
    }

    /// UTCTime (YYMMDDHHMMSSZ, 1950–2049) or GeneralizedTime (YYYYMMDDHHMMSSZ).
    mutating func readTime() -> Date? {
        guard let (tag, contents) = readAny(), let text = String(bytes: contents, encoding: .ascii) else { return nil }
        let digits: String
        switch tag {
        case 0x17:
            guard text.count == 13, text.hasSuffix("Z"), let yy = Int(text.prefix(2)) else { return nil }
            digits = String(yy < 50 ? 2000 + yy : 1900 + yy) + text.dropFirst(2).dropLast()
        case 0x18:
            guard text.count == 15, text.hasSuffix("Z") else { return nil }
            digits = String(text.dropLast())
        default:
            return nil
        }
        guard digits.count == 14, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        func field(_ start: Int, _ length: Int) -> Int {
            let from = digits.index(digits.startIndex, offsetBy: start)
            return Int(digits[from..<digits.index(from, offsetBy: length)]) ?? -1
        }
        var components = DateComponents()
        components.year = field(0, 4)
        components.month = field(4, 2)
        components.day = field(6, 2)
        components.hour = field(8, 2)
        components.minute = field(10, 2)
        components.second = field(12, 2)
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else { return nil }
        calendar.timeZone = utc
        guard (1...12).contains(components.month ?? 0), (1...31).contains(components.day ?? 0),
              (0...23).contains(components.hour ?? -1), (0...59).contains(components.minute ?? -1),
              (0...60).contains(components.second ?? -1)
        else { return nil }
        return calendar.date(from: components)
    }
}

extension ServiceKind {
    /// False when the app talks to a third-party API (Tailscale) rather than to a
    /// server the user runs: its certificate isn't the user's to renew.
    public var hasOwnCertificate: Bool { self != .tailscale }
}

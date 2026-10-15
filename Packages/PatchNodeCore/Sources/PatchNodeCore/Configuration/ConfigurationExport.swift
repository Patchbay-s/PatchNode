import Foundation

/// PatchNode's configuration as a file, **without any token or password**:
/// services (type, name, URL), PromQL favorites, Home Assistant pins, tabs and
/// dashboard order. Versioned so a newer app can read older files and refuse
/// files it doesn't understand.
public struct ConfigurationExport: Sendable, Equatable, Codable {
    public static let format = "PatchNode-configuration"
    public static let currentVersion = 1
    /// Larger files are refused before decoding.
    public static let maxFileSize = 1_000_000
    public static let maxServices = 200
    public static let maxFavorites = 500
    public static let maxPins = 1_000

    public struct Service: Sendable, Equatable, Codable {
        public var id: UUID
        public var kind: String
        public var name: String
        public var url: String

        public init(id: UUID, kind: String, name: String, url: String) {
            self.id = id; self.kind = kind; self.name = name; self.url = url
        }
    }

    public struct Favorite: Sendable, Equatable, Codable {
        public var id: UUID
        public var name: String
        public var query: String
        public var unit: String
        public var rangeMinutes: Int
        public var serviceID: UUID
        public var createdAt: Date

        public init(id: UUID, name: String, query: String, unit: String, rangeMinutes: Int, serviceID: UUID, createdAt: Date) {
            self.id = id; self.name = name; self.query = query; self.unit = unit
            self.rangeMinutes = rangeMinutes; self.serviceID = serviceID; self.createdAt = createdAt
        }
    }

    public struct Pin: Sendable, Equatable, Codable {
        public var id: UUID
        public var serviceID: UUID
        public var entityID: String
        public var sortOrder: Int

        public init(id: UUID, serviceID: UUID, entityID: String, sortOrder: Int) {
            self.id = id; self.serviceID = serviceID; self.entityID = entityID; self.sortOrder = sortOrder
        }
    }

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var services: [Service]
    public var favorites: [Favorite]
    public var pins: [Pin]
    /// `TabSelection` encoding, nil if not exported.
    public var tabs: String?
    /// Dashboard card order (comma-separated), nil if not exported.
    public var dashboardOrder: String?

    public init(
        services: [Service], favorites: [Favorite] = [], pins: [Pin] = [],
        tabs: String? = nil, dashboardOrder: String? = nil, exportedAt: Date = .now
    ) {
        format = Self.format
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.services = services
        self.favorites = favorites
        self.pins = pins
        self.tabs = tabs
        self.dashboardOrder = dashboardOrder
    }

    public enum ReadError: Error, Sendable, Equatable {
        case tooLarge
        case notPatchNode
        /// Made by a newer PatchNode: update the app first.
        case newerVersion(Int)
        case unreadable
    }

    /// Compact, stable JSON (sorted keys, ISO 8601 dates).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws(ReadError) -> ConfigurationExport {
        guard data.count <= maxFileSize else { throw .tooLarge }
        struct Header: Decodable {
            let format: String?
            let version: Int?
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw .unreadable }
        guard header.format == format, let version = header.version, version >= 1 else { throw .notPatchNode }
        guard version <= currentVersion else { throw .newerVersion(version) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let export = try? decoder.decode(ConfigurationExport.self, from: data) else { throw .unreadable }
        return export
    }

    /// File name suggested when sharing.
    public static func fileName(at date: Date = .now) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        return "PatchNode-\(day).PatchNode.json"
    }
}

/// What importing a file would change, computed from plain values so it can be
/// previewed before anything is written.
public struct ConfigurationImportPlan: Sendable, Equatable {
    public enum Mode: Sendable, Hashable, CaseIterable {
        /// Keeps everything already configured, adds what's new.
        case merge
        /// Removes the current services (and their tokens), then adds the file's.
        case replace
    }

    public enum SkipReason: Sendable, Hashable {
        /// Same service already configured (same ID, or same type and address).
        case duplicate
        case invalidURL
        case unknownKind
        case emptyName
        /// Beyond `ConfigurationExport.maxServices`.
        case tooMany
        /// A demo service's ID or address: never imported as a real service.
        case reserved
    }

    /// Longest name kept; tabs and dashboard order longer than `maxSettingLength` are ignored.
    public static let maxNameLength = 100
    public static let maxSettingLength = 1_024
    /// Chart ranges kept between 5 minutes and 30 days.
    public static let rangeMinutes = 5...43_200

    public let mode: Mode
    public let servicesToAdd: [ConfigurationExport.Service]
    /// IDs of current services removed (replace only); their tokens go too.
    public let servicesToRemove: [UUID]
    public let skipped: [(name: String, reason: SkipReason)]
    public let favoritesToAdd: [ConfigurationExport.Favorite]
    public let pinsToAdd: [ConfigurationExport.Pin]
    public let tabs: String?
    public let dashboardOrder: String?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.mode == rhs.mode && lhs.servicesToAdd == rhs.servicesToAdd && lhs.servicesToRemove == rhs.servicesToRemove
            && lhs.skipped.map(\.name) == rhs.skipped.map(\.name) && lhs.skipped.map(\.reason) == rhs.skipped.map(\.reason)
            && lhs.favoritesToAdd == rhs.favoritesToAdd && lhs.pinsToAdd == rhs.pinsToAdd
            && lhs.tabs == rhs.tabs && lhs.dashboardOrder == rhs.dashboardOrder
    }

    /// `existing`: what is configured now (same shapes as the file).
    /// `fixedURL`: the address some kinds always use (Tailscale's API), whatever
    /// the file says.
    public init(
        file: ConfigurationExport, existing: ConfigurationExport, mode: Mode,
        fixedURL: (ServiceKind) -> URL? = { _ in nil }
    ) {
        self.mode = mode
        let current = mode == .replace ? [] : existing.services
        servicesToRemove = mode == .replace ? existing.services.map(\.id) : []

        var takenIDs = Set(current.map(\.id))
        var takenOrigins = Set(current.compactMap { Self.identity(kind: $0.kind, url: $0.url) })
        var added: [ConfigurationExport.Service] = []
        var skipped: [(name: String, reason: SkipReason)] = []
        for service in file.services {
            let name = String(service.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
            guard !name.isEmpty else { skipped.append((String(service.url.prefix(Self.maxNameLength)), .emptyName)); continue }
            guard let kind = ServiceKind(rawValue: service.kind) else { skipped.append((name, .unknownKind)); continue }
            guard case .success(let parsed) = validateServiceURL(fixedURL(kind)?.absoluteString ?? service.url) else {
                skipped.append((name, .invalidURL)); continue
            }
            let url = parsed
            guard !DemoCatalog.serviceIDs.contains(service.id), !DemoServer.isDemo(url) else {
                skipped.append((name, .reserved)); continue
            }
            let identity = Self.identity(kind: service.kind, url: url.absoluteString)
            guard !takenIDs.contains(service.id), identity.map({ !takenOrigins.contains($0) }) ?? true else {
                skipped.append((name, .duplicate)); continue
            }
            guard current.count + added.count < ConfigurationExport.maxServices else { skipped.append((name, .tooMany)); continue }
            takenIDs.insert(service.id)
            if let identity { takenOrigins.insert(identity) }
            added.append(ConfigurationExport.Service(id: service.id, kind: service.kind, name: name, url: url.absoluteString))
        }
        servicesToAdd = added
        self.skipped = skipped

        // Favorites and pins follow their service: kept only if it exists after
        // the import, and not already there.
        let addedIDs = Set(added.map(\.id))
        let kinds = Dictionary((current + added).map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let keptFavorites = mode == .replace ? [] : existing.favorites
        var favoriteKeys = Set(keptFavorites.map { "\($0.serviceID)|\($0.query)" })
        var favoriteIDs = Set(keptFavorites.map(\.id))
        favoritesToAdd = file.favorites.filter { favorite in
            guard addedIDs.contains(favorite.serviceID), kinds[favorite.serviceID] == ServiceKind.prometheus.rawValue,
                  !favorite.query.isEmpty, favorite.query.count <= 5_000, favoriteIDs.insert(favorite.id).inserted,
                  favoriteKeys.insert("\(favorite.serviceID)|\(favorite.query)").inserted
            else { return false }
            return true
        }
        .prefix(ConfigurationExport.maxFavorites)
        .map { favorite in
            var favorite = favorite
            favorite.name = String(favorite.name.prefix(Self.maxNameLength))
            favorite.unit = PromQLUnit(rawValue: favorite.unit)?.rawValue ?? PromQLUnit.none.rawValue
            favorite.rangeMinutes = min(max(favorite.rangeMinutes, Self.rangeMinutes.lowerBound), Self.rangeMinutes.upperBound)
            return favorite
        }
        let keptPins = mode == .replace ? [] : existing.pins
        var pinKeys = Set(keptPins.map { "\($0.serviceID)|\($0.entityID)" })
        var pinIDs = Set(keptPins.map(\.id))
        // Pins are renumbered after the service's current ones (in the file's
        // order): a huge sortOrder from a file could overflow later.
        var nextOrder = Dictionary(keptPins.map { ($0.serviceID, $0.sortOrder) }, uniquingKeysWith: max).mapValues { $0 + 1 }
        pinsToAdd = file.pins.sorted { $0.sortOrder < $1.sortOrder }.filter { pin in
            guard addedIDs.contains(pin.serviceID), kinds[pin.serviceID] == ServiceKind.homeAssistant.rawValue,
                  Self.isValidEntityID(pin.entityID), pinIDs.insert(pin.id).inserted,
                  pinKeys.insert("\(pin.serviceID)|\(pin.entityID)").inserted
            else { return false }
            return true
        }
        .prefix(ConfigurationExport.maxPins)
        .map { pin in
            var pin = pin
            pin.sortOrder = nextOrder[pin.serviceID, default: 0]
            nextOrder[pin.serviceID] = pin.sortOrder + 1
            return pin
        }

        // Tabs and order: the file's when replacing; when merging, only if nothing
        // was set yet.
        let fileTabs = file.tabs.flatMap { $0.count <= Self.maxSettingLength ? $0 : nil }
        let fileOrder = file.dashboardOrder.flatMap { $0.count <= Self.maxSettingLength ? $0 : nil }
        tabs = mode == .replace ? fileTabs : (existing.tabs?.isEmpty ?? true) ? fileTabs : nil
        dashboardOrder = mode == .replace ? fileOrder : (existing.dashboardOrder?.isEmpty ?? true) ? fileOrder : nil
    }

    /// Nothing would change.
    public var isEmpty: Bool {
        servicesToAdd.isEmpty && servicesToRemove.isEmpty && favoritesToAdd.isEmpty && pinsToAdd.isEmpty
    }

    /// Same type and same scheme, host, port and path (case-insensitive host).
    static func identity(kind: String, url: String) -> String? {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased() else { return nil }
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        return "\(kind)|\(components.scheme?.lowercased() ?? "")|\(host)|\(components.port ?? 443)|\(path)"
    }

    /// `domain.object_id`, lowercase letters, digits and underscores (same rule as
    /// Home Assistant's client).
    static func isValidEntityID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, id.count <= 255 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
        }
    }
}

/// A configuration small enough for a QR code (byte mode, medium correction).
public enum ConfigurationQRCode {
    public static let maxBytes = 2_300

    public static func fits(_ data: Data) -> Bool {
        data.count <= maxBytes
    }
}

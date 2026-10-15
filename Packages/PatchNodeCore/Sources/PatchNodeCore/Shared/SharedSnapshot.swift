import Foundation

/// Summary the app writes after each refresh and the widgets and App Intents
/// read. Never a secret, a token or a full URL: names, levels, figures and the
/// IDs an intent needs to find a VM or container again (the service is looked up
/// by its UUID in the app, where its URL and token live).
public struct SharedSnapshot: Codable, Sendable, Equatable {
    public static let formatVersion = 1
    /// Data older than this is shown as stale.
    public static let staleAge: TimeInterval = 60 * 60

    /// One dashboard family (Proxmox, Docker…) and its traffic light.
    public struct Family: Codable, Sendable, Equatable, Identifiable {
        public enum Level: String, Codable, Sendable, Equatable {
            case ok, warning, critical, unknown
        }

        /// Stable key, e.g. "proxmox".
        public let id: String
        public let title: String
        public let level: Level
        /// One short line, e.g. "12/14 VMs running".
        public let headline: String

        public init(id: String, title: String, level: Level, headline: String) {
            self.id = id; self.title = title; self.level = level; self.headline = headline
        }
    }

    /// CPU and memory of a Proxmox node, with its service (homonymous nodes).
    public struct NodeLoad: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        /// "Demo cluster · node-b".
        public let title: String
        public let isOnline: Bool
        /// 0…1.
        public let cpu: Double?
        /// 0…1.
        public let memory: Double?

        public init(id: String, title: String, isOnline: Bool, cpu: Double?, memory: Double?) {
            self.id = id; self.title = title; self.isOnline = isOnline; self.cpu = cpu; self.memory = memory
        }
    }

    /// A container that is stopped, exited with an error or unhealthy.
    public struct ContainerIssue: Codable, Sendable, Equatable, Identifiable {
        public enum Kind: String, Codable, Sendable, Equatable {
            case unhealthy, exitedWithError, stopped, restarting
        }

        public let id: String
        public let name: String
        public let host: String
        public let kind: Kind

        public init(id: String, name: String, host: String, kind: Kind) {
            self.id = id; self.name = name; self.host = host; self.kind = kind
        }
    }

    /// A VM/LXC an App Intent can restart. `serviceID` + node + type + VMID find it
    /// again; the URL and token stay in SwiftData and the Keychain.
    public struct GuestTarget: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let serviceID: UUID
        public let serviceName: String
        public let node: String
        /// "qemu" or "lxc".
        public let type: String
        public let vmid: Int
        public let name: String

        public init(id: String, serviceID: UUID, serviceName: String, node: String, type: String, vmid: Int, name: String) {
            self.id = id; self.serviceID = serviceID; self.serviceName = serviceName
            self.node = node; self.type = type; self.vmid = vmid; self.name = name
        }
    }

    /// A container an App Intent can restart.
    public struct ContainerTarget: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let serviceID: UUID
        public let serviceName: String
        /// Portainer environment ID; nil for a socket proxy.
        public let endpointID: Int?
        public let containerID: String
        public let name: String
        public let host: String

        public init(id: String, serviceID: UUID, serviceName: String, endpointID: Int?, containerID: String, name: String, host: String) {
            self.id = id; self.serviceID = serviceID; self.serviceName = serviceName
            self.endpointID = endpointID; self.containerID = containerID; self.name = name; self.host = host
        }
    }

    public var version: Int
    public var generatedAt: Date
    public var families: [Family]
    public var nodes: [NodeLoad]
    public var containerIssues: [ContainerIssue]
    public var guests: [GuestTarget]
    public var containers: [ContainerTarget]

    public init(
        generatedAt: Date, families: [Family] = [], nodes: [NodeLoad] = [], containerIssues: [ContainerIssue] = [],
        guests: [GuestTarget] = [], containers: [ContainerTarget] = []
    ) {
        version = Self.formatVersion
        self.generatedAt = generatedAt
        self.families = families
        self.nodes = nodes
        self.containerIssues = containerIssues
        self.guests = guests
        self.containers = containers
    }

    // MARK: Derived

    public func isStale(at date: Date = .now) -> Bool {
        date.timeIntervalSince(generatedAt) > Self.staleAge
    }

    /// Families whose data is known.
    public var knownFamilies: [Family] { families.filter { $0.level != .unknown } }
    public var okCount: Int { families.count { $0.level == .ok } }
    public var alertCount: Int { families.count { $0.level == .warning || $0.level == .critical } }

    /// Worst known level; `.unknown` without data.
    public var globalLevel: Family.Level {
        if families.contains(where: { $0.level == .critical }) { return .critical }
        if families.contains(where: { $0.level == .warning }) { return .warning }
        return knownFamilies.isEmpty ? .unknown : .ok
    }

    /// Same widget-visible content (families, node load, container issues).
    public func hasSameWidgetContent(as other: SharedSnapshot) -> Bool {
        families == other.families && nodes == other.nodes && containerIssues == other.containerIssues
    }

    /// Same content, whatever the time it was built: used to skip useless writes.
    public func hasSameContent(as other: SharedSnapshot) -> Bool {
        families == other.families && nodes == other.nodes && containerIssues == other.containerIssues
            && guests == other.guests && containers == other.containers
    }

    /// Caps what is stored: the widgets show a handful of rows and the intents
    /// search by name.
    public func bounded(nodes maxNodes: Int = 12, issues maxIssues: Int = 20, targets maxTargets: Int = 500) -> SharedSnapshot {
        var copy = self
        copy.nodes = Array(nodes.prefix(maxNodes))
        copy.containerIssues = Array(containerIssues.prefix(maxIssues))
        copy.guests = Array(guests.prefix(maxTargets))
        copy.containers = Array(containers.prefix(maxTargets))
        return copy
    }
}

/// Reads and writes the snapshot as a file in the App Group container shared by
/// the app and its widgets.
public struct SharedSnapshotStore: Sendable {
    /// The App Group to enable on the app and widget targets.
    public static let appGroupID = "group.fr.antxis.apple.labwatch"
    public static let fileName = "shared-snapshot.json"

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// nil when the App Group isn't enabled for this target (capability missing).
    public static func appGroup() -> SharedSnapshotStore? {
        #if canImport(Darwin)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        return SharedSnapshotStore(fileURL: container.appending(path: fileName))
        #else
        return nil
        #endif
    }

    public func read() -> SharedSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(SharedSnapshot.self, from: data),
              snapshot.version == SharedSnapshot.formatVersion
        else { return nil }
        return snapshot
    }

    /// Atomic write. Readable once the device has been unlocked after boot, so
    /// the widgets can render on the lock screen; it holds nothing secret.
    public func write(_ snapshot: SharedSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot.bounded())
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Rebuilt at every refresh: no need to keep host names in backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = fileURL
        try? url.setResourceValues(values)
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    public func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension SharedSnapshot.Family.Level {
    /// nil = not loaded yet.
    public init(_ level: HealthLevel?) {
        switch level {
        case .ok: self = .ok
        case .warning: self = .warning
        case .critical: self = .critical
        case nil: self = .unknown
        }
    }
}

/// What Settings › Diagnostics says about the widgets' cache.
public enum WidgetCacheStatus: Sendable, Equatable {
    /// The App Group isn't available to the app (capability or entitlements
    /// missing): the widgets can't be fed.
    case appGroupMissing
    /// Nothing written yet (app not refreshed since install, or demo mode).
    case empty
    case written(at: Date, families: Int, nodes: Int, guests: Int, containers: Int)
}

extension SharedSnapshotStore {
    public func status() -> WidgetCacheStatus {
        guard let snapshot = read() else { return .empty }
        return .written(
            at: snapshot.generatedAt, families: snapshot.families.count, nodes: snapshot.nodes.count,
            guests: snapshot.guests.count, containers: snapshot.containers.count
        )
    }

    /// The App Group's cache, or `.appGroupMissing`.
    public static func currentStatus() -> WidgetCacheStatus {
        appGroup()?.status() ?? .appGroupMissing
    }
}

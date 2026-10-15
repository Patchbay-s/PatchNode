import Foundation
import PatchNodeCore

/// Grafana dashboard from `/api/search?type=dash-db`.
public struct GrafanaDashboard: Sendable, Hashable, Identifiable, Decodable {
    public let uid: String
    public let title: String
    /// Path relative to the Grafana base URL ("/d/<uid>/<slug>").
    public let path: String
    public let folder: String?
    public let tags: [String]

    public var id: String { uid }

    public init(uid: String, title: String, path: String, folder: String? = nil, tags: [String] = []) {
        self.uid = uid; self.title = title; self.path = path; self.folder = folder; self.tags = tags
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let uid = c.lenientString(AnyCodingKey("uid")), let url = c.lenientString(AnyCodingKey("url")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing uid/url"))
        }
        self.uid = uid
        path = url
        title = c.lenientString(AnyCodingKey("title")) ?? uid
        folder = c.lenientString(AnyCodingKey("folderTitle"))
        tags = (try? c.decodeIfPresent([String].self, forKey: AnyCodingKey("tags"))) ?? []
    }

    /// Absolute HTTPS URL of the dashboard on `base`, or nil if the path would
    /// leave the Grafana host (only a same-host relative path is accepted).
    public func url(on base: URL) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        // A Grafana served under a sub-path already returns it in `url`.
        components.path = path.hasPrefix(basePath + "/") || basePath.isEmpty ? path : basePath + path
        components.query = nil
        components.fragment = nil
        guard let url = components.url, url.scheme == "https", url.host == base.host else { return nil }
        return url
    }
}

/// An Uptime Kuma status page with its monitors' latest state.
public struct UptimeKumaPage: Sendable, Hashable {
    public struct Monitor: Sendable, Hashable, Identifiable {
        public enum Status: Int, Sendable, Hashable {
            case down = 0, up = 1, pending = 2, maintenance = 3
        }

        public let id: Int
        public let name: String
        public let group: String?
        public let status: Status?
        public let lastMessage: String?
        public let lastPing: Double?
        public let lastBeat: Date?
        /// 0…1 over the last 24 h.
        public let uptime24h: Double?
        /// Oldest first.
        public let recentStatuses: [Status]

        public init(
            id: Int, name: String, group: String? = nil, status: Status?, lastMessage: String? = nil,
            lastPing: Double? = nil, lastBeat: Date? = nil, uptime24h: Double? = nil, recentStatuses: [Status] = []
        ) {
            self.id = id; self.name = name; self.group = group; self.status = status
            self.lastMessage = lastMessage; self.lastPing = lastPing; self.lastBeat = lastBeat
            self.uptime24h = uptime24h; self.recentStatuses = recentStatuses
        }
    }

    public let slug: String
    public let title: String
    public let monitors: [Monitor]

    public init(slug: String, title: String, monitors: [Monitor]) {
        self.slug = slug
        self.title = title
        self.monitors = monitors
    }

    public var monitorsDown: [Monitor] { monitors.filter { $0.status == .down } }
}

/// Where an Uptime Kuma status page lives, from the URL the user entered
/// (`https://kuma.example/status/<slug>`).
public struct UptimeKumaLocation: Sendable, Hashable {
    public let baseURL: URL
    public let slug: String

    public init?(statusPageURL url: URL) {
        // Percent-encoded path: an encoded "/" (%2F) must not split the slug.
        let parts = url.path(percentEncoded: true).split(separator: "/").map(String.init)
        guard let index = parts.lastIndex(of: "status"), index + 1 < parts.count,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let slug = parts[index + 1]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !slug.isEmpty, slug.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else { return nil }
        // `parts` are still percent-encoded: assign them as such (no double encoding).
        components.percentEncodedPath = parts[..<index].isEmpty ? "" : "/" + parts[..<index].joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let base = components.url else { return nil }
        self.baseURL = base
        self.slug = slug
    }
}

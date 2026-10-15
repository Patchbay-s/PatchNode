import Foundation
import PatchNodeCore

/// Read-only Proxmox Backup Server client (`<base>/api2/json/...`), with an API
/// token having the `Audit` role.
public struct PBSClient: Sendable {
    private let baseURL: URL
    private let apiTokenValue: String
    private let httpClient: any HTTPClientProtocol

    /// `apiTokenValue` is what follows `PBSAPIToken=`: `<user>@<realm>!<tokenid>:<secret>`.
    public init(baseURL: URL, apiTokenValue: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.baseURL = baseURL
        self.apiTokenValue = apiTokenValue
        self.httpClient = httpClient
    }

    /// `/version` accepts any valid token, `/admin/datastore` also checks the rights,
    /// so the connection test uses the latter.
    public func checkConnection() async throws {
        _ = try await datastoreEntries()
    }

    func datastoreEntries() async throws -> [PBSDatastoreEntry] {
        try await list(["admin", "datastore"])
    }

    func datastoreStatus(_ store: String) async throws -> PBSDatastoreStatus {
        let envelope: ProxmoxEnvelope<PBSDatastoreStatus> = try await fetch(["admin", "datastore", try Self.storeSegment(store), "status"])
        guard let status = envelope.data else { throw ServiceProviderError.invalidResponse }
        return status
    }

    public func groups(in store: String) async throws -> [PBSBackupGroup] {
        try await list(["admin", "datastore", try Self.storeSegment(store), "groups"])
    }

    /// Most recent tasks (backups, verifications, garbage collection, prune, sync).
    public func tasks(limit: Int = 50) async throws -> [ProxmoxTask] {
        let entries: [PBSTaskEntry] = try await list(
            ["nodes", "localhost", "tasks"],
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return entries.map(\.task)
    }

    /// Datastores with their space and backup groups. The list validates the token;
    /// a store whose details are refused (per-store permissions, 403) is kept
    /// without them. Sequential, and a 401 stops everything: a revoked token costs
    /// one request, never a burst.
    public func datastores() async throws -> [PBSDatastore] {
        var result: [PBSDatastore] = []
        for entry in try await datastoreEntries() {
            let status = try await Self.optional { try await datastoreStatus(entry.name) }
            let groups = try await Self.optional { try await self.groups(in: entry.name) } ?? []
            result.append(PBSDatastore(
                name: entry.name, comment: entry.comment,
                total: status?.total, used: status?.used, available: status?.available, groups: groups
            ))
        }
        return result
    }

    /// Secondary data: nil on failure, except cancellation and 401 which stop the refresh.
    static func optional<T: Sendable>(_ operation: () async throws -> T) async throws -> T? {
        do {
            return try await operation()
        } catch let error as CancellationError {
            throw error
        } catch ServiceProviderError.unauthorized {
            throw ServiceProviderError.unauthorized
        } catch {
            return nil
        }
    }

    // MARK: - Plumbing

    /// Datastore names come from the server; refuse anything that could alter the path.
    static func storeSegment(_ store: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !store.isEmpty, store != ".", store != "..",
              store.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII })
        else { throw ServiceProviderError.invalidResponse }
        return store
    }

    private var authHeaders: [String: String] {
        ["Authorization": "PBSAPIToken=\(apiTokenValue)"]
    }

    private func url(_ segments: [String], query: [URLQueryItem]) -> URL {
        var url = baseURL.appending(path: "api2/json")
        for segment in segments {
            url = url.appending(component: segment)
        }
        if !query.isEmpty {
            url = url.appending(queryItems: query)
        }
        return url
    }

    private func list<T: Decodable>(_ segments: [String], query: [URLQueryItem] = []) async throws -> [T] {
        let envelope: ProxmoxEnvelope<LossyArray<T>> = try await fetch(segments, query: query)
        return envelope.data?.elements ?? []
    }

    private func fetch<T: Decodable>(_ segments: [String], query: [URLQueryItem] = []) async throws -> T {
        try await httpClient.fetchJSON(HTTPRequestSpec(method: .get, url: url(segments, query: query), headers: authHeaders))
    }
}

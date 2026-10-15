import Foundation
import PatchNodeCore

/// Read-only Proxmox VE API client (`<base>/api2/json/...`). Handles the
/// `{"data": ...}` envelope once and maps transport errors to `ServiceProviderError`.
public struct ProxmoxClient: Sendable {
    private let baseURL: URL
    let apiTokenValue: String
    private let httpClient: any HTTPClientProtocol

    /// `apiTokenValue` is what follows `PVEAPIToken=`: `<user>@<realm>!<tokenid>=<secret>`.
    public init(baseURL: URL, apiTokenValue: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.baseURL = baseURL
        self.apiTokenValue = apiTokenValue
        self.httpClient = httpClient
    }

    // MARK: - Endpoints

    public func version() async throws -> String {
        struct Version: Decodable { let version: String }
        let payload: Version = try await object(["version"])
        return payload.version
    }

    public func clusterResources() async throws -> [ProxmoxResource] {
        try await list(["cluster", "resources"])
    }

    public func nodeStatus(node: String) async throws -> ProxmoxNodeStatus {
        try await object(["nodes", try Self.nodeSegment(node), "status"])
    }

    public func guestStatus(node: String, type: ProxmoxGuestType, vmid: Int) async throws -> ProxmoxGuestStatus {
        try await object(["nodes", try Self.nodeSegment(node), type.rawValue, String(vmid), "status", "current"])
    }

    public func guestRRD(
        node: String, type: ProxmoxGuestType, vmid: Int, timeframe: ProxmoxRRDTimeframe
    ) async throws -> [ProxmoxRRDPoint] {
        try await list(
            ["nodes", try Self.nodeSegment(node), type.rawValue, String(vmid), "rrddata"],
            query: Self.rrdQuery(timeframe)
        )
    }

    public func nodeRRD(node: String, timeframe: ProxmoxRRDTimeframe) async throws -> [ProxmoxRRDPoint] {
        try await list(["nodes", try Self.nodeSegment(node), "rrddata"], query: Self.rrdQuery(timeframe))
    }

    public func clusterTasks() async throws -> [ProxmoxTask] {
        try await list(["cluster", "tasks"])
    }

    // MARK: - Backups (read-only)

    /// `GET /cluster/backup`: scheduled vzdump jobs (Sys.Audit).
    public func backupJobs() async throws -> [ProxmoxBackupJob] {
        try await list(["cluster", "backup"])
    }

    /// `GET /cluster/backup-info/not-backed-up`: guests no enabled job covers.
    public func guestsNotBackedUp() async throws -> [ProxmoxUnprotectedGuest] {
        try await list(["cluster", "backup-info", "not-backed-up"])
    }

    /// `GET /nodes/{node}/storage/{storage}/content?content=backup` (Datastore.Audit).
    public func backups(node: String, storage: String) async throws -> [ProxmoxBackupFile] {
        let files: [ProxmoxBackupFile] = try await list(
            ["nodes", try Self.nodeSegment(node), "storage", try Self.storageSegment(storage), "content"],
            query: [URLQueryItem(name: "content", value: "backup")]
        )
        return files.map { $0.located(node: node, storage: storage) }
    }

    /// Physical disks of a node (`Sys.Audit`): Proxmox runs `smartctl -H -A` on
    /// every disk, which wakes disks in standby. Only through
    /// `DiskHealthAccess`, which asks `SMARTPolicy` first.
    func disks(node: String) async throws -> [ProxmoxDisk] {
        try await list(["nodes", try Self.nodeSegment(node), "disks", "list"])
    }

    /// ZFS pools of a node (`Sys.Audit`): `zpool list`. Read only with the
    /// disks, through `DiskHealthAccess`.
    func zfsPools(node: String) async throws -> [ProxmoxZFSPool] {
        try await list(["nodes", try Self.nodeSegment(node), "disks", "zfs"])
    }

    /// Storage IDs come from the server; same rule as node names.
    static func storageSegment(_ storage: String) throws -> String {
        try nodeSegment(storage)
    }

    // MARK: - Actions

    /// Starts a power action and returns its UPID. POST: never retried.
    public func perform(_ action: ProxmoxGuestAction, node: String, type: ProxmoxGuestType, vmid: Int) async throws -> String {
        let spec = HTTPRequestSpec(
            method: .post,
            url: url(["nodes", try Self.nodeSegment(node), type.rawValue, String(vmid), "status", action.rawValue]),
            headers: authHeaders
        )
        let envelope: ProxmoxEnvelope<String> = try await httpClient.fetchJSON(spec)
        guard let upid = envelope.data, Self.isValidUPID(upid) else { throw ProxmoxActionError.missingTaskID }
        return upid
    }

    public func taskStatus(node: String, upid: String) async throws -> ProxmoxTaskStatus {
        guard Self.isValidUPID(upid) else { throw ServiceProviderError.invalidResponse }
        return try await object(["nodes", try Self.nodeSegment(node), "tasks", upid, "status"])
    }

    /// Polls the task until it ends: every 1 s, then 2 s, then 3 s (spaced), up to
    /// `timeout` seconds overall. Only a network error or a 5xx is waited out; a
    /// refused (401/403) or unexpected answer ends the wait immediately.
    public func waitForTask(node: String, upid: String, timeout: TimeInterval = 120) async throws -> ProxmoxTaskStatus {
        guard Self.isValidUPID(upid) else { throw ServiceProviderError.invalidResponse }
        let deadline = Date.now.addingTimeInterval(timeout)
        var delay: Double = 1
        while Date.now < deadline {
            try await Task.sleep(for: .seconds(min(delay, max(deadline.timeIntervalSinceNow, 0))))
            do {
                let status = try await taskStatus(node: node, upid: upid)
                if !status.isRunning { return status }
            } catch ServiceProviderError.unreachable {
                // Network hiccup: keep waiting; the next poll is spaced further.
            } catch ServiceProviderError.unexpectedStatus(let code) where (500...599).contains(code) {
                // Server busy (not a refusal): keep waiting.
            } catch {
                // 401/403 and anything else stop at once: never repeat a refused request.
                throw error
            }
            delay = min(delay + 1, 3)
        }
        // Out of time: reported as such even if the last poll failed transiently.
        throw ProxmoxActionError.taskTimedOut(upid: upid)
    }

    /// `UPID:<node>:<pid>:<pstart>:<starttime>:<type>:<id>:<user>:` — checked before
    /// being used in a path.
    static func isValidUPID(_ upid: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ":_-.@!"))
        return upid.hasPrefix("UPID:") && upid.count < 256
            && upid.unicodeScalars.allSatisfy { allowed.contains($0) && $0.isASCII }
    }

    // MARK: - Plumbing

    /// Node names come from the server; refuse anything that could alter the path.
    static func nodeSegment(_ node: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !node.isEmpty, node != ".", node != "..",
              node.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII })
        else { throw ServiceProviderError.invalidResponse }
        return node
    }

    private static func rrdQuery(_ timeframe: ProxmoxRRDTimeframe) -> [URLQueryItem] {
        [URLQueryItem(name: "timeframe", value: timeframe.rawValue), URLQueryItem(name: "cf", value: "AVERAGE")]
    }

    func url(_ segments: [String], query: [URLQueryItem] = []) -> URL {
        var url = baseURL.appending(path: "api2/json")
        for segment in segments {
            url = url.appending(component: segment)
        }
        if !query.isEmpty {
            url = url.appending(queryItems: query)
        }
        return url
    }

    private func object<T: Decodable>(_ segments: [String], query: [URLQueryItem] = []) async throws -> T {
        let envelope: ProxmoxEnvelope<T> = try await fetch(segments, query: query)
        guard let data = envelope.data else { throw ServiceProviderError.invalidResponse }
        return data
    }

    /// `data: null` is treated as an empty list; malformed elements are dropped.
    private func list<T: Decodable>(_ segments: [String], query: [URLQueryItem] = []) async throws -> [T] {
        let envelope: ProxmoxEnvelope<LossyArray<T>> = try await fetch(segments, query: query)
        return envelope.data?.elements ?? []
    }

    private var authHeaders: [String: String] { authorizationHeaders }

    var authorizationHeaders: [String: String] {
        ["Authorization": "PVEAPIToken=\(apiTokenValue)"]
    }

    /// `data` of a GET, for this package's other files.
    func objectValue<T: Decodable>(_ segments: [String], query: [URLQueryItem] = []) async throws -> T {
        try await object(segments, query: query)
    }

    /// Form-encoded POST returning `data`. Never retried (POST).
    func postForm<T: Decodable>(_ segments: [String], form: [URLQueryItem]) async throws -> T {
        var components = URLComponents()
        components.queryItems = form
        var headers = authHeaders
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        let spec = HTTPRequestSpec(
            method: .post, url: url(segments), headers: headers,
            body: form.isEmpty ? nil : Data((components.percentEncodedQuery ?? "").utf8)
        )
        let envelope: ProxmoxEnvelope<T> = try await httpClient.fetchJSON(spec)
        guard let data = envelope.data else { throw ServiceProviderError.invalidResponse }
        return data
    }

    private func fetch<T: Decodable>(_ segments: [String], query: [URLQueryItem]) async throws -> T {
        try await httpClient.fetchJSON(HTTPRequestSpec(method: .get, url: url(segments, query: query), headers: authHeaders))
    }
}

import Foundation
import PatchNodeCore

/// How the Docker API is reached.
public enum DockerAPIFlavor: Sendable, Hashable {
    /// Portainer: `X-API-Key`, Docker API relayed under `/api/endpoints/{id}/docker`.
    case portainer
    /// Docker Engine behind a read-only socket proxy and an HTTPS reverse proxy
    /// doing Basic auth; the credential is `user:password`.
    case engine
}

/// Read-only Docker client, identical models for Portainer and a direct engine.
public struct DockerClient: Sendable {
    public static let defaultLogTail = 200
    public static let maxLogTail = 5000

    public let flavor: DockerAPIFlavor
    private let baseURL: URL
    let credential: String
    let httpClient: any HTTPClientProtocol
    /// Name shown for the single engine behind a socket proxy: the service's name,
    /// never its host (it ends up in the widgets and Siri, which carry no address).
    private let engineName: String

    public init(
        flavor: DockerAPIFlavor, baseURL: URL, credential: String,
        httpClient: any HTTPClientProtocol = HTTPClient(), engineName: String = "Docker"
    ) {
        self.flavor = flavor
        self.baseURL = baseURL
        self.credential = credential
        self.httpClient = httpClient
        self.engineName = engineName
    }

    // MARK: - Endpoints

    /// Connection and credential check: `/api/endpoints` (needs a valid key, unlike
    /// `/api/status`) or the engine's `/version`.
    public func checkConnection() async throws {
        switch flavor {
        case .portainer:
            _ = try await hosts()
        case .engine:
            _ = try await httpClient.fetchOK(spec(["version"]))
        }
    }

    public func hosts() async throws -> [DockerHost] {
        switch flavor {
        case .portainer:
            let endpoints: LossyArray<PortainerEndpoint> = try await httpClient.fetchJSON(spec(["api", "endpoints"]))
            return endpoints.elements.filter(\.isDocker).map(\.host)
        case .engine:
            return [.engine(name: engineName)]
        }
    }

    public func containers(on host: DockerHost) async throws -> [DockerContainer] {
        let list: LossyArray<DockerContainer> = try await httpClient.fetchJSON(
            spec(try enginePath(host) + ["containers", "json"], query: [URLQueryItem(name: "all", value: "true")])
        )
        return list.elements
    }

    public func details(on host: DockerHost, containerID: String) async throws -> DockerContainerDetails {
        try await httpClient.fetchJSON(spec(try enginePath(host) + ["containers", try Self.segment(containerID), "json"]))
    }

    /// One sample; Docker waits for a second reading so `cpuPercent` is available.
    public func stats(on host: DockerHost, containerID: String) async throws -> DockerStats {
        try await httpClient.fetchJSON(spec(
            try enginePath(host) + ["containers", try Self.segment(containerID), "stats"],
            query: [URLQueryItem(name: "stream", value: "false")]
        ))
    }

    /// Last `tail` lines of stdout and stderr, with timestamps. No streaming.
    public func logs(on host: DockerHost, containerID: String, tail: Int = defaultLogTail) async throws -> [DockerLogLine] {
        let clamped = min(max(tail, 1), Self.maxLogTail)
        let data = try await httpClient.fetchOK(spec(
            try enginePath(host) + ["containers", try Self.segment(containerID), "logs"],
            query: [
                URLQueryItem(name: "stdout", value: "true"),
                URLQueryItem(name: "stderr", value: "true"),
                URLQueryItem(name: "tail", value: String(clamped)),
                URLQueryItem(name: "timestamps", value: "true"),
            ]
        ))
        return DockerLogDecoder.decode(data, timestamps: true)
    }

    /// Portainer stacks; a direct engine has none (compose labels still group).
    public func stacks() async throws -> [PortainerStack] {
        guard flavor == .portainer else { return [] }
        let list: LossyArray<PortainerStack> = try await httpClient.fetchJSON(spec(["api", "stacks"]))
        return list.elements
    }

    // MARK: - Actions

    /// POST, never retried. 403 → `ServiceProviderError.forbidden` (actions disabled,
    /// e.g. socket proxy with POST=0); 404 → the container no longer exists.
    public func perform(_ action: DockerContainerAction, on host: DockerHost, containerID: String) async throws -> DockerActionOutcome {
        let spec = HTTPRequestSpec(
            method: .post,
            url: url(try enginePath(host) + ["containers", try Self.segment(containerID), action.rawValue]),
            headers: authHeaders
        )
        let (_, response) = try await httpClient.fetchResponse(spec)
        switch response.statusCode {
        case 200, 204: return .done
        case 304: return .alreadyInState
        default: throw ServiceProviderError.unexpectedStatus(response.statusCode)
        }
    }

    /// A stop/restart answers only once the container has stopped, which often
    /// exceeds the 10 s request timeout. After such a timeout the POST is NOT sent
    /// again: the container is read (GET) every few seconds until it reaches the
    /// expected state. Returns false if it didn't within `timeout`.
    public func confirm(_ action: DockerContainerAction, on host: DockerHost, containerID: String, since: Date, timeout: TimeInterval = 60) async throws -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        var delay: Double = 2
        while Date.now < deadline {
            try await Task.sleep(for: .seconds(delay))
            do {
                let details = try await details(on: host, containerID: containerID)
                switch action {
                case .stop:
                    if !details.isRunning { return true }
                case .start:
                    if details.isRunning { return true }
                case .restart:
                    if details.isRunning, let started = details.startedAt, started >= since.addingTimeInterval(-2) { return true }
                }
            } catch ServiceProviderError.unreachable {
                // Keep waiting: the daemon may be busy stopping the container.
            }
            delay = min(delay + 1, 5)
        }
        return false
    }

    // MARK: - Plumbing

    /// IDs and names come from the server; refuse anything that could alter the path.
    static func segment(_ value: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !value.isEmpty, value != ".", value != "..",
              value.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII })
        else { throw ServiceProviderError.invalidResponse }
        return value
    }

    private func enginePath(_ host: DockerHost) throws -> [String] {
        switch flavor {
        case .portainer:
            guard let endpointID = host.portainerEndpointID else { throw ServiceProviderError.invalidResponse }
            return ["api", "endpoints", String(endpointID), "docker"]
        case .engine:
            return []
        }
    }

    func url(_ segments: [String], query: [URLQueryItem] = []) -> URL {
        var url = baseURL
        for segment in segments {
            url = url.appending(component: segment)
        }
        return query.isEmpty ? url : url.appending(queryItems: query)
    }

    private func spec(_ segments: [String], query: [URLQueryItem] = []) -> HTTPRequestSpec {
        HTTPRequestSpec(method: .get, url: url(segments, query: query), headers: authHeaders)
    }

    private var authHeaders: [String: String] {
        switch flavor {
        case .portainer:
            return ["X-API-Key": credential]
        case .engine:
            guard !credential.isEmpty else { return [:] }
            return ["Authorization": "Basic \(Data(credential.utf8).base64EncodedString())"]
        }
    }
}

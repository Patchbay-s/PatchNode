import Foundation
import PatchNodeCore

/// `GET /api/stacks/{id}`: what an update must send back unchanged (its
/// environment) and whether Portainer manages the file itself (Git).
public struct PortainerStackDetails: Sendable, Hashable, Decodable {
    public struct EnvironmentVariable: Sendable, Hashable, Codable {
        public let name: String
        public let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    public let id: Int
    public let name: String
    public let endpointID: Int
    /// 1 swarm, 2 compose, 3 kubernetes.
    public let type: Int
    public let environment: [EnvironmentVariable]
    /// Deployed from a Git repository: the file lives there, not in Portainer.
    public let isGitBased: Bool

    public var isCompose: Bool { type == 2 }

    public init(id: Int, name: String, endpointID: Int, type: Int, environment: [EnvironmentVariable], isGitBased: Bool) {
        self.id = id; self.name = name; self.endpointID = endpointID; self.type = type
        self.environment = environment; self.isGitBased = isGitBased
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.lenientInt(AnyCodingKey("Id")), let name = c.lenientString(AnyCodingKey("Name")),
              let endpointID = c.lenientInt(AnyCodingKey("EndpointId"))
        else { throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing Id/Name/EndpointId")) }
        self.id = id
        self.name = name
        self.endpointID = endpointID
        type = c.lenientInt(AnyCodingKey("Type")) ?? 0
        // Present but unreadable: fail rather than send `env: []` back, which
        // would wipe the stack's variables.
        environment = try c.decodeIfPresent([EnvironmentVariable].self, forKey: AnyCodingKey("Env")) ?? []
        let git = try? c.decodeIfPresent(GitConfig.self, forKey: AnyCodingKey("GitConfig"))
        isGitBased = git != nil
    }

    private struct GitConfig: Decodable {}
}

extension DockerClient {
    /// `GET /api/stacks/{id}` (Portainer only).
    public func stackDetails(id: Int) async throws -> PortainerStackDetails {
        guard flavor == .portainer, id > 0 else { throw ServiceProviderError.invalidResponse }
        return try await httpClient.fetchJSON(HTTPRequestSpec(method: .get, url: url(["api", "stacks", String(id)]), headers: portainerHeaders))
    }

    /// `GET /api/stacks/{id}/file`: the compose file Portainer deployed.
    public func stackFile(id: Int) async throws -> String {
        struct File: Decodable { let StackFileContent: String }
        guard flavor == .portainer, id > 0 else { throw ServiceProviderError.invalidResponse }
        let file: File = try await httpClient.fetchJSON(HTTPRequestSpec(method: .get, url: url(["api", "stacks", String(id), "file"]), headers: portainerHeaders))
        return file.StackFileContent
    }

    /// `PUT /api/stacks/{id}?endpointId=`: redeploys with `content` (Portainer
    /// validates it), the environment sent back unchanged, `pullImage` for an
    /// update. Never retried; Portainer answers once the stack is redeployed.
    public func updateStack(_ stack: PortainerStackDetails, content: String, pullImage: Bool) async throws {
        guard flavor == .portainer, stack.isCompose, !stack.isGitBased else { throw ServiceProviderError.invalidResponse }
        struct Payload: Encodable {
            let stackFileContent: String
            let env: [PortainerStackDetails.EnvironmentVariable]
            let prune: Bool
            let pullImage: Bool
        }
        var headers = portainerHeaders
        headers["Content-Type"] = "application/json"
        let body = try JSONEncoder().encode(Payload(stackFileContent: content, env: stack.environment, prune: false, pullImage: pullImage))
        _ = try await httpClient.fetchOK(HTTPRequestSpec(
            method: .put,
            url: url(["api", "stacks", String(stack.id)], query: [URLQueryItem(name: "endpointId", value: String(stack.endpointID))]),
            headers: headers, body: body
        ))
    }

    /// `POST /api/stacks/{id}/start` or `/stop`. Never retried.
    public func setStack(_ stack: PortainerStackDetails, running: Bool) async throws {
        guard flavor == .portainer else { throw ServiceProviderError.invalidResponse }
        _ = try await httpClient.fetchOK(HTTPRequestSpec(
            method: .post,
            url: url(["api", "stacks", String(stack.id), running ? "start" : "stop"],
                     query: [URLQueryItem(name: "endpointId", value: String(stack.endpointID))]),
            headers: portainerHeaders
        ))
    }

    private var portainerHeaders: [String: String] { ["X-API-Key": credential] }
}

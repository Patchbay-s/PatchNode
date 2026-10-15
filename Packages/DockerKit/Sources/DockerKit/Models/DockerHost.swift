import Foundation
import PatchNodeCore

/// A Docker host: one Portainer environment (endpoint), or the single engine
/// behind a socket proxy.
public struct DockerHost: Sendable, Hashable, Identifiable {
    public enum Status: Sendable, Hashable { case up, down, unknown }

    /// "portainer-<endpoint id>" or "engine".
    public let id: String
    public let name: String
    public let status: Status
    public let portainerEndpointID: Int?

    public init(id: String, name: String, status: Status, portainerEndpointID: Int? = nil) {
        self.id = id; self.name = name; self.status = status; self.portainerEndpointID = portainerEndpointID
    }

    public static func engine(name: String) -> DockerHost {
        DockerHost(id: "engine", name: name, status: .up)
    }
}

/// `GET /api/endpoints` entry (Portainer).
struct PortainerEndpoint: Decodable {
    let id: Int
    let name: String
    let type: Int?
    let status: Int?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.lenientInt(AnyCodingKey("Id")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing Id"))
        }
        self.id = id
        name = c.lenientString(AnyCodingKey("Name")) ?? "#\(id)"
        type = c.lenientInt(AnyCodingKey("Type"))
        status = c.lenientInt(AnyCodingKey("Status"))
    }

    /// Docker (1), Docker agent (2), Edge agent (4). Azure and Kubernetes
    /// environments don't expose the Docker API.
    var isDocker: Bool {
        guard let type else { return true }
        return [1, 2, 4].contains(type)
    }

    var host: DockerHost {
        DockerHost(
            id: "portainer-\(id)",
            name: name,
            status: status == 1 ? .up : status == 2 ? .down : .unknown,
            portainerEndpointID: id
        )
    }
}

/// `GET /api/stacks` entry (Portainer).
public struct PortainerStack: Sendable, Hashable, Identifiable, Decodable {
    public let id: Int
    public let name: String
    public let endpointID: Int?
    public let isActive: Bool

    public init(id: Int, name: String, endpointID: Int?, isActive: Bool) {
        self.id = id; self.name = name; self.endpointID = endpointID; self.isActive = isActive
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.lenientInt(AnyCodingKey("Id")), let name = c.lenientString(AnyCodingKey("Name")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing Id/Name"))
        }
        self.id = id
        self.name = name
        endpointID = c.lenientInt(AnyCodingKey("EndpointId"))
        isActive = (c.lenientInt(AnyCodingKey("Status")) ?? 1) == 1
    }
}

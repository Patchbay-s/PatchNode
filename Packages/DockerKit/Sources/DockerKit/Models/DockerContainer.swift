import Foundation
import PatchNodeCore

/// One entry of `GET /containers/json?all=true`, identical for Portainer (relayed)
/// and a direct Docker Engine behind a socket proxy.
public struct DockerContainer: Sendable, Hashable, Identifiable, Decodable {
    public enum State: Sendable, Hashable {
        case running, paused, restarting, exited, created, dead, removing
        case other(String)

        init(_ raw: String?) {
            switch raw?.lowercased() {
            case "running": self = .running
            case "paused": self = .paused
            case "restarting": self = .restarting
            case "exited": self = .exited
            case "created": self = .created
            case "dead": self = .dead
            case "removing": self = .removing
            default: self = .other(raw ?? "")
            }
        }
    }

    /// From the healthcheck, parsed out of `Status` ("Up 2 hours (healthy)").
    public enum Health: Sendable, Hashable {
        case none, starting, healthy, unhealthy
    }

    public static let composeProjectLabel = "com.docker.compose.project"
    public static let composeServiceLabel = "com.docker.compose.service"

    public let id: String
    public let name: String
    public let image: String
    public let state: State
    /// Docker's human status, e.g. "Up 3 hours (healthy)" or "Exited (1) 2 days ago".
    public let status: String
    public let created: Date?
    public let ports: [DockerPort]
    public let labels: [String: String]

    public init(
        id: String, name: String, image: String = "", state: State, status: String = "",
        created: Date? = nil, ports: [DockerPort] = [], labels: [String: String] = [:]
    ) {
        self.id = id; self.name = name; self.image = image; self.state = state
        self.status = status; self.created = created; self.ports = ports; self.labels = labels
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.lenientString(AnyCodingKey("Id")), !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing Id"))
        }
        self.id = id
        let names = (try? c.decodeIfPresent([String].self, forKey: AnyCodingKey("Names"))) ?? []
        let firstName = names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
        name = (firstName?.isEmpty == false ? firstName : nil) ?? String(id.prefix(12))
        image = c.lenientString(AnyCodingKey("Image")) ?? ""
        state = State(c.lenientString(AnyCodingKey("State")))
        status = c.lenientString(AnyCodingKey("Status")) ?? ""
        created = c.lenientDouble(AnyCodingKey("Created")).map { Date(timeIntervalSince1970: $0) }
        ports = (try? c.decodeIfPresent(LossyArray<DockerPort>.self, forKey: AnyCodingKey("Ports")))?.elements ?? []
        labels = (try? c.decodeIfPresent([String: String].self, forKey: AnyCodingKey("Labels"))) ?? [:]
    }

    public var isRunning: Bool { state == .running }

    public var health: Health {
        let lowered = status.lowercased()
        if lowered.contains("(unhealthy)") { return .unhealthy }
        if lowered.contains("(healthy)") { return .healthy }
        if lowered.contains("(health: starting)") { return .starting }
        return .none
    }

    /// Exit code from "Exited (137) 3 hours ago".
    public var exitCode: Int? {
        guard state == .exited,
              let open = status.firstIndex(of: "("),
              let close = status[open...].firstIndex(of: ")")
        else { return nil }
        return Int(status[status.index(after: open)..<close])
    }

    public var exitedWithError: Bool {
        guard let exitCode else { return false }
        return exitCode != 0
    }

    public var composeProject: String? {
        guard let project = labels[Self.composeProjectLabel], !project.isEmpty else { return nil }
        return project
    }

    public var composeService: String? { labels[Self.composeServiceLabel] }
}

public struct DockerPort: Sendable, Hashable, Decodable {
    public let ip: String?
    public let privatePort: Int?
    public let publicPort: Int?
    public let type: String

    public init(ip: String? = nil, privatePort: Int?, publicPort: Int? = nil, type: String = "tcp") {
        self.ip = ip; self.privatePort = privatePort; self.publicPort = publicPort; self.type = type
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        ip = c.lenientString(AnyCodingKey("IP"))
        privatePort = c.lenientInt(AnyCodingKey("PrivatePort"))
        publicPort = c.lenientInt(AnyCodingKey("PublicPort"))
        type = c.lenientString(AnyCodingKey("Type")) ?? "tcp"
    }
}

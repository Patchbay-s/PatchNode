import Foundation
import PatchNodeCore

/// One Home Assistant entity (`GET /api/states`), reduced to what the app shows.
public struct HAEntity: Sendable, Hashable, Identifiable, Decodable {
    /// `domain.object_id`, e.g. `sensor.living_room_temperature`.
    public let id: String
    public let name: String
    public let state: String
    public let unit: String?
    public let deviceClass: String?
    public let lastChanged: Date?

    public init(id: String, name: String? = nil, state: String, unit: String? = nil, deviceClass: String? = nil, lastChanged: Date? = nil) {
        self.id = id; self.name = name ?? id; self.state = state; self.unit = unit
        self.deviceClass = deviceClass; self.lastChanged = lastChanged
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.lenientString(AnyCodingKey("entity_id")), HomeAssistantClient.isValidEntityID(id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing entity_id"))
        }
        self.id = id
        state = c.lenientString(AnyCodingKey("state")) ?? "unknown"
        let attributes = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("attributes"))
        let friendly = attributes?.lenientString(AnyCodingKey("friendly_name"))
        name = (friendly?.isEmpty ?? true) ? id : friendly!
        let unit = attributes?.lenientString(AnyCodingKey("unit_of_measurement"))
        self.unit = (unit?.isEmpty ?? true) ? nil : unit
        deviceClass = attributes?.lenientString(AnyCodingKey("device_class"))
        lastChanged = c.lenientString(AnyCodingKey("last_changed")).flatMap(RFC3339Timestamp.parse)
    }

    public var domain: String { String(id.prefix { $0 != "." }) }

    /// Scenes and scripts can be triggered from the app.
    public var isActivatable: Bool { domain == "scene" || domain == "script" }

    public var isUnavailable: Bool { state == "unavailable" || state == "unknown" }

    /// State with its unit, e.g. "21.5 °C".
    public var displayState: String {
        unit.map { "\(state) \($0)" } ?? state
    }
}

public enum HomeAssistantActionError: Error, Sendable, Equatable {
    /// Only scenes and scripts can be triggered.
    case notActivatable
}

/// Home Assistant REST API with a long-lived token of a non-admin user.
public struct HomeAssistantClient: Sendable {
    private let baseURL: URL
    private let token: String
    private let httpClient: any HTTPClientProtocol

    public init(baseURL: URL, token: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.baseURL = baseURL
        self.token = token
        self.httpClient = httpClient
    }

    /// `GET /api/` answers `{"message": "API running."}` to a valid token.
    public func checkConnection() async throws {
        struct Payload: Decodable { let message: String? }
        let _: Payload = try await httpClient.fetchJSON(spec(.get, ["api", ""]))
    }

    public func states() async throws -> [HAEntity] {
        let list: LossyArray<HAEntity> = try await httpClient.fetchJSON(spec(.get, ["api", "states"]))
        return list.elements
    }

    /// Activates a scene or runs a script (`scene.turn_on` / `script.turn_on`).
    /// POST: never retried. `script.turn_on` returns without waiting for the script.
    public func activate(entityID: String) async throws {
        guard Self.isValidEntityID(entityID) else { throw HomeAssistantActionError.notActivatable }
        let domain = String(entityID.prefix { $0 != "." })
        guard domain == "scene" || domain == "script" else { throw HomeAssistantActionError.notActivatable }
        let body = try JSONSerialization.data(withJSONObject: ["entity_id": entityID])
        var request = spec(.post, ["api", "services", domain, "turn_on"])
        request.headers["Content-Type"] = "application/json"
        request.body = body
        _ = try await httpClient.fetchOK(request)
    }

    /// `domain.object_id` made of lowercase letters, digits and underscores:
    /// safe to put in a path or a body.
    public static func isValidEntityID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, id.count <= 255 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
        }
    }

    private func spec(_ method: HTTPRequestSpec.Method, _ segments: [String]) -> HTTPRequestSpec {
        var url = baseURL
        for segment in segments {
            // `appending(component: "")` would drop the trailing slash `/api/` needs.
            url = segment.isEmpty ? url.appending(path: "/") : url.appending(component: segment)
        }
        return HTTPRequestSpec(method: method, url: url, headers: ["Authorization": "Bearer \(token)"])
    }
}

import Foundation
import PatchNodeCore

/// Demo tailnet: phones, laptops and servers, one offline for days, one key
/// about to expire, one waiting for approval. Answered on the device.
public struct TailscaleDemoResponder: DemoResponder {
    public init() {}

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        switch (request.method, request.segments) {
        case ("POST", ["api", "v2", "oauth", "token"]):
            return .json(object: ["access_token": "demo-access-token", "token_type": "Bearer", "expires_in": 3_600, "scope": "devices:core:read"])
        case ("GET", ["api", "v2", "tailnet", "-", "devices"]):
            let day = 86_400.0
            func device(_ id: Int, _ host: String, os: String, seen: Double, expires: Double?, connected: Bool,
                        authorized: Bool = true, version: String = "1.74.1") -> [String: Any] {
                [
                    "id": String(1_000_000_000_000_000 + id), "nodeId": "nDemo\(id)CNTRL", "hostname": host,
                    "name": "\(host).example.invalid", "addresses": ["192.0.2.\(id)", "2001:db8::\(id)"],
                    "os": os, "clientVersion": version, "authorized": authorized,
                    "lastSeen": now.addingTimeInterval(-seen).formatted(.iso8601),
                    "expires": expires.map { now.addingTimeInterval($0).formatted(.iso8601) } ?? "0001-01-01T00:00:00Z",
                    "keyExpiryDisabled": expires == nil, "connectedToControl": connected, "user": "demo@\(DemoServer.domain)",
                ]
            }
            return .json(object: ["devices": [
                device(1, "proxmox-node-a", os: "linux", seen: 5, expires: nil, connected: true),
                device(2, "proxmox-node-b", os: "linux", seen: 5, expires: nil, connected: true),
                device(3, "storage-node", os: "linux", seen: 12, expires: 120 * day, connected: true),
                device(4, "device-a", os: "iOS", seen: 30, expires: 150 * day, connected: true),
                device(5, "device-b", os: "macOS", seen: 3_600, expires: 9 * day, connected: false),
                device(6, "device-c", os: "linux", seen: 4 * day, expires: 60 * day, connected: false, version: "1.62.0"),
                device(7, "device-d", os: "linux", seen: 20, expires: 200 * day, connected: true),
                device(8, "device-e", os: "windows", seen: 60, expires: 180 * day, connected: true, authorized: false),
            ]])
        default:
            return .notFound
        }
    }
}

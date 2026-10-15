import Foundation
import PatchNodeCore
@testable import TailscaleKit

/// Realistic Tailscale API payloads. Every key, token and secret is obviously fake.
enum TailscaleFixtures {
    static let serviceID = UUID(uuidString: "7A1D0C3E-0000-4000-8000-00000000A001")!
    static let otherServiceID = UUID(uuidString: "7A1D0C3E-0000-4000-8000-00000000A002")!

    static let baseURL = URL(string: "https://tailscale-api.example.invalid")!

    static let clientID = "kFakeClient1CNTRL"
    static let clientSecret = "tskey-client-kFakeClient1CNTRL-fakeSecret1234"
    static let oauthCredential = "\(clientID):\(clientSecret)"
    static let apiKey = "tskey-api-kFakeKey1CNTRL-fake-token-1234"
    static let accessToken = "fake-ts-access-token-1234"

    static let tokenPath = "/api/v2/oauth/token"
    static let devicesPath = "/api/v2/tailnet/-/devices"

    static let tokenResponse = """
    {"access_token":"\(accessToken)","token_type":"Bearer","expires_in":3600,"scope":"devices:core:read"}
    """

    /// Relative to `referenceEpoch` (2024-05-01T10:00:00Z):
    /// - storage-node: connected, key expires in 68 days → no issue.
    /// - device-a: no `connectedToControl`, seen 2 min ago → online; key expires in 9 days.
    /// - device-b: disconnected, seen 3 days ago → offline > 24 h; key expiry disabled (zero date).
    /// - device-c: disconnected, seen 2 h ago → offline but no alert; key expired yesterday.
    /// - device-d: connected but not authorized.
    /// - a malformed entry without any id, dropped.
    static let devicesJSON = """
    {
      "devices": [
        {
          "addresses": ["192.0.2.1", "2001:db8::1"],
          "authorized": true,
          "blocksIncomingConnections": false,
          "clientVersion": "1.70.0-t1234567-gabcdef",
          "created": "2024-01-10T09:00:00Z",
          "expires": "2024-07-08T10:00:00Z",
          "hostname": "storage-node",
          "id": "1000000000000001",
          "isExternal": false,
          "keyExpiryDisabled": false,
          "lastSeen": "2024-05-01T09:59:58Z",
          "machineKey": "mkey:fake0000000000000000000000000000000000000000000000000000000001",
          "name": "storage-node.example.invalid",
          "nodeId": "nFakeNas1CNTRL",
          "nodeKey": "nodekey:fake000000000000000000000000000000000000000000000000000001",
          "os": "linux",
          "updateAvailable": true,
          "user": "owner@example.invalid",
          "connectedToControl": true
        },
        {
          "addresses": ["192.0.2.2"],
          "authorized": true,
          "clientVersion": "1.68.2",
          "expires": "2024-05-10T10:00:00Z",
          "hostname": "device-a",
          "id": "1000000000000002",
          "keyExpiryDisabled": false,
          "lastSeen": "2024-05-01T09:58:00Z",
          "name": "device-a.example.invalid",
          "nodeId": "nFakeLaptop1CNTRL",
          "os": "macOS",
          "updateAvailable": false,
          "user": "owner@example.invalid"
        },
        {
          "addresses": ["192.0.2.3"],
          "authorized": true,
          "expires": "0001-01-01T00:00:00Z",
          "hostname": "device-b",
          "id": "1000000000000003",
          "keyExpiryDisabled": true,
          "lastSeen": "2024-04-28T10:00:00Z",
          "name": "device-b.example.invalid",
          "nodeId": "nFakeOldPi1CNTRL",
          "os": "linux",
          "connectedToControl": false
        },
        {
          "addresses": ["192.0.2.4"],
          "authorized": true,
          "expires": "2024-04-30T10:00:00Z",
          "hostname": "device-c",
          "id": "1000000000000004",
          "keyExpiryDisabled": false,
          "lastSeen": "2024-05-01T08:00:00.123456789Z",
          "name": "device-c.example.invalid",
          "nodeId": "nFakePhone1CNTRL",
          "os": "iOS",
          "connectedToControl": false
        },
        {
          "addresses": ["192.0.2.5"],
          "authorized": false,
          "expires": "0001-01-01T00:00:00Z",
          "hostname": "device-d",
          "id": "1000000000000005",
          "keyExpiryDisabled": true,
          "lastSeen": "2024-05-01T09:59:59Z",
          "name": "device-d.example.invalid",
          "nodeId": "nFakeNewServer1CNTRL",
          "os": "linux",
          "connectedToControl": true
        },
        { "name": "ghost.example.invalid", "os": "linux" }
      ]
    }
    """

    static func decodeDevices(_ json: String = devicesJSON) throws -> [TailscaleDevice] {
        struct Payload: Decodable { let devices: LossyArray<TailscaleDevice> }
        return try JSONDecoder().decode(Payload.self, from: Data(json.utf8)).devices.elements
    }

    static var reference: Date { date(referenceEpoch) }
}

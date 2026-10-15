import Foundation
import Testing
import PatchNodeCore
@testable import TailscaleKit

struct TailscaleDemoTests {
    @Test func demoTailnetLoadsThroughOAuth() async throws {
        DemoServer.register(TailscaleDemoResponder(), host: DemoCatalog.host(for: .tailscale))
        let service = DemoCatalog.services.first { $0.kind == .tailscale }!
        let client = TailscaleClient(
            baseURL: service.url, serviceID: service.id, credential: service.credential, tokenCache: AccessTokenCache(),
            httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), label: nil, log: nil)
        )
        let devices = try await client.devices()
        let overview = TailscaleInventory(snapshots: [TailscaleServiceSnapshot(serviceID: service.id, serviceName: service.name, devices: devices)]).overview
        #expect(overview.total == 8)
        #expect(overview.offlineOver24h == 1)
        #expect(overview.keysExpiringSoon == 1)
        #expect(overview.awaitingApproval == 1)
    }
}

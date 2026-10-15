import Foundation
import Testing
import PatchNodeCore
@testable import SecurityKit

struct SecurityDemoTests {
    @Test func crowdSecNPMAndAdGuardLoad() async throws {
        DemoServer.register(CrowdSecDemoResponder(), host: DemoCatalog.host(for: .crowdSec))
        DemoServer.register(NPMDemoResponder(), host: DemoCatalog.host(for: .nginxProxyManager))
        DemoServer.register(AdGuardDemoResponder(), host: DemoCatalog.host(for: .adGuardHome))
        var snapshots: [SecurityServiceSnapshot] = []
        for kind in [ServiceKind.crowdSec, .nginxProxyManager, .adGuardHome] {
            let service = DemoCatalog.services.first { $0.kind == kind }!
            snapshots.append(try await SecurityProvider.loadSnapshot(
                kind: kind, baseURL: service.url, credential: service.credential, serviceID: service.id, serviceName: service.name,
                tokenCache: AccessTokenCache(),
                httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), label: nil, log: nil)
            ))
        }
        let inventory = SecurityInventory(snapshots: snapshots)
        #expect(inventory.decisions.count == 6)
        #expect(inventory.hosts.count == 7)
        #expect(inventory.hosts.count { $0.host.isFailing } == 1)
        let adGuard = try #require(inventory.adGuards.first)
        #expect(adGuard.summary.protectionEnabled)
        #expect(adGuard.summary.dnsQueries > 30_000)
        #expect(!adGuard.summary.topBlocked.isEmpty)
    }
}

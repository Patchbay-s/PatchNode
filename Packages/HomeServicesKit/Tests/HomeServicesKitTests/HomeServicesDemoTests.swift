import Foundation
import Testing
import PatchNodeCore
@testable import HomeServicesKit

struct HomeServicesDemoTests {
    private func http() -> HTTPClient {
        HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), label: nil, log: nil)
    }

    @Test func homeAssistantAndGlancesLoad() async throws {
        DemoServer.register(HomeAssistantDemoResponder(), host: DemoCatalog.host(for: .homeAssistant))
        DemoServer.register(GlancesDemoResponder(), host: DemoCatalog.host(for: .glances))
        var snapshots: [HomeServiceSnapshot] = []
        for kind in [ServiceKind.homeAssistant, .glances] {
            let service = DemoCatalog.services.first { $0.kind == kind }!
            snapshots.append(try await HomeServicesProvider.loadSnapshot(
                kind: kind, baseURL: service.url, credential: service.credential, serviceID: service.id,
                serviceName: service.name, httpClient: http()
            ))
        }
        let inventory = HomeServicesInventory(snapshots: snapshots)
        let entities = try #require(inventory.homeAssistants.first).entities
        #expect(Set(HomeAssistantDemoResponder.suggestedEntityIDs).isSubset(of: Set(entities.map(\.id))))
        #expect(inventory.glances.count == 1)
        #expect(inventory.glancesOverview.fullFileSystems == 1)
    }

    @Test func sceneActivationIsAccepted() async throws {
        DemoServer.register(HomeAssistantDemoResponder(), host: DemoCatalog.host(for: .homeAssistant))
        let service = DemoCatalog.services.first { $0.kind == .homeAssistant }!
        let client = HomeAssistantClient(baseURL: service.url, token: service.credential, httpClient: http())
        try await client.checkConnection()
        try await client.activate(entityID: "scene.movie_night")
    }
}

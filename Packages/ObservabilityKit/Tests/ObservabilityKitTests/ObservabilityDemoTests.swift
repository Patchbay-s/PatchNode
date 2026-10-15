import Foundation
import Testing
import PatchNodeCore
@testable import ObservabilityKit

@Suite(.serialized)
struct ObservabilityDemoTests {
    init() {
        DemoServer.register(PrometheusDemoResponder(), host: DemoCatalog.host(for: .prometheus))
        DemoServer.register(AlertmanagerDemoResponder(), host: DemoCatalog.host(for: .alertmanager))
        DemoServer.register(GrafanaDemoResponder(), host: DemoCatalog.host(for: .grafana))
        DemoServer.register(UptimeKumaDemoResponder(), host: DemoCatalog.host(for: .uptimeKuma))
    }

    private func load(_ kind: ServiceKind) async throws -> ObservabilityServiceSnapshot {
        let service = DemoCatalog.services.first { $0.kind == kind }!
        return try await ObservabilityProvider.loadSnapshot(
            kind: kind, baseURL: service.url, credential: service.credential, serviceID: service.id,
            serviceName: service.name, httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), label: nil, log: nil)
        )
    }

    @Test func everyServiceLoads() async throws {
        let snapshots = [
            try await load(.prometheus), try await load(.alertmanager),
            try await load(.grafana), try await load(.uptimeKuma),
        ]
        let inventory = ObservabilityInventory(snapshots: snapshots)
        #expect(inventory.targets.count == 6)
        #expect(inventory.alerts.count == 5) // 3 Alertmanager, 1 Grafana, 1 Uptime Kuma monitor down
        #expect(inventory.overview.targetsDown == 1)
        // The "info" certificate alert isn't worth a notification.
        let conditions = inventory.watchedConditions()
        #expect(conditions.count == 4)
        #expect(conditions.allSatisfy { $0.kind == .alertFiring })
        #expect(snapshots[2].dashboards.count == 5)
        let page = try #require(snapshots[3].statusPage)
        #expect(page.monitors.count == 7)
    }

    @Test func promQLChartsGetASeries() async throws {
        let service = DemoCatalog.services.first { $0.kind == .prometheus }!
        let client = PrometheusClient(baseURL: service.url, credential: service.credential,
                                      httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), label: nil, log: nil))
        let result = try await client.queryRange("rate(node_cpu_seconds_total[5m])", start: .now.addingTimeInterval(-3_600), end: .now)
        if case .matrix(let series) = result {
            #expect(series.count == 2)
            #expect(series[0].samples.count > 20)
        } else {
            Issue.record("expected a matrix, got \(result)")
        }
    }
}

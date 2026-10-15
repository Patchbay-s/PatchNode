import Foundation
import Testing
import PatchNodeCore
@testable import ObservabilityKit

@Suite("ObservabilityProvider")
struct ObservabilityProviderTests {
    private static let serviceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private static let checkPaths: [ServiceKind: (URL, String)] = [
        .prometheus: (Fixtures.prometheusURL, "/api/v1/status/buildinfo"),
        .alertmanager: (Fixtures.alertmanagerURL, "/api/v2/status"),
        .grafana: (Fixtures.grafanaURL, "/api/search"),
        .uptimeKuma: (Fixtures.kumaStatusURL, "/api/status-page/homelab"),
    ]

    private func provider(_ kind: ServiceKind, url: URL? = nil, credential: String = "", fake: FakeHTTPClient) -> ObservabilityProvider {
        ObservabilityProvider(id: Self.serviceID, kind: kind, displayName: "Lab \(kind)",
                              baseURL: url ?? Self.checkPaths[kind]!.0, credential: credential, httpClient: fake)
    }

    private func describe(_ status: HealthStatus) -> String {
        switch status {
        case .ok: "ok"
        case .degraded(let message): "degraded: \(message)"
        case .unreachable: "unreachable"
        case .unauthorized: "unauthorized"
        }
    }

    // MARK: healthCheck

    @Test(arguments: ObservabilityProvider.supportedKinds)
    func healthCheckOkHitsTheKindEndpoint(kind: ServiceKind) async throws {
        let fake = FakeHTTPClient.json("{}")
        let status = try await provider(kind, fake: fake).healthCheck()
        #expect(describe(status) == "ok")
        #expect(await fake.receivedPaths == [Self.checkPaths[kind]!.1])
    }

    @Test(arguments: ObservabilityProvider.supportedKinds)
    func healthCheck401And403AreUnauthorizedWithoutRetry(kind: ServiceKind) async throws {
        for outcome in [FakeHTTPClient.Outcome.unauthorized, .forbidden] {
            let fake = FakeHTTPClient(outcome)
            #expect(describe(try await provider(kind, fake: fake).healthCheck()) == "unauthorized")
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    @Test(arguments: ObservabilityProvider.supportedKinds)
    func healthCheck500IsDegradedWithStatus(kind: ServiceKind) async throws {
        let status = describe(try await provider(kind, fake: FakeHTTPClient(.serverError)).healthCheck())
        #expect(status.hasPrefix("degraded"))
        #expect(status.contains("500"))
    }

    @Test(arguments: ObservabilityProvider.supportedKinds)
    func healthCheckTimeoutIsUnreachable(kind: ServiceKind) async throws {
        let fake = FakeHTTPClient(.timeout)
        #expect(describe(try await provider(kind, fake: fake).healthCheck()) == "unreachable")
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func healthCheckInvalidResponseIsDegraded() async throws {
        let fake = FakeHTTPClient(.failure(HTTPClientError.invalidResponse))
        #expect(describe(try await provider(.prometheus, fake: fake).healthCheck()).hasPrefix("degraded"))
    }

    @Test func healthCheckSendsCredentials() async throws {
        let grafana = FakeHTTPClient.json("[]")
        _ = try await provider(.grafana, credential: Fixtures.grafanaToken, fake: grafana).healthCheck()
        #expect(await grafana.receivedSpecs.first?.headers["Authorization"] == "Bearer \(Fixtures.grafanaToken)")
        #expect(await grafana.receivedURLs.first.map(queryItems) == ["limit": "1"])

        let prometheus = FakeHTTPClient.json("{}")
        _ = try await provider(.prometheus, credential: Fixtures.basicCredential, fake: prometheus).healthCheck()
        #expect(await prometheus.receivedSpecs.first?.headers["Authorization"]?.hasPrefix("Basic ") == true)

        let kuma = FakeHTTPClient.json("{}")
        _ = try await provider(.uptimeKuma, credential: "ignored-fake-token-1234", fake: kuma).healthCheck()
        #expect(await kuma.receivedSpecs.first?.headers.isEmpty == true)
    }

    @Test func kumaURLWithoutStatusIsDegradedBeforeAnyRequest() async throws {
        let fake = FakeHTTPClient.json("{}")
        let status = try await provider(.uptimeKuma, url: URL(string: "https://kuma.example.invalid/dashboard")!, fake: fake).healthCheck()
        #expect(describe(status).hasPrefix("degraded"))
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func unsupportedKindIsDegradedWithoutRequest() async throws {
        let fake = FakeHTTPClient.json("{}")
        let status = try await ObservabilityProvider(id: Self.serviceID, kind: .glances, displayName: "x",
                                                     baseURL: Fixtures.grafanaURL, credential: "", httpClient: fake).healthCheck()
        #expect(describe(status).hasPrefix("degraded"))
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func healthCheckRethrowsCancellation() async throws {
        let fake = FakeHTTPClient(.failure(CancellationError()))
        await #expect(throws: CancellationError.self) { _ = try await provider(.prometheus, fake: fake).healthCheck() }
    }

    // MARK: loadSnapshot

    private func load(_ kind: ServiceKind, url: URL? = nil, fake: FakeHTTPClient) async throws -> ObservabilityServiceSnapshot {
        try await ObservabilityProvider.loadSnapshot(kind: kind, baseURL: url ?? Self.checkPaths[kind]!.0, credential: "",
                                                     serviceID: Self.serviceID, serviceName: "Lab", httpClient: fake)
    }

    @Test func prometheusSnapshotHasTargets() async throws {
        let fake = FakeHTTPClient.json(Fixtures.targets)
        let snapshot = try await load(.prometheus, fake: fake)
        #expect(snapshot.kind == .prometheus && snapshot.serviceID == Self.serviceID && snapshot.serviceName == "Lab")
        #expect(snapshot.baseURL == Fixtures.prometheusURL)
        #expect(snapshot.targets.count == 3)
        #expect(snapshot.alerts.isEmpty && snapshot.dashboards.isEmpty && snapshot.statusPage == nil)
        #expect(await fake.receivedPaths == ["/api/v1/targets"])
    }

    @Test func alertmanagerSnapshotHasAlerts() async throws {
        let snapshot = try await load(.alertmanager, fake: .json(Fixtures.alertmanagerAlerts))
        #expect(snapshot.alerts.map(\.name) == ["InstanceDown", "DiskAlmostFull", "BackupStale"])
    }

    @Test func grafanaSnapshotHasDashboardsAndAlerts() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/search": .json(Fixtures.grafanaSearch),
            "/api/alertmanager/grafana/api/v2/alerts": .json(Fixtures.grafanaAlerts),
        ])
        let snapshot = try await load(.grafana, fake: fake)
        #expect(snapshot.dashboards.map(\.uid) == ["node-exporter", "home"])
        #expect(snapshot.alerts.map(\.name) == ["High CPU"])
    }

    @Test(arguments: [FakeHTTPClient.Outcome.serverError, .forbidden, .timeout, .invalidJSON])
    func grafanaAlertsFailureIsIgnored(alertsOutcome: FakeHTTPClient.Outcome) async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/search": .json(Fixtures.grafanaSearch),
            "/api/alertmanager/grafana/api/v2/alerts": alertsOutcome,
        ])
        let snapshot = try await load(.grafana, fake: fake)
        #expect(snapshot.dashboards.count == 2)
        #expect(snapshot.alerts.isEmpty)
    }

    @Test(arguments: [
        (FakeHTTPClient.Outcome.unauthorized, ServiceProviderError.unauthorized),
        (.serverError, .unexpectedStatus(500)),
        (.invalidJSON, .decodingFailed),
    ])
    func grafanaDashboardsFailureThrows(outcome: FakeHTTPClient.Outcome, expected: ServiceProviderError) async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/search": outcome,
            "/api/alertmanager/grafana/api/v2/alerts": .json(Fixtures.grafanaAlerts),
        ])
        await #expect(throws: expected) { _ = try await load(.grafana, fake: fake) }
        #expect(await fake.receivedPaths == ["/api/search"])
    }

    @Test func kumaSnapshotUsesKumaBaseURL() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/status-page/homelab": .json(Fixtures.kumaStatusPage),
            "/api/status-page/heartbeat/homelab": .json(Fixtures.kumaHeartbeats),
        ])
        let snapshot = try await load(.uptimeKuma, fake: fake)
        #expect(snapshot.baseURL.absoluteString == "https://kuma.example.invalid")
        #expect(snapshot.statusPage?.monitors.count == 4)
    }

    @Test func kumaSnapshotWithoutStatusPathThrows() async throws {
        let fake = FakeHTTPClient.json("{}")
        await #expect(throws: ObservabilityProviderError.notAStatusPage) {
            _ = try await load(.uptimeKuma, url: URL(string: "https://kuma.example.invalid/")!, fake: fake)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func unsupportedKindSnapshotThrows() async throws {
        await #expect(throws: ObservabilityProviderError.unsupportedKind) {
            _ = try await load(.dockerPortainer, url: Fixtures.grafanaURL, fake: .json("{}"))
        }
    }

    // MARK: summary

    @Test func alertmanagerSummaryDetails() async throws {
        let summary = try await provider(.alertmanager, fake: .json(Fixtures.alertmanagerAlerts)).summary()
        #expect(summary.headline == "3")
        #expect(summary.details == ["activeAlerts": "3", "critical": "1", "warning": "1", "targetsDown": "0"])
    }

    @Test func prometheusSummaryCountsTargetsDown() async throws {
        let summary = try await provider(.prometheus, fake: .json(Fixtures.targets)).summary()
        #expect(summary.headline == "0")
        #expect(summary.details["targetsDown"] == "1")
    }

    @Test func kumaSummaryCountsDownMonitorsAsCritical() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/status-page/homelab": .json(Fixtures.kumaStatusPage),
            "/api/status-page/heartbeat/homelab": .json(Fixtures.kumaHeartbeats),
        ])
        let summary = try await provider(.uptimeKuma, fake: fake).summary()
        #expect(summary.details == ["activeAlerts": "1", "critical": "1", "warning": "0", "targetsDown": "0"])
    }

    @Test func summaryPropagatesUnauthorized() async throws {
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await provider(.alertmanager, fake: FakeHTTPClient(.unauthorized)).summary()
        }
    }
}

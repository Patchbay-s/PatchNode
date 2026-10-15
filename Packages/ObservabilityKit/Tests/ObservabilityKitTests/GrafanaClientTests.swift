import Foundation
import Testing
import PatchNodeCore
@testable import ObservabilityKit

@Suite("GrafanaClient")
struct GrafanaClientTests {
    private static let alertsPath = "/api/alertmanager/grafana/api/v2/alerts"

    private func client(_ fake: FakeHTTPClient, base: URL = Fixtures.grafanaURL) -> GrafanaClient {
        GrafanaClient(baseURL: base, token: Fixtures.grafanaToken, httpClient: fake)
    }

    // MARK: Requests

    @Test func checkConnectionUsesSearchWithLimitOneAndBearer() async throws {
        let fake = FakeHTTPClient.json("[]")
        try await client(fake).checkConnection()
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.url.path == "/api/search")
        #expect(queryItems(spec.url) == ["limit": "1"])
        #expect(spec.headers == ["Authorization": "Bearer \(Fixtures.grafanaToken)"])
        #expect(!spec.redactedDescription.contains(Fixtures.grafanaToken))
        #expect(!spec.redactedDescription.contains("fake-grafana-token-1234"))
    }

    @Test func dashboardsRequestTypeAndLimit() async throws {
        let fake = FakeHTTPClient.json("[]")
        _ = try await client(fake).dashboards()
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.url.path == "/api/search")
        #expect(queryItems(spec.url) == ["type": "dash-db", "limit": "500"])
        #expect(spec.headers["Authorization"] == "Bearer \(Fixtures.grafanaToken)")
    }

    @Test func alertsUseGrafanaAlertmanagerPath() async throws {
        let fake = FakeHTTPClient.json("[]")
        _ = try await client(fake).alerts()
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.url.path == Self.alertsPath)
        #expect(queryItems(spec.url) == ["active": "true", "silenced": "false", "inhibited": "false"])
        #expect(spec.headers["Authorization"] == "Bearer \(Fixtures.grafanaToken)")
    }

    // MARK: Decoding

    @Test func decodesDashboardsDroppingMalformedEntry() async throws {
        let dashboards = try await client(.json(Fixtures.grafanaSearch)).dashboards()
        #expect(dashboards == [
            GrafanaDashboard(uid: "node-exporter", title: "Node Exporter Full", path: "/d/node-exporter/node-exporter-full",
                             folder: "Infrastructure", tags: ["linux", "prometheus"]),
            GrafanaDashboard(uid: "home", title: "Home", path: "/d/home/home", folder: nil, tags: []),
        ])
    }

    @Test func decodesGrafanaAlerts() async throws {
        let alerts = try await client(.json(Fixtures.grafanaAlerts)).alerts()
        #expect(alerts.count == 1)
        let alert = try #require(alerts.first)
        #expect(alert.id == "grafana|5e8c7b6a59483726")
        #expect(alert.source == .grafana)
        #expect(alert.name == "High CPU")
        #expect(alert.severity == .critical) // "page"
        #expect(alert.summary == "CPU above 90% on proxmox.example.invalid")
        #expect(alert.since == date(referenceEpoch - 1200))
    }

    @Test func alerts404MeansUnifiedAlertingOff() async throws {
        let fake = FakeHTTPClient(.json(#"{"message":"Not found"}"#, status: 404))
        #expect(try await client(fake).alerts().isEmpty)
    }

    @Test func alerts500Throws() async throws {
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) {
            _ = try await client(FakeHTTPClient(.serverError)).alerts()
        }
    }

    @Test func emptyListsAreEmpty() async throws {
        #expect(try await client(.json("[]")).dashboards().isEmpty)
        #expect(try await client(.json("[]")).alerts().isEmpty)
    }

    @Test func invalidJSONAndEmptyBodyAreDecodingFailures() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) { _ = try await client(FakeHTTPClient(.invalidJSON)).dashboards() }
        await #expect(throws: ServiceProviderError.decodingFailed) { _ = try await client(FakeHTTPClient(.emptyBody)).dashboards() }
        await #expect(throws: ServiceProviderError.decodingFailed) { _ = try await client(FakeHTTPClient(.invalidJSON)).alerts() }
        await #expect(throws: ServiceProviderError.decodingFailed) { _ = try await client(FakeHTTPClient(.emptyBody)).alerts() }
    }

    @Test(arguments: [
        (FakeHTTPClient.Outcome.unauthorized, ServiceProviderError.unauthorized),
        (.forbidden, .forbidden),
        (.timeout, .unreachable),
    ])
    func failuresAreMappedWithoutRetry(outcome: FakeHTTPClient.Outcome, expected: ServiceProviderError) async throws {
        for operation in 0..<3 {
            let fake = FakeHTTPClient(outcome)
            let grafana = client(fake)
            await #expect(throws: expected) {
                switch operation {
                case 0: try await grafana.checkConnection()
                case 1: _ = try await grafana.dashboards()
                default: _ = try await grafana.alerts()
                }
            }
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    // MARK: Dashboard URL

    private func dashboard(_ path: String) -> GrafanaDashboard {
        GrafanaDashboard(uid: "abc", title: "Node", path: path)
    }

    @Test func relativePathResolvesOnSameHTTPSHost() {
        #expect(dashboard("/d/abc/node").url(on: Fixtures.grafanaURL)?.absoluteString == "https://grafana.example.invalid/d/abc/node")
        #expect(dashboard("/d/abc/node").url(on: URL(string: "https://grafana.example.invalid:3000/")!)?.absoluteString
                == "https://grafana.example.invalid:3000/d/abc/node")
    }

    @Test(arguments: [
        "https://lab.example.invalid/grafana",
        "https://lab.example.invalid/grafana/",
    ])
    func subPathBaseIsPrefixedOnlyOnce(base: String) {
        let base = URL(string: base)!
        #expect(dashboard("/grafana/d/abc/node").url(on: base)?.absoluteString == "https://lab.example.invalid/grafana/d/abc/node")
        #expect(dashboard("/d/abc/node").url(on: base)?.absoluteString == "https://lab.example.invalid/grafana/d/abc/node")
    }

    @Test(arguments: [
        "//evil.example/x",
        "https://evil.example/x",
        "d/x",
        "",
        "javascript:alert(1)",
    ])
    func pathLeavingTheHostIsRejected(path: String) {
        #expect(dashboard(path).url(on: Fixtures.grafanaURL) == nil)
    }

    @Test func baseQueryAndFragmentAreDropped() {
        let base = URL(string: "https://grafana.example.invalid/?orgId=1#top")!
        #expect(dashboard("/d/abc/node").url(on: base)?.absoluteString == "https://grafana.example.invalid/d/abc/node")
    }

    @Test func queryInDashboardPathNeverBecomesAQueryOrAnotherHost() throws {
        let url = try #require(dashboard("/d/abc/node?orgId=1#panel").url(on: Fixtures.grafanaURL))
        #expect(url.host == "grafana.example.invalid")
        #expect(url.query == nil)
        #expect(url.fragment == nil)
    }

    @Test func nonHTTPSBaseGivesNoURL() {
        #expect(dashboard("/d/abc/node").url(on: URL(string: "http://grafana.example.invalid")!) == nil)
    }
}

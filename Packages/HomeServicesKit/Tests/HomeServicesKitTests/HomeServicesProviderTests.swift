import Foundation
import Testing
import PatchNodeCore
@testable import HomeServicesKit

@Suite("HomeServicesProvider")
struct HomeServicesProviderTests {
    private static let serviceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// `path` is `URL.path`, which Foundation reports without the trailing slash:
    /// `absoluteURL` pins the exact URL sent (`/api/` for Home Assistant).
    private static let checks: [ServiceKind: (url: URL, credential: String, path: String, absoluteURL: String, okBody: String)] = [
        .homeAssistant: (Fixtures.homeAssistantURL, Fixtures.haToken, "/api", "https://ha.example.invalid/api/", Fixtures.apiRunning),
        .glances: (Fixtures.glancesURL, Fixtures.glancesCredential, "/api/4/all", "https://glances.example.invalid/api/4/all", Fixtures.glancesV4),
    ]

    private func provider(_ kind: ServiceKind, url: URL? = nil, httpClient: any HTTPClientProtocol) -> HomeServicesProvider {
        let check = Self.checks[kind]
        return HomeServicesProvider(
            id: Self.serviceID, kind: kind, displayName: "Lab \(kind)",
            baseURL: url ?? check?.url ?? Fixtures.homeAssistantURL,
            credential: check?.credential ?? "", httpClient: httpClient
        )
    }

    private func describe(_ status: HealthStatus) -> String {
        switch status {
        case .ok: "ok"
        case .degraded(let message): "degraded: \(message)"
        case .unreachable(let error): "unreachable: \(error)"
        case .unauthorized: "unauthorized"
        }
    }

    // MARK: healthCheck

    @Test(arguments: HomeServicesProvider.supportedKinds)
    func healthCheckOkHitsTheKindEndpointWithCredentials(kind: ServiceKind) async throws {
        let check = try #require(Self.checks[kind])
        let fake = FakeHTTPClient(routes: [check.path: .json(check.okBody)])
        #expect(describe(try await provider(kind, httpClient: fake).healthCheck()) == "ok")
        #expect(await fake.receivedURLs.map(\.absoluteString) == [check.absoluteURL])
        let authorization = await fake.receivedSpecs.first?.headers["Authorization"]
        #expect(authorization?.hasPrefix(kind == .homeAssistant ? "Bearer " : "Basic ") == true)
    }

    @Test(arguments: HomeServicesProvider.supportedKinds)
    func healthCheck401And403AreUnauthorizedWithoutRetry(kind: ServiceKind) async throws {
        for outcome in [FakeHTTPClient.Outcome.unauthorized, .forbidden] {
            let fake = FakeHTTPClient(outcome)
            #expect(describe(try await provider(kind, httpClient: fake).healthCheck()) == "unauthorized")
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    @Test(arguments: HomeServicesProvider.supportedKinds)
    func healthCheckTimeoutIsUnreachable(kind: ServiceKind) async throws {
        let fake = FakeHTTPClient(.timeout)
        let status = try await provider(kind, httpClient: fake).healthCheck()
        guard case .unreachable(let error) = status else {
            Issue.record("expected unreachable, got \(describe(status))")
            return
        }
        #expect(error as? HomeServicesProviderError == .unreachable)
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: HomeServicesProvider.supportedKinds)
    func healthCheck500IsDegradedWithStatus(kind: ServiceKind) async throws {
        let fake = FakeHTTPClient(.serverError)
        #expect(describe(try await provider(kind, httpClient: fake).healthCheck()) == "degraded: HTTP 500")
    }

    @Test(arguments: HomeServicesProvider.supportedKinds)
    func healthCheckInvalidOrEmptyBodyIsDegraded(kind: ServiceKind) async throws {
        let outcomes: [FakeHTTPClient.Outcome] = [.invalidJSON, .emptyBody, .failure(HTTPClientError.invalidResponse)]
        for outcome in outcomes {
            let status = describe(try await provider(kind, httpClient: FakeHTTPClient(outcome)).healthCheck())
            #expect(status == "degraded: invalid response")
        }
    }

    @Test func healthCheckGlancesNotGlancesJSONIsDegraded() async throws {
        let fake = FakeHTTPClient(routes: ["/api/4/all": .json(Fixtures.notGlances)])
        #expect(describe(try await provider(.glances, httpClient: fake).healthCheck()) == "degraded: invalid response")
    }

    @Test func healthCheckGlancesV3ServerIsOk() async throws {
        let fake = FakeHTTPClient(routes: ["/api/3/all": .json(Fixtures.glancesV3)])
        #expect(describe(try await provider(.glances, httpClient: fake).healthCheck()) == "ok")
        #expect(await fake.receivedPaths == ["/api/4/all", "/api/3/all"])
    }

    @Test func healthCheckUnsupportedKindIsDegradedWithoutRequest() async throws {
        let fake = FakeHTTPClient.json("{}")
        let status = describe(try await provider(.grafana, httpClient: fake).healthCheck())
        #expect(status == "degraded: unsupported service")
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func healthCheckPropagatesCancellation() async throws {
        let fake = FakeHTTPClient(.failure(CancellationError()))
        await #expect(throws: CancellationError.self) {
            _ = try await provider(.homeAssistant, httpClient: fake).healthCheck()
        }
    }

    @Test(arguments: HomeServicesProvider.supportedKinds)
    func healthCheckRefusesPlainHTTPBeforeAnyNetworkAccess(kind: ServiceKind) async throws {
        // Real HTTPClient: the scheme check happens before any URLSession call.
        let url = try #require(URL(string: "http://insecure.example.invalid"))
        let status = try await provider(kind, url: url, httpClient: HTTPClient()).healthCheck()
        #expect(describe(status).hasPrefix("unreachable"))
    }

    // MARK: summary / loadSnapshot

    @Test func summaryForHomeAssistantCountsEntities() async throws {
        let fake = FakeHTTPClient(routes: ["/api/states": .json(Fixtures.states)])
        let summary = try await provider(.homeAssistant, httpClient: fake).summary()
        #expect(summary.headline == "6")
        #expect(summary.details == ["entities": "6"])
    }

    @Test func summaryForGlancesShowsRoundedCPUAndFullFileSystems() async throws {
        let fake = FakeHTTPClient(routes: ["/api/4/all": .json(Fixtures.glancesV4)])
        let summary = try await provider(.glances, httpClient: fake).summary()
        #expect(summary.headline == "12")
        #expect(summary.details == ["fullFileSystems": "1"])
    }

    @Test func summaryForGlancesWithoutCPUShowsDash() async throws {
        let fake = FakeHTTPClient(routes: ["/api/4/all": .json(#"{"mem":{"percent":10}}"#)])
        #expect(try await provider(.glances, httpClient: fake).summary().headline == "–")
    }

    @Test func summaryPropagatesClientErrors() async throws {
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await provider(.homeAssistant, httpClient: FakeHTTPClient(.unauthorized)).summary()
        }
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await provider(.glances, httpClient: FakeHTTPClient(.invalidJSON)).summary()
        }
    }

    @Test func loadSnapshotSortsHomeAssistantEntitiesByName() async throws {
        let fake = FakeHTTPClient(routes: ["/api/states": .json(Fixtures.states)])
        let snapshot = try await HomeServicesProvider.loadSnapshot(
            kind: .homeAssistant, baseURL: Fixtures.homeAssistantURL, credential: Fixtures.haToken,
            serviceID: Self.serviceID, serviceName: "Home", httpClient: fake
        )
        #expect(snapshot.serviceID == Self.serviceID)
        #expect(snapshot.serviceName == "Home")
        #expect(snapshot.kind == .homeAssistant)
        #expect(snapshot.glances == nil)
        #expect(snapshot.entities.map(\.name) == [
            "Good morning", "Living room", "Living room temperature", "Movie night",
            "sensor.garage_door_battery", "sensor.power_meter",
        ])
    }

    @Test func loadSnapshotForGlances() async throws {
        let fake = FakeHTTPClient(routes: ["/api/4/all": .json(Fixtures.glancesV4)])
        let snapshot = try await HomeServicesProvider.loadSnapshot(
            kind: .glances, baseURL: Fixtures.glancesURL, credential: "",
            serviceID: Self.serviceID, serviceName: "NAS", httpClient: fake
        )
        #expect(snapshot.kind == .glances)
        #expect(snapshot.entities.isEmpty)
        #expect(snapshot.glances?.hostname == "nas")
    }

    @Test func loadSnapshotRejectsUnsupportedKindWithoutRequest() async throws {
        let fake = FakeHTTPClient.json("[]")
        await #expect(throws: HomeServicesProviderError.unsupportedKind) {
            _ = try await HomeServicesProvider.loadSnapshot(
                kind: .prometheus, baseURL: Fixtures.homeAssistantURL, credential: "",
                serviceID: Self.serviceID, serviceName: "X", httpClient: fake
            )
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func supportedKinds() {
        #expect(HomeServicesProvider.supportedKinds == [.homeAssistant, .glances])
    }
}

import Foundation
import Testing
import PatchNodeCore
@testable import TailscaleKit

private typealias F = TailscaleFixtures

@Suite("TailscaleProvider")
struct TailscaleProviderTests {
    private func provider(
        _ fake: any HTTPClientProtocol, credential: String = F.oauthCredential, baseURL: URL = F.baseURL
    ) -> TailscaleProvider {
        TailscaleProvider(id: F.serviceID, displayName: "Tailnet", baseURL: baseURL, credential: credential, httpClient: fake)
    }

    private func routes(devices: FakeHTTPClient.Outcome = .json(F.devicesJSON)) -> FakeHTTPClient {
        FakeHTTPClient(routes: [F.tokenPath: .json(F.tokenResponse), F.devicesPath: devices])
    }

    private func describe(_ status: HealthStatus) -> String {
        switch status {
        case .ok: "ok"
        case .degraded(let message): "degraded: \(message)"
        case .unreachable: "unreachable"
        case .unauthorized: "unauthorized"
        }
    }

    @Test func kindAndIdentity() {
        let provider = provider(routes())
        #expect(provider.kind == .tailscale)
        #expect(provider.id == F.serviceID)
        #expect(provider.displayName == "Tailnet")
    }

    @Test func healthCheckOk() async throws {
        let fake = routes()
        #expect(describe(try await provider(fake).healthCheck()) == "ok")
        #expect(await fake.receivedPaths == [F.tokenPath, F.devicesPath])
    }

    @Test func healthCheck401And403OnDevicesAreUnauthorizedWithoutRetry() async throws {
        for outcome in [FakeHTTPClient.Outcome.unauthorized, .forbidden] {
            let fake = routes(devices: outcome)
            #expect(describe(try await provider(fake).healthCheck()) == "unauthorized")
            #expect(await fake.receivedPaths == [F.tokenPath, F.devicesPath])
        }
    }

    @Test func healthCheckRefusedOAuthClientIsUnauthorized() async throws {
        let fake = FakeHTTPClient(routes: [F.tokenPath: .json(#"{"error":"invalid_client"}"#, status: 400)])
        #expect(describe(try await provider(fake).healthCheck()) == "unauthorized")
        #expect(await fake.receivedPaths == [F.tokenPath])
    }

    @Test func healthCheckMalformedCredentialIsUnauthorizedWithoutRequest() async throws {
        let fake = routes()
        #expect(describe(try await provider(fake, credential: "garbage").healthCheck()) == "unauthorized")
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func healthCheck500IsDegradedWithStatus() async throws {
        #expect(describe(try await provider(routes(devices: .serverError)).healthCheck()) == "degraded: HTTP 500")
    }

    @Test func healthCheckInvalidJSONAndEmptyBodyAreDegraded() async throws {
        for outcome in [FakeHTTPClient.Outcome.invalidJSON, .emptyBody, .failure(HTTPClientError.invalidResponse)] {
            #expect(describe(try await provider(routes(devices: outcome)).healthCheck()) == "degraded: invalid response")
        }
    }

    @Test func healthCheckTimeoutIsUnreachable() async throws {
        let fake = routes(devices: .timeout)
        #expect(describe(try await provider(fake).healthCheck()) == "unreachable")
        #expect(await fake.receivedPaths == [F.tokenPath, F.devicesPath])
    }

    @Test func healthCheckRejectsNonHTTPSURLBeforeSending() async throws {
        // Real HTTPClient: the scheme check fires before any URLSession call.
        let status = try await provider(HTTPClient(), baseURL: URL(string: "http://tailscale-api.example.invalid")!).healthCheck()
        #expect(describe(status) == "unreachable")
    }

    @Test func healthCheckRethrowsCancellation() async {
        let fake = routes(devices: .failure(CancellationError()))
        await #expect(throws: CancellationError.self) { try await provider(fake).healthCheck() }
    }

    @Test func summaryCountsOnlineDevices() async throws {
        let json = """
        {"devices":[
          {"nodeId":"nFakeA","name":"a.example.invalid","hostname":"a","connectedToControl":true,"keyExpiryDisabled":true,"expires":"0001-01-01T00:00:00Z"},
          {"nodeId":"nFakeB","name":"b.example.invalid","hostname":"b","connectedToControl":false,"lastSeen":"2020-01-01T00:00:00Z","keyExpiryDisabled":true,"expires":"0001-01-01T00:00:00Z"}
        ]}
        """
        let summary = try await provider(routes(devices: .json(json))).summary()
        #expect(summary.headline == "1/2")
        #expect(summary.details == ["online": "1", "total": "2", "offlineOver24h": "1", "keysExpiringSoon": "0"])
    }

    @Test func summaryPropagatesErrors() async {
        await #expect(throws: ServiceProviderError.unauthorized) { try await provider(routes(devices: .unauthorized)).summary() }
    }
}

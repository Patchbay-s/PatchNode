import Foundation
import Testing
import PatchNodeCore
@testable import SecurityKit

private typealias F = SecurityFixtures

@Suite("SecurityProvider")
struct SecurityProviderTests {
    private static let setups: [ServiceKind: (url: URL, credential: String, paths: [String])] = [
        .crowdSec: (F.crowdSecURL, F.bouncerKey, [F.decisionsPath]),
        .nginxProxyManager: (F.npmURL, F.npmCredential, [F.tokensPath, F.proxyHostsPath]),
        .adGuardHome: (F.adGuardURL, F.adGuardCredential, [F.statusPath, F.statsPath]),
    ]

    private static func healthyServer() -> FakeHTTPClient {
        FakeHTTPClient(routes: [
            F.decisionsPath: .json(F.decisionsJSON),
            F.tokensPath: .json(F.npmTokenResponse()),
            F.proxyHostsPath: .json(F.proxyHostsJSON),
            F.statusPath: .json(F.statusJSON),
            F.statsPath: .json(F.statsJSON),
        ])
    }

    private func provider(_ kind: ServiceKind, http: any HTTPClientProtocol, url: URL? = nil, credential: String? = nil) -> SecurityProvider {
        let setup = Self.setups[kind]
        return SecurityProvider(
            id: F.serviceID, kind: kind, displayName: "Lab \(kind)",
            baseURL: url ?? setup?.url ?? F.crowdSecURL, credential: credential ?? setup?.credential ?? "",
            httpClient: http
        )
    }

    private func describe(_ status: HealthStatus) -> String {
        switch status {
        case .ok: "ok"
        case .degraded(let message): "degraded: \(message)"
        case .unreachable: "unreachable"
        case .unauthorized: "unauthorized"
        }
    }

    @Test func supportedKinds() {
        #expect(SecurityProvider.supportedKinds == [.crowdSec, .nginxProxyManager, .adGuardHome])
    }

    // MARK: healthCheck

    @Test(arguments: SecurityProvider.supportedKinds)
    func healthCheckOkHitsTheKindEndpoints(kind: ServiceKind) async throws {
        let fake = Self.healthyServer()
        #expect(describe(try await provider(kind, http: fake).healthCheck()) == "ok")
        #expect(await fake.receivedPaths == Self.setups[kind]!.paths)
    }

    @Test(arguments: SecurityProvider.supportedKinds)
    func healthCheck401And403AreUnauthorizedWithoutRetry(kind: ServiceKind) async throws {
        for outcome in [FakeHTTPClient.Outcome.unauthorized, .forbidden] {
            let fake = FakeHTTPClient(outcome)
            #expect(describe(try await provider(kind, http: fake).healthCheck()) == "unauthorized")
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    @Test func healthCheckRefusedNPMLoginIsUnauthorized() async throws {
        let fake = FakeHTTPClient(routes: [F.tokensPath: .json(#"{"error":{"message":"Invalid password"}}"#, status: 400)])
        #expect(describe(try await provider(.nginxProxyManager, http: fake).healthCheck()) == "unauthorized")
        #expect(await fake.receivedPaths == [F.tokensPath])
    }

    @Test(arguments: SecurityProvider.supportedKinds)
    func healthCheck500IsDegradedWithStatus(kind: ServiceKind) async throws {
        #expect(describe(try await provider(kind, http: FakeHTTPClient(.serverError)).healthCheck()) == "degraded: HTTP 500")
    }

    @Test(arguments: SecurityProvider.supportedKinds)
    func healthCheckTimeoutIsUnreachable(kind: ServiceKind) async throws {
        let fake = FakeHTTPClient(.timeout)
        #expect(describe(try await provider(kind, http: fake).healthCheck()) == "unreachable")
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: SecurityProvider.supportedKinds)
    func healthCheckInvalidJSONIsDegraded(kind: ServiceKind) async throws {
        #expect(describe(try await provider(kind, http: FakeHTTPClient(.invalidJSON)).healthCheck()) == "degraded: invalid response")
    }

    @Test func healthCheckEmptyBodyIsDegradedExceptForCrowdSec() async throws {
        // CrowdSec answers an empty body when there is no decision.
        #expect(describe(try await provider(.crowdSec, http: FakeHTTPClient(.emptyBody)).healthCheck()) == "ok")
        for kind in [ServiceKind.nginxProxyManager, .adGuardHome] {
            #expect(describe(try await provider(kind, http: FakeHTTPClient(.emptyBody)).healthCheck()) == "degraded: invalid response")
        }
    }

    @Test func healthCheckUnsupportedKindSendsNothing() async throws {
        let fake = Self.healthyServer()
        #expect(describe(try await provider(.grafana, http: fake, url: F.crowdSecURL, credential: "").healthCheck()) == "degraded: unsupported service")
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func healthCheckInvalidNPMCredentialSendsNothing() async throws {
        let fake = Self.healthyServer()
        #expect(describe(try await provider(.nginxProxyManager, http: fake, credential: "no-colon").healthCheck()) == "unauthorized")
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test(arguments: SecurityProvider.supportedKinds)
    func healthCheckRejectsNonHTTPSURLBeforeSending(kind: ServiceKind) async throws {
        // Real HTTPClient: the scheme check fires before any URLSession call.
        let url = URL(string: "http://security.example.invalid")!
        #expect(describe(try await provider(kind, http: HTTPClient(), url: url).healthCheck()) == "unreachable")
    }

    @Test func healthCheckRethrowsCancellation() async {
        let fake = FakeHTTPClient(.failure(CancellationError()))
        await #expect(throws: CancellationError.self) { try await provider(.crowdSec, http: fake).healthCheck() }
    }

    // MARK: summary

    @Test func crowdSecSummaryCountsActiveBans() async throws {
        let summary = try await provider(.crowdSec, http: Self.healthyServer()).summary()
        // 4 valid decisions, one simulated.
        #expect(summary.headline == "3")
        #expect(summary.details["activeBans"] == "3")
    }

    @Test func npmSummaryCountsHosts() async throws {
        let summary = try await provider(.nginxProxyManager, http: Self.healthyServer()).summary()
        #expect(summary.details["hostsTotal"] == "4")
        #expect(summary.details["hostsFailing"] == "1")
    }

    @Test func adGuardSummaryCountsQueries() async throws {
        let summary = try await provider(.adGuardHome, http: Self.healthyServer()).summary()
        #expect(summary.details["dnsQueries"] == "24567")
        #expect(summary.details["dnsBlocked"] == "3135")
    }

    @Test func summaryPropagatesErrors() async {
        await #expect(throws: ServiceProviderError.unauthorized) {
            try await provider(.adGuardHome, http: FakeHTTPClient(.unauthorized)).summary()
        }
        await #expect(throws: SecurityProviderError.unsupportedKind) {
            try await provider(.prometheus, http: Self.healthyServer(), url: F.crowdSecURL, credential: "").summary()
        }
    }

    @Test func loadSnapshotSharesTheTokenCache() async throws {
        let fake = Self.healthyServer()
        let cache = AccessTokenCache()
        for _ in 0..<2 {
            let snapshot = try await SecurityProvider.loadSnapshot(
                kind: .nginxProxyManager, baseURL: F.npmURL, credential: F.npmCredential,
                serviceID: F.serviceID, serviceName: "NPM", tokenCache: cache, httpClient: fake
            )
            #expect(snapshot.kind == .nginxProxyManager)
            #expect(snapshot.proxyHosts.count == 4)
        }
        #expect(await fake.receivedPaths == [F.tokensPath, F.proxyHostsPath, F.proxyHostsPath])
    }
}

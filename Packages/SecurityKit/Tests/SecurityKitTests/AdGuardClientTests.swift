import Foundation
import Testing
import PatchNodeCore
@testable import SecurityKit

private typealias F = SecurityFixtures

@Suite("AdGuardClient")
struct AdGuardClientTests {
    private func routes(
        status: FakeHTTPClient.Outcome = .json(F.statusJSON),
        stats: FakeHTTPClient.Outcome = .json(F.statsJSON)
    ) -> FakeHTTPClient {
        FakeHTTPClient(routes: [F.statusPath: status, F.statsPath: stats])
    }

    private func client(_ fake: FakeHTTPClient, credential: String = F.adGuardCredential) -> AdGuardClient {
        AdGuardClient(baseURL: F.adGuardURL, credential: credential, httpClient: fake)
    }

    // MARK: Requests

    @Test func fetchesStatusThenStatsWithBasicAuth() async throws {
        let fake = routes()
        _ = try await client(fake).summary()
        let specs = await fake.receivedSpecs
        #expect(specs.map(\.url.path) == [F.statusPath, F.statsPath])
        let expected = "Basic " + Data(F.adGuardCredential.utf8).base64EncodedString()
        for spec in specs {
            #expect(spec.method == .get)
            #expect(spec.url.host == "adguard.example.invalid")
            #expect(spec.headers["Authorization"] == expected)
        }
    }

    @Test func emptyCredentialSendsNoAuthorizationHeader() async throws {
        let fake = routes()
        _ = try await client(fake, credential: "").summary()
        #expect(await fake.receivedSpecs.allSatisfy { $0.headers["Authorization"] == nil })
    }

    @Test func redactedDescriptionHidesBasicCredential() async throws {
        let fake = routes()
        _ = try await client(fake).summary()
        let encoded = Data(F.adGuardCredential.utf8).base64EncodedString()
        for spec in await fake.receivedSpecs {
            let description = spec.redactedDescription
            #expect(!description.contains(encoded))
            #expect(!description.contains("fake-adguard-pass-1234"))
            #expect(description.contains("Authorization: <redacted>"))
        }
    }

    // MARK: Decoding

    @Test func summaryOfRealisticInstance() async throws {
        let summary = try await client(routes()).summary()
        #expect(summary.protectionEnabled)
        #expect(summary.running)
        #expect(summary.version == "v0.107.52")
        #expect(summary.dnsQueries == 24567)
        // Filtering + safe browsing + parental control; safe search is a rewrite, not a block.
        #expect(summary.blocked == 3120 + 12 + 3)
        #expect(summary.averageProcessingTime == 0.0213)
        #expect(summary.topQueried == [
            .init(domain: "connectivity-check.example.invalid", count: 1520),
            .init(domain: "api.example.invalid", count: 830),
            .init(domain: "cdn.example.invalid", count: 412),
        ])
        #expect(summary.topBlocked == [
            .init(domain: "ads.example.invalid", count: 410),
            .init(domain: "tracker.example.invalid", count: 120),
        ])
        let ratio = try #require(summary.blockedRatio)
        #expect(abs(ratio - 3135.0 / 24567.0) < 1e-9)
    }

    @Test func protectionDisabledIsReported() async throws {
        let summary = try await client(routes(status: .json(F.statusDisabledJSON))).summary()
        #expect(!summary.protectionEnabled)
    }

    @Test func topDomainsAreLimitedToTen() async throws {
        let summary = try await client(routes(stats: .json(F.statsJSON(topQueriedCount: 14)))).summary()
        #expect(summary.topQueried.count == 10)
        #expect(summary.topQueried.first == .init(domain: "d0.example.invalid", count: 1000))
        #expect(summary.topBlocked.isEmpty)
    }

    @Test func minimalStatsDefaultToZeroAndNegativeCountsAreClamped() async throws {
        let summary = try await client(routes(stats: .json(#"{"num_dns_queries":-5,"num_blocked_filtering":-1}"#))).summary()
        #expect(summary.dnsQueries == 0)
        #expect(summary.blocked == 0)
        #expect(summary.blockedRatio == nil)
        #expect(summary.averageProcessingTime == nil)
    }

    @Test func blockedRatioIsCappedAtOne() {
        #expect(AdGuardSummary(protectionEnabled: true, dnsQueries: 10, blocked: 50).blockedRatio == 1)
    }

    // MARK: Errors

    @Test func statusUnauthorizedCostsASingleRequest() async throws {
        let fake = routes(status: .unauthorized)
        await #expect(throws: ServiceProviderError.unauthorized) { try await client(fake).summary() }
        #expect(await fake.receivedPaths == [F.statusPath])
    }

    @Test func statusForbiddenIsDistinctAndNotRetried() async throws {
        let fake = routes(status: .forbidden)
        await #expect(throws: ServiceProviderError.forbidden) { try await client(fake).summary() }
        #expect(await fake.receivedPaths == [F.statusPath])
    }

    @Test func statsUnauthorizedAfterStatusIsNotRetried() async throws {
        let fake = routes(stats: .unauthorized)
        await #expect(throws: ServiceProviderError.unauthorized) { try await client(fake).summary() }
        #expect(await fake.receivedPaths == [F.statusPath, F.statsPath])
    }

    @Test func timeoutIsUnreachable() async throws {
        let fake = routes(status: .timeout)
        await #expect(throws: ServiceProviderError.unreachable) { try await client(fake).summary() }
        #expect(await fake.receivedPaths == [F.statusPath])
    }

    @Test func serverErrorIsUnexpectedStatus() async throws {
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) { try await client(routes(stats: .serverError)).summary() }
    }

    @Test(arguments: [FakeHTTPClient.Outcome.invalidJSON, .emptyBody, .json(#"{"running":true,"version":"v0.107.52"}"#)])
    func unusableStatusIsDecodingFailure(outcome: FakeHTTPClient.Outcome) async throws {
        let fake = routes(status: outcome)
        await #expect(throws: ServiceProviderError.decodingFailed) { try await client(fake).summary() }
        #expect(await fake.receivedPaths == [F.statusPath])
    }

    @Test func unusableStatsIsDecodingFailure() async throws {
        for outcome in [FakeHTTPClient.Outcome.invalidJSON, .emptyBody] {
            await #expect(throws: ServiceProviderError.decodingFailed) { try await client(routes(stats: outcome)).summary() }
        }
    }

    @Test func checkConnectionOnlyFetchesStatus() async throws {
        let fake = routes()
        try await client(fake).checkConnection()
        #expect(await fake.receivedPaths == [F.statusPath])
    }
}

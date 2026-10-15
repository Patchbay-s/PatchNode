import Foundation
import Testing
import PatchNodeCore
@testable import SecurityKit

private typealias F = SecurityFixtures

@Suite("CrowdSecClient")
struct CrowdSecClientTests {
    private func client(_ fake: FakeHTTPClient, apiKey: String = F.bouncerKey) -> CrowdSecClient {
        CrowdSecClient(baseURL: F.crowdSecURL, apiKey: apiKey, httpClient: fake)
    }

    private func decisions(_ fake: FakeHTTPClient) async throws -> [CrowdSecDecision] {
        try await client(fake).decisions(now: F.reference)
    }

    // MARK: Request

    @Test func requestsLocalDecisionsWithBouncerKey() async throws {
        let fake = FakeHTTPClient.json("[]")
        _ = try await decisions(fake)
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(await fake.receivedSpecs.count == 1)
        #expect(spec.method == .get)
        #expect(spec.url.host == "crowdsec.example.invalid")
        #expect(spec.url.port == 8080)
        #expect(spec.url.path == F.decisionsPath)
        #expect(queryItems(spec.url) == ["origins": "crowdsec,cscli"])
        #expect(spec.headers["X-Api-Key"] == F.bouncerKey)
        #expect(spec.body == nil)
    }

    @Test func redactedDescriptionHidesBouncerKey() async throws {
        let fake = FakeHTTPClient.json("[]")
        _ = try await decisions(fake)
        let description = try #require(await fake.receivedSpecs.first).redactedDescription
        #expect(!description.contains(F.bouncerKey))
        #expect(!description.contains("fake-bouncer"))
        #expect(description.contains("X-Api-Key: <redacted>"))
    }

    // MARK: Decoding

    @Test func decodesRealisticDecisions() async throws {
        let list = try await decisions(FakeHTTPClient.json(F.decisionsJSON))
        #expect(list.map(\.id) == ["1287", "1288", "1290", "1291"])

        let ip = list[0]
        #expect(ip.type == "ban")
        #expect(ip.scope == "Ip")
        #expect(ip.value == "203.0.113.45")
        #expect(ip.scenario == "crowdsecurity/http-probing")
        #expect(ip.origin == "crowdsec")
        #expect(!ip.simulated)
        #expect(ip.country == nil)
        let expiry = try #require(ip.expiresAt)
        #expect(abs(expiry.timeIntervalSince1970 - (referenceEpoch + 14390.304318377)) < 0.001)
    }

    @Test func untilWinsOverDuration() async throws {
        let range = try await decisions(FakeHTTPClient.json(F.decisionsJSON))[1]
        #expect(range.scope == "Range")
        #expect(range.expiresAt == date(referenceEpoch + 86400))
    }

    @Test func countryScopeExposesUppercasedCountry() async throws {
        let country = try await decisions(FakeHTTPClient.json(F.decisionsJSON))[2]
        #expect(country.country == "ZZ")
        #expect(country.origin == "cscli")
        #expect(country.expiresAt == date(referenceEpoch + 167 * 3600))
    }

    @Test func simulatedFlagAndOtherTypes() async throws {
        let simulated = try await decisions(FakeHTTPClient.json(F.decisionsJSON))[3]
        #expect(simulated.simulated)
        #expect(simulated.type == "captcha")
        #expect(simulated.expiresAt == date(referenceEpoch + 720))
    }

    @Test func minimalDecisionUsesDefaults() throws {
        let decision = try JSONDecoder().decode(CrowdSecDecision.self, from: Data(#"{"value":"203.0.113.9","scenario":""}"#.utf8))
        #expect(decision.id == "203.0.113.9")
        #expect(decision.type == "ban")
        #expect(decision.scope == "Ip")
        #expect(decision.scenario == nil)
        #expect(decision.expiresAt == nil)
    }

    @Test func uuidIsUsedWhenIDIsMissing() throws {
        let decision = try JSONDecoder().decode(CrowdSecDecision.self, from: Data(#"{"uuid":"fake-uuid-1","value":"203.0.113.9"}"#.utf8))
        #expect(decision.id == "fake-uuid-1")
    }

    @Test func invalidDurationLeavesExpiryUnknown() async throws {
        let list = try await decisions(FakeHTTPClient.json(#"[{"id":1,"value":"203.0.113.1","duration":"soon"}]"#))
        #expect(list.count == 1)
        #expect(list[0].expiresAt == nil)
    }

    @Test(arguments: ["null", "  null\n", "", " \n\t", "[]"])
    func nullOrEmptyBodyIsEmptyList(body: String) async throws {
        #expect(try await decisions(FakeHTTPClient.json(body)).isEmpty)
    }

    @Test func listIsCappedAtMaxDecisions() async throws {
        let list = try await decisions(FakeHTTPClient.json(F.decisionsJSON(count: CrowdSecClient.maxDecisions + 5)))
        #expect(list.count == CrowdSecClient.maxDecisions)
        #expect(list.first?.id == "0")
    }

    // MARK: Errors

    @Test func unauthorizedAndForbiddenAreDistinctAndNotRetried() async throws {
        for (outcome, expected) in [(FakeHTTPClient.Outcome.unauthorized, ServiceProviderError.unauthorized), (.forbidden, .forbidden)] {
            let fake = FakeHTTPClient(outcome)
            await #expect(throws: expected) { try await decisions(fake) }
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    @Test func timeoutIsUnreachable() async throws {
        let fake = FakeHTTPClient(.timeout)
        await #expect(throws: ServiceProviderError.unreachable) { try await decisions(fake) }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func serverErrorIsUnexpectedStatus() async throws {
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) { try await decisions(FakeHTTPClient(.serverError)) }
    }

    @Test(arguments: ["<html><body>Bad Gateway</body></html>", #"{"message":"access forbidden"}"#, "[{"])
    func invalidJSONIsDecodingFailure(body: String) async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) { try await decisions(FakeHTTPClient.json(body)) }
    }

    @Test func checkConnectionFetchesDecisions() async throws {
        let fake = FakeHTTPClient.json("null")
        try await client(fake).checkConnection()
        #expect(await fake.receivedPaths == [F.decisionsPath])
    }
}

@Suite("GoDuration")
struct GoDurationTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let text: String
        let seconds: Double
        var testDescription: String { "\"\(text)\"" }
    }

    @Test(arguments: [
        Case(text: "3h59m50.304318377s", seconds: 14390.304318377),
        Case(text: "1h", seconds: 3600),
        Case(text: "2m", seconds: 120),
        Case(text: "45s", seconds: 45),
        Case(text: "1.5s", seconds: 1.5),
        Case(text: "150ms", seconds: 0.15),
        Case(text: "10us", seconds: 0.00001),
        Case(text: "10µs", seconds: 0.00001),
        Case(text: "500ns", seconds: 0.0000005),
        Case(text: "1h2m3s4ms", seconds: 3723.004),
        Case(text: "167h0m0s", seconds: 601_200),
        Case(text: "-1m2s", seconds: -62),
        Case(text: "-150ms", seconds: -0.15),
        Case(text: "+5s", seconds: 5),
        Case(text: " 5s ", seconds: 5),
        Case(text: "0", seconds: 0),
        Case(text: "0s", seconds: 0),
    ])
    func parsesGoDurations(testCase: Case) throws {
        let seconds = try #require(GoDuration.seconds(testCase.text))
        #expect(abs(seconds - testCase.seconds) < 1e-9)
    }

    @Test(arguments: ["", " ", "-", "+", "abc", "5", "5x", "h", "1.2.3s", "5m5", "1d", "s5", "--5s", "1 h"])
    func rejectsInvalidDurations(text: String) {
        #expect(GoDuration.seconds(text) == nil)
    }
}

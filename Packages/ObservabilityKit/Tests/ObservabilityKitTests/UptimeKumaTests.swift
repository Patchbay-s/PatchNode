import Foundation
import Testing
import PatchNodeCore
@testable import ObservabilityKit

@Suite("UptimeKumaLocation")
struct UptimeKumaLocationTests {
    private func location(_ string: String) -> UptimeKumaLocation? {
        UptimeKumaLocation(statusPageURL: URL(string: string)!)
    }

    @Test func rootDeployment() throws {
        let location = try #require(location("https://kuma.example.invalid/status/homelab"))
        #expect(location.baseURL.absoluteString == "https://kuma.example.invalid")
        #expect(location.slug == "homelab")
    }

    @Test func subPathDeployment() throws {
        let location = try #require(location("https://lab.example.invalid/kuma/status/lab"))
        #expect(location.baseURL.absoluteString == "https://lab.example.invalid/kuma")
        #expect(location.slug == "lab")
    }

    @Test func trailingSlashQueryAndFragmentIgnored() throws {
        let location = try #require(location("https://kuma.example.invalid:8443/status/home-lab_2/?refresh=1#top"))
        #expect(location.baseURL.absoluteString == "https://kuma.example.invalid:8443")
        #expect(location.slug == "home-lab_2")
    }

    @Test(arguments: [
        "https://kuma.example.invalid/dashboard",
        "https://kuma.example.invalid/status",
        "https://kuma.example.invalid/status/",
        "https://kuma.example.invalid/",
        "https://kuma.example.invalid",
    ])
    func urlWithoutStatusSlugIsRejected(url: String) {
        #expect(location(url) == nil)
    }

    @Test(arguments: [
        "https://kuma.example.invalid/status/..",
        "https://kuma.example.invalid/status/caf%C3%A9",
        "https://kuma.example.invalid/status/a%20b",
        "https://kuma.example.invalid/status/a.b",
    ])
    func slugWithInvalidCharactersIsRejected(url: String) {
        #expect(location(url) == nil)
    }

    /// An encoded "/" must not split the slug: "a%2Fb" is rejected, not read as "a".
    @Test func encodedSlashInSlugIsRejected() {
        #expect(location("https://kuma.example.invalid/status/a%2Fb") == nil)
    }
}

@Suite("UptimeKumaClient")
struct UptimeKumaClientTests {
    private static let infoPath = "/api/status-page/homelab"
    private static let beatsPath = "/api/status-page/heartbeat/homelab"

    private func client(_ fake: FakeHTTPClient, url: URL = Fixtures.kumaStatusURL) throws -> UptimeKumaClient {
        UptimeKumaClient(location: try #require(UptimeKumaLocation(statusPageURL: url)), httpClient: fake)
    }

    private func fake(info: FakeHTTPClient.Outcome = .json(Fixtures.kumaStatusPage),
                      beats: FakeHTTPClient.Outcome = .json(Fixtures.kumaHeartbeats)) -> FakeHTTPClient {
        FakeHTTPClient(routes: [Self.infoPath: info, Self.beatsPath: beats])
    }

    @Test func pageRequestsBothEndpointsWithoutAuth() async throws {
        let fake = fake()
        _ = try await client(fake).page()
        let specs = await fake.receivedSpecs
        #expect(specs.map(\.url.absoluteString) == [
            "https://kuma.example.invalid/api/status-page/homelab",
            "https://kuma.example.invalid/api/status-page/heartbeat/homelab",
        ])
        #expect(specs.allSatisfy { $0.headers.isEmpty && $0.method == .get })
    }

    @Test func subPathDeploymentKeepsPrefix() async throws {
        let fake = FakeHTTPClient(routes: [
            "/kuma/api/status-page/lab": .json(Fixtures.kumaStatusPage),
            "/kuma/api/status-page/heartbeat/lab": .json(Fixtures.kumaHeartbeats),
        ])
        let page = try await client(fake, url: URL(string: "https://lab.example.invalid/kuma/status/lab")!).page()
        #expect(page.slug == "lab")
        #expect(await fake.receivedPaths == ["/kuma/api/status-page/lab", "/kuma/api/status-page/heartbeat/lab"])
    }

    @Test func checkConnectionUsesStatusPageEndpoint() async throws {
        let fake = fake()
        try await client(fake).checkConnection()
        #expect(await fake.receivedPaths == [Self.infoPath])
    }

    @Test func buildsMonitorsPerGroupWithLatestHeartbeat() async throws {
        let page = try await client(fake()).page()
        #expect(page.slug == "homelab")
        #expect(page.title == "Homelab")
        #expect(page.monitors.map(\.id) == [1, 2, 3, 4]) // entry without id dropped, "4" accepted
        #expect(page.monitors.map(\.group) == ["Services", "Services", "Infra", "Infra"])

        let nextcloud = page.monitors[0]
        #expect(nextcloud.name == "Nextcloud")
        #expect(nextcloud.status == .up)
        #expect(nextcloud.lastMessage == "200 - OK")
        #expect(nextcloud.lastPing == 38.5)
        let beat = try #require(nextcloud.lastBeat)
        #expect(abs(beat.timeIntervalSince1970 - (referenceEpoch + 0.123)) < 0.0005)
        #expect(nextcloud.uptime24h == 0.9993) // "1_720" ignored
        #expect(nextcloud.recentStatuses == [.up, .up])

        let jellyfin = page.monitors[1]
        #expect(jellyfin.status == .down)
        #expect(jellyfin.lastMessage == "timeout of 48000ms exceeded")
        #expect(jellyfin.lastPing == nil)
        #expect(jellyfin.lastBeat == date(referenceEpoch + 0.25)) // ISO form (Kuma 2.0)
        #expect(jellyfin.uptime24h == 0.95) // given as a string
        #expect(jellyfin.recentStatuses == [.up, .down])

        for monitor in page.monitors[2...] { // empty history / absent from heartbeatList
            #expect(monitor.status == nil)
            #expect(monitor.lastBeat == nil)
            #expect(monitor.uptime24h == nil)
            #expect(monitor.recentStatuses.isEmpty)
        }
        #expect(page.monitorsDown.map(\.name) == ["Jellyfin"])
    }

    @Test func emptyMessageIsNil() async throws {
        let beats = #"{"heartbeatList":{"1":[{"status":1,"time":"2024-05-01 10:00:00","msg":"","ping":5}]},"uptimeList":{}}"#
        let page = try await client(fake(beats: .json(beats))).page()
        #expect(page.monitors.first?.lastMessage == nil)
    }

    @Test func recentStatusesKeepLast30OldestFirst() async throws {
        // 40 beats: 10 down, then alternating up / pending, last one maintenance.
        var statuses = Array(repeating: 0, count: 10) + (10..<39).map { $0 % 2 == 0 ? 1 : 2 }
        statuses.append(3)
        let page = try await client(fake(beats: .json(Fixtures.kumaHeartbeats(monitorID: 1, statuses: statuses)))).page()
        let monitor = try #require(page.monitors.first)
        let expected = statuses.suffix(30).compactMap(UptimeKumaPage.Monitor.Status.init(rawValue:))
        #expect(monitor.recentStatuses.count == 30)
        #expect(monitor.recentStatuses == expected)
        #expect(!monitor.recentStatuses.contains(.down))
        #expect(monitor.status == .maintenance)
        #expect(monitor.lastMessage == "beat 39")
    }

    @Test(arguments: [
        ("2024-05-01 10:00:00.123", referenceEpoch + 0.123),
        ("2024-05-01 10:00:00", referenceEpoch),
        ("2024-05-01T10:00:00.123Z", referenceEpoch + 0.123),
        ("2024-05-01T12:00:00+02:00", referenceEpoch),
        (" 2024-05-01 10:00:00 ", referenceEpoch),
    ])
    func parsesKumaTimestamps(text: String, expected: TimeInterval) throws {
        let parsed = try #require(UptimeKumaClient.parseTime(text))
        #expect(abs(parsed.timeIntervalSince1970 - expected) < 0.0005)
    }

    @Test(arguments: ["", "yesterday", "2024-13-01 10:00:00", "2024-05-01"])
    func rejectsInvalidTimestamps(text: String) {
        #expect(UptimeKumaClient.parseTime(text) == nil)
    }

    @Test func emptyPayloadsGiveEmptyPageTitledWithSlug() async throws {
        let page = try await client(fake(info: .json("{}"), beats: .json("{}"))).page()
        #expect(page.title == "homelab")
        #expect(page.monitors.isEmpty)
        #expect(page.monitorsDown.isEmpty)
    }

    @Test func invalidJSONAndEmptyBodyAreDecodingFailures() async throws {
        for outcome in [FakeHTTPClient.Outcome.invalidJSON, .emptyBody] {
            await #expect(throws: ServiceProviderError.decodingFailed) { _ = try await client(fake(info: outcome)).page() }
            await #expect(throws: ServiceProviderError.decodingFailed) { _ = try await client(fake(beats: outcome)).page() }
        }
    }

    @Test(arguments: [
        (FakeHTTPClient.Outcome.unauthorized, ServiceProviderError.unauthorized),
        (.forbidden, .forbidden),
        (.timeout, .unreachable),
        (.json(#"{"ok":false,"msg":"Status Page Not Found"}"#, status: 404), .unexpectedStatus(404)),
    ])
    func failuresAreMappedWithoutRetry(outcome: FakeHTTPClient.Outcome, expected: ServiceProviderError) async throws {
        let infoFails = fake(info: outcome)
        await #expect(throws: expected) { _ = try await client(infoFails).page() }
        #expect(await infoFails.receivedPaths == [Self.infoPath])

        let beatsFail = fake(beats: outcome)
        await #expect(throws: expected) { _ = try await client(beatsFail).page() }
        #expect(await beatsFail.receivedPaths == [Self.infoPath, Self.beatsPath])
    }
}

import Foundation
import Testing
import PatchNodeCore
@testable import HomeServicesKit

@Suite("GlancesClient")
struct GlancesClientTests {
    private static let v4Path = "/api/4/all"
    private static let v3Path = "/api/3/all"

    private func client(_ fake: FakeHTTPClient, credential: String = "", baseURL: URL = Fixtures.glancesURL) -> GlancesClient {
        GlancesClient(baseURL: baseURL, credential: credential, httpClient: fake)
    }

    // MARK: Glances 4

    @Test func summaryDecodesRealisticV4Payload() async throws {
        let fake = FakeHTTPClient(routes: [Self.v4Path: .json(Fixtures.glancesV4)])
        let summary = try await client(fake).summary()
        #expect(await fake.receivedPaths == [Self.v4Path])
        #expect(await fake.receivedSpecs.first?.method == .get)

        #expect(summary.apiVersion == 4)
        #expect(summary.hostname == "nas")
        #expect(summary.system == "Debian GNU/Linux 12")
        #expect(summary.cpuPercent == 12.3)
        #expect(summary.cpuCores == 8)
        #expect(summary.memoryPercent == 43.3)
        #expect(summary.memoryTotal == 16_681_451_520)
        #expect(summary.memoryUsed == 7_228_006_400)
        #expect(summary.swapPercent == 3.2)
        #expect(summary.load1 == 0.52)
        #expect(summary.load5 == 0.61)
        #expect(summary.load15 == 0.58)
        #expect(summary.uptime == "5 days, 3:12:09")

        #expect(summary.fileSystems.map(\.mountPoint) == ["/", "/srv/data", "/boot/efi"], "entry without mnt_point dropped")
        let data = try #require(summary.fileSystems.first { $0.mountPoint == "/srv/data" })
        #expect(data.device == "/dev/md0")
        #expect(data.size == 3_998_614_962_176)
        #expect(data.used == 3_558_767_316_992)
        #expect(data.percent == 89.0)
        #expect(summary.fullFileSystems.map(\.mountPoint) == ["/srv/data"])

        #expect(summary.temperatures == [
            GlancesSummary.Sensor(label: "Package id 0", value: 52, unit: "C"),
            GlancesSummary.Sensor(label: "acpitz 1", value: 27.8, unit: "C"),
            GlancesSummary.Sensor(label: "nvme0 Composite", value: 41.9, unit: "C"),
        ], "fan, battery and null-valued sensors excluded")
    }

    @Test func summaryWithoutCredentialSendsNoAuthorizationHeader() async throws {
        let fake = FakeHTTPClient(routes: [Self.v4Path: .json(Fixtures.glancesV4)])
        _ = try await client(fake, credential: "").summary()
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.headers["Authorization"] == nil)
        #expect(spec.headers.isEmpty)
    }

    @Test func summaryWithCredentialSendsBasicHeaderAndRedactsIt() async throws {
        let fake = FakeHTTPClient(routes: [Self.v4Path: .json(Fixtures.glancesV4)])
        _ = try await client(fake, credential: Fixtures.glancesCredential).summary()
        let spec = try #require(await fake.receivedSpecs.first)
        let encoded = Data(Fixtures.glancesCredential.utf8).base64EncodedString()
        #expect(spec.headers["Authorization"] == "Basic \(encoded)")
        #expect(!spec.redactedDescription.contains(encoded))
        #expect(!spec.redactedDescription.contains("fake-password-1234"))
        #expect(spec.redactedDescription.contains("Authorization: <redacted>"))
    }

    @Test func summaryUnderASubpath() async throws {
        let fake = FakeHTTPClient(routes: ["/glances/api/4/all": .json(Fixtures.glancesV4)])
        _ = try await client(fake, baseURL: URL(string: "https://proxy.example.invalid/glances/")!).summary()
        #expect(await fake.receivedURLs.map(\.absoluteString) == ["https://proxy.example.invalid/glances/api/4/all"])
    }

    // MARK: Fallback to Glances 3

    @Test func summaryFallsBackToV3On404() async throws {
        let fake = FakeHTTPClient(routes: [
            Self.v4Path: .json(Fixtures.notFound, status: 404),
            Self.v3Path: .json(Fixtures.glancesV3),
        ])
        let summary = try await client(fake, credential: Fixtures.glancesCredential).summary()
        #expect(await fake.receivedPaths == [Self.v4Path, Self.v3Path])
        let specs = await fake.receivedSpecs
        #expect(specs.allSatisfy { $0.headers["Authorization"]?.hasPrefix("Basic ") == true })

        #expect(summary.apiVersion == 3)
        #expect(summary.hostname == "raspberrypi")
        #expect(summary.system == "Linux", "empty linux_distro falls back to os_name")
        #expect(summary.cpuPercent == 71.4)
        #expect(summary.cpuCores == 4, "from core.log when load.cpucore is missing")
        #expect(summary.memoryPercent == 92.0)
        #expect(summary.swapPercent == 50.0)
        #expect(summary.load1 == 2.1)
        #expect(summary.uptime == "12 days, 0:04:51")
        #expect(summary.fileSystems.map(\.mountPoint) == ["/"])
        #expect(summary.fullFileSystems.map(\.mountPoint) == ["/"], "85 % is the inclusive threshold")
        #expect(summary.temperatures == [GlancesSummary.Sensor(label: "cpu_thermal 0", value: 131, unit: "F")])
    }

    @Test func summaryV3404TooSurfacesUnexpectedStatus() async throws {
        let fake = FakeHTTPClient(.json(Fixtures.notFound, status: 404))
        await #expect(throws: ServiceProviderError.unexpectedStatus(404)) { try await client(fake).summary() }
        #expect(await fake.receivedPaths == [Self.v4Path, Self.v3Path])
    }

    @Test func summaryV3FailureAfterFallbackIsPropagated() async throws {
        let fake = FakeHTTPClient(routes: [
            Self.v4Path: .json(Fixtures.notFound, status: 404),
            Self.v3Path: .unauthorized,
        ])
        await #expect(throws: ServiceProviderError.unauthorized) { try await client(fake).summary() }
        #expect(await fake.receivedPaths == [Self.v4Path, Self.v3Path])
    }

    @Test func summaryDoesNotFallBackOnOtherFailures() async throws {
        let cases: [(FakeHTTPClient.Outcome, ServiceProviderError)] = [
            (.unauthorized, .unauthorized),
            (.forbidden, .forbidden),
            (.timeout, .unreachable),
            (.serverError, .unexpectedStatus(500)),
            (.invalidJSON, .decodingFailed),
            (.emptyBody, .decodingFailed),
            (.json(Fixtures.notGlances), .decodingFailed),
        ]
        for (outcome, expected) in cases {
            let fake = FakeHTTPClient(routes: [Self.v4Path: outcome, Self.v3Path: .json(Fixtures.glancesV3)])
            await #expect(throws: expected) { try await client(fake).summary() }
            #expect(await fake.receivedPaths == [Self.v4Path], "no fallback nor retry for \(expected)")
        }
    }

    // MARK: Decoding edge cases

    @Test(arguments: [Fixtures.notGlances, "{}", "[]", "null", #""API running""#, #"{"system":{"hostname":"nas"},"uptime":"1 day"}"#])
    func nonGlancesJSONIsDecodingFailed(body: String) async throws {
        let fake = FakeHTTPClient(routes: [Self.v4Path: .json(body)])
        await #expect(throws: ServiceProviderError.decodingFailed) { try await client(fake).summary() }
    }

    @Test func minimalPayloadWithOnlyMemoryDecodes() async throws {
        let fake = FakeHTTPClient(routes: [Self.v4Path: .json(#"{"mem":{"percent":"55.5","total":"1000"}}"#)])
        let summary = try await client(fake).summary()
        #expect(summary.memoryPercent == 55.5, "numeric strings accepted")
        #expect(summary.memoryTotal == 1000)
        #expect(summary.cpuPercent == nil)
        #expect(summary.hostname == nil)
        #expect(summary.system == nil)
        #expect(summary.fileSystems.isEmpty)
        #expect(summary.temperatures.isEmpty)
    }

    @Test func malformedPluginsAreIgnored() async throws {
        let body = #"{"cpu":{"total":5},"fs":{"unexpected":"object"},"sensors":"none","system":["x"]}"#
        let summary = try await client(FakeHTTPClient(routes: [Self.v4Path: .json(body)])).summary()
        #expect(summary.cpuPercent == 5)
        #expect(summary.fileSystems.isEmpty)
        #expect(summary.temperatures.isEmpty)
        #expect(summary.hostname == nil)
    }

    // MARK: checkConnection

    @Test func checkConnectionSucceedsOnV4() async throws {
        let fake = FakeHTTPClient(routes: [Self.v4Path: .json(Fixtures.glancesV4)])
        try await client(fake).checkConnection()
        #expect(await fake.receivedPaths == [Self.v4Path])
    }

    @Test func checkConnectionFailuresWithoutRetry() async throws {
        let cases: [(FakeHTTPClient.Outcome, ServiceProviderError)] = [
            (.unauthorized, .unauthorized),
            (.forbidden, .forbidden),
            (.timeout, .unreachable),
            (.invalidJSON, .decodingFailed),
            (.emptyBody, .decodingFailed),
        ]
        for (outcome, expected) in cases {
            let fake = FakeHTTPClient(outcome)
            await #expect(throws: expected) { try await client(fake).checkConnection() }
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    // MARK: fullFileSystems

    @Test func fullFileSystemsUsesInclusive85PercentThreshold() {
        let summary = GlancesSummary(fileSystems: [
            .init(mountPoint: "/a", percent: 84.99),
            .init(mountPoint: "/b", percent: 85),
            .init(mountPoint: "/c", percent: 99.9),
            .init(mountPoint: "/d", percent: nil),
        ])
        #expect(summary.fullFileSystems.map(\.mountPoint) == ["/b", "/c"])
        #expect(GlancesSummary.diskAlertPercent == 85)
        #expect(GlancesSummary.memoryAlertPercent == 90)
    }
}

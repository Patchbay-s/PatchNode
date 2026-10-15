import Foundation
import Testing
import PatchNodeCore
@testable import ObservabilityKit

@Suite("AlertmanagerClient")
struct AlertmanagerClientTests {
    private func client(_ fake: FakeHTTPClient, credential: String = "") -> AlertmanagerClient {
        AlertmanagerClient(baseURL: Fixtures.alertmanagerURL, credential: credential, httpClient: fake)
    }

    private func alert(_ json: String) async throws -> ObservabilityAlert {
        let alerts = try await client(.json("[\(json)]")).alerts()
        return try #require(alerts.first)
    }

    @Test func alertsRequestsActiveUnsilencedUninhibited() async throws {
        let fake = FakeHTTPClient.json("[]")
        _ = try await client(fake).alerts()
        let url = try #require(await fake.receivedURLs.first)
        #expect(url.host == "alertmanager.example.invalid")
        #expect(url.path == "/api/v2/alerts")
        #expect(queryItems(url) == ["active": "true", "silenced": "false", "inhibited": "false"])
        #expect(await fake.receivedSpecs.first?.headers.isEmpty == true)
    }

    @Test func includeSilencedAsksForAndKeepsSuppressedAlerts() async throws {
        let fake = FakeHTTPClient.json(Fixtures.alertmanagerAlerts)
        let alerts = try await client(fake).alerts(includeSilenced: true)
        let url = try #require(await fake.receivedURLs.first)
        #expect(queryItems(url) == ["active": "true", "silenced": "true", "inhibited": "true"])
        #expect(alerts.map(\.name).contains("Silenced"))
    }

    @Test func basicHeaderWhenCredentialPresentAndMaskedInDescription() async throws {
        let fake = FakeHTTPClient.json("[]")
        _ = try await client(fake, credential: Fixtures.basicCredential).alerts()
        let spec = try #require(await fake.receivedSpecs.first)
        let encoded = Data(Fixtures.basicCredential.utf8).base64EncodedString()
        #expect(spec.headers["Authorization"] == "Basic \(encoded)")
        #expect(!spec.redactedDescription.contains(encoded))
    }

    @Test func checkConnectionUsesStatusEndpoint() async throws {
        let fake = FakeHTTPClient.json(#"{"cluster":{"status":"ready"},"versionInfo":{"version":"0.27.0"}}"#)
        try await client(fake).checkConnection()
        #expect(await fake.receivedPaths == ["/api/v2/status"])
    }

    @Test func normalizesAlertsAndFiltersSuppressed() async throws {
        let alerts = try await client(.json(Fixtures.alertmanagerAlerts)).alerts()
        #expect(alerts.map(\.name) == ["InstanceDown", "DiskAlmostFull", "BackupStale"])

        let down = alerts[0]
        #expect(down.id == "alertmanager|a1b2c3d4e5f60718")
        #expect(down.source == .alertmanager)
        #expect(down.severity == .critical)
        #expect(down.summary == "Instance node.example.invalid:9100 down") // summary > description
        let since = try #require(down.since)
        #expect(abs(since.timeIntervalSince1970 - (referenceEpoch - 287.655)) < 0.0005)
        #expect(down.labels["job"] == "node")

        let disk = alerts[1]
        #expect(disk.severity == .warning)
        #expect(disk.summary == "Disk /data at 91%") // description > message
        #expect(disk.since == date(referenceEpoch - 7200))

        let backup = alerts[2]
        #expect(backup.severity == .info)
        #expect(backup.summary == "Backup older than 24 h")
        #expect(backup.since == date(referenceEpoch - 18_000 + 0.5)) // 07:00:00.5+02:00
    }

    @Test func idFallsBackToDeterministicLabelDigest() async throws {
        let first = try await alert(#"{"labels":{"alertname":"DiskAlmostFull","severity":"warning","instance":"nas.example.invalid:9100"},"status":{"state":"active"}}"#)
        let reordered = try await alert(#"{"labels":{"instance":"nas.example.invalid:9100","severity":"warning","alertname":"DiskAlmostFull"},"status":{"state":"active"}}"#)
        #expect(first.id == "alertmanager|DiskAlmostFull,alertname=DiskAlmostFull,instance=nas.example.invalid:9100,severity=warning")
        #expect(first.id == reordered.id)
    }

    @Test func nameFallsBackToRuleTitleThenGeneric() async throws {
        #expect(try await alert(#"{"labels":{"__alert_rule_title__":"High CPU"}}"#).name == "High CPU")
        let bare = try await alert(#"{"labels":{}}"#)
        #expect(bare.name == "Alert")
        #expect(bare.severity == .warning)
        #expect(bare.summary == nil)
        #expect(bare.since == nil)
    }

    @Test(arguments: [
        ("critical", ObservabilityAlert.Severity.critical), ("page", .critical), ("error", .critical), ("CRITICAL", .critical),
        ("info", .info), ("none", .info), ("low", .info),
        ("warning", .warning), ("major", .warning),
    ])
    func severityLabelMapping(label: String, expected: ObservabilityAlert.Severity) async throws {
        #expect(ObservabilityAlert.Severity(label: label) == expected)
        let decoded = try await alert(#"{"fingerprint":"f1","labels":{"alertname":"X","severity":"\#(label)"}}"#)
        #expect(decoded.severity == expected)
    }

    @Test func missingSeverityIsWarning() {
        #expect(ObservabilityAlert.Severity(label: nil) == .warning)
    }

    @Test func invalidStartsAtGivesNilSince() async throws {
        #expect(try await alert(#"{"labels":{"alertname":"X"},"startsAt":"yesterday"}"#).since == nil)
    }

    @Test func emptyListIsEmpty() async throws {
        #expect(try await client(.json("[]")).alerts().isEmpty)
    }

    @Test func invalidJSONAndEmptyBodyAreDecodingFailures() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) { _ = try await client(FakeHTTPClient(.invalidJSON)).alerts() }
        await #expect(throws: ServiceProviderError.decodingFailed) { _ = try await client(FakeHTTPClient(.emptyBody)).alerts() }
        // An object instead of the expected array.
        await #expect(throws: ServiceProviderError.decodingFailed) { _ = try await client(.json(#"{"alerts":[]}"#)).alerts() }
    }

    @Test(arguments: [
        (FakeHTTPClient.Outcome.unauthorized, ServiceProviderError.unauthorized),
        (.forbidden, .forbidden),
        (.timeout, .unreachable),
        (.serverError, .unexpectedStatus(500)),
    ])
    func failuresAreMappedWithoutRetry(outcome: FakeHTTPClient.Outcome, expected: ServiceProviderError) async throws {
        let fake = FakeHTTPClient(outcome)
        await #expect(throws: expected) { _ = try await client(fake, credential: Fixtures.basicCredential).alerts() }
        #expect(await fake.receivedSpecs.count == 1)
    }
}

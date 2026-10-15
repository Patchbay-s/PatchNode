import Foundation
import Testing
@testable import PatchNodeCore

/// Self-signed test certificates (EC P-256) for `*.example.invalid`, made with
/// `openssl ca -startdate 20260101000000Z -enddate …`.
private enum TestCertificates {
    /// notAfter 2027-03-15 12:00:00 UTC, encoded as UTCTime.
    static let utcTime = Data(base64Encoded: "MIIBIzCBygIBATAKBggqhkjOPQQDAjAeMRwwGgYDVQQDDBNwdmUuZXhhbXBsZS5pbnZhbGlkMB4XDTI2MDEwMTAwMDAwMFoXDTI3MDMxNTEyMDAwMFowHjEcMBoGA1UEAwwTcHZlLmV4YW1wbGUuaW52YWxpZDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABAgx7ZSdUdzq/chwlhMH1Oadfb6Rnkdxnz32DknXKYaDGeaxvhyHyBrEqDwn3A+8oYqwFx3fGoNxJ/jhVb9V/5owCgYIKoZIzj0EAwIDSAAwRQIgRs0rzBDSZ7qug4/z4QnUzNmHndgnh6itPRs8yetlx3YCIQClxXnwLWIWImad2msznhllMmxTfpPm2Ko3ZCQgazsjnQ==")!
    /// notAfter 2051-06-01 08:30:00 UTC, encoded as GeneralizedTime (after 2049).
    static let generalizedTime = Data(base64Encoded: "MIIBJTCBzAIBAjAKBggqhkjOPQQDAjAeMRwwGgYDVQQDDBNuYXMuZXhhbXBsZS5pbnZhbGlkMCAXDTI2MDEwMTAwMDAwMFoYDzIwNTEwNjAxMDgzMDAwWjAeMRwwGgYDVQQDDBNuYXMuZXhhbXBsZS5pbnZhbGlkMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEqUdCQbYMxIjiFN4IwJn8GvEgyKdGV6+9zCaA0aK+VqbRYb/R+MgyoAHz1VeI1aWmBI/hOulJTzyYelEXiV6VIjAKBggqhkjOPQQDAgNIADBFAiEAhlz14h/ZThzRpO16FXPOM6AbeHQ2KIbXNMCTWVvNa8kCIHkKyh2+lfzJLU5zSYYufFOLb01qgi9D2UPqni9YYOu2")!
}

private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

struct X509ValidityTests {
    @Test func readsUTCTimeNotAfter() {
        #expect(X509Validity.notAfter(der: TestCertificates.utcTime) == utc(2027, 3, 15, 12))
    }

    @Test func readsGeneralizedTimeNotAfter() {
        #expect(X509Validity.notAfter(der: TestCertificates.generalizedTime) == utc(2051, 6, 1, 8, 30))
    }

    @Test func rejectsGarbageAndTruncatedData() {
        #expect(X509Validity.notAfter(der: Data()) == nil)
        #expect(X509Validity.notAfter(der: Data([0x30, 0x82, 0xFF, 0xFF])) == nil)
        #expect(X509Validity.notAfter(der: Data("not a certificate".utf8)) == nil)
        let truncated = TestCertificates.utcTime.prefix(TestCertificates.utcTime.count / 2)
        #expect(X509Validity.notAfter(der: Data(truncated)) == nil)
    }

    @Test func rejectsMalformedTimes() {
        var reader = DERReader(bytes: [0x17, 0x0D] + Array("271315120000Z".utf8))  // month 13
        #expect(reader.readTime() == nil)
        reader = DERReader(bytes: [0x17, 0x0C] + Array("2703151200Z0".utf8))       // wrong length
        #expect(reader.readTime() == nil)
        reader = DERReader(bytes: [0x18, 0x0F] + Array("20270315120000+".utf8))    // no Z
        #expect(reader.readTime() == nil)
        reader = DERReader(bytes: [0x17, 0x0D] + Array("490101000000Z".utf8))      // 2049
        #expect(reader.readTime() == utc(2049, 1, 1))
        reader = DERReader(bytes: [0x17, 0x0D] + Array("500101000000Z".utf8))      // 1950
        #expect(reader.readTime() == utc(1950, 1, 1))
    }
}

struct CertificateExpiryTests {
    let now = utc(2026, 10, 1)

    private func expiry(inDays days: Double) -> CertificateExpiry {
        CertificateExpiry(notAfter: now.addingTimeInterval(days * 86_400), observedAt: now)
    }

    @Test func levelsAt14And7Days() {
        #expect(expiry(inDays: 30).level(now: now) == .ok)
        #expect(expiry(inDays: 14).level(now: now) == .ok)
        #expect(expiry(inDays: 13.9).level(now: now) == .warning)
        #expect(expiry(inDays: 7).level(now: now) == .warning)
        #expect(expiry(inDays: 6.9).level(now: now) == .critical)
        #expect(expiry(inDays: -1).level(now: now) == .critical)
    }

    @Test func daysRemainingRoundsDown() {
        #expect(expiry(inDays: 13.9).daysRemaining(now: now) == 13)
        #expect(expiry(inDays: 0.5).daysRemaining(now: now) == 0)
        #expect(expiry(inDays: -0.5).daysRemaining(now: now) == -1)
        #expect(!expiry(inDays: 20).needsAttention(now: now))
        #expect(expiry(inDays: 10).needsAttention(now: now))
    }
}

struct CertificateRegistryTests {
    let now = utc(2026, 10, 1)

    @Test func recordsByOriginCaseInsensitiveWithDefaultPort() throws {
        let registry = CertificateRegistry()
        registry.record(host: "proxmox.example.invalid", port: 8006, notAfter: utc(2027, 1, 1), at: now)
        registry.record(host: "grafana.example.invalid", port: 443, notAfter: utc(2026, 12, 1), at: now)
        #expect(registry.expiry(for: URL(string: "https://proxmox.example.invalid:8006/api2/json")!)?.notAfter == utc(2027, 1, 1))
        #expect(registry.expiry(for: URL(string: "https://proxmox.example.invalid/")!) == nil)
        #expect(registry.expiry(for: URL(string: "https://grafana.example.invalid/d/x")!)?.notAfter == utc(2026, 12, 1))
    }

    @Test func latestObservationWins() {
        let registry = CertificateRegistry()
        registry.record(host: "ha.example.invalid", port: 443, notAfter: utc(2026, 10, 5), at: now)
        registry.record(host: "ha.example.invalid", port: 443, notAfter: utc(2027, 1, 3), at: now)
        #expect(registry.expiry(for: URL(string: "https://ha.example.invalid")!)?.notAfter == utc(2027, 1, 3))
    }

    @Test func removesOneOrigin() {
        let registry = CertificateRegistry()
        registry.record(host: "ha.example.invalid", port: 443, notAfter: utc(2027, 1, 3), at: now)
        registry.record(host: "proxmox.example.invalid", port: 8006, notAfter: utc(2027, 1, 3), at: now)
        registry.remove(for: URL(string: "https://HA.example.invalid/api")!)
        #expect(registry.expiry(for: URL(string: "https://ha.example.invalid")!) == nil)
        #expect(registry.expiry(for: URL(string: "https://proxmox.example.invalid:8006")!) != nil)
    }

    @Test func ignoresNonHTTPSAndClears() {
        let registry = CertificateRegistry()
        registry.record(host: "ha.example.invalid", port: 443, notAfter: utc(2027, 1, 3), at: now)
        #expect(registry.expiry(for: URL(string: "http://ha.example.invalid")!) == nil)
        registry.removeAll()
        #expect(registry.expiry(for: URL(string: "https://ha.example.invalid")!) == nil)
    }

    @Test func demoServicesHaveOneCertificateAboutToExpire() {
        let registry = CertificateRegistry()
        let levels = ServiceKind.allCases.compactMap { kind in
            registry.expiry(for: DemoCatalog.url(for: kind), now: now)?.level(now: now)
        }
        #expect(levels.count == ServiceKind.allCases.count)
        #expect(registry.expiry(for: DemoCatalog.url(for: .uptimeKuma), now: now)?.level(now: now) == .warning)
        #expect(levels.filter { $0 != .ok }.count == 1)
    }

    @Test func attentionListsExpiringOnesSoonestFirstAndSkipsTailscale() {
        let registry = CertificateRegistry()
        registry.record(host: "a.example.invalid", port: 443, notAfter: now.addingTimeInterval(10 * 86_400), at: now)
        registry.record(host: "b.example.invalid", port: 443, notAfter: now.addingTimeInterval(3 * 86_400), at: now)
        registry.record(host: "c.example.invalid", port: 443, notAfter: now.addingTimeInterval(90 * 86_400), at: now)
        registry.record(host: "api.tailscale.com", port: 443, notAfter: now.addingTimeInterval(2 * 86_400), at: now)
        let items: [(ServiceKind, String)] = [
            (.grafana, "https://a.example.invalid"), (.homeAssistant, "https://b.example.invalid"),
            (.prometheus, "https://c.example.invalid"), (.tailscale, "https://api.tailscale.com"),
            (.glances, "https://never-seen.example.invalid"),
        ]
        let result = registry.attention(among: items, now: now, kind: \.0, url: { URL(string: $0.1)! })
        #expect(result.map(\.item.1) == ["https://b.example.invalid", "https://a.example.invalid"])
        #expect(result.map { $0.expiry.level(now: now) } == [.critical, .warning])
    }

    @Test func certificateConditionsChangeKeyAtSevenDays() {
        let registry = CertificateRegistry()
        registry.record(host: "a.example.invalid", port: 443, notAfter: now.addingTimeInterval(10 * 86_400), at: now)
        let items: [(String, ServiceKind, String)] = [("svc-a", .grafana, "https://a.example.invalid")]
        let first = registry.watchedConditions(among: items, now: now, id: \.0, kind: \.1, url: { URL(string: $0.2)! })
        let later = registry.watchedConditions(among: items, now: now.addingTimeInterval(4 * 86_400), id: \.0, kind: \.1, url: { URL(string: $0.2)! })
        #expect(first.count == 1 && later.count == 1)
        #expect(first.first?.kind == .certificateExpiring)
        #expect(first != later)
        #expect(first.first?.scope == "svc-a")
    }
}

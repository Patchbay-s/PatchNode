import Foundation
import Testing
@testable import PatchNodeCore

struct SupportReportTests {
    let pveID = UUID()
    let dockerID = UUID()

    private func request(_ outcome: RequestLog.Outcome, status: Int?, path: String) -> RequestLog.Kind {
        .request(RequestLog.Request(
            method: "GET", path: path, attempt: 1, statusCode: status, contentType: "text/html",
            server: "openresty/1.25 on npm.example.invalid", networkProtocol: "h2", reusedConnection: true,
            localPort: 51234, duration: 0.2, outcome: outcome, freshConnection: false, context: .normal
        ))
    }

    private func report(log: RequestLog) -> SupportReport {
        SupportReport(
            appVersion: "1.0 (3)", systemVersion: "27.0", deviceModel: "iPhone18,1", language: "fr-FR",
            services: [(pveID, .proxmoxVE), (dockerID, .dockerSocketProxy), (UUID(), .proxmoxVE)],
            demoMode: false, log: log.entries()
        )
    }

    @Test func containsOnlyTypesVersionsAndErrorClassifications() {
        let log = RequestLog()
        let pve = RequestLog.Label(serviceID: pveID, serviceName: "Test Site node-1 test-user", baseURL: URL(string: "https://proxmox.example.invalid:8006/test-prefix"))
        let docker = RequestLog.Label(serviceID: dockerID, serviceName: "Test storage", baseURL: URL(string: "https://docker.example.invalid"))
        log.append(request(.ok, status: 200, path: "/api2/json/cluster/resources"), label: pve)
        log.append(request(.blockedByProxy, status: 403, path: "/api2/json/nodes/node-1/qemu/100/status/current?token"), label: pve)
        log.append(request(.unauthorized, status: 401, path: "/containers/json?all"), label: docker)
        let text = report(log: log).text()
        #expect(text.contains("proxmoxVE ×2"))
        #expect(text.contains("dockerSocketProxy ×1"))
        #expect(text.contains("proxmoxVE: blockedByProxy, HTTP 403"))
        #expect(text.contains("dockerSocketProxy: unauthorized, HTTP 401"))
        #expect(text.contains("Demo mode: no"))
        let forbidden = [
            "Test Site", "node-1", "test-user", "Test storage", "192.0.2.23", "proxmox.example.invalid", "test-prefix", "/api2", "/containers",
            "openresty", "51234", "token", "https", pveID.uuidString, dockerID.uuidString, "text/html",
        ]
        for value in forbidden {
            #expect(!text.contains(value), "report leaks \(value)")
        }
    }

    @Test func keepsTheLatestErrorPerTypeAndSkipsSuccessesAndCancellations() {
        let log = RequestLog()
        let label = RequestLog.Label(serviceID: pveID, serviceName: "x")
        log.append(request(.timedOut, status: nil, path: "/a"), label: label, date: .now.addingTimeInterval(-600))
        log.append(request(.misdirected, status: 421, path: "/a"), label: label, date: .now.addingTimeInterval(-60))
        log.append(request(.cancelled, status: nil, path: "/a"), label: label)
        log.append(request(.ok, status: 200, path: "/a"), label: label)
        let errors = report(log: log).recentErrors
        #expect(errors.count == 1)
        #expect(errors.first?.outcome == .misdirected)
        #expect(errors.first?.statusCode == 421)
    }

    @Test func unknownServicesAndEventsAreIgnored() {
        let log = RequestLog()
        log.append(request(.unauthorized, status: 401, path: "/a"), label: RequestLog.Label(serviceID: UUID(), serviceName: "removed"))
        log.append(.event(.sessionsReset), label: nil)
        #expect(report(log: log).recentErrors.isEmpty)
        #expect(report(log: log).text().contains("  none"))
    }

    @Test func systemValuesAreSanitised() {
        let report = SupportReport(
            appVersion: "1.0\n<script>https://evil.example", systemVersion: "27.0", deviceModel: "iPhone",
            language: "en", services: [], demoMode: true, log: []
        )
        #expect(!report.appVersion.contains("\n"))
        #expect(!report.appVersion.contains("/"))
        #expect(!report.appVersion.contains(":"))
        #expect(report.text().contains("Service types: none"))
    }

    @Test func messageBodyAttachesTheReportOnlyWhenChosen() {
        let report = report(log: RequestLog())
        #expect(SupportMessage.body(description: "  It fails  ", report: nil) == "It fails")
        #expect(SupportMessage.body(description: "It fails", report: report).contains("PatchNode diagnostic report"))
        #expect(SupportMessage.subject(category: .setupHelp, kind: .proxmoxVE) == "PatchNode – Setup help – proxmoxVE")
    }

    @Test func mailtoLinkIsEncodedAndRejectsInvalidAddresses() throws {
        let url = try #require(SupportMessage.mailtoURL(to: "support@example.com", subject: "PatchNode – Bug", body: "Line 1\nLine 2 & more"))
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.hasPrefix("mailto:support@example.com?subject="))
        #expect(!url.absoluteString.contains(" "))
        #expect(SupportMessage.mailtoURL(to: "not an address", subject: "", body: "") == nil)
        #expect(SupportMessage.mailtoURL(to: "a@b.example?cc=x@y.example", subject: "", body: "") == nil)
        #expect(SupportMessage.mailtoURL(to: "a@b.example,x@y.example", subject: "", body: "") == nil)
        #expect(SupportMessage.mailtoURL(to: "a@b.example\nBcc: x@y.example", subject: "", body: "") == nil)
        let injected = try #require(SupportMessage.mailtoURL(to: "support@example.com", subject: "s", body: "x&cc=evil@example.com&bcc=a+b%20c"))
        let query = injected.absoluteString.split(separator: "?", maxSplits: 1)[1]
        #expect(query.split(separator: "&").count == 2)
        #expect(!injected.absoluteString.contains("&cc="))
        #expect(!injected.absoluteString.contains("+"))
    }
}

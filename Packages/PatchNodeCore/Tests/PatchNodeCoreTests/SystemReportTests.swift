import Foundation
import Testing
@testable import PatchNodeCore

struct SystemReportTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Shaped like `MXDiagnosticPayload.jsonRepresentation()`, with values that
    /// must never reach a support e-mail planted in the metadata.
    let diagnostics = Data(#"""
    {"timeStampBegin":"2027-01-14 10:00:00 +0000","timeStampEnd":"2027-01-15 10:00:00 +0000",
     "crashDiagnostics":[{"version":"1.0.0","callStackTree":{"callStacks":[{"threadAttributed":true}]},
       "diagnosticMetaData":{"appVersion":"1.1","appBuildVersion":"3","osVersion":"iPhone OS 27.0 (24A100)",
         "deviceType":"iPhone18,1","exceptionType":1,"exceptionCode":0,"signal":11,
         "terminationReason":"Namespace SIGNAL https://proxmox.example.invalid:8006/api2/json token=PVEAPIToken=test-user@pam!test-token=EXAMPLE_NOT_A_REAL_TOKEN from 192.0.2.4 storage.example.invalid Sample host sample-user@example.org"}}],
     "hangDiagnostics":[{"diagnosticMetaData":{"appVersion":"1.1","appBuildVersion":"3","hangDuration":"3.2 sec"}}]}
    """#.utf8)

    let metrics = Data(#"""
    {"timeStampBegin":"2027-01-14 00:00:00 +0000","timeStampEnd":"2027-01-15 00:00:00 +0000",
     "metaData":{"appVersion":"1.1","appBuildVersion":"3","osVersion":"iPhone OS 27.0"},
     "memoryMetrics":{"peakMemoryUsage":{"value":182,"unit":"MB"}},
     "cpuMetrics":{"cumulativeCPUTime":"95 sec"}}
    """#.utf8)

    @Test func parsesDiagnosticsAndMetrics() throws {
        let reports = SystemReportParser.diagnostics(from: diagnostics, receivedAt: t0)
        #expect(reports.map(\.kind) == [.crash, .hang])
        let crash = try #require(reports.first)
        #expect(crash.appVersion == "1.1 (3)")
        #expect(crash.details.contains(.init("Signal", "11")))
        #expect(crash.periodStart != nil)
        let performance = try #require(SystemReportParser.metrics(from: metrics, receivedAt: t0))
        #expect(performance.details.contains(.init("Peak memory", "182 MB")))
        #expect(SystemReportParser.diagnostics(from: Data("garbage".utf8), receivedAt: t0).isEmpty)
        #expect(SystemReportParser.metrics(from: Data("[]".utf8), receivedAt: t0) == nil)
    }

    /// The support summary carries no URL, host, address, service name, e-mail
    /// or token, even when iOS's own text contains them.
    @Test func supportSummaryHasNoURLHostServiceNameOrToken() {
        let reports = SystemReportParser.diagnostics(from: diagnostics, receivedAt: t0)
        let summary = SystemReportText.supportSummary(reports, forbidden: ["Sample host", "proxmox.example.invalid"])
        for forbidden in ["https", "://", "proxmox.example.invalid", "192.0.2.4", "storage.example.invalid",
                          "Sample host", "sample-user", "PVEAPIToken", "root@pam", "EXAMPLE_NOT_A_REAL_TOKEN", "token="] {
            #expect(!summary.contains(forbidden), "\(forbidden) in \(summary)")
        }
        #expect(summary.contains("crash"))
        #expect(summary.contains("signal 11"))
        #expect(summary.contains("hang duration 3.2 sec"))
        // Never the call stacks.
        #expect(!summary.contains("callStack"))
    }

    @Test func cleanRemovesNetworkValues() {
        #expect(SystemReportText.clean("see http://x.example/a?b=c now") == "see [removed] now")
        #expect(!SystemReportText.clean("fe80::1:2:3:4 down").contains("fe80"))
        #expect(SystemReportText.clean("Labo VM", forbidden: ["labo"]) == "[removed] VM")
        for value in ["server.example.invalid:8006 refused", "192.0.2.4 refused", "at /Users/test-user/Library/x",
                      "X-API-Key: abc123", "Bearer abcd1234", "token abcdefgh"] {
            let cleaned = SystemReportText.clean(value)
            for secret in ["server.example.invalid", "192.0.2.4", "test-user", "abc123", "abcd1234", "abcdefgh"] {
                #expect(!cleaned.contains(secret), "\(secret) in \(cleaned)")
            }
        }
    }

    @Test func storeKeepsThirtyDaysFiftyReportsAndNoDuplicate() {
        var store = SystemReportStore()
        let reports = SystemReportParser.diagnostics(from: diagnostics, receivedAt: t0)
        store.add(reports, now: t0)
        // MetricKit's past payloads come again at the next launch: same reports.
        store.add(SystemReportParser.diagnostics(from: diagnostics, receivedAt: t0 + 60), now: t0 + 60)
        #expect(store.reports.count == 2)
        #expect(store.add(SystemReportParser.diagnostics(from: diagnostics, receivedAt: t0 + 120), now: t0 + 120) == 0)
        store.prune(now: t0 + SystemReportStore.retention + 1)
        #expect(store.reports.isEmpty)
        let many = (0..<(SystemReportStore.maxReports + 10)).map { index in
            SystemReport(kind: .performance, receivedAt: t0 + Double(index), periodStart: t0 + Double(index), periodEnd: nil,
                         appVersion: nil, osVersion: nil, details: [], rawJSON: nil, contentHash: "\(index)")
        }
        store.add(many, now: t0 + 100)
        #expect(store.reports.count == SystemReportStore.maxReports)
        #expect(store.reports.first?.receivedAt == t0 + Double(SystemReportStore.maxReports + 9))
        #expect(SystemReportStore.decoded(from: store.encoded()) == store)
    }

    @Test func archivePersistsInItsDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PatchNode-reports-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = SystemReportArchive(directory: directory)
        await archive.add(diagnosticsJSON: diagnostics, now: t0)
        await archive.add(metricsJSON: metrics, now: t0)
        #expect(await SystemReportArchive(directory: directory).reports(now: t0).count == 3)
        await archive.removeAll(now: t0 + 86_400 * 10)
        #expect(await SystemReportArchive(directory: directory).reports(now: t0).isEmpty)
        // iOS delivers the same past payloads at the next launch: still deleted.
        await archive.add(diagnosticsJSON: diagnostics, now: t0 + 86_400 * 10)
        #expect(await archive.reports(now: t0 + 86_400 * 10).isEmpty)
    }

    @Test func bigDistinctReportsStayDistinct() {
        // Beyond the raw JSON cap, the fingerprint still comes from the full JSON.
        func crash(_ marker: String) -> Data {
            let padding = String(repeating: "x", count: SystemReportParser.maxRawBytes)
            return Data(#"{"crashDiagnostics":[{"diagnosticMetaData":{"signal":11},"pad":"\#(padding)\#(marker)"}]}"#.utf8)
        }
        let first = SystemReportParser.diagnostics(from: crash("a"), receivedAt: t0)
        let second = SystemReportParser.diagnostics(from: crash("b"), receivedAt: t0)
        #expect(first.first?.rawJSON == nil)
        var store = SystemReportStore()
        #expect(store.add(first + second, now: t0) == 2)
    }

    @Test func supportBodyAppendsTheSummaryOnlyWhenChosen() {
        #expect(SupportMessage.body(description: "Hi", report: nil) == "Hi")
        #expect(SupportMessage.body(description: "Hi", report: nil, crashSummary: "iOS crash and hang reports (last 30 days): 0")
            == "Hi\n\n---\niOS crash and hang reports (last 30 days): 0")
    }
}

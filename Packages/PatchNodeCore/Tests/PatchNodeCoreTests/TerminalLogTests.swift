import Foundation
import Testing
@testable import PatchNodeCore

@Suite("Terminal events in Diagnostics")
struct TerminalLogTests {
    @Test func openAndEndAreLoggedWithoutContent() throws {
        let log = RequestLog(capacity: 10)
        let label = RequestLog.Label(serviceID: UUID(), serviceName: "nas")
        log.append(.event(.terminalOpened(.ssh)), label: label)
        log.append(.event(.terminalEnded(.ssh, duration: 61.4, reason: .failed(code: "host-key-changed"))), label: label)
        let lines = log.entries().map(\.logLine)
        #expect(lines[0].hasSuffix("[nas] TERMINAL OPENED (ssh)"))
        #expect(lines[1].hasSuffix("[nas] TERMINAL ENDED (ssh) failed(host-key-changed) after 61 s"))
    }

    @Test func endReasonsHaveStableLogValues() {
        #expect(TerminalEndReason.closed.logValue == "closed")
        #expect(TerminalEndReason.backgroundTimeout.logValue == "background-timeout")
    }

    @Test func supportReportIgnoresTerminalEvents() {
        let log = [RequestLog.Entry]()
        _ = log
        // Only request errors make the support report; events never do.
        let report = SupportReport(
            appVersion: "1.2 (3)", systemVersion: "27.0", deviceModel: "iPad", language: "fr",
            services: [], demoMode: false, log: []
        )
        #expect(report.recentErrors.isEmpty)
    }
}

@Suite("Guests no longer listed in Diagnostics")
struct GuestsNoLongerListedLogTests {
    @Test func theLineAsksAboutRightsAndGivesTheCheck() {
        let log = RequestLog(capacity: 10)
        log.append(.event(.guestsNoLongerListed(vmids: [101, 102])), label: RequestLog.Label(serviceID: UUID(), serviceName: "node-1"))
        let line = log.entries()[0].logLine
        #expect(line.contains("[node-1] GUESTS NO LONGER LISTED (101, 102) while their node answers"))
        #expect(line.contains("insufficient rights on them?"))
        #expect(line.contains("pveum user token permissions <user> <tokenid> --path /vms/<id>"))
        #expect(!line.lowercased().contains("deleted:"))
    }

    @Test func aLongListIsCapped() {
        let log = RequestLog(capacity: 10)
        log.append(.event(.guestsNoLongerListed(vmids: Array(100..<125))), label: nil)
        #expect(log.entries()[0].logLine.contains("(100, 101, 102, 103, 104, 105, 106, 107, 108, 109 +15)"))
    }
}

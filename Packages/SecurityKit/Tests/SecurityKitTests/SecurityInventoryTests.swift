import Foundation
import Testing
import PatchNodeCore
@testable import SecurityKit

private typealias F = SecurityFixtures

@Suite("SecurityInventory")
struct SecurityInventoryTests {
    private func crowdSec(_ decisions: [CrowdSecDecision], id: UUID = F.serviceID) -> SecurityServiceSnapshot {
        SecurityServiceSnapshot(serviceID: id, serviceName: "CrowdSec", kind: .crowdSec, decisions: decisions)
    }

    private func npm(_ hosts: [NPMProxyHost], id: UUID = F.serviceID) -> SecurityServiceSnapshot {
        SecurityServiceSnapshot(serviceID: id, serviceName: "NPM", kind: .nginxProxyManager, proxyHosts: hosts)
    }

    private func adGuard(_ summary: AdGuardSummary, id: UUID) -> SecurityServiceSnapshot {
        SecurityServiceSnapshot(serviceID: id, serviceName: "AdGuard", kind: .adGuardHome, adGuard: summary)
    }

    @Test func decisionsSortedPermanentFirstThenLongestRemaining() {
        let inventory = SecurityInventory(snapshots: [crowdSec([
            CrowdSecDecision(id: "soon", value: "203.0.113.1", expiresAt: date(referenceEpoch + 60)),
            CrowdSecDecision(id: "late", value: "203.0.113.2", expiresAt: date(referenceEpoch + 86400)),
            CrowdSecDecision(id: "forever", value: "203.0.113.3"),
            CrowdSecDecision(id: "mid", value: "203.0.113.4", expiresAt: date(referenceEpoch + 3600)),
        ])])
        #expect(inventory.decisions.map(\.decision.id) == ["forever", "late", "mid", "soon"])
    }

    @Test func hostsSortedFailingFirstThenNaturalTitle() {
        let inventory = SecurityInventory(snapshots: [npm([
            NPMProxyHost(id: 1, domainNames: ["b10.example.invalid"]),
            NPMProxyHost(id: 2, domainNames: ["B2.example.invalid"]),
            NPMProxyHost(id: 3, domainNames: ["z.example.invalid"], nginxOnline: false),
            NPMProxyHost(id: 4, domainNames: ["a.example.invalid"], enabled: false, nginxOnline: false),
        ])])
        #expect(inventory.hosts.map(\.host.id) == [3, 4, 2, 1])
    }

    @Test func overviewAggregatesAllServices() {
        let inventory = SecurityInventory(snapshots: [
            crowdSec([
                CrowdSecDecision(id: "1", value: "203.0.113.1"),
                CrowdSecDecision(id: "2", value: "203.0.113.2"),
                CrowdSecDecision(id: "3", value: "203.0.113.3", simulated: true),
            ]),
            npm([
                NPMProxyHost(id: 1, domainNames: ["a.example.invalid"], nginxOnline: true),
                NPMProxyHost(id: 2, domainNames: ["b.example.invalid"], nginxOnline: false),
                NPMProxyHost(id: 3, domainNames: ["c.example.invalid"], enabled: false),
            ], id: F.otherServiceID),
            adGuard(AdGuardSummary(protectionEnabled: true, dnsQueries: 1000, blocked: 100), id: UUID()),
            adGuard(AdGuardSummary(protectionEnabled: false, dnsQueries: 500, blocked: 20), id: UUID()),
        ])
        let overview = inventory.overview
        #expect(overview.activeBans == 2)
        #expect(overview.hostsTotal == 3)
        #expect(overview.hostsEnabled == 2)
        #expect(overview.hostsFailing == 1)
        #expect(overview.dnsQueries == 1500)
        #expect(overview.dnsBlocked == 120)
        #expect(overview.protectionDisabled == 1)
        #expect(inventory.adGuards.count == 2)
    }

    @Test func filtersPerServiceAndKeepsIDsUnique() {
        let decision = CrowdSecDecision(id: "same", value: "203.0.113.1")
        let host = NPMProxyHost(id: 1, domainNames: ["a.example.invalid"])
        let inventory = SecurityInventory(snapshots: [
            crowdSec([decision]), crowdSec([decision], id: F.otherServiceID),
            npm([host]), npm([host], id: F.otherServiceID),
        ])
        #expect(inventory.decisions(for: F.serviceID).count == 1)
        #expect(inventory.decisions(for: F.otherServiceID).count == 1)
        #expect(inventory.hosts(for: F.otherServiceID).map(\.serviceID) == [F.otherServiceID])
        #expect(Set(inventory.decisions.map(\.id)).count == 2)
        #expect(Set(inventory.hosts.map(\.id)).count == 2)
    }

    @Test func emptyInventory() {
        let inventory = SecurityInventory(snapshots: [])
        #expect(inventory.decisions.isEmpty && inventory.hosts.isEmpty && inventory.adGuards.isEmpty)
        #expect(inventory.overview.level(failedServices: 0, totalServices: 0) == .ok)
    }

    // MARK: level

    @Test func levelIsCriticalWhenNoServiceAnswered() {
        let overview = SecurityInventory(snapshots: []).overview
        #expect(overview.level(failedServices: 3, totalServices: 3) == .critical)
    }

    @Test func levelIsWarningForPartialFailureFailingHostOrProtectionOff() {
        #expect(SecurityInventory(snapshots: []).overview.level(failedServices: 1, totalServices: 2) == .warning)
        let failing = SecurityInventory(snapshots: [npm([NPMProxyHost(id: 1, domainNames: ["a.example.invalid"], nginxOnline: false)])])
        #expect(failing.overview.level(failedServices: 0, totalServices: 1) == .warning)
        let off = SecurityInventory(snapshots: [adGuard(AdGuardSummary(protectionEnabled: false), id: F.serviceID)])
        #expect(off.overview.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func bansAloneAreInformational() {
        let bans = SecurityInventory(snapshots: [crowdSec((0..<50).map { CrowdSecDecision(id: "\($0)", value: "203.0.113.\($0)") })])
        #expect(bans.overview.activeBans == 50)
        #expect(bans.overview.level(failedServices: 0, totalServices: 1) == .ok)
    }
}

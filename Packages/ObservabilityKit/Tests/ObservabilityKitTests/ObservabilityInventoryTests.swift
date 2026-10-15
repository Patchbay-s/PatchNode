import Foundation
import Testing
import PatchNodeCore
@testable import ObservabilityKit

@Suite("ObservabilityInventory")
struct ObservabilityInventoryTests {
    private let amID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let kumaID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private let promID = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!
    private let grafanaID = UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!

    private func alert(_ id: String, _ severity: ObservabilityAlert.Severity, since: TimeInterval?) -> ObservabilityAlert {
        ObservabilityAlert(id: "alertmanager|\(id)", source: .alertmanager, severity: severity, name: id, since: since.map { date(referenceEpoch + $0) })
    }

    private var kumaPage: UptimeKumaPage {
        UptimeKumaPage(slug: "homelab", title: "Homelab", monitors: [
            .init(id: 1, name: "Nextcloud", status: .up),
            .init(id: 2, name: "Jellyfin", status: .down, lastMessage: "timeout of 48000ms exceeded", lastBeat: date(referenceEpoch)),
            .init(id: 3, name: "NAS", status: nil),
            .init(id: 4, name: "Router", status: .pending),
        ])
    }

    private func snapshot(_ id: UUID, _ kind: ServiceKind, alerts: [ObservabilityAlert] = [], targets: [PrometheusTarget] = [],
                          dashboards: [GrafanaDashboard] = [], page: UptimeKumaPage? = nil) -> ObservabilityServiceSnapshot {
        ObservabilityServiceSnapshot(serviceID: id, serviceName: "\(kind)", kind: kind, baseURL: Fixtures.grafanaURL,
                                     alerts: alerts, targets: targets, dashboards: dashboards, statusPage: page)
    }

    @Test func downKumaMonitorsBecomeCriticalAlerts() throws {
        let inventory = ObservabilityInventory(snapshots: [snapshot(kumaID, .uptimeKuma, page: kumaPage)])
        #expect(inventory.pages.map(\.page) == [kumaPage])
        #expect(inventory.alerts.count == 1) // only "down"; pending / nil ignored
        let item = try #require(inventory.alerts.first)
        #expect(item.serviceID == kumaID)
        #expect(item.alert == ObservabilityAlert(
            id: "uptimeKuma|homelab|2", source: .uptimeKuma, severity: .critical, name: "Jellyfin",
            summary: "timeout of 48000ms exceeded", since: date(referenceEpoch)
        ))
    }

    @Test func alertsSortedBySeverityThenOldestWithNilSinceLast() {
        let inventory = ObservabilityInventory(snapshots: [
            snapshot(amID, .alertmanager, alerts: [
                alert("info", .info, since: -5000),
                alert("critNil", .critical, since: nil),
                alert("warn", .warning, since: -1000),
                alert("crit100", .critical, since: -100),
                alert("crit500", .critical, since: -500),
            ]),
            snapshot(kumaID, .uptimeKuma, page: kumaPage), // Jellyfin, critical, since 0
        ])
        #expect(inventory.alerts.map(\.alert.name) == ["crit500", "crit100", "Jellyfin", "critNil", "warn", "info"])
    }

    @Test func duplicateAlertInSameServiceIsKeptOnce() {
        let duplicated = alert("dup", .warning, since: 0)
        let inventory = ObservabilityInventory(snapshots: [snapshot(amID, .alertmanager, alerts: [duplicated, duplicated])])
        #expect(inventory.alerts.count == 1)
    }

    /// Two Alertmanager replicas (HA pair) report the same fingerprint: each service
    /// keeps its own copy and building the inventory must not crash.
    @Test func sameAlertFromTwoServicesDoesNotCrash() {
        let alert = ObservabilityAlert(id: "alertmanager|a1b2c3d4e5f60718", source: .alertmanager, severity: .critical, name: "InstanceDown")
        let snapshots = ["00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002"].map {
            ObservabilityServiceSnapshot(serviceID: UUID(uuidString: $0)!, serviceName: $0, kind: .alertmanager,
                                         baseURL: URL(string: "https://alertmanager.example.invalid")!, alerts: [alert])
        }
        let inventory = ObservabilityInventory(snapshots: snapshots)
        #expect(inventory.alerts.count == 2)
    }

    @Test func targetsDownFirstThenJobThenInstance() {
        let inventory = ObservabilityInventory(snapshots: [snapshot(promID, .prometheus, targets: [
            PrometheusTarget(job: "node", instance: "b.example.invalid:9100", health: .up),
            PrometheusTarget(job: "node", instance: "z.example.invalid:9100", health: .down),
            PrometheusTarget(job: "blackbox", instance: "a.example.invalid", health: .up),
            PrometheusTarget(job: "api", instance: "x.example.invalid", health: .down),
            PrometheusTarget(job: "api", instance: "u.example.invalid", health: .unknown),
        ])])
        #expect(inventory.targets.map(\.target.instance) == [
            "x.example.invalid", "z.example.invalid:9100", "u.example.invalid", "a.example.invalid", "b.example.invalid:9100",
        ])
        #expect(inventory.downTargets.map(\.target.instance) == ["x.example.invalid", "z.example.invalid:9100"])
    }

    @Test func dashboardsSortedByFolderThenTitle() throws {
        let inventory = ObservabilityInventory(snapshots: [snapshot(grafanaID, .grafana, dashboards: [
            GrafanaDashboard(uid: "n10", title: "Node 10", path: "/d/n10/node-10", folder: "Infrastructure"),
            GrafanaDashboard(uid: "zeta", title: "Zeta", path: "/d/zeta/zeta", folder: "Apps"),
            GrafanaDashboard(uid: "n2", title: "Node 2", path: "/d/n2/node-2", folder: "Infrastructure"),
            GrafanaDashboard(uid: "home", title: "Home", path: "/d/home/home", folder: nil),
        ])])
        #expect(inventory.dashboards.map(\.dashboard.uid) == ["home", "zeta", "n2", "n10"])
        let first = try #require(inventory.dashboards.first)
        #expect(first.url?.absoluteString == "https://grafana.example.invalid/d/home/home")
    }

    @Test func overviewCounts() {
        let inventory = ObservabilityInventory(snapshots: [
            snapshot(amID, .alertmanager, alerts: [alert("c", .critical, since: 0), alert("w1", .warning, since: 0),
                                                   alert("w2", .warning, since: 1), alert("i", .info, since: 0)]),
            snapshot(kumaID, .uptimeKuma, page: kumaPage),
            snapshot(promID, .prometheus, targets: [
                PrometheusTarget(job: "node", instance: "a", health: .up),
                PrometheusTarget(job: "node", instance: "b", health: .down),
            ]),
        ])
        #expect(inventory.overview == inventory.overview) // Hashable sanity
        #expect(inventory.overview.activeAlerts == 5)
        #expect(inventory.overview.critical == 2)
        #expect(inventory.overview.warning == 2)
        #expect(inventory.overview.info == 1)
        #expect(inventory.overview.targetsTotal == 2)
        #expect(inventory.overview.targetsDown == 1)
    }

    @Test func emptyInventory() {
        let inventory = ObservabilityInventory(snapshots: [])
        #expect(inventory.alerts.isEmpty && inventory.targets.isEmpty && inventory.pages.isEmpty && inventory.dashboards.isEmpty)
        #expect(inventory.overview.activeAlerts == 0)
        #expect(inventory.overview.level(failedServices: 0, totalServices: 0) == .ok)
    }

    // MARK: level()

    private func overview(alerts: [ObservabilityAlert.Severity] = [], targets: [PrometheusTarget.Health] = []) -> ObservabilityOverview {
        ObservabilityInventory(snapshots: [snapshot(amID, .alertmanager,
            alerts: alerts.enumerated().map { alert("a\($0.offset)", $0.element, since: 0) },
            targets: targets.enumerated().map { PrometheusTarget(job: "j", instance: "i\($0.offset)", health: $0.element) })]).overview
    }

    @Test func levelCriticalWhenAllServicesFailed() {
        #expect(overview().level(failedServices: 3, totalServices: 3) == .critical)
    }

    @Test func levelCriticalOnCriticalAlert() {
        #expect(overview(alerts: [.critical]).level(failedServices: 0, totalServices: 2) == .critical)
    }

    @Test func levelWarningCases() {
        #expect(overview(alerts: [.warning, .info]).level(failedServices: 0, totalServices: 2) == .warning)
        #expect(overview(targets: [.up, .down]).level(failedServices: 0, totalServices: 2) == .warning)
        #expect(overview().level(failedServices: 1, totalServices: 2) == .warning)
    }

    @Test func levelOkOtherwise() {
        #expect(overview(alerts: [.info], targets: [.up, .unknown]).level(failedServices: 0, totalServices: 2) == .ok)
    }
}

import Foundation
import PatchNodeCore

/// What one observability service returned during a refresh.
public struct ObservabilityServiceSnapshot: Sendable, Hashable {
    public let serviceID: UUID
    public let serviceName: String
    public let kind: ServiceKind
    public let baseURL: URL
    public let alerts: [ObservabilityAlert]
    public let targets: [PrometheusTarget]
    public let dashboards: [GrafanaDashboard]
    public let statusPage: UptimeKumaPage?
    public let fetchedAt: Date

    public init(
        serviceID: UUID, serviceName: String, kind: ServiceKind, baseURL: URL,
        alerts: [ObservabilityAlert] = [], targets: [PrometheusTarget] = [],
        dashboards: [GrafanaDashboard] = [], statusPage: UptimeKumaPage? = nil, fetchedAt: Date = .now
    ) {
        self.serviceID = serviceID; self.serviceName = serviceName; self.kind = kind; self.baseURL = baseURL
        self.alerts = alerts; self.targets = targets; self.dashboards = dashboards
        self.statusPage = statusPage; self.fetchedAt = fetchedAt
    }
}

/// Alerts from every source (Alertmanager, Grafana, Uptime Kuma monitors that are
/// down) sorted by severity, plus Prometheus targets, status pages and dashboards.
public struct ObservabilityInventory: Sendable {
    public struct AlertItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let alert: ObservabilityAlert
        public var id: String { "\(serviceID.uuidString)|\(alert.id)" }
    }

    public struct TargetItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let target: PrometheusTarget
        public var id: String { "\(serviceID.uuidString)|\(target.id)" }
    }

    public struct PageItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let page: UptimeKumaPage
        public var id: String { serviceID.uuidString }
    }

    public struct DashboardItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let baseURL: URL
        public let dashboard: GrafanaDashboard
        public var id: String { "\(serviceID.uuidString)|\(dashboard.uid)" }
        public var url: URL? { dashboard.url(on: baseURL) }
    }

    public let alerts: [AlertItem]
    public let targets: [TargetItem]
    public let pages: [PageItem]
    public let dashboards: [DashboardItem]
    public let overview: ObservabilityOverview

    public var downTargets: [TargetItem] { targets.filter { $0.target.health == .down } }

    public init(snapshots: [ObservabilityServiceSnapshot]) {
        var alerts: [AlertItem] = []
        var targets: [TargetItem] = []
        var pages: [PageItem] = []
        var dashboards: [DashboardItem] = []
        var seenAlerts = Set<String>()

        for snapshot in snapshots {
            var serviceAlerts = snapshot.alerts
            if let page = snapshot.statusPage {
                pages.append(PageItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, page: page))
                serviceAlerts += page.monitorsDown.map { monitor in
                    ObservabilityAlert(
                        id: "uptimeKuma|\(page.slug)|\(monitor.id)",
                        source: .uptimeKuma,
                        severity: .critical,
                        name: monitor.name,
                        summary: monitor.lastMessage,
                        since: monitor.lastBeat
                    )
                }
            }
            for alert in serviceAlerts where seenAlerts.insert("\(snapshot.serviceID.uuidString)|\(alert.id)").inserted {
                alerts.append(AlertItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, alert: alert))
            }
            targets += snapshot.targets.map {
                TargetItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, target: $0)
            }
            dashboards += snapshot.dashboards.map {
                DashboardItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, baseURL: snapshot.baseURL, dashboard: $0)
            }
        }

        // Same order as `sortedBySeverity()`; several services may report the same
        // alert id (Alertmanager replicas), so no dictionary keyed by alert id.
        self.alerts = alerts.sorted { lhs, rhs in
            if lhs.alert.severity != rhs.alert.severity { return lhs.alert.severity > rhs.alert.severity }
            return (lhs.alert.since ?? .distantFuture) < (rhs.alert.since ?? .distantFuture)
        }
        self.targets = targets.sorted { ($0.target.health == .down ? 0 : 1, $0.target.job, $0.target.instance) < ($1.target.health == .down ? 0 : 1, $1.target.job, $1.target.instance) }
        self.pages = pages
        self.dashboards = dashboards.sorted { lhs, rhs in
            let folder = (lhs.dashboard.folder ?? "").localizedStandardCompare(rhs.dashboard.folder ?? "")
            if folder != .orderedSame { return folder == .orderedAscending }
            return lhs.dashboard.title.localizedStandardCompare(rhs.dashboard.title) == .orderedAscending
        }
        self.overview = ObservabilityOverview(alerts: self.alerts, targets: self.targets)
    }
}

public struct ObservabilityOverview: Sendable, Hashable {
    public let activeAlerts: Int
    public let critical: Int
    public let warning: Int
    public let info: Int
    public let targetsTotal: Int
    public let targetsDown: Int

    init(alerts: [ObservabilityInventory.AlertItem], targets: [ObservabilityInventory.TargetItem]) {
        activeAlerts = alerts.count
        critical = alerts.count { $0.alert.severity == .critical }
        warning = alerts.count { $0.alert.severity == .warning }
        info = alerts.count { $0.alert.severity == .info }
        targetsTotal = targets.count
        targetsDown = targets.count { $0.target.health == .down }
    }

    /// Critical: no service answered or a critical alert fires. Warning: a service
    /// failed, a warning alert fires or a Prometheus target is down.
    public func level(failedServices: Int, totalServices: Int) -> HealthLevel {
        if totalServices > 0 && failedServices >= totalServices { return .critical }
        if critical > 0 { return .critical }
        if failedServices > 0 || warning > 0 || targetsDown > 0 { return .warning }
        return .ok
    }
}

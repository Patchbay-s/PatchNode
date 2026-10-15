import Foundation
import PatchNodeCore

extension ObservabilityInventory {
    /// Firing alerts of warning or critical severity (Alertmanager, Grafana,
    /// Uptime Kuma monitors down), one per alert. Prometheus targets down are
    /// not included: Alertmanager usually alerts on them already.
    public func watchedConditions() -> Set<WatchedCondition> {
        Set(alerts.filter { $0.alert.severity >= .warning }.map {
            WatchedCondition(kind: .alertFiring, scope: $0.serviceID.uuidString, key: $0.alert.id)
        })
    }
}

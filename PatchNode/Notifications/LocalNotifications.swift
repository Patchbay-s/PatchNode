import Foundation
import UserNotifications
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit

/// Local notifications, sent only from a background refresh (in the foreground
/// the user sees the dashboard). One notification per kind, with a count and no
/// name, address or detail: nothing identifying on the lock screen.
@MainActor
enum LocalNotifications {
    /// What the watch remembers between refreshes (kinds, opaque keys, dates).
    private static let stateKey = "notificationWatchState"

    /// Updates what is known; posts the new problems when `deliver` (background).
    /// Problems count as announced once handed to iOS, even if the user turned
    /// notifications off meanwhile: they aren't kept for later.
    static func observe(_ conditions: Set<WatchedCondition>, unevaluated: Set<WatchedScope>, deliver: Bool) async {
        let defaults = UserDefaults.standard
        var watch = ConditionWatch.decoded(from: defaults.data(forKey: stateKey))
        let announced = watch.update(current: conditions, unevaluated: unevaluated, enabled: WatchedKindSettings.enabled, deliver: deliver)
        defaults.set(watch.encoded(), forKey: stateKey)
        guard !announced.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        for kind in WatchedKind.allCases {
            guard let count = announced[kind], count > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "PatchNode"
            content.body = body(for: kind, count: count)
            content.sound = .default
            content.threadIdentifier = kind.rawValue
            // Same identifier per kind: a newer notification replaces the older one.
            let request = UNNotificationRequest(identifier: "PatchNode.\(kind.rawValue)", content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    /// Asks iOS once; false if the user refused (Settings › Notifications then).
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default: return false
        }
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func body(for kind: WatchedKind, count: Int) -> String {
        switch kind {
        case .serviceUnreachable: String(localized: "\(count) services stopped answering.")
        case .backupFailed: String(localized: "\(count) backups failed.")
        case .containerUnhealthy: String(localized: "\(count) containers are unhealthy.")
        case .alertFiring: String(localized: "\(count) new alerts are firing.")
        case .certificateExpiring: String(localized: "\(count) certificates expire soon.")
        case .diskProblem: String(localized: "\(count) disk problems detected.")
        }
    }

    static func title(for kind: WatchedKind) -> String {
        switch kind {
        case .serviceUnreachable: String(localized: "Service unreachable")
        case .backupFailed: String(localized: "Backup failed")
        case .containerUnhealthy: String(localized: "Container unhealthy")
        case .alertFiring: String(localized: "New alert")
        case .certificateExpiring: String(localized: "Certificate expiring (14 and 7 days)")
        case .diskProblem: String(localized: "Disk problem (from the last disk read)")
        }
    }
}

extension AppModel {
    /// Every problem currently seen, and the kinds of problems of each service
    /// that couldn't be checked this time (they keep their state).
    func watchedConditions(now: Date = .now) -> (current: Set<WatchedCondition>, unevaluated: Set<WatchedScope>) {
        var current = Set<WatchedCondition>()
        var unevaluated = Set<WatchedScope>()
        func skip(_ serviceID: UUID) {
            for kind in WatchedKind.allCases { unevaluated.insert(WatchedScope(kind: kind, scope: serviceID.uuidString)) }
        }
        // All unreachable at once: VPN off or no network, not a service problem;
        // nothing is evaluated.
        let allUnreachable = aggregateConnectivity(from: stores.flatMap { $0.healthStatuses }) == .allUnreachable
        for store in stores {
            for service in store.services {
                let state = store.states[service.id]
                if allUnreachable {
                    skip(service.id)
                } else if state == .unreachable {
                    current.insert(WatchedCondition(kind: .serviceUnreachable, scope: service.id.uuidString, key: "unreachable"))
                }
                // Not loaded this time: its other problems are unknown, not solved.
                if state != .loaded {
                    for kind in WatchedKind.allCases where kind != .serviceUnreachable {
                        unevaluated.insert(WatchedScope(kind: kind, scope: service.id.uuidString))
                    }
                }
            }
        }
        current.formUnion(proxmoxStore.inventory.watchedConditions(now: now))
        current.formUnion(backupStore.inventory.watchedConditions(now: now))
        current.formUnion(dockerStore.inventory.watchedConditions())
        current.formUnion(observabilityStore.inventory.watchedConditions())
        current.formUnion(CertificateRegistry.shared.watchedConditions(
            among: stores.flatMap { $0.services }, now: now, id: { $0.id.uuidString }, kind: { $0.kind }, url: { $0.url }
        ))
        // Disks: only the last wanted read (button or automatic), never a
        // request of their own; nothing for a service turned off.
        let disks = SMARTReadingStore.shared.watchedConditions(serviceIDs: proxmoxStore.services.map(\.id), settings: smartSettings)
        current.formUnion(disks.current)
        unevaluated.formUnion(disks.unevaluated)
        return (current, unevaluated)
    }

    /// After a refresh. The demo never notifies nor touches the real state.
    func observeConditions(deliver: Bool) async {
        guard !DemoMode.isOn else { return }
        let (current, unevaluated) = watchedConditions()
        await LocalNotifications.observe(current, unevaluated: unevaluated, deliver: deliver)
    }
}

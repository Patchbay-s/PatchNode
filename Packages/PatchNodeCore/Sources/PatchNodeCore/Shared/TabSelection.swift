import Foundation

/// A screen of the app that can sit in the tab bar or be opened from its
/// dashboard card.
public enum AppScreen: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case dashboard
    case proxmox
    case backups
    case docker
    case observability
    case security
    case tailscale
    case homeAssistant
    case glances

    public var id: String { rawValue }

    /// The screen showing services of this type.
    public static func screen(for kind: ServiceKind) -> AppScreen {
        switch kind {
        case .proxmoxVE: .proxmox
        case .proxmoxBackupServer: .backups
        case .dockerPortainer, .dockerSocketProxy: .docker
        case .prometheus, .alertmanager, .grafana, .uptimeKuma: .observability
        case .crowdSec, .nginxProxyManager, .adGuardHome: .security
        case .tailscale: .tailscale
        case .homeAssistant: .homeAssistant
        case .glances: .glances
        }
    }

    /// Screens with at least one configured service, in `allCases` order. The
    /// dashboard is always available.
    public static func available(for kinds: some Sequence<ServiceKind>) -> [AppScreen] {
        let screens = Set(kinds.map(screen(for:)))
        return allCases.filter { $0 == .dashboard || screens.contains($0) }
    }
}

/// The tabs the user chose: at most `maxTabs` screens, Settings always added
/// last by the tab view, so iOS never folds tabs into "More". The dashboard
/// always stays (screens left out of the bar open from its cards).
public enum TabSelection {
    public static let maxTabs = 4
    public static let storageKey = "tabSelection"

    /// Tabs to show. `stored` is nil until the user changes anything: then the
    /// dashboard and the first three configured screens. Screens whose services
    /// were all deleted drop out; screens added later stay out of the bar.
    public static func resolve(stored: [AppScreen]?, available: [AppScreen]) -> [AppScreen] {
        let chosen = stored ?? available
        var result: [AppScreen] = [.dashboard]
        for screen in chosen where screen != .dashboard && available.contains(screen) && !result.contains(screen) {
            result.append(screen)
        }
        // The dashboard keeps the place the user gave it.
        if let stored, let index = stored.filter({ available.contains($0) }).firstIndex(of: .dashboard) {
            result.removeFirst()
            result.insert(.dashboard, at: min(index, result.count))
        }
        return Array(result.prefix(maxTabs))
    }

    /// Whether `screen` can be switched on or off in `tabs`.
    public static func canToggle(_ screen: AppScreen, in tabs: [AppScreen]) -> Bool {
        if screen == .dashboard { return false }
        return tabs.contains(screen) || tabs.count < maxTabs
    }

    public static func toggled(_ screen: AppScreen, in tabs: [AppScreen]) -> [AppScreen] {
        guard canToggle(screen, in: tabs) else { return tabs }
        if tabs.contains(screen) { return tabs.filter { $0 != screen } }
        return tabs + [screen]
    }

    public static func encode(_ tabs: [AppScreen]) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }

    /// Empty string: never customised. Unknown names (a screen removed in a
    /// later version) are skipped.
    public static func decode(_ stored: String) -> [AppScreen]? {
        guard !stored.isEmpty else { return nil }
        return stored.split(separator: ",").compactMap { AppScreen(rawValue: String($0)) }
    }
}

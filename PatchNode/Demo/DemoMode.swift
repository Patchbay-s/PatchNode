import SwiftUI
import SwiftData
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit
import TailscaleKit
import SecurityKit
import HomeServicesKit

nonisolated extension DemoMode {
    /// Registers the demo responders for the demo hosts. Once, at launch.
    static func installResponders() {
        let responders: [ServiceKind: any DemoResponder] = [
            .proxmoxVE: ProxmoxDemoResponder(),
            .proxmoxBackupServer: PBSDemoResponder(),
            .dockerSocketProxy: DockerDemoResponder(portainer: false),
            .dockerPortainer: DockerDemoResponder(portainer: true),
            .prometheus: PrometheusDemoResponder(),
            .alertmanager: AlertmanagerDemoResponder(),
            .grafana: GrafanaDemoResponder(),
            .uptimeKuma: UptimeKumaDemoResponder(),
            .tailscale: TailscaleDemoResponder(),
            .crowdSec: CrowdSecDemoResponder(),
            .nginxProxyManager: NPMDemoResponder(),
            .adGuardHome: AdGuardDemoResponder(),
            .homeAssistant: HomeAssistantDemoResponder(),
            .glances: GlancesDemoResponder(),
        ]
        for (kind, responder) in responders {
            DemoServer.register(responder, host: DemoCatalog.host(for: kind))
        }
    }

    /// The demo services, sorted by name like the user's.
    static let descriptors: [ServiceDescriptor] = DemoCatalog.services
        .map { ServiceDescriptor(id: $0.id, kind: $0.kind, name: $0.name, url: $0.url) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    /// Chosen Home Assistant entities and PromQL charts, so the demo screens aren't
    /// empty. Recognised by the demo service IDs; removed when the demo ends.
    static func seed(in context: ModelContext) {
        clean(in: context)
        if let home = DemoCatalog.services.first(where: { $0.kind == .homeAssistant }) {
            for (index, entity) in HomeAssistantDemoResponder.suggestedEntityIDs.enumerated() {
                context.insert(HomeAssistantPin(serviceID: home.id, entityID: entity, sortOrder: 10_000 + index))
            }
        }
        if let prometheus = DemoCatalog.services.first(where: { $0.kind == .prometheus }) {
            context.insert(PromQLFavorite(
                name: String(localized: "CPU usage"), query: #"100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))"#,
                unit: .percent, rangeMinutes: 60, serviceID: prometheus.id
            ))
            context.insert(PromQLFavorite(
                name: String(localized: "Memory used"), query: "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)",
                unit: .percent, rangeMinutes: 360, serviceID: prometheus.id
            ))
        }
        try? context.save()
    }

    /// Starts the demo: sample choices seeded, then the stores switch to the demo
    /// services (MainTabView reads the flag).
    @MainActor static func enter(context: ModelContext) {
        seed(in: context)
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Back to the user's services. A demo opened without a passcode locks again.
    @MainActor static func exit(context: ModelContext, lock: AppLockController) {
        clean(in: context)
        UserDefaults.standard.set(false, forKey: key)
        if lock.isDemoOnly {
            lock.lockImmediately()
        }
    }

    static func clean(in context: ModelContext) {
        let ids = DemoCatalog.serviceIDs
        // Disk health of the demo services (mode and reading).
        for id in ids { SMARTSettingsStore.remove(id) }
        let pins = (try? context.fetch(FetchDescriptor<HomeAssistantPin>())) ?? []
        for pin in pins where ids.contains(pin.serviceID) { context.delete(pin) }
        let favorites = (try? context.fetch(FetchDescriptor<PromQLFavorite>())) ?? []
        for favorite in favorites where ids.contains(favorite.serviceID) { context.delete(favorite) }
        try? context.save()
    }
}

/// Reserves the banner's height at the top of a tab, above its navigation bar
/// (large and inline titles alike).
struct DemoBannerInset: ViewModifier {
    let isOn: Bool
    let onExit: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if isOn {
                DemoBanner(onExit: onExit)
            }
        }
    }
}

/// Always visible while the demo runs: says the data is fictitious and leaves the
/// demo in one tap.
struct DemoBanner: View {
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text("Demo: sample data, no server contacted")
            } icon: {
                Image(systemName: "sparkles.rectangle.stack")
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(2)
            Spacer(minLength: 8)
            Button("Exit demo", action: onExit)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // Opaque: content scrolling under the navigation bar must not show through.
        .background {
            Rectangle().fill(.background).overlay(.orange.opacity(0.18))
        }
        .accessibilityElement(children: .contain)
    }
}

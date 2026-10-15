import Foundation

/// One service of the demo HomeLab: a fixed ID (so choices made in demo mode can
/// be recognised and cleaned up), a demo host and a fake credential of the right
/// shape. Nothing here is stored in the Keychain or SwiftData.
public struct DemoService: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: ServiceKind
    public let name: String
    public let url: URL
    public let credential: String
}

/// The demo HomeLab: one service of every type, answered on the device by the
/// families' demo responders (`DemoServer`).
public enum DemoCatalog {
    public static let services: [DemoService] = ServiceKind.allCases.enumerated().map { index, kind in
        DemoService(
            id: UUID(uuidString: String(format: "D3E0D3E0-0000-4000-8000-%012d", index + 1))!,
            kind: kind,
            name: name(for: kind),
            url: url(for: kind),
            credential: credential(for: kind)
        )
    }

    public static let serviceIDs: Set<UUID> = Set(services.map(\.id))

    public static func service(id: UUID) -> DemoService? {
        services.first { $0.id == id }
    }

    public static func host(for kind: ServiceKind) -> String {
        "\(hostLabel(for: kind)).\(DemoServer.domain)"
    }

    public static func url(for kind: ServiceKind) -> URL {
        let host = host(for: kind)
        return switch kind {
        case .proxmoxVE: URL(string: "https://\(host):8006")!
        case .proxmoxBackupServer: URL(string: "https://\(host):8007")!
        case .uptimeKuma: URL(string: "https://\(host)/status/homelab")!
        default: URL(string: "https://\(host)")!
        }
    }

    private static func hostLabel(for kind: ServiceKind) -> String {
        switch kind {
        case .proxmoxVE: "proxmox"
        case .proxmoxBackupServer: "pbs"
        case .dockerPortainer: "portainer"
        case .dockerSocketProxy: "docker"
        case .tailscale: "tailscale"
        case .grafana: "grafana"
        case .prometheus: "prometheus"
        case .alertmanager: "alertmanager"
        case .uptimeKuma: "status"
        case .crowdSec: "crowdsec"
        case .homeAssistant: "home"
        case .adGuardHome: "adguard"
        case .nginxProxyManager: "npm"
        case .glances: "glances"
        }
    }

    /// Short names: the whole screen is labelled "Demo" already.
    private static func name(for kind: ServiceKind) -> String {
        switch kind {
        case .proxmoxVE: "Demo cluster"
        case .proxmoxBackupServer: "Demo PBS"
        case .dockerPortainer: "Demo Portainer"
        case .dockerSocketProxy: "Demo NAS"
        case .tailscale: "Demo tailnet"
        case .grafana: "Demo Grafana"
        case .prometheus: "Demo Prometheus"
        case .alertmanager: "Demo Alertmanager"
        case .uptimeKuma: "Demo status page"
        case .crowdSec: "Demo CrowdSec"
        case .homeAssistant: "Demo home"
        case .adGuardHome: "Demo AdGuard"
        case .nginxProxyManager: "Demo NPM"
        case .glances: "Demo server"
        }
    }

    /// Fake values of the shape each provider expects.
    private static func credential(for kind: ServiceKind) -> String {
        switch kind {
        case .proxmoxVE: "demo@pve!patchnode=00000000-0000-0000-0000-000000000000"
        case .proxmoxBackupServer: "demo@pbs!patchnode:00000000-0000-0000-0000-000000000000"
        case .dockerPortainer: "ptr_demo"
        case .grafana: "glsa_demo"
        case .tailscale: "demo-client:tskey-client-demo"
        case .crowdSec: "demo-bouncer-key"
        case .nginxProxyManager: "demo@patchnode-demo.invalid:demo"
        case .homeAssistant: "demo-token"
        case .uptimeKuma: ""
        case .dockerSocketProxy, .prometheus, .alertmanager, .adGuardHome, .glances: "demo:demo"
        }
    }
}

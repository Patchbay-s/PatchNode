/// Groups of the service type picker, in display order.
public enum ServiceCategory: String, Sendable, CaseIterable, Hashable {
    case virtualization
    case docker
    case observability
    case networkAndSecurity
    case home

    /// Kinds of this category, in display order.
    public var kinds: [ServiceKind] {
        switch self {
        case .virtualization: [.proxmoxVE, .proxmoxBackupServer]
        case .docker: [.dockerPortainer, .dockerSocketProxy]
        case .observability: [.prometheus, .alertmanager, .grafana, .uptimeKuma, .glances]
        case .networkAndSecurity: [.tailscale, .crowdSec, .nginxProxyManager, .adGuardHome]
        case .home: [.homeAssistant]
        }
    }
}

extension ServiceKind {
    public var category: ServiceCategory {
        ServiceCategory.allCases.first { $0.kinds.contains(self) } ?? .virtualization
    }
}

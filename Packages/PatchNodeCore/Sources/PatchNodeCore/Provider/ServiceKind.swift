public enum ServiceKind: String, Sendable, Codable, CaseIterable {
    case proxmoxVE
    case proxmoxBackupServer
    case dockerPortainer
    case dockerSocketProxy
    case tailscale
    case grafana
    case prometheus
    case alertmanager
    case uptimeKuma
    case crowdSec
    case homeAssistant
    case adGuardHome
    case nginxProxyManager
    case glances
}

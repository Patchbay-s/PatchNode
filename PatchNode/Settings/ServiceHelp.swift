import Foundation
import PatchNodeCore

enum ServiceHelp {
    static func text(for kind: ServiceKind) -> String {
        switch kind {
        case .proxmoxVE:
            return String(localized: "In Datacenter > Permissions, create a dedicated user (e.g. monitor@pve), then an API token for it (e.g. PatchNode). Paste the full token value as user@realm!tokenid=secret.\nReading: role PVEAuditor on /, for the user and for the token:\npveum acl modify / --roles PVEAuditor --users monitor@pve\npveum acl modify / --roles PVEAuditor --tokens 'monitor@pve!PatchNode'\nActions (start, shut down, reboot): rather than PVEVMUser, create a role with the VM.PowerMgmt privilege only, on /vms (or /vms/<id> for a single VM). A role on a path below / replaces the inherited ones: grant PVEAuditor with it there, or the guests vanish from PatchNode:\npveum role add PatchNodePower --privs VM.PowerMgmt\npveum acl modify /vms --roles 'PVEAuditor,PatchNodePower' --users monitor@pve\npveum acl modify /vms --roles 'PVEAuditor,PatchNodePower' --tokens 'monitor@pve!PatchNode'\nWith Privilege Separation ticked, the token only has the rights both it and its user have: grant them to both, as above.")
        case .dockerPortainer:
            return String(localized: "In Portainer, create a dedicated standard (non-admin) user with access only to the environments to monitor (Read-only user role on Business Edition), then My account > Access tokens > Add access token, and paste the token. Use the Portainer URL itself.")
        case .dockerSocketProxy:
            return String(localized: "Put a read-only socket proxy (e.g. tecnativa/docker-socket-proxy with CONTAINERS=1, INFO=1, POST=0) behind an HTTPS reverse proxy with Basic authentication. With Nginx Proxy Manager: Access Lists > Add Access List, Authorization tab, add a user name and password; select that Access List on the proxy host, then enter the same user name and password below. Never expose /var/run/docker.sock or the raw port 2375: that gives full root access to the host.")
        case .prometheus:
            return String(localized: "Prometheus has no token: keep it reachable only through your private network. If a reverse proxy adds Basic authentication (e.g. an Nginx Proxy Manager Access List), enter its user name and password, otherwise leave both fields empty.")
        case .alertmanager:
            return String(localized: "Alertmanager has no token: keep it reachable only through your private network. If a reverse proxy adds Basic authentication (e.g. an Nginx Proxy Manager Access List), enter its user name and password, otherwise leave both fields empty. Silenced alerts are not shown.")
        case .grafana:
            return String(localized: "In Grafana, Administration > Users and access > Service accounts: create an account with the Viewer role, then add a token and paste it. Dashboards open in an embedded browser where you sign in normally: the token is never put in a URL.")
        case .uptimeKuma:
            return String(localized: "Enter the URL of a public status page (…/status/<slug>). No token is needed; only the monitors shown on that page are read.")
        case .proxmoxBackupServer:
            return String(localized: "In Configuration > Access Control, create a dedicated user, then an API token for it (API Token tab). Grant the Audit role on / (read-only). Paste the full token value as user@realm!tokenid:secret.")
        case .tailscale:
            return String(localized: "In the Tailscale admin console, Settings > Trust credentials: create an OAuth client with the devices:core:read scope only (read), then enter client-id:client-secret. The app exchanges it for a 1-hour access token kept in memory only. Tailscale is the only service reached outside your private network (api.tailscale.com).")
        case .crowdSec:
            return String(localized: "On the CrowdSec host, run cscli bouncers add PatchNode and paste the key. Use the Local API URL behind your HTTPS reverse proxy. Only local detections and manual bans are shown; the bouncer API gives no country for IP bans.")
        case .nginxProxyManager:
            return String(localized: "In Nginx Proxy Manager, Users > Add User: create a dedicated user with the View Only permission for proxy hosts, then enter its e-mail and password. The app gets a session token from it, kept in memory only.")
        case .adGuardHome:
            return String(localized: "Create a dedicated AdGuard Home user (users section of AdGuardHome.yaml) and enter its user name and password. AdGuard Home has no read-only role: this user can change the DNS settings, so keep the service reachable only through your private network.")
        case .homeAssistant:
            return String(localized: "Sign in to Home Assistant with a dedicated non-admin user, then Profile > Security > Long-lived access tokens: create a token and paste it. Choose the entities to show afterwards; scenes and scripts run only after a confirmation.")
        case .glances:
            return String(localized: "Run Glances in web server mode (glances -w) behind your HTTPS reverse proxy. If it was started with --password, enter the user name and password (the default user is glances), otherwise leave both fields empty. Tip: add --disable-plugin processlist to make each refresh much lighter.")
        }
    }

    /// Example URL for the type. Generic placeholders: no real host.
    static func urlPlaceholder(for kind: ServiceKind) -> String {
        switch kind {
        case .proxmoxVE: "https://proxmox.example.invalid:8006"
        case .proxmoxBackupServer: "https://pbs.example.com:8007"
        case .dockerPortainer: "https://portainer.example.com"
        case .dockerSocketProxy: "https://docker.example.com"
        case .prometheus: "https://prometheus.example.com"
        case .alertmanager: "https://alertmanager.example.com"
        case .grafana: "https://grafana.example.com"
        case .uptimeKuma: "https://status.example.com/status/home"
        case .tailscale: "https://api.tailscale.com"
        case .crowdSec: "https://crowdsec.example.com"
        case .nginxProxyManager: "https://npm.example.com"
        case .adGuardHome: "https://adguard.example.com"
        case .homeAssistant: "https://ha.example.com"
        case .glances: "https://glances.example.com"
        }
    }

    /// Shape of the credential for the type (not a real value). Two-field
    /// credentials (user and password) have none.
    static func credentialPlaceholder(for kind: ServiceKind) -> String {
        switch kind {
        case .proxmoxVE: "monitor@pve!PatchNode=xxxxxxxx-xxxx-…"
        case .proxmoxBackupServer: "monitor@pbs!PatchNode:xxxxxxxx-xxxx-…"
        case .dockerPortainer: "ptr_…"
        case .tailscale: "client-id:tskey-client-…"
        case .crowdSec: String(localized: "Bouncer key")
        case .grafana: "glsa_…"
        case .homeAssistant: "eyJ…"
        case .dockerSocketProxy, .adGuardHome, .nginxProxyManager, .prometheus, .alertmanager, .glances, .uptimeKuma: ""
        }
    }

    /// Label of the single credential field (two-field credentials use User /
    /// Password).
    static func credentialLabel(for kind: ServiceKind) -> String {
        switch kind {
        case .dockerPortainer: String(localized: "Access token")
        case .grafana: String(localized: "Service account token")
        case .uptimeKuma: String(localized: "No credential needed")
        case .tailscale: String(localized: "client-id:client-secret")
        case .crowdSec: String(localized: "Bouncer key")
        case .homeAssistant: String(localized: "Long-lived access token")
        default: String(localized: "API token")
        }
    }
}

extension ServiceCategory {
    var title: String {
        switch self {
        case .virtualization: String(localized: "Virtualization")
        case .docker: "Docker"
        case .observability: String(localized: "Observability")
        case .networkAndSecurity: String(localized: "Network and security")
        case .home: String(localized: "Home")
        }
    }
}

extension ServiceKind {
    /// Product names, shown as-is in every language.
    var displayName: String {
        switch self {
        case .proxmoxVE: "Proxmox VE"
        case .proxmoxBackupServer: "Proxmox Backup Server"
        case .dockerPortainer: "Portainer"
        case .dockerSocketProxy: String(localized: "Docker (socket proxy)")
        case .tailscale: "Tailscale"
        case .grafana: "Grafana"
        case .prometheus: "Prometheus"
        case .alertmanager: "Alertmanager"
        case .uptimeKuma: "Uptime Kuma"
        case .crowdSec: "CrowdSec"
        case .homeAssistant: "Home Assistant"
        case .adGuardHome: "AdGuard Home"
        case .nginxProxyManager: "Nginx Proxy Manager"
        case .glances: "Glances"
        }
    }
}

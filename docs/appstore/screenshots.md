# Screenshots to take (in demo mode)

Required: iPhone 6.9" (1320 × 2868 portrait, e.g. iPhone 17 Pro Max). App Store
Connect scales them for smaller iPhones. iPad is not supported (iPhone-only app):
no iPad screenshots.

Preparation:
- Settings › Demo › Try the demo. Light mode for the set (optionally a dark set).
- Status bar: 9:41, full battery, Wi-Fi (Xcode › Simulator or a device in Demo Mode).
- Keep the orange demo banner: it's honest, and it's what reviewers see. If a clean
  set is wanted, the banner is the only difference with real data.
- Take the English set, then switch the device to French for the French set.
  Spanish, German and Italian (1.1): same set with the device in each language, or reuse
  the English set (App Store Connect falls back to the primary language's screenshots).

| # | Screen | What it shows | Caption (en / fr) |
| --- | --- | --- | --- |
| 1 | Dashboard | Cards: Proxmox, Docker, Observability, PBS, Tailscale, Security | Your whole HomeLab at a glance / Tout votre HomeLab d'un coup d'œil |
| 2 | Proxmox | Two nodes, VMs and containers, failed task badge | Proxmox nodes, VMs and containers / Nœuds, VM et conteneurs Proxmox |
| 3 | VM detail (homeassistant) | CPU / memory / network charts, day view | Charts per hour, day or week / Graphiques heure, jour, semaine |
| 4 | Action confirmation | "Shut down VM 101 network-appliance on node-a?" sheet | Every action names its target / Chaque action nomme sa cible |
| 5 | Docker | Hosts and stacks, one unhealthy, one exited with error | Docker containers, health and logs / Conteneurs Docker, santé et journaux |
| 6 | Observability | Critical and warning alerts, target down, status page | Alerts that matter first / Les alertes importantes d'abord |
| 7 | Security | CrowdSec bans, NPM hosts, AdGuard stats | Network and security / Réseau et sécurité |
| 8 | Home Screen with widgets | Small status + medium Proxmox nodes widgets | Widgets for your Home Screen / Widgets pour l'écran d'accueil |
| 9 | Settings › Tabs | Tab bar choice | Your tabs, your way / Vos onglets, à votre façon |
| 10 | Onboarding page 2 | Private network, HTTPS, Keychain | Private by design / Confidentiel par conception |

Widgets show the user's last real data (the demo publishes no widget data): for #8,
take the capture with a real HomeLab, or skip it.

Optional: App Preview video (15–30 s) scrolling the dashboard and opening a VM.

# App Review notes (App Store Connect › App Review Information › Notes)

Paste the English text below. No demo account is needed: the app has no account.

---

PatchNode monitors the user's own self-hosted servers (Proxmox, Docker, Prometheus, Home Assistant…) over their private network. There is no account and no server run by us, so without a HomeLab the app would be empty.

To review every feature, please use the built-in DEMO MODE. It shows a complete sample HomeLab generated on the device; no network request is made.

How to open the demo:
1. Launch the app and unlock it with Face ID or the device passcode (the app is protected by device authentication).
2. On the introduction, swipe to the last page and tap "Try the demo".
   - Later, the demo can be started or stopped from Settings › Demo, or from the empty Dashboard.
   - On a device without a passcode, the lock screen offers "Explore the demo".
3. An orange banner at the top of every screen shows "Demo: sample data, no server contacted" with an "Exit demo" button.

In the demo you can:
- Browse the Dashboard, Proxmox (open a VM for its charts), Docker (open a container for its logs), Observability (alerts, PromQL charts), Security (CrowdSec, Nginx Proxy Manager, AdGuard Home), Tailscale, Home Assistant and Glances.
- Try actions: open a VM or container and tap Shut down, Start or Restart. A confirmation naming the target appears, then Face ID; the action is simulated and the state changes.
- Choose the tab bar screens in Settings › Tabs.

Grafana dashboards are web pages of the user's own Grafana, so they are not available in the demo.

New in 1.1, also visible in the demo: Proxmox › Disk health (a failed disk and a degraded ZFS pool), a TLS certificate about to expire (banner on the Dashboard, Settings › Diagnostics), Settings › Notifications, Settings › Export and import, Settings › iCloud (not available while the demo runs).

No VPN functionality: the app does not use NetworkExtension and does not create, configure or manage any VPN tunnel or network setting. Tailscale is only one of the monitored services: with a read-only OAuth client the user creates, the app reads the list of devices of their tailnet through Tailscale's public API (api.tailscale.com) and displays it. Users who reach their servers through a VPN set it up themselves, outside the app.

New in 1.2 — SSH client and consoles, also in the demo: PatchNode can open terminal sessions to the user's OWN servers only: Proxmox consoles through the Proxmox API (Proxmox › a VM or container › Console; or swipe right on a node), an SSH terminal (Settings › SSH, off by default; the key is created on the device and never leaves it), and Docker Compose management (Docker › a stack › Manage the project). There is no server of ours and no third-party service involved; the user adds every host. In the demo, consoles, SSH sessions and compose actions are simulated on the device (Proxmox › a container › Console or Enter the container; a VM › Console shows a simulated graphical console; Docker › a stack › Manage the project). The graphical console uses noVNC, a JavaScript library bundled in the app and loaded locally (no code is downloaded). Every session asks for Face ID; nothing typed is stored.

Network: the app only connects to servers the user adds (HTTPS for APIs, SSH for the SSH terminal) and to api.tailscale.com if the user adds Tailscale. Encryption: HTTPS through Apple's frameworks, and SSH (standard algorithms, ed25519/curve25519/AES-GCM/ChaCha20-Poly1305) through Apple's open-source SwiftNIO SSH and Swift Crypto — export compliance to be confirmed for 1.2 (see docs/RELEASE.md).

Privacy: no data is collected; tokens stay in the device Keychain.

iCloud sync (1.1): off by default (Settings › iCloud). When the user turns it on, the configuration (service names and addresses, charts, tabs) is stored in the user's own private CloudKit database, and, only with a separate option also off by default, the tokens in iCloud Keychain. The developer has no access to either, and no account of ours is needed. Notifications are local (posted by the device after a background refresh), never pushed from a server.

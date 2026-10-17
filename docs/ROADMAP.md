# PatchNode — roadmap

Last updated: 2026-10-17.

This public roadmap tracks product-level work only. Device and server names,
addresses, credentials, and environment-specific test notes do not belong here.

## Available

PatchNode provides a native dashboard for iPhone and iPad, and runs on Apple
silicon Macs as a Designed for iPad app. It supports Proxmox VE and Backup
Server, Docker through Portainer or a socket proxy, Tailscale, Grafana,
Prometheus, Alertmanager, Uptime Kuma, CrowdSec, Nginx Proxy Manager, AdGuard
Home, Home Assistant, and Glances.

Other available features include widgets, shortcuts, local notifications,
optional iCloud configuration sync, export and import, SSH and Proxmox
consoles, Docker Compose management, and demo mode.

## In preparation: 1.3

- [x] New app icon.
- [x] E-mail support (patchbay-s@proton.me) in the app, the website and the
      privacy policy.
- [ ] On-device checks (see [TESTS.md](TESTS.md)), then App Store submission.

## Next

- [ ] Continue accessibility review and improve VoiceOver coverage.
- [ ] Have Spanish, German, and Italian interface text reviewed by native
      speakers.
- [ ] Expand compatibility testing across supported service versions.
- [ ] Evaluate additional services proposed through the
      [new service issue template](../.github/ISSUE_TEMPLATE/new_service.yml).

No Apple Watch app is planned.

## How to follow progress

Use the repository's open issues and pull requests for current implementation
details. Release-specific tasks are listed in [RELEASE.md](RELEASE.md).

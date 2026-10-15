# Security policy

PatchNode holds credentials to people's own servers. Security reports are
welcome and handled first.

## Reporting a vulnerability

**Please do not open a public issue.** Report it privately through GitHub
Security Advisories:

1. Go to the [Security tab](https://github.com/Patchbay-s/PatchNode/security) of
   the repository.
2. Click **Report a vulnerability**.
3. Describe the problem, the affected version (Settings › About in the app, or
   a commit) and the steps to reproduce. Do not include real tokens, addresses
   or host names: use fabricated values.

You should get a first answer within 7 days. Once a fix is released, the
advisory is published with credit to the reporter, unless you prefer to stay
anonymous.

## Supported versions

Only the latest version published on the App Store and the repository's default
branch
receive security fixes.

## Security model

What PatchNode is designed to guarantee:

- **Credentials stay in the Keychain.** Tokens, passwords and the SSH key are
  stored only in the system Keychain, by default available on this device only
  when it is unlocked and never synchronized. An explicit option, off by
  default and protected by Face ID or Touch ID, can store them in iCloud
  Keychain (end-to-end encrypted by Apple). The SSH key of the device never
  leaves it.
- **Each credential is bound to its server.** A token is only sent to the
  origin (scheme, host, port) it was saved for.
- **No third-party server.** The app talks directly to the services you
  configure, plus `api.tailscale.com` if you add Tailscale. There is no account,
  no backend, no analytics and no telemetry. Optional iCloud sync of the
  configuration uses your own private CloudKit database and never includes
  secrets unless you enable the Keychain option above.
- **Private network access.** PatchNode is meant to reach your services over
  your LAN or a VPN such as Tailscale or WireGuard. It does not need, and the
  guides advise against, exposing your admin interfaces to the internet.
- **Transport.** HTTPS only, no App Transport Security exception, certificates
  checked by the system. SSH host keys are pinned on first use and confirmed on
  each device.
- **Least privilege.** The in-app guides create dedicated, read-only
  credentials (for example a Proxmox token with the `PVEAuditor` role); actions
  need an explicit extra right and a confirmation naming the target.
- **Logs.** Authentication headers are masked in every log, terminal and file
  contents are never logged.
- **Local protection.** Face ID / Touch ID (or the device passcode) to open the
  app and when it comes back to the foreground, content hidden in the app
  switcher, Face ID before every console, SSH session or Compose change.

Out of scope: the security of the servers you connect to, of your VPN and of a
device that is unlocked by someone else.

# Contributing to PatchNode

Thanks for your interest in PatchNode. Focused issues and small pull requests
are the easiest to review.

- Bugs and ideas: [open an issue](https://github.com/Patchbay-s/PatchNode/issues/new/choose)
  (there are templates for bugs, features and new services).
- Security problems: **do not open a public issue**, see [SECURITY.md](SECURITY.md).

## Setup

Requirements: a Mac with the Xcode version that supports the deployment target
of the project (iOS / iPadOS 27, macOS 27 for the "Designed for iPad" Mac app),
and Swift 6.

```bash
git clone https://github.com/Patchbay-s/PatchNode.git
cd PatchNode
cp Config/Local.xcconfig.example Config/Local.xcconfig
open PatchNode.xcodeproj
```

`Config/Local.xcconfig` holds the settings that belong to your Apple Developer
account. It is ignored by git and included by `Config/Base.xcconfig`:

```text
DEVELOPMENT_TEAM = ABCDE12345   // your Team ID (Xcode › Settings › Accounts, or developer.apple.com › Membership)
```

Never set `DEVELOPMENT_TEAM` in the Xcode project itself:
`scripts/check-pbxproj.sh` rejects it.

The simulator needs no team. To run on your own device with a personal team,
The bundle identifier and its App Group and iCloud container are already
registered to the App Store app: keep them unchanged when building the official
app. For a personal fork, change them locally to your own prefix and do not
commit that change.

## Build and test

```bash
# App (simulator, no signing)
xcodebuild -scheme PatchNode -destination 'generic/platform=iOS Simulator' build

# Unit tests of every package (most of them also run on Linux)
for p in Packages/*/; do (cd "$p" && swift test); done

# Static checks, run them before every pull request
scripts/check-pbxproj.sh        # Xcode project consistency
scripts/check-environment.sh    # SwiftUI environment injection
scripts/check-shipped-hosts.sh  # no private address or host name in the code
```

The project has unit tests only (Swift Testing), no UI tests. A pull request
must keep every package test and every script green.

## Conventions

- **Swift 6, strict concurrency.** `async`/`await` and actors; no
  `@unchecked Sendable` without a comment that explains why it is safe.
- **SwiftUI with Observation** (`@Observable`), no `ObservableObject`.
- **No new third-party dependency** without an issue discussing it first. The
  current ones are pinned to an exact version and their licenses ship with the
  app (Settings › About › Licenses).
- **The Xcode project uses synchronized folders**: a file added under
  `PatchNode/` or `PatchNodeWidgets/` is part of the target. Run
  `scripts/check-pbxproj.sh` after any change to the project.
- **Localization.** English is the development language. Every user-facing
  string goes through the String Catalogs (`Localizable.xcstrings`,
  `InfoPlist.xcstrings`) and exists in English, French, Spanish, German and
  Italian. If you can't translate, add the English string and say so in the
  pull request; it will be marked `needs_review`.
- **Commits**: one logical change per commit, imperative subject
  (`fix(docker): decode multiplexed logs with a TTY`), signed off (see DCO
  below).

### Security rules (non-negotiable)

These rules protect people who point the app at their own servers. A pull
request that breaks one will not be merged.

- Secrets (tokens, passwords, keys) are stored only in the Keychain, through
  `KeychainSecretStore`, never in SwiftData, CloudKit, `UserDefaults`, logs or
  code. Each secret is bound to the origin of its server and is never sent to
  another origin.
- HTTPS only. No App Transport Security exception, no delegate that accepts an
  invalid certificate.
- `Authorization`, `X-API-Key` and similar headers are masked in every log,
  even in debug builds.
- 10 s timeout, spaced retries, never a retry on 401/403 or on a POST (a burst
  of failed logins can get the user banned by their own IPS).
- Every action that changes a state (start, stop, restart, apply a Compose
  file…) asks for an explicit confirmation that names its target.
- No address, domain or host name of a real installation in the code, the
  tests or the docs. Use the documentation ranges (`192.0.2.0/24`,
  `198.51.100.0/24`, `203.0.113.0/24`) and `example.com` /
  `homelab.example`.
- No analytics, no telemetry, no server of the developer.

## Adding a new service type

Each family of services lives in its own Swift package under `Packages/` and
conforms to the `ServiceProvider` protocol of `PatchNodeCore`:

```swift
public protocol ServiceProvider: Sendable {
    var id: UUID { get }
    var kind: ServiceKind { get }
    var displayName: String { get }
    func healthCheck() async throws -> HealthStatus
    func summary() async throws -> ServiceSummary
}
```

Steps, in order:

1. **Open an issue first** with the "New service" template: the API, the
   authentication and the least-privileged credential it allows.
2. Add a case to `ServiceKind` and place it in a `ServiceCategory`
   (`Packages/PatchNodeCore/Sources/PatchNodeCore/Provider/`). The SwiftData
   schema stores the raw value: never rename or remove an existing case.
3. Implement the client and the provider in the package of its family (or a new
   package if none fits), using the shared HTTP client of `PatchNodeCore`.
   Read-only by default.
4. Add unit tests with **fabricated** fixtures (never a copy of a real response
   from your own servers): parsing, `null` and missing fields, 401/403
   handling, no retry on POST.
5. Add demo data in `DemoCatalog` so the service appears in the demo mode.
6. Wire the app: `AppModel` (provider creation), the dashboard card, the tab or
   screen, and the add-service help (`ServiceHelp`).
7. Write the in-app guide (`Packages/PatchNodeCore/Sources/PatchNodeCore/Guides/`):
   where to create the credential, which rights, how to keep the service on the
   private network.
8. Translate every new string (see Localization) and update `docs/SPEC.md`
   (credentials table and API reference).

## Developer Certificate of Origin (DCO)

Every commit must be signed off. By signing off, you certify the
[Developer Certificate of Origin 1.1](https://developercertificate.org/): you
wrote the change, or have the right to submit it under the project's license.

```bash
git commit -s -m "feat(proxmox): show the last backup of a guest"
```

This adds a line `Signed-off-by: Your Name <you@example.com>` that must match
the commit author. To sign off commits you already made:
`git rebase --signoff main`.

## License of contributions and app store distribution

PatchNode is licensed under the [GPL-3.0](LICENSE), with an **additional
permission** that allows distribution through Apple's App Store and similar
app stores (see [NOTICE](NOTICE)).

By submitting a contribution, you agree that it is licensed under the GPL-3.0
**including this additional permission**, so that it can ship in the official
app on the App Store. Contributions that cannot be accepted on these terms
cannot be merged.

The project's names and icon are not covered by the license: see
[TRADEMARKS.md](TRADEMARKS.md).

# App Store Connect — App Privacy questionnaire

## Data collection
- "Do you or your third-party partners collect data from this app?" → **No, we do not
  collect data from this app.**
- Result shown on the App Store: **Data Not Collected**.

Why this is accurate (Apple's definition: "collect" = transmitted off the device in a
way that allows you or partners to access it beyond servicing the request in real time):
- No analytics, crash reporting SDK, advertising or third-party SDK (no external
  dependency at all).
- Everything the user types stays on the device (SwiftData in the app's private
  container, Keychain `WhenUnlockedThisDeviceOnly`, UserDefaults for preferences),
  unless the user turns on iCloud sync (1.1, below).
- Network traffic goes only to the user's own servers and, for Tailscale, to
  api.tailscale.com on the user's behalf with the user's credential. The developer
  receives nothing.
- Crash reports from Apple (opt-in by the user, via App Store Connect) are not
  collection by the app.

## iCloud sync (1.1, optional, off by default)
- Configuration (services' names and addresses, PromQL charts, Home Assistant
  entities, tabs, dashboard order): SwiftData + CloudKit, **the user's private
  database** (`iCloud.fr.antxis.apple.labwatch`). Tokens (separate option): iCloud
  Keychain, end-to-end encrypted.
- The developer can't read a user's private CloudKit database or iCloud Keychain
  (the CloudKit Dashboard only shows the developer's own test account data). Apple's
  definition of collection requires data the developer or partners can access:
  **answer unchanged, "Data Not Collected"**. Apple's guidance treats data stored in
  the user's own iCloud, out of the developer's reach, as not collected.
- The privacy policy describes it (section "iCloud sync").
- Review notes: mention that sync is off by default and needs no account of ours.

## iOS reports (MetricKit, 1.1)
- The app subscribes to `MXMetricManager`: crash, hang, resource and daily
  performance reports iOS delivers to it are stored in the app's container (30
  days, 50 reports at most) and shown in Settings › Diagnostics › iOS reports.
- Nothing is transmitted by the app. The user may share a report through the share
  sheet, or attach a crash summary (off by default, previewed, no URL/host/service
  name/token/call stack, tested) to a support e-mail they send themselves: same
  reasoning as the diagnostic report below. **Answer unchanged: "Data Not
  Collected".**

## Support e-mail (Settings › Help and support › Contact support)
How it works: the app prefills a message in the system Mail composer
(`MFMailComposeViewController`), or opens a `mailto:` link, or copies the address. The
user reviews and sends it from their own mail account. The app itself makes no network
request; there is no backend.

What reaches the developer, only if the user sends the e-mail: their e-mail address
(as sender), the text they typed, and — only if they turn it on, off by default, with
the full text previewed — a diagnostic report (app and iOS versions, device model,
language, service types, demo mode, classification and HTTP code of the latest errors
per service type; never a URL, host, address, service name, token or content).

**Recommended answer: stay "Data Not Collected".** Apple's App Privacy definitions
exclude data that meets all the "optional disclosure" criteria: not used for tracking
or advertising, collected infrequently, optional for the user, and provided by the user
through a clearly visible interface where they choose to send it. A support e-mail
the user writes, reviews and sends from Mail matches all of them, and the app never
transmits it on its own.

Conservative alternative (if Apple Review asks, or if you prefer to declare it):
- Contact Info › **Email Address** — App Functionality (customer support), linked to
  the user, not used for tracking.
- User Content › **Customer Support** — App Functionality, linked to the user, not
  used for tracking.
- Diagnostics › **Other Diagnostic Data** — App Functionality, linked to the user (it
  arrives in an e-mail from them), not used for tracking.
Either way, update the privacy policy's Support section (already written) and keep
the mailbox dedicated to support.

## Tracking
- "Do you use data for tracking?" → **No.** `NSPrivacyTracking = false`, no tracking
  domains.

## Privacy manifests (checked in)
- `PatchNode/PrivacyInfo.xcprivacy`: no tracking, no collected data types; required
  reason API: UserDefaults `CA92.1` (the app's own preferences).
- `PatchNodeWidgets/PrivacyInfo.xcprivacy`: no tracking, no collected data, no
  required-reason API (the widget reads a JSON file from the App Group).
- No file timestamp, system boot time, disk space or keyboard APIs are used.

## Export compliance
- `ITSAppUsesNonExemptEncryption = NO` in `PatchNode/Info.plist`: only HTTPS/TLS and the
  Keychain through Apple's frameworks (exempt). No export documentation needed.

## Other App Store Connect answers
- Sign-in required: **No** (no account). Demo: built-in demo mode (see review-notes.md).
- Support URL (required by App Store Connect): the site's support page (see
  `site/README.md`).
- Content rights: the app shows only the user's own data.
- Advertising identifier (IDFA): **not used**.

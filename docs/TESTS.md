# PatchNode — verification checklist

This checklist is safe to publish: use demo data or a deliberately isolated
test environment. Do not add real server names, addresses, credentials,
diagnostic exports, or screenshots from a live installation to the repository.

## Repository checks

- [x] `git diff --check`
- [x] `scripts/check-pbxproj.sh`
- [x] `scripts/check-environment.sh`
- [x] `scripts/check-shipped-hosts.sh`
- [ ] Run `swift test` in every package on the maintainer's Mac.
- [ ] Build the app with Xcode on the maintainer's Mac:

  ```sh
  xcodebuild -project PatchNode.xcodeproj -scheme PatchNode \
    -destination 'generic/platform=iOS' build
  ```

The app and Apple-platform tests were not built in the static audit environment.

## On-device checks after an update

- [ ] Install the update over the existing app; do not delete the previous
      installation first.
- [ ] Confirm saved services, their settings, and saved credentials are still
      present and usable. Verify this before removing the previous app version.
- [ ] Confirm widgets, shortcuts, and configuration preferences still work.
- [ ] Confirm the app and widget display name is PatchNode.
- [ ] Check the English, French, Spanish, German, and Italian display names and
      key screens.
- [ ] Exercise demo mode and the main screens for each supported service.
- [ ] Confirm export files and diagnostic sharing contain no credentials or
      real installation details.
- [ ] Check the privacy and support links after GitHub Pages is published.

## Screenshot review

- [ ] Capture only in demo mode or with fabricated data.
- [ ] Before committing any capture, inspect and blur or replace every address,
      domain, host name, user name, token, and serial number.
- [ ] Review the full image at readable zoom; do not rely only on a thumbnail.

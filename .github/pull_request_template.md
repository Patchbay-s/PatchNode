## What and why

<!-- What this pull request changes and the problem it solves. Link the issue: "Closes #…" -->

## How it was tested

<!-- Device(s) and OS version, services and versions tested against, or "unit tests only". -->

- [ ] `swift test` passes in every package I touched
- [ ] `scripts/check-pbxproj.sh`, `scripts/check-environment.sh` and `scripts/check-shipped-hosts.sh` pass
- [ ] The app builds in Xcode

## Checklist

- [ ] No token, password, real IP address, domain or host name anywhere (code, tests, screenshots); fabricated values only (`192.0.2.0/24`, `homelab.example`)
- [ ] Secrets only through `KeychainSecretStore`; HTTPS only; auth headers masked in logs
- [ ] Every action that changes a state asks for a confirmation that names its target
- [ ] New user-facing strings are in the String Catalogs (English, plus French, Spanish, German and Italian if I can)
- [ ] Every commit is signed off (`git commit -s`, see CONTRIBUTING.md)
- [ ] I agree that this contribution is licensed under the GPL-3.0 with the app store additional permission described in NOTICE

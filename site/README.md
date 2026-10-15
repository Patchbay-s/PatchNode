# PatchNode website

Static pages for PatchNode: home, privacy policy and support, in English (root),
French (`fr/`), Spanish (`es/`), German (`de/`) and Italian (`it/`). No
JavaScript, no cookies, no analytics.

The pages are generated: edit `scripts/build-site.py` (texts, support address)
or `docs/appstore/privacy-policy.md` (privacy policy), then run

```sh
python3 scripts/build-site.py
```

from the repository root and commit the result.

## Publishing

`.github/workflows/pages.yml` deploys this folder to GitHub Pages on every push
to `main` or the current migration branch that touches `site/`. In the repository settings, set
Settings › Pages › Source to **GitHub Actions**.

This folder is deployed from this repository by GitHub Actions.

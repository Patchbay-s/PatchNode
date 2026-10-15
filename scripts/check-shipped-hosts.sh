#!/bin/sh
# Fails if a developer-specific host, domain or private address appears in what
# ships in the app (targets' folders, packages' sources, asset catalog).
# Your own domains and host names go in scripts/private-patterns.txt (one
# extended regex per line, ignored by git): they are checked too, in the whole
# tree, without ever being committed.
set -eu
cd "$(dirname "$0")/.."

shipped="PatchNode PatchNodeWidgets Assets.xcassets"
for package in Packages/*/Sources; do shipped="$shipped $package"; done
for path in $shipped; do
    [ -e "$path" ] || { echo "check-shipped-hosts: missing $path" >&2; exit 2; }
done

# RFC 1918 and CGNAT (Tailscale) addresses; .lan / .home.arpa hosts; tailnet
# names. Docker's default bridge (172.17-18.x) and the demo tailnet
# (tail-demo.ts.net) are allowed.
pattern='192\.168\.[0-9]+\.[0-9]+|(^|[^0-9.])10\.[0-9]+\.[0-9]+\.[0-9]+|(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+|\.lan([^a-z]|$)|\.home\.arpa|[a-z0-9-]+\.ts\.net'
allowed='100\.64\.0\.0\/10|172\.1[78]\.0\.|host\.tailnet\.ts\.net|tail-demo\.ts\.net|100\.64\.0\.\\\\\(id\)'

status=0
# shellcheck disable=SC2086
matches=$(grep -rInE "$pattern" $shipped) || status=$?
if [ "$status" -gt 1 ]; then
    echo "check-shipped-hosts: grep failed ($status)" >&2
    exit 2
fi
matches=$(printf '%s\n' "$matches" | grep -vE "$allowed" | grep -v '^$' || true)
if [ -n "$matches" ]; then
    echo "check-shipped-hosts: developer-specific host or private address found:" >&2
    echo "$matches" >&2
    exit 1
fi
# Private patterns (your domain, host names, tailnet), checked in every tracked file.
private="scripts/private-patterns.txt"
if [ -f "$private" ]; then
    git check-ignore -q "$private" || { echo "check-shipped-hosts: $private must be ignored by git" >&2; exit 2; }
    found=$(git grep -nIiE -f "$private" -- . ":!$private" || true)
    if [ -n "$found" ]; then
        echo "check-shipped-hosts: private pattern found in tracked files:" >&2
        echo "$found" >&2
        exit 1
    fi
fi
echo "check-shipped-hosts: OK"

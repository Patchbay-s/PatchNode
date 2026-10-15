#!/usr/bin/env bash
# Fails if a view can read an environment object nobody provides (crash
# "No Observable object of type … found"):
#   - every type read with @Environment(Type.self) in the app, the widgets or
#     the packages is injected by PatchNode/AppEnvironment.swift (`as Type`)
#   - every scene of PatchNodeApp.swift (WindowGroup, Window, DocumentGroup…)
#     applies .appEnvironment(model)
#   - the presentations that open sessions re-apply it (workspace, console
#     and SSH sheets, onboarding)
#   - no ObservableObject API (@EnvironmentObject, .environmentObject,
#     @StateObject): the stores are @Observable, read with @Environment only
# Exit code 0 = OK, 1 = errors (listed).
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import glob, re, sys

errors = []
sources = [p for root in ("PatchNode", "PatchNodeWidgets", "Packages")
           for p in glob.glob(f"{root}/**/*.swift", recursive=True) if "/.build/" not in p]

def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

# Types the views read.
readers = {}
for path in sources:
    for n, line in enumerate(read(path).splitlines(), 1):
        if line.lstrip().startswith("//"):
            continue
        for t in re.findall(r"@Environment\(\s*([A-Z]\w*)\.self\s*\)", line):
            readers.setdefault(t, []).append(f"{path}:{n}")
        if re.search(r"@EnvironmentObject|\.environmentObject\(|@StateObject|@ObservedObject", line):
            errors.append(f"{path}:{n}: ObservableObject API; use @Observable with .environment / @Environment")

# Types injected.
env_file = "PatchNode/AppEnvironment.swift"
injected = set(re.findall(r"\.environment\(\s*model(?:\.\w+)?\s+as\s+(\w+)\s*\)", read(env_file)))
if not injected:
    errors.append(f"{env_file}: no `.environment(model… as Type)` found")
for t, places in sorted(readers.items()):
    if t not in injected:
        errors.append(f"{t} read but not injected by {env_file}: " + ", ".join(places))

# Every scene applies it.
app = read("PatchNode/PatchNodeApp.swift")
body = app[app.find("var body: some Scene"):]
scene_starts = [m.start() for m in re.finditer(r"\b(WindowGroup|Window|DocumentGroup|UtilityWindow|Settings|MenuBarExtra)\s*(\(|\{)", body)]
if not scene_starts:
    errors.append("PatchNodeApp.swift: no scene found")
for i, start in enumerate(scene_starts):
    end = scene_starts[i + 1] if i + 1 < len(scene_starts) else len(body)
    if ".appEnvironment(model)" not in body[start:end]:
        line = app[:app.find(body) + start].count("\n") + 1
        errors.append(f"PatchNode/PatchNodeApp.swift:{line}: scene without .appEnvironment(model)")

# Presentations that open sessions.
main = read("PatchNode/MainTabView.swift")
for view in ("TerminalWorkspaceView()", "ConsoleAccessSheet(help: help)",
             "SSHHostKeySheet(confirmation: confirmation)", "OnboardingView()"):
    if not re.search(re.escape(view) + r"\s*\n\s*\.appEnvironment\(model\)", main):
        errors.append(f"PatchNode/MainTabView.swift: {view} presented without .appEnvironment(model)")

if errors:
    print("check-environment: FAILED")
    for e in errors:
        print("  - " + e)
    sys.exit(1)
print(f"check-environment: OK ({len(readers)} types read, {len(injected)} injected, {len(scene_starts)} scene(s))")
PY

#!/usr/bin/env bash
# Checks PatchNode.xcodeproj without Xcode (usable in the cloud environment):
#   - project.pbxproj parses (OpenStep plist), no duplicate object IDs,
#     every referenced object ID exists
#   - synchronized folders, local packages, Info.plists, membership exceptions
#     and shared schemes point to things that exist
#   - every Swift file of the app folder is compiled by exactly one target, no
#     two Swift files share a basename in a target, no Swift file lies outside
#     the synchronized folders
#   - target settings: bundle IDs, iOS 27.0, Swift 6, no ATS exception
#   - extensions (lesson of the first device build): GENERATE_INFOPLIST_FILE=YES,
#     Info.plist excluded from the target's resources (else "Multiple commands
#     produce"), bundle ID prefixed by the app's, embedded in and depended on
#     by the app; MARKETING_VERSION and CURRENT_PROJECT_VERSION defined once at
#     the project level, never on a target (so app and extensions match);
#     a hand-written Info.plist without generation must carry CFBundleIdentifier
#   - every target signs with an entitlements file declaring the App Group of
#     SharedSnapshotStore.appGroupID, the same in all targets (the build passes
#     without it but the widgets stay empty), and no Keychain sharing
# Exit code 0 = OK, 1 = errors (listed).
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import os, re, sys, glob

ROOT = os.getcwd()
PROJECT = "PatchNode.xcodeproj"
PBX = os.path.join(PROJECT, "project.pbxproj")
EXPECTED_BUNDLE_IDS = {
    "PatchNode": "fr.antxis.apple.labwatch",
    "PatchNodeWidgets": "fr.antxis.apple.labwatch.widgets",
}
errors, notes = [], []

# --- OpenStep plist parser ---------------------------------------------------
class Parser:
    def __init__(self, text):
        self.t, self.i, self.duplicates = text, 0, []

    def skip(self):
        t = self.t
        while self.i < len(t):
            if t[self.i].isspace():
                self.i += 1
            elif t.startswith("//", self.i):
                self.i = t.index("\n", self.i) + 1 if "\n" in t[self.i:] else len(t)
            elif t.startswith("/*", self.i):
                self.i = t.index("*/", self.i) + 2
            else:
                break

    def value(self):
        self.skip()
        c = self.t[self.i]
        if c == "{":
            self.i += 1
            d = {}
            while True:
                self.skip()
                if self.t[self.i] == "}":
                    self.i += 1
                    return d
                key = self.scalar()
                self.skip(); self.expect("=")
                val = self.value()
                self.skip(); self.expect(";")
                if key in d:
                    self.duplicates.append(key)
                d[key] = val
        if c == "(":
            self.i += 1
            items = []
            while True:
                self.skip()
                if self.t[self.i] == ")":
                    self.i += 1
                    return items
                items.append(self.value())
                self.skip()
                if self.t[self.i] == ",":
                    self.i += 1
        return self.scalar()

    def scalar(self):
        self.skip()
        t = self.t
        if t[self.i] == '"':
            j, out = self.i + 1, []
            while t[j] != '"':
                if t[j] == "\\":
                    out.append(t[j:j + 2]); j += 2
                else:
                    out.append(t[j]); j += 1
            self.i = j + 1
            return "".join(out)
        m = re.compile(r"[A-Za-z0-9_$/.:\-+]+").match(t, self.i)
        if not m:
            raise ValueError(f"unexpected {t[self.i:self.i+20]!r} at {self.i}")
        self.i = m.end()
        return m.group(0)

    def expect(self, ch):
        if self.t[self.i] != ch:
            raise ValueError(f"expected {ch!r} at {self.i}, got {self.t[self.i:self.i+20]!r}")
        self.i += 1

try:
    text = open(PBX, encoding="utf-8").read()
    parser = Parser(text)
    root = parser.value()
except Exception as e:  # noqa: BLE001
    print(f"ERROR: {PBX} does not parse: {e}")
    sys.exit(1)

objects = root.get("objects", {})
for dup in parser.duplicates:
    if re.fullmatch(r"[0-9A-F]{24}", dup):
        errors.append(f"duplicate object ID {dup}")

ID = re.compile(r"^[0-9A-F]{24}$")
def refs(value):
    if isinstance(value, dict):
        for v in value.values():
            yield from refs(v)
    elif isinstance(value, list):
        for v in value:
            yield from refs(v)
    elif isinstance(value, str) and ID.match(value):
        yield value

for oid, obj in objects.items():
    for r in refs(obj):
        if r not in objects:
            errors.append(f"{oid} ({obj.get('isa')}) references missing object {r}")
if root.get("rootObject") not in objects:
    errors.append("rootObject missing")

def of(isa):
    return {k: v for k, v in objects.items() if v.get("isa") == isa}

# --- Files and folders ---------------------------------------------------------
synced = of("PBXFileSystemSynchronizedRootGroup")
synced_paths = {}
for oid, g in synced.items():
    path = g.get("path", "")
    if not os.path.isdir(path):
        errors.append(f"synchronized folder '{path}' does not exist")
    synced_paths[oid] = path

for oid, f in of("PBXFileReference").items():
    if f.get("sourceTree") == "BUILT_PRODUCTS_DIR":
        continue
    path = f.get("path")
    if path and not os.path.exists(path):
        errors.append(f"file reference '{path}' does not exist")

# --- Account-specific settings (open source) ----------------------------------
# The Team ID lives in Config/Local.xcconfig (gitignored), included by
# Config/Base.xcconfig, the base configuration of the project's build settings.
for cid, c in objects.items():
    if c.get("isa") == "XCBuildConfiguration" and c.get("buildSettings", {}).get("DEVELOPMENT_TEAM"):
        errors.append(f"{cid}: DEVELOPMENT_TEAM set in the project; put it in Config/Local.xcconfig")
project = objects.get(root.get("rootObject"), {})
for cid in objects.get(project.get("buildConfigurationList"), {}).get("buildConfigurations", []):
    base = objects.get(objects.get(cid, {}).get("baseConfigurationReference"), {})
    if base.get("path") != "Config/Base.xcconfig":
        errors.append(f"project configuration {cid} must use Config/Base.xcconfig as its base configuration")
if os.path.exists("Config/Local.xcconfig") and os.system("git check-ignore -q Config/Local.xcconfig") != 0:
    errors.append("Config/Local.xcconfig must be ignored by git")

excluded = {}  # target id -> set of excluded paths (relative to repo)
for oid, ex in of("PBXFileSystemSynchronizedBuildFileExceptionSet").items():
    owner = next((p for g, p in synced_paths.items() if oid in objects[g].get("exceptions", [])), None)
    if owner is None:
        errors.append(f"exception set {oid} is not attached to a synchronized folder")
        continue
    for member in ex.get("membershipExceptions", []):
        full = os.path.join(owner, member)
        if not os.path.exists(full):
            errors.append(f"membership exception '{full}' does not exist")
        excluded.setdefault(ex.get("target"), set()).add(full)

# --- Targets ------------------------------------------------------------------
targets = of("PBXNativeTarget")
names = {t["name"]: oid for oid, t in targets.items()}
for expected in EXPECTED_BUNDLE_IDS:
    if expected not in names:
        errors.append(f"target '{expected}' missing")

def settings(target):
    lst = objects[target["buildConfigurationList"]]
    return {objects[c]["name"]: objects[c]["buildSettings"] for c in lst["buildConfigurations"]}

# Versions are defined once at the project level and inherited by every target.
VERSION_KEYS = ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION")
project_settings = settings(objects[root["rootObject"]])

swift_owner = {}
teams, versions, bundle_ids = set(), {}, {}
for tid, t in targets.items():
    name = t["name"]
    folders = [synced_paths[g] for g in t.get("fileSystemSynchronizedGroups", []) if g in synced_paths]
    for config, s in settings(t).items():
        where = f"{name}/{config}"
        if name in EXPECTED_BUNDLE_IDS and s.get("PRODUCT_BUNDLE_IDENTIFIER") != EXPECTED_BUNDLE_IDS[name]:
            errors.append(f"{where}: PRODUCT_BUNDLE_IDENTIFIER is {s.get('PRODUCT_BUNDLE_IDENTIFIER')!r}")
        if s.get("SWIFT_VERSION") not in ("6", "6.0"):
            errors.append(f"{where}: SWIFT_VERSION is {s.get('SWIFT_VERSION')!r}, expected 6")
        if "DEVELOPMENT_TEAM" in s:
            teams.add(s["DEVELOPMENT_TEAM"])
        target_ios = s.get("IPHONEOS_DEPLOYMENT_TARGET")
        if target_ios not in (None, "27.0"):
            errors.append(f"{where}: IPHONEOS_DEPLOYMENT_TARGET is {target_ios}")
        plist = s.get("INFOPLIST_FILE")
        if plist and not os.path.isfile(plist):
            errors.append(f"{where}: INFOPLIST_FILE '{plist}' does not exist")
        generated = s.get("GENERATE_INFOPLIST_FILE") == "YES"
        if t.get("productType") != "com.apple.product-type.application" and not generated:
            errors.append(f"{where}: extension/non-app target needs GENERATE_INFOPLIST_FILE = YES")
        if plist and any(plist.startswith(folder.rstrip("/") + "/") for folder in folders) \
                and plist not in excluded.get(tid, set()):
            errors.append(f"{where}: {plist} is in the synchronized folder but not excluded from the "
                          "target (copied as a resource: \"Multiple commands produce\")")
        if plist and not generated and os.path.isfile(plist) \
                and "CFBundleIdentifier" not in open(plist, encoding="utf-8", errors="replace").read():
            errors.append(f"{where}: {plist} has no CFBundleIdentifier and GENERATE_INFOPLIST_FILE is not YES")
        for key in VERSION_KEYS:
            if key in s:
                errors.append(f"{where}: {key} is set on the target; define it once at the project level")
            value = s.get(key, project_settings.get(config, {}).get(key))
            if not value:
                errors.append(f"{where}: {key} is not set (expected at the project level)")
            versions.setdefault(key, {})[where] = value
        bundle_ids[where] = (t.get("productType"), s.get("PRODUCT_BUNDLE_IDENTIFIER"))
        for key in s:
            if "NSAppTransportSecurity" in key or "NSAllowsArbitraryLoads" in key:
                errors.append(f"{where}: ATS exception setting {key}")
    basenames = {}
    count = 0
    for folder in folders:
        for path in glob.glob(os.path.join(folder, "**", "*.swift"), recursive=True):
            if path in excluded.get(tid, set()):
                continue
            count += 1
            if path in swift_owner:
                errors.append(f"'{path}' is compiled by both {swift_owner[path]} and {name}")
            swift_owner[path] = name
            base = os.path.basename(path)
            if base in basenames:
                errors.append(f"{name}: two Swift files named {base}: {basenames[base]} and {path}")
            basenames[base] = path
    notes.append(f"{name}: {count} Swift files from {', '.join(folders) or 'no folder'}")
    for dep in t.get("packageProductDependencies", []):
        if dep not in objects:
            errors.append(f"{name}: missing package product {dep}")

# Extensions: bundle ID under the app's, same versions, embedded and built with it.
app_ids = {bid for (ptype, bid) in bundle_ids.values() if ptype == "com.apple.product-type.application"}
for where, (ptype, bid) in bundle_ids.items():
    if ptype != "com.apple.product-type.application" and not any((bid or "").startswith(a + ".") for a in app_ids):
        errors.append(f"{where}: bundle ID {bid!r} is not prefixed by the app's ({', '.join(sorted(app_ids))})")
for key, values in versions.items():
    if len(set(values.values())) > 1:
        errors.append(f"{key} differs between targets: " + ", ".join(f"{w}={v}" for w, v in sorted(values.items())))
if len(teams) > 1:
    errors.append(f"several DEVELOPMENT_TEAM values: {', '.join(sorted(teams))}")
app_targets = [t for t in targets.values() if t.get("productType") == "com.apple.product-type.application"]
for tid, t in targets.items():
    if t.get("productType") != "com.apple.product-type.app-extension":
        continue
    product = t.get("productReference")
    for app in app_targets:
        embedded = any(
            objects[bf].get("fileRef") == product
            for phase in app.get("buildPhases", []) if objects[phase].get("isa") == "PBXCopyFilesBuildPhase"
            for bf in objects[phase].get("files", [])
        )
        depends = any(objects[d].get("target") == tid for d in app.get("dependencies", []))
        if not embedded:
            errors.append(f"{t['name']} is not embedded in {app['name']} (copy files phase)")
        if not depends:
            errors.append(f"{app['name']} has no target dependency on {t['name']}")

# Swift files of the app folders that no target compiles.
for folder in {p for p in synced_paths.values()}:
    for path in glob.glob(os.path.join(folder, "**", "*.swift"), recursive=True):
        if path not in swift_owner and not any(path in ex for ex in excluded.values()):
            errors.append(f"'{path}' is in no target")
for path in glob.glob("*.swift"):
    errors.append(f"'{path}' at the repository root is compiled by no target")

# --- Local packages -------------------------------------------------------------
products = {}
for oid, p in of("XCLocalSwiftPackageReference").items():
    rel = p.get("relativePath", "")
    manifest = os.path.join(rel, "Package.swift")
    if os.path.isabs(rel):
        errors.append(f"package path '{rel}' must be relative")
    if not os.path.isfile(manifest):
        errors.append(f"local package '{rel}' has no Package.swift")
        continue
    for m in re.finditer(r'\.library\(\s*name:\s*"([^"]+)"', open(manifest).read()):
        products[m.group(1)] = rel
for oid, d in of("XCSwiftPackageProductDependency").items():
    if d.get("productName") not in products:
        errors.append(f"package product '{d.get('productName')}' is provided by no referenced local package")
project = objects[root["rootObject"]]
referenced = set(project.get("packageReferences", []))
for oid in of("XCLocalSwiftPackageReference"):
    if oid not in referenced:
        errors.append(f"local package {oid} is not listed in the project's packageReferences")

# --- App Group entitlements (widgets stay empty without them, yet it builds) --
import plistlib
source = open("Packages/PatchNodeCore/Sources/PatchNodeCore/Shared/SharedSnapshot.swift").read()
m = re.search(r'appGroupID\s*=\s*"([^"]+)"', source)
app_group = m.group(1) if m else None
if not app_group:
    errors.append("SharedSnapshotStore.appGroupID not found in PatchNodeCore")
groups_by_target = {}
for tid, t in targets.items():
    name = t["name"]
    for config, s in settings(t).items():
        where = f"{name}/{config}"
        path = s.get("CODE_SIGN_ENTITLEMENTS")
        if not path:
            errors.append(f"{where}: no CODE_SIGN_ENTITLEMENTS (the App Group shared with the widgets is missing)")
            continue
        if not os.path.isfile(path):
            errors.append(f"{where}: CODE_SIGN_ENTITLEMENTS '{path}' does not exist")
            continue
        try:
            entitlements = plistlib.load(open(path, "rb"))
        except Exception as error:
            errors.append(f"{path}: not a valid plist ({error})")
            continue
        groups = entitlements.get("com.apple.security.application-groups") or []
        if not isinstance(groups, list):
            errors.append(f"{path}: com.apple.security.application-groups must be an array")
            groups = []
        if app_group and app_group not in groups:
            errors.append(f"{path}: App Group '{app_group}' (SharedSnapshotStore.appGroupID) missing")
        if "keychain-access-groups" in entitlements:
            errors.append(f"{path}: keychain-access-groups set (the widgets must not read the tokens)")
        # iCloud (1.1, optional configuration sync): the app only, its own container.
        containers = entitlements.get("com.apple.developer.icloud-container-identifiers")
        if containers is not None:
            bundle_id = s.get("PRODUCT_BUNDLE_IDENTIFIER", "")
            if t.get("productType") != "com.apple.product-type.application":
                errors.append(f"{path}: iCloud entitlement on {name} (only the app syncs; the widgets read the snapshot)")
            if containers != [f"iCloud.{bundle_id}"]:
                errors.append(f"{where}: iCloud container must be exactly ['iCloud.{bundle_id}'], got {containers}")
            if "CloudKit" not in (entitlements.get("com.apple.developer.icloud-services") or []):
                errors.append(f"{path}: icloud-services must list CloudKit")
            if "aps-environment" not in entitlements:
                errors.append(f"{path}: aps-environment missing (CloudKit sync needs remote notifications)")
        groups_by_target.setdefault(name, set()).add(tuple(sorted(groups)))
distinct = {g for sets in groups_by_target.values() for g in sets}
if len(distinct) > 1:
    errors.append("App Groups differ between targets/configurations: "
                  + "; ".join(f"{n}: {sorted(v)}" for n, v in sorted(groups_by_target.items())))
elif distinct:
    notes.append(f"App Group in every target: {', '.join(next(iter(distinct)))}")

# --- Info.plists and schemes -------------------------------------------------
for plist in glob.glob("**/Info.plist", recursive=True):
    if ".build" in plist:
        continue
    content = open(plist, encoding="utf-8", errors="replace").read()
    if "NSAllowsArbitraryLoads" in content or "NSExceptionDomains" in content:
        errors.append(f"{plist}: ATS exception")

for scheme in glob.glob(os.path.join(PROJECT, "xcshareddata", "xcschemes", "*.xcscheme")):
    for bid in re.findall(r'BlueprintIdentifier\s*=\s*"([0-9A-F]{24})"', open(scheme).read()):
        if bid not in targets:
            errors.append(f"{scheme}: BlueprintIdentifier {bid} is not a target")

for n in notes:
    print(f"  {n}")
print(f"  local packages: {', '.join(sorted(set(products.values())))}")
if errors:
    print(f"\n{len(errors)} error(s):")
    for e in errors:
        print(f"  ERROR: {e}")
    sys.exit(1)
print("check-pbxproj: OK")
PY

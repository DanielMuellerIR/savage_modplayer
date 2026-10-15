#!/bin/bash
# Nur lesende Prüfung vor der Signatur mit dem privaten Update-Schlüssel.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 2 && "$2" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Aufruf: $0 <Release.dmg> <vX.Y.Z>" >&2; exit 2;
}
DMG="$1"
VERSION="${2#v}"
TEAM="9QSWKSR4NQ"
REQUIREMENT="anchor apple generic and certificate leaf[subject.OU] = \"$TEAM\""
codesign --verify --strict -R="$REQUIREMENT" "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"

MOUNT_DIR="$(mktemp -d)"
MOUNTED=0
cleanup() {
    if [[ "$MOUNTED" == 1 ]]; then
        # Bei fehlgeschlagenem Aushängen den Mountpunkt unberührt lassen.
        hdiutil detach "$MOUNT_DIR" -quiet || return
    fi
    rmdir "$MOUNT_DIR"
}
trap cleanup EXIT
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
MOUNTED=1
shopt -s nullglob
APPS=("$MOUNT_DIR"/*.app)
[[ ${#APPS[@]} == 1 && "${APPS[0]##*/}" == "Savage Mod Player.app" ]] || {
    echo "FEHLER: Genau eine Savage Mod Player.app erwartet." >&2; exit 1;
}
APP="${APPS[0]}"
PLIST="$APP/Contents/Info.plist"
python3 - "$PLIST" build_app.sh "$VERSION" <<'PY'
import pathlib, plistlib, re, sys
plist = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
source = pathlib.Path(sys.argv[2]).read_text()
expected = {
    "CFBundleIdentifier": "com.viben.SavageModPlayer",
    "CFBundleVersion": sys.argv[3],
    "CFBundleShortVersionString": sys.argv[3],
    "SUFeedURL": re.search(r'<key>SUFeedURL</key>\s*<string>([^<]+)', source)[1],
    "SUPublicEDKey": re.search(r'<key>SUPublicEDKey</key>\s*<string>([^<]+)', source)[1],
    "SURequireSignedFeed": True,
    "SUVerifyUpdateBeforeExtraction": True,
    "SUAllowsAutomaticUpdates": False,
    "SUEnableSystemProfiling": False,
}
for key, value in expected.items():
    if plist.get(key) != value:
        raise SystemExit(f"FEHLER: Unerwarteter Bundle-Wert für {key}")
PY
codesign --verify --deep --strict -R="$REQUIREMENT" "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"
for target in \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
    "$APP/Contents/Frameworks/Sparkle.framework" \
    "$APP/Contents/PlugIns/SavageModPlayerQuickLook.appex"
do
    codesign --verify --strict -R="$REQUIREMENT" "$target"
done
mkdir -p .build/sparkle-release
cp "$PLIST" .build/sparkle-release/Info.plist
echo "Release-Artefakt verifiziert: $VERSION"

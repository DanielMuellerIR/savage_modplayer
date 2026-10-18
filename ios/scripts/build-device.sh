#!/usr/bin/env bash
# Baut die App fuer ein echtes iPhone (Sideload mit eigenem Developer-Team).
#
# Die Team-ID steht im Xcode-Projekt (DEVELOPMENT_TEAM). Sie ist kein Geheimnis:
# Apple bettet sie in die Signatur jeder ausgelieferten App ein, `codesign -dv`
# liest sie aus jedem heruntergeladenen DMG heraus, und sie steht in diesem Repo
# ohnehin schon in build_app.sh und beiden READMEs. Ein Versteckspiel waere
# Aufwand ohne Schutzwirkung. Zu schuetzen sind die privaten Schluessel der
# Signaturzertifikate und das Notary-Profil — nicht diese Kennung.
#
# Wer mit einem anderen Team baut, setzt SAVAGE_DEVELOPMENT_TEAM.
#
# Aufruf:
#   ios/scripts/build-device.sh              # baut und archiviert
#   ios/scripts/build-device.sh --install    # zusaetzlich auf ein angeschlossenes
#                                            # Geraet installieren
#   SAVAGE_DEVICE='<Name oder ID>' ios/scripts/build-device.sh --install
#                                            # Ziel bei mehreren iPhones
#
# Hintergrundwiedergabe und Sperrbildschirm-Steuerung lassen sich NUR hier
# pruefen — der Simulator belegt davon nichts. Die Pruefliste steht in
# docs/testing.md unter "iOS-Geraetetest".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    cat <<EOF
Usage: ios/scripts/build-device.sh [--install]

  --install   Archiv zusaetzlich auf ein angeschlossenes iPhone installieren.
  -h, --help  Diese Hilfe anzeigen.

Umgebung: SAVAGE_DEVICE (Ziel bei mehreren iPhones), SAVAGE_DEVELOPMENT_TEAM.
EOF
}

# ALLE Argumente parsen, Unbekanntes ablehnen: frueher wurde nur das erste
# Argument mit --install verglichen — "build-device.sh typo --install"
# archivierte erfolgreich, installierte aber nichts und meldete keinen
# Bedienfehler.
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "FEHLER: Unbekannte Option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

REPO_DIR="$(dirname "$IOS_DIR")"
DERIVED_DATA="${DERIVED_DATA:-$IOS_DIR/build/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$IOS_DIR/build/SavageModPlayer.xcarchive}"
# Produktversion kommt aus der VERSION-Datei, nicht aus dem .xcodeproj.
APP_VERSION="$(cat "$REPO_DIR/VERSION")"
LOG="${BUILD_LOG:-$IOS_DIR/build/build-device.log}"
mkdir -p "$(dirname "$LOG")"

# Alle Argumente in einem nichtleeren Array halten: Das mit macOS ausgelieferte
# Bash 3 behandelt "${LEERES_ARRAY[@]}" unter `set -u` als ungesetzte Variable.
XCODEBUILD_ARGS=(
    archive
    -project "$IOS_DIR/SavageModPlayer.xcodeproj"
    -scheme SavageModPlayer
    -configuration Release
    -destination 'generic/platform=iOS'
    -derivedDataPath "$DERIVED_DATA"
    -archivePath "$ARCHIVE_PATH"
    MARKETING_VERSION="$APP_VERSION"
)
if [ -n "${SAVAGE_CLOUDKIT_PROFILE:-}" ]; then
    CLOUDKIT_DIR="$DERIVED_DATA/CloudKit"
    mkdir -p "$CLOUDKIT_DIR"
    python3 "$REPO_DIR/tools/prepare-cloudkit.py" \
        --profile "$SAVAGE_CLOUDKIT_PROFILE" --platform ios \
        --team "${SAVAGE_DEVELOPMENT_TEAM:-9QSWKSR4NQ}" \
        --container "${SAVAGE_CLOUDKIT_CONTAINER:-iCloud.com.viben.SavageModPlayer}" \
        --environment "${SAVAGE_CLOUDKIT_ENVIRONMENT:-Development}" \
        --output-directory "$CLOUDKIT_DIR" > "$CLOUDKIT_DIR/settings.json"
    XCODEBUILD_ARGS+=(-xcconfig "$CLOUDKIT_DIR/CloudKit.xcconfig")
fi
if [ -n "${SAVAGE_DEVELOPMENT_TEAM:-}" ]; then
    XCODEBUILD_ARGS+=(DEVELOPMENT_TEAM="$SAVAGE_DEVELOPMENT_TEAM")
fi

echo "==> Geraete-Build"
set +e
xcodebuild "${XCODEBUILD_ARGS[@]}" >"$LOG" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    echo "FEHLER: Archivieren fehlgeschlagen (Exit $STATUS):"
    grep -E "error:|\*\* ARCHIVE" "$LOG" | tail -30 || tail -30 "$LOG"
    echo "Vollstaendiges Protokoll: $LOG"
    exit "$STATUS"
fi

echo "OK: Archiv liegt unter $ARCHIVE_PATH"

if [ "$INSTALL" -eq 1 ]; then
    APP="$ARCHIVE_PATH/Products/Applications/SavageModPlayer.app"
    if [ ! -d "$APP" ]; then
        echo "FEHLER: App im Archiv nicht gefunden: $APP"
        exit 4
    fi

    # `devicectl list devices` enthaelt auch Watches und kann mehrere iPhones
    # mit Namen samt Leerzeichen liefern. Die tabellarische Ausgabe mit awk zu
    # zerlegen waehlt dann leicht die falsche Spalte oder das falsche Geraet.
    # Deshalb die dokumentierte JSON-Schnittstelle verwenden. Bei mehreren
    # iPhones muss der Aufrufer bewusst Name oder ID angeben.
    if [ -n "${SAVAGE_DEVICE:-}" ]; then
        TARGET_DEVICE="$SAVAGE_DEVICE"
    else
        DEVICE_LIST_JSON="$(mktemp "${TMPDIR:-/tmp}/savage-devices.XXXXXX")"
        # Cleanup-Trap direkt nach mktemp: auch Signal oder Abbruch zwischen
        # Anlegen und Loeschen laesst keine Geraetekennungen im Temp-Verzeichnis
        # liegen. Nach dem regulaeren Loeschen wird der Trap zurueckgenommen.
        trap 'rm -f "$DEVICE_LIST_JSON"' EXIT
        set +e
        xcrun devicectl list devices --json-output "$DEVICE_LIST_JSON" --quiet
        DEVICE_LIST_STATUS=$?
        set -e
        if [ "$DEVICE_LIST_STATUS" -ne 0 ]; then
            exit "$DEVICE_LIST_STATUS"
        fi

        set +e
        TARGET_DEVICE=$(/usr/bin/python3 - "$DEVICE_LIST_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    devices = json.load(handle).get("result", {}).get("devices", [])

iphones = [
    device for device in devices
    if device.get("hardwareProperties", {}).get("platform") == "iOS"
    and device.get("connectionProperties", {}).get("pairingState") == "paired"
]
if len(iphones) != 1:
    print(
        "FEHLER: Genau ein gekoppeltes iPhone erwartet, gefunden: "
        f"{len(iphones)}. SAVAGE_DEVICE='<Name oder ID>' setzen.",
        file=sys.stderr,
    )
    raise SystemExit(5)
print(iphones[0]["identifier"])
PY
        )
        DEVICE_STATUS=$?
        set -e
        rm -f "$DEVICE_LIST_JSON"
        trap - EXIT
        if [ "$DEVICE_STATUS" -ne 0 ]; then exit "$DEVICE_STATUS"; fi
    fi

    echo "==> Installiere auf angeschlossenem Geraet"
    xcrun devicectl device install app --device "$TARGET_DEVICE" "$APP"
    echo "OK: installiert. Jetzt die Geraete-Pruefliste aus docs/testing.md abarbeiten."
fi

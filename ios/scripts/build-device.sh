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
#
# Hintergrundwiedergabe und Sperrbildschirm-Steuerung lassen sich NUR hier
# pruefen — der Simulator belegt davon nichts. Die Pruefliste steht in
# docs/testing.md unter "iOS-Geraetetest".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"

INSTALL=0
if [ "${1:-}" = "--install" ]; then INSTALL=1; fi

REPO_DIR="$(dirname "$IOS_DIR")"
DERIVED_DATA="${DERIVED_DATA:-$IOS_DIR/build/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$IOS_DIR/build/SavageModPlayer.xcarchive}"
# Produktversion kommt aus der VERSION-Datei, nicht aus dem .xcodeproj.
APP_VERSION="$(cat "$REPO_DIR/VERSION")"
LOG="${BUILD_LOG:-$IOS_DIR/build/build-device.log}"
mkdir -p "$(dirname "$LOG")"

# Leeres Array, wenn nichts ueberschrieben wird — dann gilt der Wert aus dem
# Projekt. Ein leeres "" als Argument wuerde xcodebuild dagegen stoeren.
TEAM_OVERRIDE=()
if [ -n "${SAVAGE_DEVELOPMENT_TEAM:-}" ]; then
    TEAM_OVERRIDE=(DEVELOPMENT_TEAM="$SAVAGE_DEVELOPMENT_TEAM")
fi

echo "==> Geraete-Build"
set +e
xcodebuild archive \
    -project "$IOS_DIR/SavageModPlayer.xcodeproj" \
    -scheme SavageModPlayer \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    MARKETING_VERSION="$APP_VERSION" \
    "${TEAM_OVERRIDE[@]}" \
    >"$LOG" 2>&1
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
    echo "==> Installiere auf angeschlossenem Geraet"
    xcrun devicectl device install app --device "$(xcrun devicectl list devices \
        | awk 'NR>2 && $0 !~ /^$/ {print $3; exit}')" "$APP"
    echo "OK: installiert. Jetzt die Geraete-Pruefliste aus docs/testing.md abarbeiten."
fi

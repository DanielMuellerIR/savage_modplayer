#!/usr/bin/env bash
# Baut die App fuer ein echtes iPhone (Sideload mit eigenem Developer-Team).
#
# Die Team-ID steht NICHT im Repo. Sie kommt aus ios/Signing.local.xcconfig
# (gitignoriert), Vorlage ist ios/Signing.local.xcconfig.example. Dieselbe Datei
# liest auch Xcode ueber ios/Signing.xcconfig — es gibt also genau eine Stelle,
# und in Xcode muss nichts von Hand ausgewaehlt werden.
#
# Ohne Team-ID bricht das Skript mit einer klaren Meldung ab, statt einen
# unsignierten Build zu produzieren, der auf dem Geraet nicht startet.
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

# Team-ID nur pruefen, nicht durchreichen: den Wert holt sich xcodebuild selbst
# aus ios/Signing.xcconfig, das seinerseits die lokale Datei einbindet. Hier geht
# es allein darum, im Fehlerfall etwas Verstaendliches zu sagen, statt den Nutzer
# mit einem Signaturfehler von xcodebuild allein zu lassen.
SIGNING_LOCAL="$IOS_DIR/Signing.local.xcconfig"
TEAM="${SAVAGE_DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM" ] && [ -f "$SIGNING_LOCAL" ]; then
    # Nur die eine erwartete Zeile auswerten, nichts blind ausfuehren.
    TEAM="$(grep -E '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=' "$SIGNING_LOCAL" \
        | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r' | xargs)"
fi

if [ -z "$TEAM" ] || [ "$TEAM" = "XXXXXXXXXX" ]; then
    cat <<'MSG'
FEHLER: Keine Team-ID gefunden.

So wird sie gesetzt (die Datei ist gitignoriert und gehoert nicht ins Repo):

    cp ios/Signing.local.xcconfig.example ios/Signing.local.xcconfig
    # danach dort die eigene Team-ID bei DEVELOPMENT_TEAM eintragen

Dieselbe Datei benutzt auch Xcode. In Xcode ist danach nichts mehr
auszuwaehlen — und es kann auch nichts versehentlich eingecheckt werden.

Alternativ einmalig fuer diesen Aufruf:

    SAVAGE_DEVELOPMENT_TEAM=XXXXXXXXXX ios/scripts/build-device.sh
MSG
    exit 2
fi

REPO_DIR="$(dirname "$IOS_DIR")"
DERIVED_DATA="${DERIVED_DATA:-$IOS_DIR/build/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$IOS_DIR/build/SavageModPlayer.xcarchive}"
# Produktversion kommt aus der VERSION-Datei, nicht aus dem .xcodeproj.
APP_VERSION="$(cat "$REPO_DIR/VERSION")"
LOG="${BUILD_LOG:-$IOS_DIR/build/build-device.log}"
mkdir -p "$(dirname "$LOG")"

echo "==> Geraete-Build (Team-ID wird nicht protokolliert)"
set +e
xcodebuild archive \
    -project "$IOS_DIR/SavageModPlayer.xcodeproj" \
    -scheme SavageModPlayer \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    MARKETING_VERSION="$APP_VERSION" \
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

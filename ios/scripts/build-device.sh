#!/usr/bin/env bash
# Baut die App fuer ein echtes iPhone (Sideload mit eigenem Developer-Team).
#
# Die Team-ID steht NICHT im Repo. Sie kommt aus ios/.env (gitignoriert), Vorlage
# ist ios/.env.example. Ohne Team-ID bricht das Skript mit einer klaren Meldung
# ab, statt einen unsignierten Build zu produzieren, der auf dem Geraet nicht
# startet.
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

# Team-ID einlesen: erst Umgebungsvariable, dann ios/.env.
TEAM="${SAVAGE_DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM" ] && [ -f "$IOS_DIR/.env" ]; then
    # Nur die eine erwartete Zeile auswerten, nichts blind ausfuehren.
    TEAM="$(grep -E '^SAVAGE_DEVELOPMENT_TEAM=' "$IOS_DIR/.env" | head -1 | cut -d= -f2- | tr -d '"'"'"' \r')"
fi

if [ -z "$TEAM" ]; then
    cat <<'MSG'
FEHLER: Keine Team-ID gefunden.

So wird sie gesetzt (die Datei ist gitignoriert und gehoert nicht ins Repo):

    cp ios/.env.example ios/.env
    # danach in ios/.env die eigene Team-ID eintragen

Alternativ einmalig fuer diesen Aufruf:

    SAVAGE_DEVELOPMENT_TEAM=XXXXXXXXXX ios/scripts/build-device.sh
MSG
    exit 2
fi

DERIVED_DATA="${DERIVED_DATA:-$IOS_DIR/build/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$IOS_DIR/build/SavageModPlayer.xcarchive}"
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
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
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

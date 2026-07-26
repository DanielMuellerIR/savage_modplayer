#!/usr/bin/env bash
# Baut die iPhone-App fuer den Simulator. Headless, ohne Signatur, ohne Team-ID.
#
# Aufruf:
#   ios/scripts/build-simulator.sh            # Debug
#   CONFIGURATION=Release ios/scripts/build-simulator.sh
#
# Exit 0 = Build erfolgreich. Warnungen aus dem EIGENEN Code fuehren zu Exit 3,
# damit ein "gruener" Build nicht heimlich Warnungen ansammelt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$IOS_DIR")"

CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-$IOS_DIR/build/DerivedData}"
LOG="${BUILD_LOG:-$IOS_DIR/build/build-simulator.log}"

mkdir -p "$(dirname "$LOG")"

echo "==> Simulator-Build ($CONFIGURATION)"
set +e
xcodebuild build \
    -project "$IOS_DIR/SavageModPlayer.xcodeproj" \
    -scheme SavageModPlayer \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    >"$LOG" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    echo "FEHLER: Build fehlgeschlagen (Exit $STATUS). Letzte Zeilen:"
    grep -E "error:|warning:|\*\* BUILD" "$LOG" | tail -30 || tail -30 "$LOG"
    echo "Vollstaendiges Protokoll: $LOG"
    exit "$STATUS"
fi

# Nur Warnungen aus dem eigenen Quellbaum zaehlen. Warnungen aus dem SDK oder
# aus fremdem Code kann dieses Projekt nicht abstellen.
OWN_WARNINGS="$(grep "warning:" "$LOG" | grep -E "$REPO_DIR/(ios|Sources)/" | sort -u || true)"
if [ -n "$OWN_WARNINGS" ]; then
    echo "FEHLER: Warnungen im eigenen Code:"
    echo "$OWN_WARNINGS"
    exit 3
fi

echo "OK: Build erfolgreich, keine Warnungen im eigenen Code."
echo "Produkt: $DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator/SavageModPlayer.app"

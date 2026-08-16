#!/usr/bin/env bash
# Faehrt die iOS-Testsuite headless im Simulator.
#
# Aufruf:
#   ios/scripts/run-tests.sh
#   SIMULATOR_NAME="iPhone 17" ios/scripts/run-tests.sh
#   TEST_FILTER=SavageModPlayerTests/LibraryImportUITests ios/scripts/run-tests.sh
#
# Ohne SIMULATOR_NAME nimmt das Skript das erste verfuegbare iPhone und spricht
# es ueber seine eindeutige ID an. Ein Ziel nur per Name wuerde `xcodebuild`
# implizit auf `OS:latest` festlegen und scheitert, wenn dieses Modell nur in
# einer aelteren installierten Laufzeit existiert. Exit 0 = alle Tests gruen.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"

DERIVED_DATA="${DERIVED_DATA:-$IOS_DIR/build/DerivedData}"
LOG="${TEST_LOG:-$IOS_DIR/build/run-tests.log}"
mkdir -p "$(dirname "$LOG")"

# Zielgeraet bestimmen. `simctl list devices available` liefert Zeilen der Form
# "    iPhone 17 Pro (UUID) (Shutdown)". Auch ein ausdruecklich genannter
# Simulator wird hier auf seine eindeutige UUID aufgeloest; `xcodebuild` wuerde
# bei einem Ziel nur per Name implizit `OS:latest` verlangen und ein vorhandenes
# Modell aus einer aelteren Laufzeit faelschlich nicht finden.
DEVICE_LIST="$(xcrun simctl list devices available 2>/dev/null || true)"
DEVICE_NAME=""
DEVICE_ID=""
while IFS= read -r DEVICE_LINE; do
    CANDIDATE_NAME="$(printf '%s\n' "$DEVICE_LINE" \
        | sed -nE 's/^ +(.+) \([0-9A-Fa-f-]{36}\) \((Booted|Shutdown)\)[[:space:]]*$/\1/p')"
    CANDIDATE_ID="$(printf '%s\n' "$DEVICE_LINE" \
        | sed -nE 's/^ +.+ \(([0-9A-Fa-f-]{36})\) \((Booted|Shutdown)\)[[:space:]]*$/\1/p')"
    [ -n "$CANDIDATE_NAME" ] || continue
    case "$CANDIDATE_NAME" in iPhone*) ;; *) continue ;; esac
    if [ -z "${SIMULATOR_NAME:-}" ] || [ "$CANDIDATE_NAME" = "$SIMULATOR_NAME" ]; then
        DEVICE_NAME="$CANDIDATE_NAME"
        DEVICE_ID="$CANDIDATE_ID"
        break
    fi
done <<< "$DEVICE_LIST"

if [ -z "$DEVICE_NAME" ] || [ -z "$DEVICE_ID" ]; then
    echo "FEHLER: Kein iPhone-Simulator verfuegbar. Verfuegbare Geraete:"
    printf '%s\n' "$DEVICE_LIST"
    exit 2
fi

DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
echo "==> Tests auf Simulator: $DEVICE_NAME ($DEVICE_ID)"

ARGS=(
    test
    -project "$IOS_DIR/SavageModPlayer.xcodeproj"
    -scheme SavageModPlayer
    -configuration Debug
    -destination "$DESTINATION"
    -derivedDataPath "$DERIVED_DATA"
    CODE_SIGNING_ALLOWED=NO
)
if [ -n "${TEST_FILTER:-}" ]; then
    ARGS+=(-only-testing:"$TEST_FILTER")
fi

set +e
xcodebuild "${ARGS[@]}" >"$LOG" 2>&1
STATUS=$?
set -e

grep -E "Test Suite .* (passed|failed)|Executed [0-9]+ test|error:|\*\* TEST" "$LOG" | tail -25 || true

if [ "$STATUS" -ne 0 ]; then
    echo "FEHLER: Tests fehlgeschlagen (Exit $STATUS). Fehlerzeilen:"
    grep -E "error:|XCTAssert|failed -" "$LOG" | head -40 || true
    echo "Vollstaendiges Protokoll: $LOG"
    exit "$STATUS"
fi

echo "OK: iOS-Tests gruen."

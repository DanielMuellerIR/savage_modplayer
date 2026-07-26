#!/usr/bin/env bash
# Faehrt die iOS-Testsuite headless im Simulator.
#
# Aufruf:
#   ios/scripts/run-tests.sh
#   SIMULATOR_NAME="iPhone 17" ios/scripts/run-tests.sh
#   TEST_FILTER=SavageModPlayerTests/LibraryImportUITests ios/scripts/run-tests.sh
#
# Ohne SIMULATOR_NAME nimmt das Skript das erste verfuegbare iPhone der neuesten
# installierten iOS-Laufzeit. Exit 0 = alle Tests gruen.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"

DERIVED_DATA="${DERIVED_DATA:-$IOS_DIR/build/DerivedData}"
LOG="${TEST_LOG:-$IOS_DIR/build/run-tests.log}"
mkdir -p "$(dirname "$LOG")"

# Zielgeraet bestimmen. `simctl list devices available` liefert Zeilen der Form
# "    iPhone 17 Pro (UUID) (Shutdown)"; daraus fischen wir den ersten Namen.
if [ -n "${SIMULATOR_NAME:-}" ]; then
    DEVICE_NAME="$SIMULATOR_NAME"
else
    DEVICE_NAME="$(xcrun simctl list devices available \
        | grep -oE '^ +iPhone [^(]+' \
        | head -1 \
        | sed 's/^ *//; s/ *$//')"
fi

if [ -z "$DEVICE_NAME" ]; then
    echo "FEHLER: Kein iPhone-Simulator verfuegbar. Verfuegbare Geraete:"
    xcrun simctl list devices available
    exit 2
fi

echo "==> Tests auf Simulator: $DEVICE_NAME"

ARGS=(
    test
    -project "$IOS_DIR/SavageModPlayer.xcodeproj"
    -scheme SavageModPlayer
    -configuration Debug
    -destination "platform=iOS Simulator,name=$DEVICE_NAME"
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

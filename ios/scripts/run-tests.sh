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
# "    iPhone 17 Pro (UUID) (Shutdown)"; daraus fischen wir den ersten Namen.
# Das `|| true` ist noetig: unter `set -euo pipefail` beendet ein leerer
# grep-Treffer (oder ein scheiterndes simctl) sonst schon die Zuweisung —
# die Diagnose mit Geraeteliste und Exit 2 unten waere unerreichbar.
if [ -n "${SIMULATOR_NAME:-}" ]; then
    DEVICE_NAME="$SIMULATOR_NAME"
    DESTINATION="platform=iOS Simulator,name=$DEVICE_NAME"
else
    DEVICE_LINE="$( (xcrun simctl list devices available \
        | grep -m1 -E '^ +iPhone .+ \([0-9A-F-]{36}\) \((Booted|Shutdown)\)[[:space:]]*$') || true)"
    DEVICE_NAME="$(printf '%s\n' "$DEVICE_LINE" \
        | sed -E 's/^ +(.+) \([0-9A-F-]{36}\) \((Booted|Shutdown)\)[[:space:]]*$/\1/')"
    DEVICE_ID="$(printf '%s\n' "$DEVICE_LINE" \
        | sed -E 's/^ +.+ \(([0-9A-F-]{36})\) \((Booted|Shutdown)\)[[:space:]]*$/\1/')"
    DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
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

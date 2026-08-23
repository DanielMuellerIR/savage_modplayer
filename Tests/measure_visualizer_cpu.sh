#!/bin/bash
# Misst, was die Visualisierungen der Mac-App wirklich kosten.
#
# Warum ein eigenes Skript: Die Bildrate ist seit 1.6.10 einstellbar, und der
# Backlog verlangt fuer jede weitere Optimierung an diesem Pfad eine Messung
# vorher und nachher. Ohne festes Vorgehen sind zwei Messungen nicht
# vergleichbar.
#
# Gemessen wird die WIRKLICH verbrauchte CPU-Zeit ueber ein festes Zeitfenster,
# nicht der Momentanwert von `%CPU`. Der Unterschied ist gross: Momentanwerte
# streuten in einem Versuch zwischen 11 % und 25 % fuer denselben Zustand,
# waehrend die verbrauchte Zeit ueber 30 Sekunden stabil blieb.
#
# Der Lauf bleibt stumm (Lautstaerke 0) und zieht keinen Fokus (direkter
# Programmstart statt `open`). Die Voreinstellungen werden vorher gesichert und
# am Ende zurueckgespielt.
#
# Aufruf:
#   bash Tests/measure_visualizer_cpu.sh <modul> [hz ...]
# Beispiel:
#   bash Tests/measure_visualizer_cpu.sh audio/beispiel.mod 30 10 30 10
#
# Referenzwerte (2026-08-23, Mac mit M5-Chip, 4-Kanal-MOD, Fenster 1354x830, stumm):
#   30 Hz ≈ 22 %, 24 Hz ≈ 20 %, 15 Hz ≈ 18 %, 10 Hz ≈ 14 % eines Kerns.

set -uo pipefail
cd "$(dirname "$0")/.."

MODULE="${1:-}"
if [ -z "$MODULE" ] || [ ! -f "$MODULE" ]; then
    echo "Aufruf: bash Tests/measure_visualizer_cpu.sh <modul> [hz ...]" >&2
    exit 2
fi
shift
RATES=("$@")
[ ${#RATES[@]} -eq 0 ] && RATES=(30 10)

APP="Savage Mod Player.app"
BIN="$APP/Contents/MacOS/SavageModPlayerApp"
DOMAIN=com.viben.SavageModPlayer
# Einschwingzeit vor der Messung: Fenster, Audio-Engine und Visualisierungen
# brauchen ein paar Sekunden, bis die Last stabil ist.
SETTLE=12
WINDOW=30

if [ ! -x "$BIN" ]; then
    echo "FEHLER: $BIN fehlt. Zuerst 'bash build_app.sh' laufen lassen." >&2
    exit 2
fi

BACKUP="$(mktemp -t savage-visualizer-defaults).plist"
cleanup() {
    pkill -f "$BIN" 2>/dev/null
    if [ -s "$BACKUP" ]; then
        defaults import "$DOMAIN" "$BACKUP" 2>/dev/null
    fi
    rm -f "$BACKUP"
}
trap cleanup EXIT
defaults export "$DOMAIN" "$BACKUP" 2>/dev/null || true

echo "=== Visualizer-CPU: $(basename "$MODULE") ==="
for hz in "${RATES[@]}"; do
    pkill -f "$BIN" 2>/dev/null
    sleep 1
    defaults write "$DOMAIN" savage.volume -float 0
    defaults write "$DOMAIN" savage.visualizerHz -float "$hz"

    "$BIN" -ApplePersistenceIgnoreState YES "$MODULE" >/dev/null 2>&1 &
    pid=$!
    sleep "$SETTLE"
    before="$(ps -o cputime= -p $pid | tr -d ' ')"
    sleep "$WINDOW"
    after="$(ps -o cputime= -p $pid | tr -d ' ')"
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null

    python3 - "$before" "$after" "$WINDOW" "$hz" <<'PY'
import sys

def seconds(text):
    total = 0.0
    for part in text.split(":"):
        total = total * 60 + float(part)
    return total

before, after, window, hz = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
used = seconds(after) - seconds(before)
print("%4s Hz: %5.2f s CPU in %.0f s = %5.1f %% eines Kerns" % (hz, used, window, 100 * used / window))
PY
done

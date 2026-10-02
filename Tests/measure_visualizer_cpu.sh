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

set -euo pipefail
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
BIN="${SAVAGE_VISUALIZER_BIN:-$APP/Contents/MacOS/SavageModPlayerApp}"
DOMAIN=com.viben.SavageModPlayer
# Einschwingzeit vor der Messung: Fenster, Audio-Engine und Visualisierungen
# brauchen ein paar Sekunden, bis die Last stabil ist.
SETTLE="${SAVAGE_VISUALIZER_SETTLE:-12}"
WINDOW="${SAVAGE_VISUALIZER_WINDOW:-30}"

if [ ! -x "$BIN" ]; then
    echo "FEHLER: $BIN fehlt. Zuerst 'bash build_app.sh' laufen lassen." >&2
    exit 2
fi

WORK="$(mktemp -d -t savage-visualizer-defaults)"
BACKUP="$WORK/defaults-backup.plist"
DEFAULTS_STATE=unknown
DEFAULTS_TOUCHED=0
MEASUREMENT_PID=""

stop_measurement_process() {
    if [ -n "$MEASUREMENT_PID" ] && kill -0 "$MEASUREMENT_PID" 2>/dev/null; then
        kill "$MEASUREMENT_PID" 2>/dev/null || true
        wait "$MEASUREMENT_PID" 2>/dev/null || true
    fi
    MEASUREMENT_PID=""
}

cleanup() {
    status=$?
    trap - EXIT
    stop_measurement_process
    restore_failed=0
    if [ "$DEFAULTS_STATE" = present ]; then
        if defaults import "$DOMAIN" "$BACKUP" >/dev/null 2>&1; then
            # Nur eine nachweislich importierte Sicherung darf verschwinden.
            rm -f "$BACKUP"
        else
            echo "FEHLER: Voreinstellungen konnten nicht wiederhergestellt werden; Sicherung bleibt unter $BACKUP" >&2
            restore_failed=1
        fi
    elif [ "$DEFAULTS_STATE" = absent ] && [ "$DEFAULTS_TOUCHED" -eq 1 ]; then
        # Gab es vor der Messung noch keine Domain, darf der Lauf auch keine
        # mit Messwerten fuer Lautstaerke und Bildrate zuruecklassen.
        if ! defaults delete "$DOMAIN" >/dev/null 2>&1; then
            echo "FEHLER: Neu angelegte Voreinstellungen konnten nicht entfernt werden." >&2
            restore_failed=1
        fi
    fi
    rmdir "$WORK" 2>/dev/null || true
    if [ "$restore_failed" -ne 0 ] && [ "$status" -eq 0 ]; then
        status=1
    fi
    exit "$status"
}
trap cleanup EXIT

# `defaults export` meldet sowohl eine fehlende Domain als auch echte Lese- oder
# Schreibfehler mit ungleich null. Erst die erfolgreiche Domain-Liste
# unterscheidet beide Faelle; bei einer vorhandenen Domain ist ein gescheitertes
# Backup ein harter Fehler, bevor der erste Messwert geschrieben wird.
if ! DEFAULT_DOMAINS="$(defaults domains 2>/dev/null)"; then
    echo "FEHLER: Voreinstellungs-Domains konnten nicht gelesen werden." >&2
    exit 1
fi
# Die lange Liste wird zuerst vollstaendig normalisiert. Ein direktes `grep -q`
# in der Pipe beendet seine Vorgaenger nach dem Treffer und sieht mit `pipefail`
# deshalb faelschlich wie ein Fehler aus.
NORMALIZED_DOMAINS="$(printf '%s\n' "$DEFAULT_DOMAINS" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if grep -Fxq "$DOMAIN" <<< "$NORMALIZED_DOMAINS"; then
    DEFAULTS_STATE=present-unbacked
    if ! defaults export "$DOMAIN" "$BACKUP" >/dev/null 2>&1; then
        echo "FEHLER: Vorhandene Voreinstellungen konnten nicht gesichert werden." >&2
        exit 1
    fi
    DEFAULTS_STATE=present
else
    DEFAULTS_STATE=absent
fi

echo "=== Visualizer-CPU: $(basename "$MODULE") ==="
for hz in "${RATES[@]}"; do
    stop_measurement_process
    DEFAULTS_TOUCHED=1
    defaults write "$DOMAIN" savage.volume -float 0
    defaults write "$DOMAIN" savage.visualizerHz -float "$hz"

    "$BIN" -ApplePersistenceIgnoreState YES "$MODULE" >/dev/null 2>&1 &
    MEASUREMENT_PID=$!
    sleep "$SETTLE"
    before="$(ps -o cputime= -p "$MEASUREMENT_PID" | tr -d ' ')"
    sleep "$WINDOW"
    after="$(ps -o cputime= -p "$MEASUREMENT_PID" | tr -d ' ')"
    stop_measurement_process

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

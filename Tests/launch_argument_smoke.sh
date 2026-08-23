#!/bin/bash
# Startlauf-Smoke fuer die Mac-App: Erscheint beim Start ein Hauptfenster, und
# landet ein uebergebenes Modul wirklich im Player?
#
# Hintergrund (2026-08-23): AppKit deutet ein positionales Startargument als
# "diese Datei oeffnen". SwiftUI erzeugt dann sein Standardfenster nicht —
# `SavageModPlayer <song.mod>` startete ohne jedes Fenster, und ohne Fenster
# konnte auch `.onOpenURL` die Datei nicht entgegennehmen. Die App schaltet die
# Deutung in `SavageModPlayerApp.init()` ab (`NSTreatUnknownArgumentsAsOpen`);
# dieses Skript ist der Beleg, dass es wirkt und wirksam bleibt.
#
# Ohne Bedienung, ohne Bildschirmaufnahme und ohne Bedienungshilfen-Rechte:
#   * Die Fensterzahl kommt aus `CGWindowListCopyWindowInfo`, wo Besitzer und
#     Groesse eines Fensters auch ohne Berechtigung lesbar sind (nur der
#     Fenstertitel nicht).
#   * Ob das Modul geladen wurde, steht danach in der Voreinstellung
#     `savage.lastPlayed`, die `loadModFile` bei jedem Ladeweg schreibt.
#   * Die App wird direkt ueber ihr Programm gestartet statt ueber `open`, damit
#     sie den Fokus nicht an sich zieht. Nur der Fall "Oeffnen mit" braucht
#     `open`, und `-g` haelt sie auch dort im Hintergrund.
#
# Der Lauf bleibt stumm und aendert nichts dauerhaft: Lautstaerke 0 und ein
# leerer Autoplay-Ordner werden vorher gesetzt, die komplette
# Voreinstellungs-Domain vorher gesichert und am Ende zurueckgespielt.
#
# Aufruf:  bash Tests/launch_argument_smoke.sh ["<pfad zur .app>"]
# Beendet mit 0, wenn alle Faelle bestehen, sonst 1.

set -uo pipefail
cd "$(dirname "$0")/.."

APP="${1:-Savage Mod Player.app}"
BIN="$APP/Contents/MacOS/SavageModPlayerApp"
OWNER="Savage Mod Player"            # CFBundleName — so heisst der Fensterbesitzer
DOMAIN="com.viben.SavageModPlayer"
WAIT_SECONDS=12

if [ ! -x "$BIN" ]; then
    echo "FEHLER: $BIN fehlt. Zuerst 'bash build_app.sh' laufen lassen." >&2
    exit 2
fi

WORK="$(mktemp -d)"

restore_defaults() {
    if [ -s "$WORK/defaults-backup.plist" ]; then
        defaults import "$DOMAIN" "$WORK/defaults-backup.plist" 2>/dev/null
    else
        defaults delete "$DOMAIN" 2>/dev/null
    fi
}
cleanup() {
    pkill -f "$BIN" 2>/dev/null
    restore_defaults
    rm -rf "$WORK"
}
trap cleanup EXIT

# --- Voreinstellungen sichern und den Lauf stumm stellen --------------------
defaults export "$DOMAIN" "$WORK/defaults-backup.plist" 2>/dev/null || true
defaults write "$DOMAIN" savage.volume -float 0

# --- Fensterzaehler ---------------------------------------------------------
cat > "$WORK/winprobe.swift" <<'SWIFT'
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
var count = 0
for window in list {
    guard window[kCGWindowOwnerName as String] as? String == owner else { continue }
    // Ebene 0 ist ein normales Fenster; Menueleiste und Einblendungen liegen
    // darueber. Die Groessenschwelle sortiert Menueleisten-Streifen aus.
    guard window[kCGWindowLayer as String] as? Int == 0 else { continue }
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = bounds["Width"] as? Double ?? 0
    let height = bounds["Height"] as? Double ?? 0
    if width > 200 && height > 200 { count += 1 }
}
print(count)
SWIFT
swiftc -O -o "$WORK/winprobe" "$WORK/winprobe.swift" \
    || { echo "FEHLER: winprobe liess sich nicht bauen" >&2; exit 2; }

# --- Synthetisches, klangloses Testmodul ------------------------------------
# Minimal gueltiges 4-Kanal-M.K.-MOD mit einem Sample aus Nullbytes: rechtlich
# unbedenklich und auch bei aufgedrehter Lautstaerke lautlos.
mkdir -p "$WORK/autoplay"
python3 - "$WORK/smoketest.mod" <<'PY'
import sys
d = bytearray(1084 + 1024 + 4)
d[0:9] = b"SMOKETEST"
d[20 + 23] = 0x02          # Sample 1: Laenge 2 Words
d[20 + 25] = 64            # Sample 1: Lautstaerke
d[950] = 1                 # Songlaenge 1 Position
d[1080:1084] = b"M.K."
period = 428               # C-3
d[1084 + 0] = (period >> 8) & 0x0F
d[1084 + 1] = period & 0xFF
d[1084 + 2] = 1 << 4       # Instrument 1
open(sys.argv[1], "wb").write(bytes(d))
PY
# Autoplay zeigt auf denselben stummen Titel — sonst spielte der Lauf ohne
# Argument den echten Autoplay-Ordner des Nutzers laut ab.
cp "$WORK/smoketest.mod" "$WORK/autoplay/smoketest.mod"
defaults write "$DOMAIN" savage.autoplayFolder -string "$WORK/autoplay"

# --- Ein Fall ---------------------------------------------------------------
# $1 Beschriftung
# $2 erwarteter Wert von savage.lastPlayed ("" = egal)
# $3 Startart: "argv" (Argumente folgen) oder "openwith" (LaunchServices)
run_case() {
    local label="$1" expected="$2" mode="$3"
    shift 3
    pkill -f "$BIN" 2>/dev/null
    defaults delete "$DOMAIN" savage.lastPlayed 2>/dev/null
    sleep 1
    local pid=""
    if [ "$mode" = "openwith" ]; then
        # Der Weg von Finder und Dock: LaunchServices schickt ein Apple-Event,
        # kein argv. `-g` laesst die App im Hintergrund, `-n` erzwingt eine
        # frische Instanz.
        open -g -n -a "$APP" "$@"
    else
        "$BIN" -ApplePersistenceIgnoreState YES "$@" >"$WORK/app.log" 2>&1 &
        pid=$!
        disown "$pid" 2>/dev/null
    fi

    local windows=0 waited=0
    for (( waited = 1; waited <= WAIT_SECONDS; waited++ )); do
        sleep 1
        windows="$("$WORK/winprobe" "$OWNER")"
        [ "$windows" != "0" ] && break
    done
    # Kurz nachlaufen lassen: das Fenster steht, das Laden im Hintergrund kann
    # ein Sekundenbruchteil spaeter fertig sein.
    local played=""
    if [ "$windows" != "0" ] && [ -n "$expected" ]; then
        for _ in 1 2 3 4 5 6; do
            played="$(defaults read "$DOMAIN" savage.lastPlayed 2>/dev/null)"
            [ "$played" = "$expected" ] && break
            sleep 1
        done
    fi
    pkill -f "$BIN" 2>/dev/null

    if [ "$windows" = "0" ]; then
        echo "FAIL  $label — nach ${WAIT_SECONDS}s kein Fenster"
        FAILURES=$((FAILURES + 1))
    elif [ -n "$expected" ] && [ "$played" != "$expected" ]; then
        echo "FAIL  $label — Fenster nach ${waited}s, aber geladen wurde '$played' statt '$expected'"
        FAILURES=$((FAILURES + 1))
    else
        echo "ok    $label — Fenster nach ${waited}s${expected:+, geladen: $played}"
    fi
}

FAILURES=0
echo "=== Startlauf-Smoke: $APP ==="
run_case "ohne Argument"                       "smoketest.mod" argv
run_case "Datei als Argument"                  "smoketest.mod" argv "$WORK/smoketest.mod"
run_case "Ordner als Argument"                 "smoketest.mod" argv "$WORK/autoplay"
run_case "unbekanntes Argument"                "smoketest.mod" argv "gibt-es-nicht"
run_case "--autoplay ohne Filter"              "smoketest.mod" argv --autoplay
run_case "Oeffnen mit (Finder/LaunchServices)" "smoketest.mod" openwith "$WORK/smoketest.mod"

if [ "$FAILURES" -eq 0 ]; then
    echo "=== alle Faelle bestanden ==="
    exit 0
fi
echo "=== $FAILURES Fall/Faelle fehlgeschlagen ==="
exit 1

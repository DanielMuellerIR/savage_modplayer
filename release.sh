#!/bin/bash
# release.sh — Release-DMG bauen: App bauen, notarisieren, DMG packen und notarisieren.
#
# Die drei Einstiegspunkte des Projekts trennen bewusst:
#   bash build_app.sh   baut die App im Projektverzeichnis, mehr nicht
#   ./install.sh        baut, notarisiert und installiert nach /Applications
#   ./release.sh        baut, notarisiert und packt das DMG — installiert NIE
#
# Wichtig ist die doppelte Notarisierung: Erst bekommt die App ihr eigenes
# Ticket angeheftet, dann das fertige DMG. Nur so startet die App auch dann
# sauber, wenn jemand sie aus dem Image herauszieht — ein Ticket allein am DMG
# reicht dafür nicht.
#
# Voraussetzungen:
#   - "Developer ID Application"-Zertifikat im Schlüsselbund
#   - NOTARY_PROFILE oder `git config savageModPlayer.notaryProfile`
#
# Aufruf:
#   ./release.sh                     # vollständiger Release-Lauf
#   ./release.sh --no-finder-layout  # ohne AppleScript-Finder-Layout (headless)
#
# Letzte Zeile bei Erfolg: RELEASE OK: <pfad-zum-dmg> (<version>)
set -euo pipefail
cd "$(dirname "$0")"

usage() {
    cat <<EOF
Usage: ./release.sh [--no-finder-layout]

  --no-finder-layout  Finder-/AppleScript-Layout ueberspringen (headless).
  -h, --help          Diese Hilfe anzeigen.
EOF
}

# Argumente VOR jeder Wirkung vollstaendig parsen: ./release.sh --help darf
# weder Profilpruefung noch Build oder Notarisierung anstossen, und ein
# Tippfehler bricht sofort ab, statt kostenpflichtige bzw. zustandsaendernde
# Release-Arbeit zu starten.
DMG_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-finder-layout) DMG_ARGS+=("$arg") ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unbekannte Option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

source ./notarize-lib.sh

require_notary_profile

APP="Savage Mod Player.app"
VERSION="$(cat VERSION)"
DMG="build/Savage Mod Player.dmg"

echo "=== 1/3 App bauen (mit erzwungener Developer-ID-Signatur) ==="
REQUIRE_CODESIGN=1 bash build_app.sh

echo "=== 2/3 App notarisieren ==="
notarize_app "$APP"

echo "=== 3/3 DMG bauen und notarisieren ==="
# Ein DMG aus einem frueheren Lauf koennte einen Fehlschlag als Erfolg tarnen —
# vorher entfernen, damit der Existenztest unten das Ergebnis DIESES Laufs
# prueft. (Das leere Array braucht unter Bash 3 + set -u die +-Expansion.)
rm -f "$DMG"
bash build_dmg.sh --notarize ${DMG_ARGS[@]+"${DMG_ARGS[@]}"}

if [[ ! -f "$DMG" ]]; then
    echo "FEHLER: Erwartetes DMG fehlt: $DMG" >&2
    exit 1
fi
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | tail -2

echo "RELEASE OK: $PWD/$DMG ($VERSION)"

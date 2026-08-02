#!/bin/bash
# install.sh — Savage Mod Player notarisiert nach /Applications installieren.
#
# Die drei Einstiegspunkte des Projekts trennen bewusst:
#   bash build_app.sh   baut die App im Projektverzeichnis, mehr nicht
#   ./install.sh        baut, notarisiert und installiert nach /Applications
#   ./release.sh        baut, notarisiert und packt das DMG — installiert nie
#
# Warum notarisiert: In /Applications gehören nur Bundles mit angeheftetem
# Notary-Ticket, die Gatekeeper akzeptiert. Ein ad-hoc signierter Testbuild
# bleibt im Projektverzeichnis.
#
# Voraussetzungen:
#   - "Developer ID Application"-Zertifikat im Schlüsselbund
#   - NOTARY_PROFILE oder `git config savageModPlayer.notaryProfile`
#
# Aufruf:  ./install.sh
# Letzte Zeile bei Erfolg: INSTALL OK: /Applications/Savage Mod Player.app (<version>)
set -euo pipefail
cd "$(dirname "$0")"

usage() {
    cat <<EOF
Usage: ./install.sh

Baut, notarisiert und installiert nach /Applications. Es gibt keine Optionen;
-h/--help zeigt nur diese Hilfe.
EOF
}

# install.sh kennt keine Optionen: Hilfe sofort beantworten, alles andere
# ablehnen — frueher lief ./install.sh --help ungebremst durch Build,
# Notarisierung, pkill und den Austausch unter /Applications.
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        *) echo "Unbekannte Option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

source ./notarize-lib.sh

require_notary_profile

APP="Savage Mod Player.app"
DESTINATION="/Applications/$APP"
VERSION="$(cat VERSION)"

echo "=== 1/3 App bauen (mit erzwungener Developer-ID-Signatur) ==="
REQUIRE_CODESIGN=1 bash build_app.sh

echo "=== 2/3 Notarisieren ==="
notarize_app "$APP"

echo "=== 3/3 Installieren ==="
# Erst neben das Ziel legen, dann atomar austauschen: ein Abbruch mittendrin
# darf keine halb ersetzte App in /Applications hinterlassen.
STAGED="/Applications/.$APP.install-$$"
rm -rf "$STAGED"
trap 'rm -rf "$STAGED"' EXIT
ditto "$APP" "$STAGED"
pkill -x SavageModPlayerApp 2>/dev/null || true
/usr/bin/swift - "$STAGED" "$DESTINATION" <<'SWIFT'
import Foundation

let fileManager = FileManager.default
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
if fileManager.fileExists(atPath: destination.path) {
    _ = try fileManager.replaceItemAt(
        destination,
        withItemAt: source,
        backupItemName: nil,
        options: [.usingNewMetadataOnly]
    )
} else {
    try fileManager.moveItem(at: source, to: destination)
}
SWIFT
trap - EXIT

# Nach dem Kopieren erneut prüfen: erst dann ist die Installation belegt.
xcrun stapler validate "$DESTINATION"
spctl -a -t exec -vv "$DESTINATION" 2>&1 | tail -2

echo "INSTALL OK: $DESTINATION ($VERSION)"

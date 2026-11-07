#!/bin/bash
# build.sh — einheitlicher Einstieg zum Bauen.
#
# Unter Linux baut linux/build-gui.sh die Qt-App und die Swift-Engine.
# macOS: Baut nur, ohne Notarisierung oder Installation. Ohne Developer-ID im
# Schlüsselbund signiert build_app.sh ad hoc — eine Signatur ist also keine
# Voraussetzung (REQUIRE_CODESIGN=1 erzwingt sie, SIGN_APP=0 lässt sie weg).
# Die eigentliche Arbeit macht build_app.sh, das seinen Namen wegen Tests, CI
# und Doku behält; Argumente und Umgebungsvariablen gehen unverändert durch,
# der Exit-Code ist der von build_app.sh (exec ersetzt diesen Prozess).
#
# Aufruf:  ./build.sh
# Letzte Zeile bei Erfolg: BUILD OK: <pfad>/Savage Mod Player.app
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -s)" = Linux ]; then exec bash linux/build-gui.sh "$@"; fi
exec bash build_app.sh "$@"

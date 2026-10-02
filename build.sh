#!/bin/bash
# build.sh — einheitlicher Einstieg zum Bauen.
#
# Baut nur: keine Notarisierung, keine Installation. Ohne Developer-ID im
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
exec bash build_app.sh "$@"

#!/bin/bash
# Baut ein statisch gelinktes `savage-cli` fuer Linux im Container.
#
# Warum statisch: Ein normal gebautes Binary braucht auf dem Zielrechner die
# passende Swift-Laufzeit. Mit `--static-swift-stdlib` steckt sie im Programm —
# das Ergebnis laeuft auf jedem Linux mit den paar Systembibliotheken, gegen die
# ohnehin dynamisch gelinkt wird (libasound, libz, libc). Dafuer ist es gross,
# rund 70 MB.
#
# Der Bau laeuft im offiziellen `swift`-Container, damit auf dem Host keine
# Swift-Werkzeugkette noetig ist. Ergebnis: `.build/release/savage-cli`.
#
# Aufruf (auf einem Linux-Rechner mit Docker, im Projektverzeichnis):
#   bash linux/build-static.sh [--image swift:6.0]
#
# Kein AppImage: Dafuer braeuchte es `appimagetool`, das nicht in den
# Paketquellen liegt, sondern als Binary aus dem Netz geholt wird. Solange
# niemand es ausdruecklich will, bleibt es beim statischen Programm plus
# `linux/install.sh` — das deckt denselben Zweck ohne Download ab.

set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="swift:6.0"
while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="${2:?--image braucht einen Namen}"; shift 2 ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
done

if ! command -v docker >/dev/null 2>&1; then
    echo "FEHLER: docker fehlt. Der Bau laeuft bewusst im Container." >&2
    exit 2
fi

echo "=== Statisches savage-cli bauen ($IMAGE) ==="
# libasound2-dev fuer die ALSA-Ausgabe, zlib1g-dev fuer den eigenen ZIP-Leser.
# `bsdtar` (libarchive-tools) wird NICHT gebraucht — es ist seit 1.6.10 nur noch
# fuer `.7z` zustaendig und keine Bauabhaengigkeit.
docker run --rm -v "$PWD":/src -w /src "$IMAGE" bash -c '
    set -e
    apt-get update -qq
    apt-get install -y -qq libasound2-dev zlib1g-dev
    swift build -c release --static-swift-stdlib --product savage-cli
'

BINARY=".build/release/savage-cli"
if [ ! -x "$BINARY" ]; then
    echo "FEHLER: $BINARY wurde nicht erzeugt." >&2
    exit 1
fi
echo "=== Fertig ==="
ls -lh "$BINARY"
echo "Installieren: bash linux/install.sh --binary $BINARY"

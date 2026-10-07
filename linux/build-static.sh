#!/bin/bash
# Baut ein statisch gelinktes `savage-cli` fuer Linux im Container.
#
# Warum statisch: Ein normal gebautes Binary braucht auf dem Zielrechner die
# passende Swift-Laufzeit. Mit `--static-swift-stdlib` steckt sie im Programm —
# das Ergebnis laeuft auf jedem Linux mit den paar Systembibliotheken, gegen die
# ohnehin dynamisch gelinkt wird (libasound, libdbus-1, libz, libc). Dafuer ist es gross,
# rund 70 MB.
#
# Der Bau laeuft im offiziellen `swift`-Container, damit auf dem Host keine
# Swift-Werkzeugkette noetig ist. Ergebnis: `.build/release/savage-cli`.
#
# Aufruf (auf einem Linux-Rechner mit Docker, im Projektverzeichnis):
#   bash linux/build-static.sh [--image swift:6.0]
#
# Ein zusätzliches AppImage entsteht anschließend mit linux/build-appimage.sh.

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
# libasound2-dev fuer ALSA, libdbus-1-dev fuer MPRIS, zlib1g-dev fuer ZIP.
# `bsdtar` (libarchive-tools) wird NICHT gebraucht — es ist seit 1.6.10 nur noch
# fuer `.7z` zustaendig und keine Bauabhaengigkeit.
# Der Container laeuft als root (apt-get braucht das), das Arbeitsverzeichnis
# ist schreibbar eingebunden. Ohne die Rueckgabe der Eigentuemerschaft gehoert
# `.build` hinterher root: Der aufrufende Nutzer kann dann weder lokal
# weiterbauen noch aufraeumen, bis er wieder einen privilegierten Container
# startet (Review-Fund 2026-08-25; im Plan zum Linux-Port bereits beschrieben).
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
if ! DOCKER_SECURITY_OPTIONS="$(docker info --format '{{join .SecurityOptions ","}}')"; then
    echo "FEHLER: Docker-Sicherheitsmodus konnte nicht ermittelt werden." >&2
    exit 2
fi
DOCKER_ARGS=(--rm)
RETURN_OWNERSHIP=1
case "$DOCKER_SECURITY_OPTIONS" in
    *name=rootless*)
        # Bei Rootless-Docker ist Container-UID 0 bereits der aufrufende
        # Host-Nutzer. `chown $HOST_UID` im Container wuerde dagegen auf eine
        # fremde Unter-UID abgebildet.
        RETURN_OWNERSHIP=0
        ;;
    *name=userns*)
        # Beim rootful userns-remap muessen die Host-IDs fuer genau diesen
        # Container unveraendert sichtbar sein, bevor root sie zurueckgibt.
        DOCKER_ARGS+=(--userns=host)
        ;;
esac

set +e
docker run "${DOCKER_ARGS[@]}" -v "$PWD":/src -w /src \
    -e "HOST_UID=$HOST_UID" -e "HOST_GID=$HOST_GID" \
    -e "RETURN_OWNERSHIP=$RETURN_OWNERSHIP" \
    "$IMAGE" bash -c '
    set -e
    apt-get update -qq
    apt-get install -y -qq libasound2-dev libdbus-1-dev zlib1g-dev
    set +e
    swift build -c release --static-swift-stdlib --product savage-cli
    rc=$?
    set -e
    # Auch nach einem Fehlschlag: Die halb gebauten Zwischenstaende gehoeren
    # sonst genauso root wie ein fertiges Binary.
    if [ "$RETURN_OWNERSHIP" -eq 1 ] && [ -e .build ]; then
        if ! chown -R "$HOST_UID:$HOST_GID" .build; then
            echo "FEHLER: .build-Eigentuemerschaft konnte nicht zurueckgegeben werden." >&2
            exit 1
        fi
    fi
    exit $rc
'
container_rc=$?
set -e

# Der Container-Modus ist eine Implementierungsannahme; der Host beweist das
# Ergebnis rekursiv. Ein fehlgeschlagener chown darf dadurch weder nach einem
# roten noch nach einem gruenen Build unsichtbar bleiben.
if [ -e .build ]; then
    wrong_owner="$(find .build \( ! -user "$HOST_UID" -o ! -group "$HOST_GID" \) -print -quit)"
    if [ -n "$wrong_owner" ]; then
        echo "FEHLER: Build-Artefakt gehoert nicht dem aufrufenden Nutzer: $wrong_owner" >&2
        exit 1
    fi
fi
if [ "$container_rc" -ne 0 ]; then
    exit "$container_rc"
fi

BINARY=".build/release/savage-cli"
if [ ! -x "$BINARY" ]; then
    echo "FEHLER: $BINARY wurde nicht erzeugt." >&2
    exit 1
fi
echo "=== Fertig ==="
ls -lh "$BINARY"
echo "Installieren: bash linux/install.sh --binary $BINARY"

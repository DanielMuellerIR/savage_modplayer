#!/bin/bash
# Baut die Linux-App mit Qt und einer statisch eingebundenen Swift-Laufzeit.
# Aufruf: bash linux/build-gui.sh [--image swift:6.2.1-noble]
set -euo pipefail
cd "$(dirname "$0")/.."
IMAGE=swift:6.2.1-noble
while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="${2:?--image braucht einen Namen}"; shift 2 ;;
        -h|--help) echo 'Usage: linux/build-gui.sh [--image <Swift-Docker-Image>]'; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
done
for tool in cmake docker; do
    command -v "$tool" >/dev/null || { echo "FEHLER: $tool fehlt." >&2; exit 2; }
done
cmake -S linux/gui -B .build/linux-gui -DCMAKE_BUILD_TYPE=Release
cmake --build .build/linux-gui --parallel 4
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
SECURITY_OPTIONS="$(docker info --format '{{join .SecurityOptions ","}}')"
DOCKER_ARGS=(--rm)
RETURN_OWNERSHIP=1
case "$SECURITY_OPTIONS" in
    *name=rootless*) RETURN_OWNERSHIP=0 ;;
    *name=userns*) DOCKER_ARGS+=(--userns=host) ;;
esac
# Die Container-Ausgabe wird auch bei einem fehlgeschlagenen Build zurückgegeben.
set +e
docker run "${DOCKER_ARGS[@]}" -v "$PWD:/src" -w /src \
    -e "HOST_UID=$HOST_UID" -e "HOST_GID=$HOST_GID" -e "RETURN_OWNERSHIP=$RETURN_OWNERSHIP" \
    "$IMAGE" bash -c '
    set -e
    apt-get update -qq
    apt-get install -y -qq libasound2-dev libdbus-1-dev zlib1g-dev
    set +e
    swift build -c release --static-swift-stdlib --product savage-desktop-engine
    rc=$?
    if [ "$RETURN_OWNERSHIP" -eq 1 ] && [ -e .build ]; then
        chown -R "$HOST_UID:$HOST_GID" .build || exit 1
    fi
    exit "$rc"
'
result=$?
set -e
wrong_owner="$(find .build \( ! -user "$HOST_UID" -o ! -group "$HOST_GID" \) -print -quit)"
if [ -n "$wrong_owner" ]; then echo "FEHLER: Fremder Eigentümer: $wrong_owner" >&2; exit 1; fi
[ "$result" -eq 0 ] || exit "$result"
install -m 0755 .build/release/savage-desktop-engine .build/linux-gui/savage-desktop-engine
printf 'BUILD OK: %s/.build/linux-gui/savage-mod-player\n' "$PWD"

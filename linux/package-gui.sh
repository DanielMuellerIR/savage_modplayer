#!/bin/bash
# Verpackt einen vorhandenen Linux-GUI-Bau; veröffentlicht und installiert nichts.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR=.build/linux-gui
while [ $# -gt 0 ]; do
    case "$1" in
        --build-dir) BUILD_DIR="${2:?--build-dir braucht einen Pfad}"; shift 2 ;;
        -h|--help) echo 'Usage: linux/package-gui.sh [--build-dir PATH]'; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
done
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || { echo 'Linux x86_64 wird benötigt.' >&2; exit 2; }
for file in savage-mod-player savage-desktop-engine; do
    [ -x "$BUILD_DIR/$file" ] || { echo "FEHLER: $BUILD_DIR/$file fehlt." >&2; exit 2; }
    if ldd "$BUILD_DIR/$file" | grep -E 'not found|libswift|libFoundation'; then
        echo 'FEHLER: Fehlende Systembibliotheken oder dynamische Swift-Laufzeit.' >&2; exit 2
    fi
done
mkdir -p build
VERSION="$(cat VERSION)"
OUT="$PWD/build/savage-mod-player-${VERSION}-linux-x86_64.tar.gz"
WORK="$(mktemp -d "$PWD/build/linux-package.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
PACKAGE="$WORK/savage-mod-player-linux"
mkdir "$PACKAGE"
install -m755 "$BUILD_DIR/savage-mod-player" "$BUILD_DIR/savage-desktop-engine" "$PACKAGE/"
install -m644 VERSION LICENSE linux/licenses/Swift-LICENSE.txt linux/update.py linux/install.py linux/savage-mod-player.desktop linux/savage-collection.xml src/AppIcon.png "$PACKAGE/"
install -m644 config/sparkle-public-key.txt "$PACKAGE/update-public-key.txt"
cat > "$PACKAGE/install.sh" <<'INSTALL'
#!/bin/sh
set -eu
cd "$(dirname "$0")"
exec python3 install.py . "$@"
INSTALL
chmod 755 "$PACKAGE/install.sh"
tar -C "$WORK" -czf "$WORK/package.tar.gz" savage-mod-player-linux
mv "$WORK/package.tar.gz" "$OUT"
(cd build && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
printf 'RELEASE OK: %s\n' "$OUT"

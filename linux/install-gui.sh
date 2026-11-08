#!/bin/bash
# Installiert die Qt-App benutzerlokal. Die CLI bleibt separat verfügbar.
# Aufruf: bash linux/install-gui.sh [--prefix <Pfad>] [--build-dir <Pfad>]
set -euo pipefail
cd "$(dirname "$0")/.."
PREFIX="$HOME/.local"
BUILD_DIR=.build/linux-gui
UNINSTALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="${2:?--prefix braucht einen Pfad}"; shift 2 ;;
        --build-dir) BUILD_DIR="${2:?--build-dir braucht einen Pfad}"; shift 2 ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help) echo 'Usage: linux/install-gui.sh [--prefix <Pfad>] [--build-dir <Pfad>] [--uninstall]'; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
done
APP_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/256x256/apps"
MIME_DIR="$PREFIX/share/mime/packages"
refresh() {
    if command -v update-desktop-database >/dev/null; then update-desktop-database "$APP_DIR"; fi
    if command -v update-mime-database >/dev/null; then update-mime-database "$PREFIX/share/mime"; fi
}
if [ "$UNINSTALL" -eq 1 ]; then
    rm -f -- "$PREFIX/bin/savage-mod-player" "$APP_DIR/savage-mod-player.desktop" "$ICON_DIR/savage-mod-player.png" "$MIME_DIR/savage-collection.xml"
    if [ -f "$APP_DIR/savage-cli.desktop.before-gui" ]; then mv -f -- "$APP_DIR/savage-cli.desktop.before-gui" "$APP_DIR/savage-cli.desktop"; fi
    refresh
    echo 'GUI-Starteinträge entfernt. Versionierte Programme und Sammlungsdaten bleiben erhalten.'
    exit 0
fi
command -v python3 >/dev/null || { echo 'FEHLER: python3 fehlt.' >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
for file in savage-mod-player savage-desktop-engine; do
    [ -x "$BUILD_DIR/$file" ] || { echo "FEHLER: $BUILD_DIR/$file fehlt. Zuerst ./build.sh ausführen." >&2; exit 2; }
    install -m755 "$BUILD_DIR/$file" "$WORK/"
done
install -m644 VERSION LICENSE linux/licenses/Swift-LICENSE.txt linux/update.py linux/install.py linux/savage-mod-player.desktop linux/savage-collection.xml src/AppIcon.png "$WORK/"
install -m644 config/sparkle-public-key.txt "$WORK/update-public-key.txt"
python3 linux/install.py "$WORK" --prefix "$PREFIX"

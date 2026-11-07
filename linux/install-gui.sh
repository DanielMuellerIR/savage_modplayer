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
for tool in python3 sha256sum; do
    command -v "$tool" >/dev/null || { echo "FEHLER: $tool fehlt." >&2; exit 2; }
done
for file in savage-mod-player savage-desktop-engine; do
    [ -x "$BUILD_DIR/$file" ] || { echo "FEHLER: $BUILD_DIR/$file fehlt. Zuerst ./build.sh ausführen." >&2; exit 2; }
done
# Versionierte Ziele erlauben einen atomaren Starterwechsel ohne laufende Dateien zu ersetzen.
VERSION="$(cat VERSION)"
DIGEST="$(sha256sum "$BUILD_DIR/savage-mod-player" "$BUILD_DIR/savage-desktop-engine" | sha256sum | cut -c1-16)"
INSTALL_DIR="$PREFIX/lib/savage-mod-player/$VERSION-$DIGEST"
mkdir -p "$PREFIX/bin" "$APP_DIR" "$ICON_DIR" "$MIME_DIR" "$INSTALL_DIR"
for target in "$PREFIX/bin/savage-mod-player" "$APP_DIR/savage-mod-player.desktop" "$APP_DIR/savage-cli.desktop"; do
    if [[ -L "$target" || ( -e "$target" && ! -f "$target" ) ]]; then echo "FEHLER: Ziel ist keine reguläre Datei: $target" >&2; exit 2; fi
done
install -m 0755 "$BUILD_DIR/savage-mod-player" "$INSTALL_DIR/savage-mod-player"
install -m 0755 "$BUILD_DIR/savage-desktop-engine" "$INSTALL_DIR/savage-desktop-engine"
install -m 0644 src/AppIcon.png "$ICON_DIR/savage-mod-player.png"
install -m 0644 linux/savage-collection.xml "$MIME_DIR/savage-collection.xml"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd -P)"
LAUNCHER="$(mktemp "$PREFIX/bin/.savage-mod-player.XXXXXX")"
DESKTOP_TEMP="$(mktemp "$APP_DIR/.savage-mod-player.XXXXXX")"
trap 'rm -f -- "$LAUNCHER" "$DESKTOP_TEMP"' EXIT
# Shell-Quoting erfolgt getrennt vom Desktop-Exec-Quoting.
python3 - "$INSTALL_DIR/savage-mod-player" > "$LAUNCHER" <<'PY'
import shlex, sys
print('#!/bin/sh')
print('exec '+shlex.quote(sys.argv[1])+' "$@"')
PY
chmod 0755 "$LAUNCHER"
mv -f -- "$LAUNCHER" "$PREFIX/bin/savage-mod-player"
EXEC_PATH="$(cd "$PREFIX/bin" && pwd -P)/savage-mod-player"
EXEC_PATH="${EXEC_PATH//\\/\\\\\\\\}"
EXEC_PATH="${EXEC_PATH//\"/\\\\\"}"
EXEC_PATH="${EXEC_PATH//\$/\\\\\$}"
EXEC_PATH="${EXEC_PATH//\`/\\\\\`}"
EXEC_PATH="${EXEC_PATH//%/%%}"
EXEC_PATH="${EXEC_PATH//$'\n'/\\n}"
EXEC_PATH="${EXEC_PATH//$'\r'/\\r}"
EXEC_PATH="${EXEC_PATH//$'\t'/\\t}"
while IFS= read -r line; do
    if [[ "$line" == Exec=* ]]; then
        printf '%s' 'Exec=/bin/sh -c "exec \\"\\$@\\"" savage-mod-player '
        printf '"%s" %%F\n' "$EXEC_PATH"
    else printf '%s\n' "$line"; fi
done < linux/savage-mod-player.desktop > "$DESKTOP_TEMP"
chmod 0644 "$DESKTOP_TEMP"
mv -f -- "$DESKTOP_TEMP" "$APP_DIR/savage-mod-player.desktop"
# Bestehende Dateizuordnungen mit der alten Desktop-ID sollen ebenfalls die GUI öffnen.
if [ -f "$APP_DIR/savage-cli.desktop" ] && [ ! -e "$APP_DIR/savage-cli.desktop.before-gui" ]; then
    cp -p -- "$APP_DIR/savage-cli.desktop" "$APP_DIR/savage-cli.desktop.before-gui"
fi
if [ -f "$APP_DIR/savage-cli.desktop.before-gui" ]; then
    cat "$APP_DIR/savage-mod-player.desktop" > "$APP_DIR/savage-cli.desktop"
    printf '\nNoDisplay=true\n' >> "$APP_DIR/savage-cli.desktop"
fi
refresh
printf 'INSTALL OK: %s/bin/savage-mod-player (%s)\n' "$PREFIX" "$VERSION"

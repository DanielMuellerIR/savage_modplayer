#!/usr/bin/env bash
# Verpackt das bestehende statische Linux-CLI. Werkzeug UND eingebettete Runtime
# sind per SHA-256 festgelegt; appimagetool lädt keine aktuelle Runtime nach.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 022

BINARY=".build/release/savage-cli"
VERSION="$(cat VERSION)"
OUTPUT="build/Savage-Mod-Player-${VERSION}-x86_64.AppImage"
while [ $# -gt 0 ]; do
    case "$1" in
        --binary) BINARY="${2:?--binary braucht einen Pfad}"; shift 2 ;;
        --output) OUTPUT="${2:?--output braucht einen Pfad}"; shift 2 ;;
        -h|--help)
            echo 'Aufruf: bash linux/build-appimage.sh [--binary PFAD] [--output PFAD]'
            echo 'Linux x86_64; vorher bash linux/build-static.sh ausführen.'
            exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
done
if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
    echo 'FEHLER: AppImage-Bau ist für Linux x86_64 vorgesehen.' >&2
    exit 2
fi
for command in curl sha256sum readelf ldd; do
    command -v "$command" >/dev/null || { echo "FEHLER: $command fehlt." >&2; exit 2; }
done
[ -x "$BINARY" ] || { echo "FEHLER: CLI-Binary fehlt: $BINARY" >&2; exit 2; }
if [ -d "$OUTPUT" ] || [ "$BINARY" -ef "$OUTPUT" ]; then
    echo 'FEHLER: Ausgabe muss eine eigene Datei sein.' >&2; exit 2
fi
if ! readelf -h "$BINARY" | grep -q 'Advanced Micro Devices X86-64'; then
    echo 'FEHLER: Das CLI ist kein x86_64-ELF.' >&2; exit 2
fi
LIBRARIES="$(ldd "$BINARY")"
if echo "$LIBRARIES" | grep -Eq 'libswift|libFoundation|not found'; then
    echo 'FEHLER: Statische Swift-Laufzeit oder Systembibliotheken fehlen.' >&2; exit 2
fi
GLIBC_MIN="$(readelf --version-info "$BINARY" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -Vu | tail -1 | cut -d_ -f2)"
[ -n "$GLIBC_MIN" ] || { echo 'FEHLER: glibc-Anforderung fehlt.' >&2; exit 2; }

TOOL_VERSION=1.9.1
TOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_SHA256=d30a3ba1388ef57be73faabf606e0d326682f48c87f666106a3c8d6b35b58b4f
TOOL="$PWD/build/tools/appimagetool-${TOOL_VERSION}-x86_64.AppImage"
mkdir -p build/tools "$(dirname "$OUTPUT")"
WORK="$(mktemp -d "$PWD/build/appimage.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
if [ ! -f "$TOOL" ]; then
    curl --fail --location --retry 2 \
        "https://github.com/AppImage/appimagetool/releases/download/${TOOL_VERSION}/appimagetool-x86_64.AppImage" \
        --output "$WORK/tool.AppImage"
    echo "$TOOL_SHA256  $WORK/tool.AppImage" | sha256sum --check --status
    mv "$WORK/tool.AppImage" "$TOOL"
fi
echo "$TOOL_SHA256  $TOOL" | sha256sum --check --status
chmod +x "$TOOL"
OFFSET="$("$TOOL" --appimage-offset)"
[[ "$OFFSET" =~ ^[0-9]+$ ]] || { echo 'FEHLER: Ungültiger Runtime-Offset.' >&2; exit 1; }
head -c "$OFFSET" "$TOOL" > "$WORK/runtime"
echo "$RUNTIME_SHA256  $WORK/runtime" | sha256sum --check --status

APPDIR="$WORK/SavageModPlayer.AppDir"
DOC="$APPDIR/usr/share/doc/savage-cli"
mkdir -p "$APPDIR/usr/bin" "$DOC/licenses"
cp "$BINARY" "$APPDIR/usr/bin/savage-cli"
chmod 755 "$APPDIR/usr/bin/savage-cli"
cp linux/AppRun "$APPDIR/AppRun"
chmod 755 "$APPDIR/AppRun"
cp src/AppIcon.png "$APPDIR/savage-cli.png"
ln -s savage-cli.png "$APPDIR/.DirIcon"
sed 's/^Icon=.*/Icon=savage-cli/' linux/savage-cli.desktop > "$APPDIR/savage-cli.desktop"
cp LICENSE VERSION README.md README.de.md "$DOC/"
cp linux/licenses/*.txt "$DOC/licenses/"
cat > "$DOC/build-info.txt" <<INFO
Savage Mod Player $VERSION, Linux x86_64
Minimum glibc: $GLIBC_MIN
Swift runtime: statically linked
System libraries: ALSA, D-Bus, zlib, libstdc++, libgcc, libc/libm
appimagetool: $TOOL_VERSION, SHA-256 $TOOL_SHA256
AppImage runtime: caf24f9, SHA-256 $RUNTIME_SHA256
Runtime source/build: https://github.com/AppImage/type2-runtime/tree/caf24f9
INFO
if command -v desktop-file-validate >/dev/null; then
    desktop-file-validate "$APPDIR/savage-cli.desktop"
fi
export ARCH=x86_64
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream --runtime-file "$WORK/runtime" \
    "$APPDIR" "$WORK/player.AppImage"
chmod 755 "$WORK/player.AppImage"
# Der gepackte Einstieg muss auch außerhalb des AppDir funktionieren.
"$WORK/player.AppImage" --appimage-extract-and-run --help >/dev/null
mv "$WORK/player.AppImage" "$OUTPUT"
OUTPUT_DIR="$(CDPATH= cd -- "$(dirname "$OUTPUT")" && pwd)"
OUTPUT_NAME="$(basename "$OUTPUT")"
(cd "$OUTPUT_DIR" && sha256sum "$OUTPUT_NAME" > "$OUTPUT_NAME.sha256")
echo "APPIMAGE OK: $OUTPUT (glibc >= $GLIBC_MIN)"

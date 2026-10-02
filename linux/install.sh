#!/bin/bash
# Installiert savage-cli samt Desktop-Eintrag unter Linux — standardmaessig nur
# fuer den aufrufenden Nutzer, ohne root.
#
# Was hier landet (Vorgabe `~/.local`):
#   <prefix>/bin/savage-cli                              das Programm
#   <prefix>/share/applications/savage-cli.desktop       der Eintrag im Menue
#
# Die vier Dateitypen (MOD, S3M, XM, IT) sind bei freedesktop.org bereits
# definiert, samt Endungen. Der Eintrag meldet savage-cli nur als Anwendung
# dafuer an — es wird kein eigener MIME-Typ erfunden.
#
# Aufruf:
#   bash linux/install.sh [--prefix <verzeichnis>] [--binary <pfad>]
#   bash linux/install.sh --uninstall [--prefix <verzeichnis>]
#
# Ohne `--binary` wird `.build/release/savage-cli` genommen. Ein statisches
# Binary (siehe linux/build-static.sh) laeuft auch ohne passende
# Swift-Laufzeit auf dem Zielrechner.

set -euo pipefail
cd "$(dirname "$0")/.."

PREFIX="${HOME}/.local"
BINARY=".build/release/savage-cli"
UNINSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)    PREFIX="${2:?--prefix braucht ein Verzeichnis}"; shift 2 ;;
        --binary)    BINARY="${2:?--binary braucht einen Pfad}"; shift 2 ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help)
            sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unbekannte Option: $1" >&2
            exit 2 ;;
    esac
done

BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
DESKTOP_FILE="$APP_DIR/savage-cli.desktop"

refresh_desktop_database() {
    # Der Menue-Index wird nur aufgefrischt, wenn es das Werkzeug gibt. Fehlt
    # es, ist das kein Fehler — der Eintrag liegt trotzdem richtig.
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
    fi
}

if [ "$UNINSTALL" -eq 1 ]; then
    rm -f "$BIN_DIR/savage-cli" "$DESKTOP_FILE"
    refresh_desktop_database
    echo "Entfernt: $BIN_DIR/savage-cli und $DESKTOP_FILE"
    exit 0
fi

if [ ! -x "$BINARY" ]; then
    echo "FEHLER: $BINARY fehlt oder ist nicht ausfuehrbar." >&2
    echo "Zuerst 'swift build -c release --product savage-cli' oder" >&2
    echo "'bash linux/build-static.sh' laufen lassen." >&2
    exit 2
fi

if [[ -L "$DESKTOP_FILE" || ( -e "$DESKTOP_FILE" && ! -f "$DESKTOP_FILE" ) ]]; then
    echo "FEHLER: Desktop-Ziel ist keine reguläre Datei: $DESKTOP_FILE" >&2
    exit 2
fi
mkdir -p "$BIN_DIR" "$APP_DIR"
install -m 0755 "$BINARY" "$BIN_DIR/savage-cli"
# Exec verwendet zwei Escape-Ebenen: Desktop-String und dessen Argumentliste.
# Der Zielpfad bleibt ein Argument: GIO sucht sonst vor der Feldcode-Expansion
# nach einem Programmnamen mit %% statt %. Das feste Shellskript führt nur die
# übergebenen Argumente aus; auch ein Gleichheitszeichen bleibt Teil des Pfads.
EXEC_PATH="$(cd "$BIN_DIR" && pwd -P)/savage-cli"
EXEC_PATH="${EXEC_PATH//\\/\\\\\\\\}"
EXEC_PATH="${EXEC_PATH//\"/\\\\\"}"
EXEC_PATH="${EXEC_PATH//\$/\\\\\$}"
EXEC_PATH="${EXEC_PATH//\`/\\\\\`}"
EXEC_PATH="${EXEC_PATH//%/%%}"
EXEC_PATH="${EXEC_PATH//$'\n'/\\n}"
EXEC_PATH="${EXEC_PATH//$'\r'/\\r}"
EXEC_PATH="${EXEC_PATH//$'\t'/\\t}"
DESKTOP_TEMP="$(mktemp "$APP_DIR/.savage-cli.desktop.XXXXXX")"
trap 'rm -f -- "$DESKTOP_TEMP"' EXIT
while IFS= read -r line; do
    if [[ "$line" == Exec=* ]]; then
        printf '%s' 'Exec=/bin/sh -c "exec \\"\\$@\\"" savage-cli '
        printf '"%s" %%f --play\n' "$EXEC_PATH"
    else
        printf '%s\n' "$line"
    fi
done < linux/savage-cli.desktop > "$DESKTOP_TEMP"
chmod 0644 "$DESKTOP_TEMP"
mv -f "$DESKTOP_TEMP" "$DESKTOP_FILE"
refresh_desktop_database

echo "Installiert:"
echo "  $BIN_DIR/savage-cli"
echo "  $DESKTOP_FILE"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Hinweis: $BIN_DIR liegt nicht im PATH." ;;
esac

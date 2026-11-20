#!/usr/bin/env python3
"""Bündelt den Webplayer als eigenständige HTML-Datei.

Minifizierte Ausgabe: npm ci --ignore-scripts, dann python3 build.py.
Mit --debug entsteht unter .build/web eine separate Ausgabe für den Browser-Selbsttest.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
SRC_DIR = HERE / 'src'


def minify_js(src: str) -> str:
    terser = HERE / "node_modules" / "terser" / "bin" / "terser"
    if not terser.is_file():
        raise SystemExit("Web-Build: zuerst npm ci --ignore-scripts ausführen.")
    return subprocess.run(
        ["node", str(terser), "--ecma", "2020", "--format", "inline_script=true"],
        input=src, stdout=subprocess.PIPE, text=True, check=True,
    ).stdout.strip()


def minify_css(src: str) -> str:
    """
    CSS minifizieren. CSS hat keine Strings mit Bedeutung für Whitespace
    (außer in url(), content: usw.) und keine Block-Verschachtelungs-Tricks
    → ein einfacher Regex-basierter Ansatz reicht.
    """
    # /* ... */ Kommentare raus.
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.DOTALL)
    # Whitespace um Satzzeichen straffen.
    src = re.sub(r'\s*([{}:;,>])\s*', r'\1', src)
    # Trailing-Semicolon vor "}" sparen.
    src = src.replace(';}', '}')
    # Mehrfache Whitespaces zu einem.
    src = re.sub(r'\s+', ' ', src)
    return src.strip()


def minify_html(src: str) -> str:
    """
    HTML minifizieren. Entfernt Kommentare und kollabiert Whitespace
    zwischen Tags. Innerhalb von Text-Inhalten bleibt mindestens ein
    Space erhalten, damit Wörter nicht verkleben.
    """
    # <!-- ... --> Kommentare raus.
    src = re.sub(r'<!--.*?-->', '', src, flags=re.DOTALL)
    # Whitespace zwischen ">" und "<" wegnehmen.
    src = re.sub(r'>\s+<', '><', src)
    # Mehrfache Whitespaces zu einem.
    src = re.sub(r'\s+', ' ', src)
    return src.strip()


# ─────────────────────────────────────────────────────────────────────────────
# Quellen lesen und vorbereiten
# ─────────────────────────────────────────────────────────────────────────────

def strip_module_keywords(src: str) -> str:
    """
    Entfernt ES-Modul-Keywords aus modplayer.js, damit das Skript inline
    in einem <script>-Tag (ohne type=module) funktioniert.
    """
    return re.sub(r"^export (?=(?:async )?(?:class|function) )", "", src, flags=re.MULTILINE)


def build(minify: bool = True, debug: bool = False) -> Path:
    """Erstellt die HTML-Datei und gibt ihren Pfad zurück."""
    worklet_src = (HERE / 'mod-player-worklet.js').read_text()
    modplayer_src = (HERE / 'modplayer.js').read_text()
    css_src = (SRC_DIR / 'styles.css').read_text()
    body_src = (SRC_DIR / 'body.html').read_text()
    app_src = (SRC_DIR / 'app.js').read_text()
    if debug:
        app_src += "\n" + (SRC_DIR / 'debug.js').read_text()
    # Versions-String aus der VERSION-Datei lesen und in body.html einsetzen.
    # So gibt es genau eine Quelle für die Versionsnummer.
    version = (HERE / 'VERSION').read_text().strip()
    body_src = body_src.replace('{{VERSION}}', version)

    modplayer_src = strip_module_keywords(modplayer_src)

    if minify:
        worklet_src = minify_js(worklet_src)
        css_src = minify_css(css_src)
        body_src = minify_html(body_src)

    inline_src = modplayer_src + "\n" + app_src
    if minify:
        inline_src = minify_js(inline_src)

    worklet_literal = json.dumps(worklet_src).replace("<", r"<")
    html = (
        '<!doctype html>'
        '<html lang="de">'
        '<head>'
        '<meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Savage Mod Player</title>'
        f'<style>{css_src}</style>'
        '</head>'
        '<body>'
        f'{body_src}'
        '<script>'
        # Worklet-Quelltext als String → Blob-URL → audioWorklet.addModule()
        # akzeptiert das auch aus file://, ohne CORS-Stress.
        f'const WORKLET_SOURCE={worklet_literal};\n'
        "const WORKLET_BLOB_URL=URL.createObjectURL(new Blob([WORKLET_SOURCE],{type:'application/javascript'}));\n"
        f'{inline_src}'
        '</script>'
        '</body>'
        '</html>'
    )

    out = HERE / 'savage-mod-player.html'
    if debug:
        out = HERE / ".build" / "web" / out.name
        out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-min", "--no-minify", action="store_true")
    parser.add_argument("--debug", action="store_true")
    options = parser.parse_args(argv)
    minify = not options.no_min
    out = build(minify=minify, debug=options.debug)
    size = out.stat().st_size
    mode = 'minifiziert' if minify else 'unminifiziert'
    print(f'Geschrieben: {out} ({size:,} Bytes, {mode})')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

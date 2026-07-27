#!/usr/bin/env python3
"""Deterministische Evals fuer den kleinen, vollstaendigen Agenten-Kontext."""

import os
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parent.parent

# Private Namensliste — sie liegt bewusst AUSSERHALB dieses oeffentlichen Repos.
# Hier stuende sonst eine Liste privater Rechnernamen und wuerde genau die Namen
# veroeffentlichen, die sie schuetzen soll. Wir LESEN die Datei nur.
#
# Auch ihr PFAD steht hier nicht: Ein Vorgaberwert haette den Namen des privaten
# Repos in dieses oeffentliche geschrieben — genau das hat die Pruefung am
# 2026-07-27 an sich selbst gefunden. Der Pfad kommt deshalb ausschliesslich aus
# der Umgebung, zu setzen einmal pro Rechner in `~/.zshenv`.
#
# Verwendet werden ausschliesslich die mit `gate:` markierten Zeilen. Die Liste
# enthaelt daneben absichtlich unscharfe Eintraege (Produktnamen, kurze
# Abkuerzungen), die auch voellig legitim vorkommen; als Testbedingung wuerden
# die den Lauf dauerhaft rot faerben. Ist die Variable nicht gesetzt — etwa in
# oeffentlicher CI — entfaellt die Namenspruefung, und nur die strukturelle
# Pruefung greift.
_DENYLIST_ENV = "HYGIENE_DENYLIST"


def _hard_name_pattern():
    """Nur die `gate:`-Regeln als ein Muster, oder None wenn nicht lesbar."""
    pfad = os.environ.get(_DENYLIST_ENV)
    if not pfad:
        return None
    try:
        lines = Path(pfad).read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    frags = []
    for raw in lines:
        line = re.sub(r"\s+#.*$", "", raw.rstrip()).strip()
        if not line.startswith("gate:"):
            continue
        rule = line[len("gate:"):].strip()
        frags.append(rule[3:].strip() if rule.startswith("re:")
                     else re.escape(rule))
    return re.compile("|".join("(?:%s)" % f for f in frags),
                      re.IGNORECASE) if frags else None


class ContextHygieneTests(unittest.TestCase):
    def test_root_rules_fit_and_keep_invariants(self):
        agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        self.assertGreaterEqual(len(agents.encode("utf-8")), 6_000)
        self.assertLessEqual(len(agents.encode("utf-8")), 12_000)
        for marker in (
            "niemals Heap-Allokationen",
            "Korruption ablehnen",
            "Swift und JavaScript",
            "audio/",
            "Nie zwei Writer",
            "Produktversion nicht",
            "docs/testing.md",
            "tasks/backlog.md",
            "geschlossen und dürfen nicht reaktiviert",
        ):
            self.assertIn(marker, agents)

    def test_claude_bridge_is_thin(self):
        bridge = (ROOT / "CLAUDE.md").read_text(encoding="utf-8")
        self.assertIn("@AGENTS.md", bridge)
        self.assertLessEqual(len(bridge.encode("utf-8")), 256)

    def test_all_agent_chains_fit_codex_budget(self):
        root_size = (ROOT / "AGENTS.md").stat().st_size
        tracked = subprocess.run(
            ["git", "ls-files", "*AGENTS.md"], cwd=ROOT,
            check=True, capture_output=True, text=True).stdout.splitlines()
        for relative in tracked:
            nested = ROOT / relative
            if nested == ROOT / "AGENTS.md":
                continue
            with self.subTest(path=nested.relative_to(ROOT)):
                self.assertLessEqual(root_size + nested.stat().st_size, 32_768)

    def test_deferred_rules_and_stale_handoff_are_reachable(self):
        testing = (ROOT / "docs/testing.md").read_text(encoding="utf-8")
        backlog = (ROOT / "tasks/backlog.md").read_text(encoding="utf-8")
        for marker in ("DSPChannelTimingTests", "worklet-timing.mjs",
                       "build_app.sh", "QLPreviewReply(fileURL:)",
                       "Notary-Keychain"):
            self.assertIn(marker, testing)
        self.assertIn("GUI-Smoke", backlog)
        self.assertIn("Amiga-Periodentabelle", backlog)

    def test_no_markdown_file_leaks_private_infrastructure(self):
        """Alle getrackten Markdown-Dateien, nicht nur eine feste Handvoll.

        Vorher standen hier fuenf Pfade fest verdrahtet. Am 2026-07-27 fiel auf,
        dass `tasks/2026-07-05-linux-port/plan.md` nie geprueft wurde und deshalb
        zweimal den Kurznamen eines privaten Rechners veroeffentlicht hat.

        Zwei Pruefungen: private IPv4-Bereiche direkt hier, und private Namen
        gegen die `gate:`-Zeilen der Liste ausserhalb dieses Repos (siehe
        `_hard_name_pattern`). Im Repo selbst steht dadurch kein einziger
        interner Name.

        `/Users/<name>` ist bewusst KEIN Befund (Entscheidung 2026-07-27): Der
        Name steht ohnehin auf dem GitHub-Profil, und Beispiele oder Screenshots
        duerfen einen echten Desktop-Pfad zeigen.
        """
        tracked = subprocess.run(
            ["git", "ls-files", "*.md"], cwd=ROOT,
            check=True, capture_output=True, text=True).stdout.splitlines()
        self.assertGreater(len(tracked), 5, "keine Markdown-Dateien gefunden")

        # Private IPv4-Bereiche nach RFC 1918 plus der link-local-Bereich.
        # Dokumentationsadressen (192.0.2.x, 198.51.100.x, 203.0.113.x) und
        # 127.0.0.1 sind ausdruecklich erlaubt und deshalb nicht erfasst.
        private_ip = re.compile(
            r"\b(?:10\.\d{1,3}|192\.168|169\.254|172\.(?:1[6-9]|2\d|3[01]))"
            r"\.\d{1,3}\.\d{1,3}\b")

        names = _hard_name_pattern()
        for relative in tracked:
            with self.subTest(path=relative):
                text = (ROOT / relative).read_text(encoding="utf-8")
                found = private_ip.search(text)
                # assertFalse statt assertIsNone: assertIsNone druckt das
                # Match-Objekt mit und damit den Fund im Klartext. Die Meldung
                # soll auch in einem oeffentlichen CI-Log unbedenklich sein.
                self.assertFalse(
                    bool(found),
                    "private IP-Adresse in %s, Zeile %d"
                    % (relative,
                       text.count("\n", 0, found.start()) + 1 if found else 0))
                if names is None:
                    continue
                hit = names.search(text)
                self.assertFalse(
                    bool(hit),
                    "privater Name in %s, Zeile %d — Begriff siehe lokale Liste"
                    % (relative,
                       text.count("\n", 0, hit.start()) + 1 if hit else 0))


if __name__ == "__main__":
    unittest.main()

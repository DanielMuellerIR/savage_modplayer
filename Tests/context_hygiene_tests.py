#!/usr/bin/env python3
"""Deterministische Evals fuer den kleinen, vollstaendigen Agenten-Kontext."""

from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parent.parent


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

        Der Nadel-Katalog bleibt bewusst STRUKTURELL. Rechnernamen gehoeren nicht
        hierher: Dieses Repo ist oeffentlich, und eine Liste privater Hostnamen in
        einer Assertion veroeffentlicht genau die Namen, die sie schuetzen soll.
        Die namensbasierte Pruefung laeuft ausserhalb dieses Repos gegen eine
        private Denylist, ueber alle oeffentlichen Repos hinweg.

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

        for relative in tracked:
            with self.subTest(path=relative):
                text = (ROOT / relative).read_text(encoding="utf-8")
                found = private_ip.search(text)
                self.assertIsNone(
                    found,
                    "private IP-Adresse in %s: %s"
                    % (relative, found.group(0) if found else ""))


if __name__ == "__main__":
    unittest.main()

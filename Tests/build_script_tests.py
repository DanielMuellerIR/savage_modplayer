"""Quelltest für die Schutzregel „/Applications nur notarisiert".

Fleet-Regel (Daniel, 2026-08-03): Ad-hoc signierte Builds entstehen
ausschließlich im Projektordner, und nach `/Applications` wandert nur ein
Bundle mit angeheftetem Notary-Ticket.

Diese Prüfungen lesen ausschließlich den Quelltext der Skripte. Sie starten
weder einen Build noch eine Installation — ein Testlauf, der `build_app.sh`
oder `install.sh` wirklich ausführt, würde genau das anfassen, was die Regel
schützen soll.
"""

from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]

# Befehle, die etwas anlegen, überschreiben oder löschen. Steht einer davon vor
# dem Wechsel ins Projektverzeichnis, hängt das Bauziel am Arbeitsverzeichnis
# des Aufrufers.
MUTATING = re.compile(
    r"^\s*(?:rm|mkdir|cp|mv|ditto|touch|hdiutil|xcodebuild|swiftc|swift\s+build)\b")

# Der Wechsel selbst — beide Schreibweisen zählen.
PIN_PROJECT_DIR = re.compile(r'^\s*cd\s+"?\$\(dirname\s+"\$0"\)"?')

# Zeilen, die `/Applications` erwähnen dürfen, ohne dorthin zu installieren.
ALLOWED_APPLICATIONS_MENTIONS = (
    # Drag-and-drop-Ziel im DMG: ein Symlink IM Image, nicht im System.
    re.compile(r'^\s*ln\s+-s\s+/Applications\s'),
    # Xcode-Toolchain bzw. der Ordner INNERHALB eines iOS-Archivs.
    re.compile(r"/Applications/Xcode\.app"),
    re.compile(r"Products/Applications/"),
)


def _tracked_shell_scripts():
    """Alle versionierten Shell-Skripte, relativ zum Repo-Wurzelverzeichnis."""
    output = subprocess.run(
        ["git", "ls-files", "*.sh"], cwd=ROOT,
        check=True, capture_output=True, text=True).stdout
    return [line for line in output.splitlines() if line]


def _code_lines(relative):
    """Zeilen ohne reine Kommentarzeilen, als (Zeilennummer, Text)."""
    text = (ROOT / relative).read_text(encoding="utf-8")
    return [(number, line)
            for number, line in enumerate(text.splitlines(), start=1)
            if not line.lstrip().startswith("#")]


class BuildDirectoryPinningTests(unittest.TestCase):
    """Ad-hoc-Builds dürfen nur im Projektordner entstehen."""

    def test_build_scripts_pin_project_directory_before_writing(self):
        for relative in ("build_app.sh", "build_dmg.sh"):
            with self.subTest(script=relative):
                pinned_at = None
                first_write = None
                for number, line in _code_lines(relative):
                    if pinned_at is None and PIN_PROJECT_DIR.match(line):
                        pinned_at = number
                    if first_write is None and MUTATING.match(line):
                        first_write = number
                self.assertIsNotNone(
                    pinned_at,
                    '%s wechselt nicht mit cd "$(dirname "$0")" ins '
                    "Projektverzeichnis — das Bauziel waere das "
                    "Arbeitsverzeichnis des Aufrufers." % relative)
                self.assertIsNotNone(
                    first_write, "%s schreibt gar nichts mehr?" % relative)
                self.assertLess(
                    pinned_at, first_write,
                    "%s schreibt in Zeile %d, bevor es in Zeile %d ins "
                    "Projektverzeichnis wechselt."
                    % (relative, first_write, pinned_at))


class ApplicationsFolderTests(unittest.TestCase):
    """Nur install.sh darf überhaupt nach /Applications greifen."""

    def test_only_install_script_touches_applications(self):
        for relative in _tracked_shell_scripts():
            if relative == "install.sh":
                continue  # der einzige zulässige Installationsweg
            with self.subTest(script=relative):
                for number, line in _code_lines(relative):
                    if "/Applications" not in line:
                        continue
                    erlaubt = any(muster.search(line)
                                  for muster in ALLOWED_APPLICATIONS_MENTIONS)
                    self.assertTrue(
                        erlaubt,
                        "%s:%d fasst /Applications an. Dorthin installiert "
                        "ausschließlich install.sh, und nur mit angeheftetem "
                        "Notary-Ticket." % (relative, number))

    def test_install_script_notarizes_before_it_touches_applications(self):
        quelle = (ROOT / "install.sh").read_text(encoding="utf-8")
        zeilen = quelle.splitlines()

        def erste_zeile(muster):
            regex = re.compile(muster)
            for number, line in enumerate(zeilen, start=1):
                if line.lstrip().startswith("#"):
                    continue
                if regex.search(line):
                    return number
            return None

        notarisierung = erste_zeile(r'^\s*notarize_app\s+"\$APP"')
        self.assertIsNotNone(
            notarisierung, "install.sh ruft notarize_app nicht mehr auf.")

        # Erste Mutation unter /Applications: das Staging-Verzeichnis liegt
        # bereits dort, damit der Austausch danach atomar bleibt.
        erste_mutation = erste_zeile(r'^\s*(?:rm|ditto)\b.*\$STAGED')
        self.assertIsNotNone(
            erste_mutation,
            "install.sh legt kein Staging-Verzeichnis mehr an — Prüfung "
            "muss an das neue Vorgehen angepasst werden.")
        self.assertLess(
            notarisierung, erste_mutation,
            "install.sh fasst /Applications in Zeile %d an, notarisiert aber "
            "erst in Zeile %d." % (erste_mutation, notarisierung))

    def test_notarize_helper_proves_the_stapled_ticket(self):
        quelle = (ROOT / "notarize-lib.sh").read_text(encoding="utf-8")
        # Ein erfolgreicher Upload allein belegt nichts: Erst das angeheftete
        # Ticket macht das Bundle offline Gatekeeper-tauglich.
        self.assertIn("xcrun stapler validate", quelle)
        # Und ein ad-hoc signiertes Bundle wird gar nicht erst eingereicht.
        self.assertIn("Signature=adhoc", quelle)


if __name__ == "__main__":
    unittest.main()

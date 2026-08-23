"""Der Linux-Desktop-Eintrag muss zum Programm passen.

Ein `.desktop`-Eintrag faellt nicht auf, wenn er falsch ist — er erscheint
einfach nicht im Menue oder startet ins Leere. Diese Tests halten die drei
Dinge fest, die dabei wirklich schiefgehen koennen: eine kaputte Datei, ein
Aufruf, der nicht zum CLI passt, und eine Liste von Dateitypen, die von den
tatsaechlich unterstuetzten Formaten abweicht.

`desktop-file-validate` (Paket desktop-file-utils) prueft die Datei gegen die
Spezifikation. Fehlt das Werkzeug — etwa auf dem Mac —, ueberspringt sich genau
dieser eine Test; die inhaltlichen Pruefungen laufen ueberall.
"""

from pathlib import Path
import configparser
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
DESKTOP = ROOT / "linux/savage-cli.desktop"

# Die vier Formate, die der Player kann — dieselbe Liste wie
# ModuleLoader.supportedExtensions, hier als MIME-Typen von freedesktop.org.
EXPECTED_MIME_TYPES = {
    "audio/x-mod",
    "audio/x-s3m",
    "audio/x-xm",
    "audio/x-it",
}


class DesktopEntryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.entry = configparser.ConfigParser(interpolation=None, strict=True)
        # Schluessel wie `GenericName[de]` sind gross/klein bedeutsam.
        cls.entry.optionxform = str
        with DESKTOP.open(encoding="utf-8") as handle:
            cls.entry.read_file(handle)
        cls.section = cls.entry["Desktop Entry"]

    def test_validates_against_the_specification(self):
        tool = shutil.which("desktop-file-validate")
        if tool is None:
            self.skipTest("desktop-file-validate nicht installiert (Paket desktop-file-utils)")
        result = subprocess.run([tool, str(DESKTOP)], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_declares_exactly_the_supported_formats(self):
        declared = {t for t in self.section["MimeType"].split(";") if t}
        self.assertEqual(declared, EXPECTED_MIME_TYPES)

    def test_starts_the_player_in_a_terminal_with_one_file(self):
        exec_line = self.section["Exec"]
        self.assertTrue(exec_line.startswith("savage-cli "), exec_line)
        self.assertIn("--play", exec_line, "ohne --play wuerde der Eintrag nur rendern")
        self.assertIn("%f", exec_line, "der Eintrag bekommt genau eine Datei")
        self.assertNotIn("%F", exec_line, "mehrere Dateien nimmt der Player nicht entgegen")
        # Ohne Terminal gaebe es keine Tastensteuerung — und der Titel liefe
        # unsichtbar und unbedienbar durch.
        self.assertEqual(self.section["Terminal"], "true")

    def test_installer_and_entry_agree_on_the_file_name(self):
        installer = (ROOT / "linux/install.sh").read_text(encoding="utf-8")
        self.assertIn("linux/savage-cli.desktop", installer)
        self.assertIn("savage-cli.desktop", installer)


if __name__ == "__main__":
    unittest.main()

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
import tempfile
import time
import shlex
import re
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

    def test_install_uses_absolute_executable_with_spaces_and_percent(self):
        with tempfile.TemporaryDirectory() as temporary:
            prefix = Path(temporary) / "custom space 50%"
            binary = Path(temporary) / "fake-player"
            binary.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n", encoding="utf-8")
            binary.chmod(0o755)
            subprocess.run(["bash", str(ROOT / "linux/install.sh"), "--prefix",
                            str(prefix), "--binary", str(binary)], check=True,
                           capture_output=True, timeout=10)
            entry = prefix / "share/applications/savage-cli.desktop"
            line = next(line[5:] for line in entry.read_text().splitlines()
                        if line.startswith("Exec="))
            decoded = re.sub(r"\\(.)", lambda match: {"\\": "\\", "n": "\n", "t": "\t", "r": "\r", "s": " "}[match[1]], line)
            args = [arg.replace("%%", "%") for arg in shlex.split(decoded)]
            self.assertEqual(args[:2], ["/bin/sh", "-c"])
            # shlex erhält den Backslash vor $, der Desktop-Exec-Parser entfernt ihn.
            args[2] = args[2].replace(r'\$', '$')
            self.assertEqual(args[2], 'exec "$@"')
            self.assertEqual(args[4], str((prefix / "bin/savage-cli").resolve()))
            args[5] = "/tmp/example module.mod"
            result = subprocess.run(args, check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.splitlines(), [args[5], "--play"])

    def test_gio_launches_reserved_characters_in_installation_path(self):
        try:
            from gi.repository import Gio
        except ImportError:
            self.skipTest("GIO-Python-Anbindung nicht installiert")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            prefix = root / 'space="quote" $dollar `tick` \\slash 50%'
            binary = root / "fake-player"
            output = root / "launch-arguments"
            binary.write_text('#!/bin/sh\nprintf "%s\\n" "$0" "$@" > '
                              + shlex.quote(str(output)) + '\n')
            binary.chmod(0o755)
            subprocess.run(["bash", str(ROOT / "linux/install.sh"), "--prefix",
                            str(prefix), "--binary", str(binary)], check=True,
                           capture_output=True, timeout=10)
            desktop = prefix / "share/applications/savage-cli.desktop"
            content = desktop.read_text()
            self.assertIn("Terminal=true", content)
            # Das Ersatzprogramm schreibt nur Argumente; kein Terminalfenster öffnen.
            desktop.write_text(content.replace("Terminal=true", "Terminal=false"))
            target = root / "example module.mod"
            target.write_bytes(b"")
            app = Gio.DesktopAppInfo.new_from_filename(str(desktop))
            app.launch([Gio.File.new_for_path(str(target))], None)
            deadline = time.monotonic() + 3
            while not output.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertEqual(output.read_text().splitlines(),
                             [str((prefix / "bin/savage-cli").resolve()), str(target), "--play"])

    def test_installer_preserves_symlink_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            prefix = root / "prefix"
            desktop = prefix / "share/applications/savage-cli.desktop"
            desktop.parent.mkdir(parents=True)
            outside = root / "preserve.txt"
            outside.write_text("sentinel")
            outside.chmod(0o640)
            desktop.symlink_to(outside)
            binary = root / "fake-player"
            binary.write_text("#!/bin/sh\nexit 0\n")
            binary.chmod(0o755)
            result = subprocess.run(["bash", str(ROOT / "linux/install.sh"), "--prefix",
                                     str(prefix), "--binary", str(binary)], capture_output=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(outside.read_text(), "sentinel")
            self.assertEqual(outside.stat().st_mode & 0o777, 0o640)

    def test_installer_and_entry_agree_on_the_file_name(self):
        installer = (ROOT / "linux/install.sh").read_text(encoding="utf-8")
        self.assertIn("linux/savage-cli.desktop", installer)
        self.assertIn("savage-cli.desktop", installer)


if __name__ == "__main__":
    unittest.main()

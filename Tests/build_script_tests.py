"""Tests für Bau-, Minifizier- und Simulator-Skripte.

Die Notary-Prüfungen lesen nur Quelltext. Die Simulator-Prüfungen starten das
Skript mit kontrollierten Ersatzprogrammen für `xcrun` und `xcodebuild`; sie
öffnen weder Xcode noch einen Simulator.

Projektinvariante: Ad-hoc signierte Builds entstehen ausschließlich im
Projektordner, und nach `/Applications` wandert nur ein Bundle mit
angeheftetem Notary-Ticket.
"""

from pathlib import Path
import importlib.util
import os
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]

BUILD_SPEC = importlib.util.spec_from_file_location(
    "savage_build", ROOT / "build.py")
BUILD_MODULE = importlib.util.module_from_spec(BUILD_SPEC)
assert BUILD_SPEC.loader is not None
BUILD_SPEC.loader.exec_module(BUILD_MODULE)

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


class DmgMountOwnershipTests(unittest.TestCase):
    def test_early_failure_does_not_detach_an_existing_volume(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary)
            script = fixture / "build_dmg.sh"
            script.write_text((ROOT / "build_dmg.sh").read_text())
            fake_bin = fixture / "bin"
            fake_bin.mkdir()
            log = fixture / "hdiutil.log"
            tool = fake_bin / "hdiutil"
            tool.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HDI_LOG"\necho "/Volumes/Savage Mod Player"\n')
            tool.chmod(0o755)
            environment = os.environ.copy()
            environment.update(PATH=str(fake_bin) + os.pathsep + environment["PATH"],
                               HDI_LOG=str(log), NOTARY_PROFILE="unused")
            result = subprocess.run(["bash", str(script), "--no-finder-layout"],
                                    env=environment, capture_output=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(log.exists(), "Vor eigenem Mount darf kein Volume ausgehaengt werden")


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

    def test_linux_container_build_returns_ownership_to_the_caller(self):
        """Review-Fund 2026-08-25: root-eigenes `.build` blockierte den Nutzer.

        Der Container läuft als root und schreibt in das eingebundene
        Arbeitsverzeichnis. Ohne Rückgabe der Eigentümerschaft kann der
        aufrufende Nutzer danach weder lokal bauen noch aufräumen.
        """
        script = (ROOT / "linux" / "build-static.sh").read_text(encoding="utf-8")
        self.assertIn('chown -R "$HOST_UID:$HOST_GID" .build', script)
        self.assertIn(
            '-e "HOST_UID=$HOST_UID" -e "HOST_GID=$HOST_GID"', script,
            "Nicht exportierte Shellvariablen muessen mit ihrem Wert an den "
            "Container gehen; `-e HOST_UID` allein sieht sie nicht.")
        # Die Rückgabe muss auch nach einem gescheiterten Bau laufen — sonst
        # bleiben die halben Zwischenstände root-eigen.
        self.assertLess(script.index("rc=$?"), script.index("chown -R"))
        self.assertLess(script.index("chown -R"), script.index("exit $rc"))
        self.assertIn("name=rootless", script)
        self.assertIn("RETURN_OWNERSHIP=0", script)
        self.assertIn("--userns=host", script)
        self.assertNotIn('chown -R "$HOST_UID:$HOST_GID" .build 2>/dev/null || true', script)
        self.assertIn('find .build \\( ! -user "$HOST_UID" -o ! -group "$HOST_GID" \\)', script)

    def test_visualizer_measurement_backs_up_defaults_before_writing(self):
        """Ein fehlgeschlagenes Backup darf nie wie „Domain fehlte“ wirken."""
        script = (ROOT / "Tests" / "measure_visualizer_cpu.sh").read_text(
            encoding="utf-8")
        self.assertIn("defaults domains", script)
        self.assertIn("DEFAULTS_STATE=present", script)
        self.assertIn("DEFAULTS_STATE=absent", script)
        self.assertLess(script.index("defaults export"), script.index("defaults write"))
        self.assertNotIn("pkill -f", script,
                         "Messung darf keine fremde laufende App beenden")
        self.assertRegex(
            script,
            r'if defaults import .*?; then\n\s*#.*?\n\s*rm -f "\$BACKUP"',
            "Sicherung darf erst nach erfolgreichem Import geloescht werden")

    def test_visualizer_measurement_aborts_before_writes_when_backup_fails(self):
        """Der reale Shell-Ablauf darf den `defaults`-Fehler nicht umdeuten."""
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary)
            module = fixture / "test.mod"
            module.write_bytes(b"MOD")
            app = fixture / "SavageModPlayerApp"
            app.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            app.chmod(0o755)
            log = fixture / "defaults.log"
            fake_bin = fixture / "bin"
            fake_bin.mkdir()
            defaults = fake_bin / "defaults"
            defaults.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$DEFAULTS_LOG\"\n"
                "case \"$1\" in\n"
                "  domains) echo com.viben.SavageModPlayer ;;\n"
                "  export) exit 9 ;;\n"
                "  *) exit 0 ;;\n"
                "esac\n",
                encoding="utf-8")
            defaults.chmod(0o755)
            environment = os.environ.copy()
            environment.update({
                "PATH": str(fake_bin) + os.pathsep + environment["PATH"],
                "TMPDIR": str(fixture),
                "DEFAULTS_LOG": str(log),
                "SAVAGE_VISUALIZER_BIN": str(app),
            })

            result = subprocess.run(
                ["bash", str(ROOT / "Tests" / "measure_visualizer_cpu.sh"),
                 str(module), "30"],
                cwd=ROOT, env=environment, capture_output=True, text=True,
                timeout=10)

            self.assertNotEqual(result.returncode, 0)
            calls = log.read_text(encoding="utf-8")
            self.assertIn("export com.viben.SavageModPlayer", calls)
            self.assertNotIn("write ", calls)
            self.assertNotIn("import ", calls)
            self.assertNotIn("delete ", calls)

    def test_visualizer_measurement_recognizes_domain_in_long_list(self):
        """Ein frueher Treffer darf unter `pipefail` nicht als fehlend gelten."""
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary)
            module = fixture / "test.mod"
            module.write_bytes(b"MOD")
            app = fixture / "SavageModPlayerApp"
            app.write_text(
                "#!/bin/sh\nwhile :; do sleep 1; done\n", encoding="utf-8")
            app.chmod(0o755)
            log = fixture / "defaults.log"
            fake_bin = fixture / "bin"
            fake_bin.mkdir()
            defaults = fake_bin / "defaults"
            defaults.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$DEFAULTS_LOG\"\n"
                "case \"$1\" in\n"
                "  domains) printf 'com.viben.SavageModPlayer'; "
                "i=0; while [ \"$i\" -lt 10000 ]; do "
                "printf ', com.example.domain%s' \"$i\"; "
                "i=$((i + 1)); done ;;\n"
                "  export) printf backup > \"$3\" ;;\n"
                "  *) exit 0 ;;\n"
                "esac\n",
                encoding="utf-8")
            defaults.chmod(0o755)
            environment = os.environ.copy()
            environment.update({
                "PATH": str(fake_bin) + os.pathsep + environment["PATH"],
                "TMPDIR": str(fixture),
                "DEFAULTS_LOG": str(log),
                "SAVAGE_VISUALIZER_BIN": str(app),
                "SAVAGE_VISUALIZER_SETTLE": "0",
                "SAVAGE_VISUALIZER_WINDOW": "0.01",
            })

            result = subprocess.run(
                ["bash", str(ROOT / "Tests" / "measure_visualizer_cpu.sh"),
                 str(module), "30"],
                cwd=ROOT, env=environment, capture_output=True, text=True,
                timeout=10)

            self.assertEqual(result.returncode, 0, result.stderr)
            calls = log.read_text(encoding="utf-8")
            self.assertIn("export com.viben.SavageModPlayer", calls)
            self.assertIn("import com.viben.SavageModPlayer", calls)
            self.assertNotIn("delete ", calls)

    def test_visualizer_measurement_keeps_backup_when_restore_fails(self):
        """Ein Restore-Fehler muss sichtbar sein und die Sicherung behalten."""
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary)
            module = fixture / "test.mod"
            module.write_bytes(b"MOD")
            app = fixture / "SavageModPlayerApp"
            app.write_text(
                "#!/bin/sh\nwhile :; do sleep 1; done\n", encoding="utf-8")
            app.chmod(0o755)
            log = fixture / "defaults.log"
            fake_bin = fixture / "bin"
            fake_bin.mkdir()
            defaults = fake_bin / "defaults"
            defaults.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$DEFAULTS_LOG\"\n"
                "case \"$1\" in\n"
                "  domains) echo com.viben.SavageModPlayer ;;\n"
                "  export) printf backup > \"$3\" ;;\n"
                "  import) exit 9 ;;\n"
                "  *) exit 0 ;;\n"
                "esac\n",
                encoding="utf-8")
            defaults.chmod(0o755)
            environment = os.environ.copy()
            environment.update({
                "PATH": str(fake_bin) + os.pathsep + environment["PATH"],
                "TMPDIR": str(fixture),
                "DEFAULTS_LOG": str(log),
                "SAVAGE_VISUALIZER_BIN": str(app),
                "SAVAGE_VISUALIZER_SETTLE": "0",
                "SAVAGE_VISUALIZER_WINDOW": "0.01",
            })

            result = subprocess.run(
                ["bash", str(ROOT / "Tests" / "measure_visualizer_cpu.sh"),
                 str(module), "30"],
                cwd=ROOT, env=environment, capture_output=True, text=True,
                timeout=10)

            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            match = re.search(r"Sicherung bleibt unter (.+)", result.stderr)
            self.assertIsNotNone(match, result.stderr)
            self.assertTrue(Path(match.group(1)).is_file())
            calls = log.read_text(encoding="utf-8")
            self.assertIn("import com.viben.SavageModPlayer", calls)
            self.assertNotIn("delete ", calls)

    def test_linux_container_mode_controls_namespace_and_chown(self):
        """Rootless nutzt UID 0 als Hostnutzer; userns-remap wird deaktiviert."""
        source = (ROOT / "linux" / "build-static.sh").read_text(encoding="utf-8")
        for security, expected_return, expects_userns in (
                ("name=rootless", "RETURN_OWNERSHIP=0", False),
                ("name=userns", "RETURN_OWNERSHIP=1", True)):
            with self.subTest(security=security), tempfile.TemporaryDirectory() as temporary:
                fixture = Path(temporary)
                (fixture / "linux").mkdir()
                (fixture / "linux" / "build-static.sh").write_text(
                    source, encoding="utf-8")
                binary = fixture / ".build/release/savage-cli"
                binary.parent.mkdir(parents=True)
                binary.write_bytes(b"binary")
                binary.chmod(0o755)
                fake_bin = fixture / "bin"
                fake_bin.mkdir()
                log = fixture / "docker.log"
                docker = fake_bin / "docker"
                docker.write_text(
                    "#!/bin/sh\n"
                    "if [ \"$1\" = info ]; then echo \"$FAKE_DOCKER_SECURITY\"; exit 0; fi\n"
                    "printf '%s\\n' \"$*\" >> \"$DOCKER_LOG\"\n",
                    encoding="utf-8")
                docker.chmod(0o755)
                environment = os.environ.copy()
                environment.update({
                    "PATH": str(fake_bin) + os.pathsep + environment["PATH"],
                    "DOCKER_LOG": str(log),
                    "FAKE_DOCKER_SECURITY": security,
                })

                result = subprocess.run(
                    ["bash", str(fixture / "linux" / "build-static.sh")],
                    cwd=fixture, env=environment, capture_output=True, text=True,
                    timeout=10)

                self.assertEqual(result.returncode, 0, result.stderr)
                arguments = log.read_text(encoding="utf-8")
                self.assertIn(expected_return, arguments)
                self.assertEqual("--userns=host" in arguments, expects_userns)

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


class JavaScriptMinifierTests(unittest.TestCase):
    """Der Minifizierer darf sichtbare Texte nicht umschreiben."""

    def test_punctuation_inside_strings_is_preserved(self):
        source = (
            "throw new Error(`Leeres MOD (Songlänge 0): ${label}`); "
            "const choice = ok ? left : right;")

        result = BUILD_MODULE.minify_js(source)

        self.assertIn("`Leeres MOD (Songlänge 0): ${label}`", result)
        self.assertIn("const choice=ok?left:right;", result)


class IOSSimulatorScriptTests(unittest.TestCase):
    """Simulatorwahl mit kontrollierten xcrun-/xcodebuild-Antworten."""

    def _run(self, xcrun_body, simulator_name=None):
        with tempfile.TemporaryDirectory(prefix="savage-ios-script-") as tmp:
            tmp_path = Path(tmp)
            xcrun = tmp_path / "xcrun"
            xcrun.write_text("#!/bin/sh\n" + xcrun_body, encoding="utf-8")
            xcrun.chmod(0o755)
            xcodebuild = tmp_path / "xcodebuild"
            xcodebuild.write_text(
                "#!/bin/sh\nprintf '%s\\n' '** TEST SUCCEEDED **'\n",
                encoding="utf-8")
            xcodebuild.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = str(tmp_path) + os.pathsep + env["PATH"]
            env["DERIVED_DATA"] = str(tmp_path / "DerivedData")
            env["TEST_LOG"] = str(tmp_path / "run-tests.log")
            if simulator_name is not None:
                env["SIMULATOR_NAME"] = simulator_name

            return subprocess.run(
                ["bash", str(ROOT / "ios/scripts/run-tests.sh")],
                cwd=ROOT, env=env, capture_output=True, text=True)

    def test_explicit_ipad_uses_newest_matching_runtime(self):
        result = self._run(
            """printf '%s\\n' \\
'-- iOS 17.5 --' \\
'    iPad Pro 13-inch (M4) (11111111-1111-1111-1111-111111111111) (Shutdown)' \\
'-- iOS 18.2 --' \\
'    iPad Pro 13-inch (M4) (22222222-2222-2222-2222-222222222222) (Shutdown)'\n""",
            simulator_name="iPad Pro 13-inch (M4)")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("22222222-2222-2222-2222-222222222222", result.stdout)
        self.assertIn("iOS 18.2", result.stdout)

    def test_simctl_failure_keeps_the_original_diagnostic(self):
        result = self._run(
            "printf '%s\\n' 'CoreSimulator-Dienst nicht erreichbar' >&2\nexit 7\n")

        self.assertEqual(result.returncode, 2)
        self.assertIn("CoreSimulator-Dienst nicht erreichbar", result.stdout)


if __name__ == "__main__":
    unittest.main()

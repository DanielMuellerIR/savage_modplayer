"""Zusagen der Kommandozeile: Exit-Codes und Zahlgrenzen.

`savage-cli` ist die einzige kopflose Schnittstelle des Projekts. Ihr Vertrag
steht in `docs/testing.md`: ungueltige Zahlparameter — `nan`, `inf`, negative
Werte und Werte oberhalb der dokumentierten Grenze — muessen den Prozess VOR
dem Parsen oder Rendern mit Exit-Code 2 beenden. Geprueft wurde das bisher nur
von Hand; damit konnte die Zusage still verrotten.

Der Test baut nichts. Er benutzt ein vorhandenes `savage-cli` aus
`.build/release` oder `.build/debug` und ueberspringt sich sauber, wenn keines
da ist — ein Skip ist ausdruecklich kein Beleg fuer eine erfuellte Zusage.

Das Modul dafuer entsteht synthetisch im Temp-Verzeichnis: ein minimales
4-Kanal-M.K.-MOD. So braucht der Test kein Material aus `audio/`, das bewusst
nicht im Repo liegt.
"""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]

# Exit-Codes laut Quelltext von Sources/SavageCLI/main.swift.
EXIT_OK = 0
EXIT_RUNTIME = 1     # Datei fehlt, Parserfehler, Schreibfehler
EXIT_ARGUMENT = 2    # Argument- und Wertefehler, vor Parse und Render


def _binary():
    for build in ("release", "debug"):
        candidate = ROOT / ".build" / build / "savage-cli"
        if candidate.exists():
            return candidate
    return None


def _minimal_mod():
    """Kleinstes spielbares M.K.-MOD: 31 Instrumente, eine Songposition."""
    data = bytearray(1084 + 1024 + 4)
    data[20 + 22] = 0x00      # Instrument 1: Laenge 2 Words
    data[20 + 23] = 0x02
    data[20 + 25] = 64        # Volume
    data[950] = 1             # Songlaenge 1
    data[952] = 0             # Order 0 -> Pattern 0
    data[1080:1084] = b"M.K."
    # Pattern 0, Zeile 0, Kanal 0: Instrument 1, Periode 428 (C-3).
    period = 428
    data[1084] = (period >> 8) & 0x0F
    data[1085] = period & 0xFF
    data[1086] = 0x10         # Instrument 1 (untere Nibbles), kein Effekt
    data[1087] = 0x00
    data[-4:] = bytes((0, 64, 192, 0))
    return bytes(data)


class CLIContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = _binary()
        if cls.binary is None:
            raise unittest.SkipTest(
                "kein savage-cli in .build/release oder .build/debug — "
                "zuerst 'swift build -c release --product savage-cli'")
        cls._tempdir = tempfile.TemporaryDirectory()
        cls.module = Path(cls._tempdir.name) / "test.mod"
        cls.module.write_bytes(_minimal_mod())

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "_tempdir"):
            cls._tempdir.cleanup()

    def _run(self, *args):
        out = Path(self._tempdir.name) / "out.wav"
        return self._run_raw(*args, "--out", str(out), "--quiet")

    def _run_raw(self, *args):
        return subprocess.run(
            [str(self.binary), str(self.module), *args],
            capture_output=True, text=True, timeout=120)

    def test_module_renders_at_all(self):
        """Ohne diesen Nachweis saehe jeder Fehlerfall unten gleich aus."""
        self.assertEqual(self._run("--seconds", "1").returncode, EXIT_OK)

    def test_non_finite_and_out_of_range_numbers_are_argument_errors(self):
        cases = [
            ("--seconds", "nan"), ("--seconds", "inf"), ("--seconds", "-inf"),
            ("--seconds", "-1"), ("--seconds", "601"),
            ("--rate", "nan"), ("--rate", "inf"),
            ("--rate", "7999"), ("--rate", "192001"), ("--rate", "-44100"),
            ("--pattern", "-1"),
        ]
        for option, value in cases:
            with self.subTest(option=option, value=value):
                result = self._run(option, value)
                self.assertEqual(
                    result.returncode, EXIT_ARGUMENT,
                    "%s %s muss vor Parse und Render mit Exit %d enden, war %d"
                    % (option, value, EXIT_ARGUMENT, result.returncode))
                # Und zwar als Wertefehler, nicht als Nebenwirkung.
                self.assertIn(value, result.stderr + result.stdout)

    def test_documented_boundaries_are_accepted(self):
        """Die Grenzen selbst gehoeren zum gueltigen Bereich."""
        for option, value in [("--seconds", "600"), ("--seconds", "0"),
                              ("--rate", "8000"), ("--rate", "192000")]:
            with self.subTest(option=option, value=value):
                # Kurz halten: geprueft wird die Annahme des Werts, nicht die
                # volle Renderdauer.
                args = [option, value]
                if option != "--seconds":
                    args += ["--seconds", "1"]
                self.assertEqual(self._run(*args).returncode, EXIT_OK)

    def test_missing_value_and_unknown_option_are_argument_errors(self):
        for option in ("--seconds", "--rate", "--pattern"):
            with self.subTest(option=option):
                result = self._run_raw(option)
                self.assertEqual(result.returncode, EXIT_ARGUMENT)
                self.assertIn(
                    "Wert für %s fehlt." % option,
                    result.stderr + result.stdout)

        self.assertEqual(self._run("--voellig-unbekannt").returncode, EXIT_ARGUMENT)

    def test_incompatible_options_are_rejected(self):
        """--stdout kann nicht normalisieren und nicht zugleich in eine Datei."""
        result = subprocess.run(
            [str(self.binary), str(self.module), "--stdout", "--normalize"],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, EXIT_ARGUMENT)

    def test_play_together_with_an_analysis_option_is_rejected(self):
        """Review-Fund 2026-08-25: `--play --info` startete die Wiedergabe.

        Der Wiedergabe-Zweig steht im Ablauf vor der Textausgabe. Eine
        Automatisierung, die eine endliche Ausgabe erwartet, blieb daran hängen
        — und gab womöglich noch Ton aus.
        """
        for option in (["--info"], ["--pattern", "0"]):
            with self.subTest(option=option):
                result = subprocess.run(
                    [str(self.binary), str(self.module), "--play", *option],
                    capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, EXIT_ARGUMENT,
                                 result.stderr + result.stdout)
                self.assertIn("--play", result.stderr)

    def test_list_prints_one_path_per_line(self):
        folder = Path(self._tempdir.name) / "liste"
        (folder / "unterordner").mkdir(parents=True, exist_ok=True)
        for name in ("b.mod", "a.mod", "unterordner/c.mod"):
            (folder / name).write_bytes(_minimal_mod())
        (folder / "notiz.txt").write_text("kein Modul")
        result = subprocess.run(
            [str(self.binary), "--list", str(folder)],
            capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, EXIT_OK)
        printed = result.stdout.split()
        self.assertEqual(len(printed), 3, result.stdout)
        self.assertEqual(printed, sorted(printed), "Ausgabe muss nach Pfad sortiert sein")
        self.assertNotIn("notiz.txt", result.stdout)

    def test_list_ignores_non_regular_files_with_module_names(self):
        """Eine passende Endung macht weder Ordner noch FIFO zum Modul.

        Besonders die FIFO ist fuer --play gefaehrlich: Data(contentsOf:)
        wartet dort auf einen Schreiber und der Player bleibt unbegrenzt stehen.
        """
        folder = Path(self._tempdir.name) / "dateitypen"
        folder.mkdir(exist_ok=True)
        (folder / "echt.mod").write_bytes(_minimal_mod())
        (folder / "ordner.xm").mkdir()
        fifo = folder / "stream.s3m"
        os.mkfifo(fifo)

        result = subprocess.run(
            [str(self.binary), "--list", str(folder)],
            capture_output=True, text=True, timeout=60)

        self.assertEqual(result.returncode, EXIT_OK, result.stderr)
        printed = result.stdout.splitlines()
        self.assertEqual(len(printed), 1, result.stdout)
        # macOS kanonisiert /var beim Enumerieren zu /private/var.
        self.assertEqual(Path(printed[0]).resolve(), (folder / "echt.mod").resolve())

    def test_direct_input_rejects_fifo_without_waiting_for_a_writer(self):
        """Analyse und --play muessen VOR Data-Lesen auf regulär pruefen."""
        fifo = Path(self._tempdir.name) / "direkt.mod"
        os.mkfifo(fifo)

        for arguments in (["--info"], ["--play", "--seconds", "0.1"]):
            with self.subTest(arguments=arguments):
                result = subprocess.run(
                    [str(self.binary), str(fifo), *arguments],
                    capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, EXIT_RUNTIME)
                self.assertIn("reguläre Datei", result.stderr)

    def test_list_on_an_empty_folder_is_a_runtime_error(self):
        empty = Path(self._tempdir.name) / "leer-liste"
        empty.mkdir(exist_ok=True)
        result = subprocess.run(
            [str(self.binary), "--list", str(empty)],
            capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, EXIT_RUNTIME)

    def test_list_on_a_file_is_a_runtime_error(self):
        result = subprocess.run(
            [str(self.binary), "--list", str(self.module)],
            capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, EXIT_RUNTIME)

    def test_list_together_with_an_input_file_is_rejected(self):
        """Vorher gewann still --list und die Datei verschwand kommentarlos."""
        result = subprocess.run(
            [str(self.binary), str(self.module), "--list", self._tempdir.name],
            capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, EXIT_ARGUMENT)
        self.assertIn("--list", result.stderr)

    def test_missing_input_file_is_a_runtime_error_not_an_argument_error(self):
        """Der Unterschied zaehlt: 1 heisst Laufzeit, 2 heisst Aufruf."""
        result = subprocess.run(
            [str(self.binary), str(Path(self._tempdir.name) / "gibtsnicht.mod"),
             "--out", str(Path(self._tempdir.name) / "x.wav"), "--quiet"],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, EXIT_RUNTIME)


if __name__ == "__main__":
    unittest.main()

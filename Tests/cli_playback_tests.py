"""Echtzeit-Wiedergabe der Kommandozeile: Playlist, Tasten, Ctrl-C.

`savage-cli --play` laesst sich nicht wie ein Renderlauf pruefen: Es braucht
eine Audio-Ausgabe, und die Steuerung braucht ein Terminal. Beides ist mit
Bordmitteln herstellbar — ein Pseudoterminal aus `pty` als stdin, und ein
synthetisches Modul, dessen Sample nur aus Nullbytes besteht und das deshalb
auch bei aufgedrehter Anlage lautlos bleibt.

Ohne nutzbare Audio-Ausgabe (CI-Container ohne ALSA-Geraet) ueberspringt sich
die Suite sauber. Ein Skip ist ausdruecklich kein Beleg dafuer, dass die
Wiedergabe funktioniert.
"""

from pathlib import Path
import os
import pty
import select
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]

EXIT_OK = 0
EXIT_RUNTIME = 1
EXIT_ARGUMENT = 2
EXIT_INTERRUPTED = 130   # 128 + SIGINT, die uebliche Zusage an Skripte

# Wie lange auf eine erwartete Meldung gewartet wird. Grosszuegig, weil beim
# ersten Titel das Audio-Geraet noch geoeffnet werden muss.
MESSAGE_TIMEOUT = 10.0


def _binary():
    for build in ("release", "debug"):
        candidates = [ROOT / ".build" / build / "savage-cli",
                      ROOT / ".build" / "out" / "Products" / build.capitalize() / "savage-cli"]
        existing = [candidate for candidate in candidates if candidate.is_file()]
        if existing:
            return max(existing, key=lambda candidate: candidate.stat().st_mtime_ns)
    return None


def _silent_mod():
    """Minimal gueltiges M.K.-MOD, dessen Sample nur Nullbytes enthaelt."""
    data = bytearray(1084 + 1024 + 4)
    data[20 + 23] = 0x02      # Instrument 1: Laenge 2 Words
    data[20 + 25] = 64        # Lautstaerke
    data[950] = 1             # Songlaenge 1 Position
    data[1080:1084] = b"M.K."
    period = 428              # C-3
    data[1084] = (period >> 8) & 0x0F
    data[1085] = period & 0xFF
    data[1086] = 0x10         # Instrument 1
    return bytes(data)


class PlaybackSession:
    """Ein laufendes `savage-cli --play` mit Pseudoterminal an stdin."""

    def __init__(self, binary, args):
        self.master, slave = pty.openpty()
        self.process = subprocess.Popen(
            [str(binary), *args],
            stdin=slave, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        os.close(slave)
        self.log = ""

    def _drain(self, seconds):
        deadline = time.time() + seconds
        while time.time() < deadline:
            ready, _, _ = select.select([self.process.stderr], [], [], 0.05)
            if not ready:
                continue
            chunk = os.read(self.process.stderr.fileno(), 4096)
            if not chunk:
                return
            self.log += chunk.decode("utf-8", "replace")

    def wait_for(self, text, occurrences=1, timeout=MESSAGE_TIMEOUT):
        """Wartet, bis `text` mindestens `occurrences`-mal im Protokoll steht."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.log.count(text) >= occurrences:
                return True
            self._drain(0.1)
        return self.log.count(text) >= occurrences

    def send(self, keys):
        os.write(self.master, keys)

    def wait_exit(self, timeout=MESSAGE_TIMEOUT):
        try:
            code = self.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
            return None
        self._drain(0.3)
        return code

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        self.process.stderr.close()
        os.close(self.master)


class CLIPlaybackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = _binary()
        if cls.binary is None:
            raise unittest.SkipTest(
                "kein savage-cli in den Swift-Build-Ausgabepfaden — "
                "zuerst 'swift build -c release --product savage-cli'")
        cls._tempdir = tempfile.TemporaryDirectory()
        cls.folder = Path(cls._tempdir.name) / "playlist"
        (cls.folder / "unterordner").mkdir(parents=True)
        # Namen so gewaehlt, dass die Sortierung nach Pfad eindeutig ist.
        cls.tracks = [cls.folder / "1-eins.mod",
                      cls.folder / "2-zwei.mod",
                      cls.folder / "unterordner" / "3-drei.mod"]
        for track in cls.tracks:
            track.write_bytes(_silent_mod())
        (cls.folder / "keinmodul.txt").write_text("nur Text")

        # Ein Probelauf beantwortet zwei Fragen auf einmal.
        #
        # Erstens: Laesst sich auf diesem Rechner ueberhaupt abspielen? Ohne
        # Audio-Geraet endet --play mit 1, und alles Weitere waere nur Rauschen
        # im Report.
        #
        # Zweitens: Laeuft die Ausgabe im Takt der Echtzeit? Ein ALSA-Nullgeraet
        # (`pcm.!default { type null }`, der uebliche Weg fuer einen lautlosen
        # Linux-Lauf) verschluckt die Samples so schnell, wie der Renderer sie
        # liefert — drei Titel sind dann vorbei, bevor ein Tastendruck ankommt.
        # Die zeitabhaengigen Tests haetten dort nichts zu steuern und
        # ueberspringen sich mit klarer Begruendung.
        started = time.monotonic()
        probe = subprocess.run(
            [str(cls.binary), str(cls.tracks[0]), "--play", "--seconds", "3", "--quiet"],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        elapsed = time.monotonic() - started
        if probe.returncode != EXIT_OK:
            raise unittest.SkipTest(
                "keine nutzbare Audio-Ausgabe: %s" % (probe.stderr.strip() or "Exit %d" % probe.returncode))
        cls.realtime_paced = elapsed >= 2.0

    def requireRealtimePacing(self):
        if not self.realtime_paced:
            self.skipTest(
                "Audio-Ausgabe ohne Echtzeittakt (etwa ALSA-Nullgerät): "
                "die Wiedergabe ist vorbei, bevor eine Taste ankommt")

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "_tempdir"):
            cls._tempdir.cleanup()

    # ---- Playlist ohne Bedienung -------------------------------------------

    def test_playlist_plays_every_module_in_path_order(self):
        result = subprocess.run(
            [str(self.binary), "--list", str(self.folder), "--play", "--seconds", "1"],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, EXIT_OK, result.stderr)
        for position in ("[1/3]", "[2/3]", "[3/3]"):
            self.assertIn(position, result.stderr,
                          "Titel %s fehlt in der Wiedergabe" % position)
        self.assertLess(result.stderr.index("[1/3]"), result.stderr.index("[2/3]"))
        self.assertLess(result.stderr.index("[2/3]"), result.stderr.index("[3/3]"))

    def test_empty_folder_is_a_runtime_error(self):
        empty = Path(self._tempdir.name) / "leer"
        empty.mkdir(exist_ok=True)
        result = subprocess.run(
            [str(self.binary), "--list", str(empty), "--play"],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, EXIT_RUNTIME)

    def test_broken_module_is_skipped_not_fatal(self):
        mixed = Path(self._tempdir.name) / "gemischt"
        mixed.mkdir(exist_ok=True)
        (mixed / "1-kaputt.mod").write_bytes(b"\x00" * 2000)
        (mixed / "2-gut.mod").write_bytes(_silent_mod())
        result = subprocess.run(
            [str(self.binary), "--list", str(mixed), "--play", "--seconds", "1"],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, EXIT_OK, result.stderr)
        self.assertIn("Parse-Fehler", result.stderr)
        self.assertIn("[2/2]", result.stderr)

    def test_only_broken_modules_end_with_a_runtime_error(self):
        broken = Path(self._tempdir.name) / "nur-kaputt"
        broken.mkdir(exist_ok=True)
        (broken / "kaputt.mod").write_bytes(b"\x00" * 2000)
        result = subprocess.run(
            [str(self.binary), "--list", str(broken), "--play", "--seconds", "1"],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, EXIT_RUNTIME)

    # ---- Tastatursteuerung --------------------------------------------------

    def test_keys_switch_pause_and_end_playback(self):
        self.requireRealtimePacing()
        session = PlaybackSession(
            self.binary, ["--list", str(self.folder), "--play", "--seconds", "30"])
        self.addCleanup(session.close)

        self.assertTrue(session.wait_for("[1/3]"), session.log)
        self.assertIn("Tasten:", session.log,
                      "An einem Terminal gehoert der Tastenhinweis in die Ausgabe")

        session.send(b"n")
        self.assertTrue(session.wait_for("[2/3]"), session.log)

        session.send(b" ")
        self.assertTrue(session.wait_for("Pause."), session.log)
        session.send(b" ")
        self.assertTrue(session.wait_for("Weiter."), session.log)

        session.send(b"b")
        self.assertTrue(session.wait_for("[1/3]", occurrences=2), session.log)

        # Pfeil rechts ist der zweite Weg zum naechsten Titel.
        session.send(b"\x1b[C")
        self.assertTrue(session.wait_for("[2/3]", occurrences=2), session.log)

        session.send(b"q")
        self.assertEqual(session.wait_exit(), EXIT_OK, session.log)
        self.assertIn("Wiedergabe beendet.", session.log)

    def test_unknown_key_does_not_disturb_playback(self):
        self.requireRealtimePacing()
        session = PlaybackSession(
            self.binary, ["--list", str(self.folder), "--play", "--seconds", "30"])
        self.addCleanup(session.close)
        self.assertTrue(session.wait_for("[1/3]"), session.log)
        session.send(b"xyz\r\n")
        time.sleep(0.5)
        self.assertNotIn("[2/3]", session.log,
                         "Unbekannte Tasten duerfen den Titel nicht wechseln")
        session.send(b"q")
        self.assertEqual(session.wait_exit(), EXIT_OK, session.log)

    def test_quit_on_the_last_track_ends_cleanly(self):
        self.requireRealtimePacing()
        session = PlaybackSession(
            self.binary, [str(self.tracks[0]), "--play", "--seconds", "30"])
        self.addCleanup(session.close)
        self.assertTrue(session.wait_for("Spiele"), session.log)
        # Einzeltitel: keine Positionsangabe, weil es nichts zu zaehlen gibt.
        self.assertNotIn("[1/1]", session.log)
        session.send(b"q")
        self.assertEqual(session.wait_exit(), EXIT_OK, session.log)

    # ---- Ctrl-C -------------------------------------------------------------

    def test_sigint_stops_playback_with_the_conventional_exit_code(self):
        """Ohne Terminal lief `--play` frueher trotz Ctrl-C bis zum Ende weiter."""
        self.requireRealtimePacing()
        process = subprocess.Popen(
            [str(self.binary), "--list", str(self.folder), "--play", "--seconds", "30"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            time.sleep(2.0)
            process.send_signal(signal.SIGINT)
            code = process.wait(timeout=MESSAGE_TIMEOUT)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            self.fail("SIGINT beendete die Wiedergabe nicht")
        finally:
            stderr = process.stderr.read().decode("utf-8", "replace")
            process.stderr.close()
        self.assertEqual(code, EXIT_INTERRUPTED, stderr)
        self.assertIn("Wiedergabe beendet.", stderr)
        self.assertNotIn("[3/3]", stderr, "Nach Ctrl-C darf kein Titel mehr starten")


if __name__ == "__main__":
    unittest.main()

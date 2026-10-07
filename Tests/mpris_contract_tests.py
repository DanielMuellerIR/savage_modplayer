"""MPRIS-Vertrag am echten Linux-CLI. Benötigt Sitzungsbus und Audioausgabe.

Auf einem Testdesktop direkt ausführen, isoliert alternativ unter
`dbus-run-session`. Fehlende Infrastruktur ist ein Skip, kein Desktopnachweis.
Alle Audiodaten sind synthetische Nullsamples; jede Instanz wird beendet.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PLAYER = "org.mpris.MediaPlayer2.Player"
PROPS = "org.freedesktop.DBus.Properties"
PATH = "/org/mpris/MediaPlayer2"


def silent_mod():
    data = bytearray(1084 + 1024 + 4)
    data[:15] = b"MPRIS silent 01"
    data[43], data[45], data[950] = 2, 64, 1
    data[1080:1084] = b"M.K."
    data[1084:1088] = bytes([1, 172, 16, 0])
    data[1090:1092] = bytes([15, 31])  # Speed 31
    data[1094:1096] = bytes([15, 32])  # Tempo 32: ausreichend Zeit für Steuerung.
    return data


class Session:
    def __init__(self, binary, directory):
        self.process = subprocess.Popen(
            [str(binary), "--list", str(directory), "--play", "--seconds", "60", "--quiet"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.name = f"org.mpris.MediaPlayer2.savage.instance{self.process.pid}"

    def call(self, method, *args, interface=PLAYER, check=True):
        return subprocess.run(
            ["gdbus", "call", "--session", "--dest", self.name,
             "--object-path", PATH, "--method", f"{interface}.{method}", *args],
            text=True, capture_output=True, timeout=3, check=check)

    def get(self, property):
        return self.call("Get", PLAYER, property, interface=PROPS).stdout

    def wait_status(self, status):
        deadline = time.monotonic() + 5
        last = ""
        while time.monotonic() < deadline:
            result = self.call("Get", PLAYER, "PlaybackStatus", interface=PROPS, check=False)
            last = result.stdout + result.stderr
            if f"'{status}'" in result.stdout:
                return
            if self.process.poll() is not None:
                raise AssertionError(self.process.stderr.read().decode())
            time.sleep(0.05)
        raise AssertionError(f"Status {status} fehlt: {last}")

    def position(self):
        return int(re.search(r"int64 (\d+)", self.get("Position"))[1])

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.process.stderr.close()


@unittest.skipUnless(sys.platform.startswith("linux"), "MPRIS ist Linux-spezifisch")
class MPRISContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get("SAVAGE_CLI_TEST_BINARY", ROOT / ".build/release/savage-cli")).resolve()
        if not cls.binary.is_file() or not shutil.which("gdbus"):
            raise unittest.SkipTest("Release-CLI oder gdbus fehlt")
        if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
            raise unittest.SkipTest("Kein ausdrücklicher Test-Sitzungsbus")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        for name in ["01.mod", "02.mod"]:
            (directory / name).write_bytes(silent_mod())
        self.session = Session(self.binary, directory)
        self.addCleanup(self.session.close)
        try:
            self.session.wait_status("Playing")
        except AssertionError as error:
            if "Audio-Ausgabe nicht verfügbar" in str(error):
                self.skipTest(str(error))
            raise

    def test_transport_position_and_paused_track_change(self):
        s = self.session
        time.sleep(0.25)
        self.assertGreater(s.position(), 0)
        s.call("Pause")
        s.wait_status("Paused")
        time.sleep(0.2)
        paused = s.position()
        time.sleep(0.25)
        self.assertEqual(s.position(), paused)
        s.call("Pause")  # Idempotent
        s.call("Next")
        s.wait_status("Paused")
        self.assertIn("02.mod", s.get("Metadata"))
        self.assertEqual(s.position(), 0)
        s.call("PlayPause")
        s.wait_status("Playing")
        s.call("Stop")
        s.wait_status("Stopped")
        time.sleep(0.15)
        self.assertEqual(s.position(), 0)
        s.call("Stop")
        s.call("Play")
        s.wait_status("Playing")
        s.call("Previous")
        self.assertIn("01.mod", s.get("Metadata"))
        s.call("Quit", interface="org.mpris.MediaPlayer2")
        self.assertEqual(s.process.wait(timeout=5), 0)

    def test_properties_introspection_and_errors(self):
        s = self.session
        xml = subprocess.check_output(
            ["gdbus", "introspect", "--session", "--dest", s.name,
             "--object-path", PATH, "--xml"], text=True, timeout=3)
        node = ET.fromstring(xml)
        for interface in node.findall("interface"):
            if interface.attrib["name"] in [PLAYER, "org.mpris.MediaPlayer2"]:
                values = s.call("GetAll", interface.attrib["name"], interface=PROPS).stdout
                for property in interface.findall("property"):
                    self.assertIn(property.attrib["name"], values)
        self.assertIn("false", s.get("CanSeek"))
        self.assertIn("/org/savage_modplayer/track/1", s.get("Metadata"))
        s.call("Set", PLAYER, "Volume", "<0.25>", interface=PROPS)
        self.assertIn("0.25", s.get("Volume"))
        s.call("Set", PLAYER, "Volume", "<-1.0>", interface=PROPS)
        self.assertIn("0.0", s.get("Volume"))
        for method, args, expected in [
            ("Get", [PLAYER, "Missing"], "UnknownProperty"),
            ("GetAll", ["org.example.Missing"], "UnknownInterface"),
            ("Set", [PLAYER, "PlaybackStatus", "<'Playing'>"], "PropertyReadOnly"),
            ("Set", [PLAYER, "Volume", "<'bad'>"], "InvalidArgs")
        ]:
            result = s.call(method, *args, interface=PROPS, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(expected, result.stderr)
        s.call("Set", PLAYER, "Rate", "<0.0>", interface=PROPS)
        s.wait_status("Paused")
        self.assertIn("1.0", s.get("Rate"))
        s.call("Seek", "1000000")  # CanSeek=false: wirkungslos.
        result = s.call("Pause", "unexpected", check=False)
        self.assertIn("InvalidArgs", result.stderr)

    def test_unavailable_bus_preserves_playback(self):
        environment = os.environ.copy()
        environment["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/nonexistent/savage-test-bus"
        result = subprocess.run(
            [str(self.binary), str(Path(self.temp.name) / "01.mod"),
             "--play", "--seconds", "0.2", "--quiet"], env=environment,
            stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_signals_and_independent_instances(self):
        s = self.session
        other = Session(self.binary, Path(self.temp.name))
        self.addCleanup(other.close)
        other.wait_status("Playing")
        self.assertNotEqual(s.name, other.name)
        monitor = subprocess.Popen(
            ["gdbus", "monitor", "--session", "--dest", s.name, "--object-path", PATH],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            time.sleep(0.2)
            s.call("Pause")
            s.wait_status("Paused")
            other.wait_status("Playing")
            s.call("Stop")
            s.wait_status("Stopped")
            time.sleep(0.2)
        finally:
            monitor.terminate()
            output, errors = monitor.communicate(timeout=3)
        self.assertIn("PropertiesChanged", output)
        self.assertIn("PlaybackStatus", output)
        self.assertIn("Metadata", output)
        self.assertEqual(errors, "")


if __name__ == "__main__":
    unittest.main()

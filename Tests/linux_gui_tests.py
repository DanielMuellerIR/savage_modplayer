"""Linux-GUI: Installation, Dateistart und MPRIS ohne Desktop-Fokus."""
from pathlib import Path
import configparser
import json
import os
import re
import select
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

from mpris_contract_tests import silent_mod, PLAYER, PROPS, PATH

ROOT = Path(__file__).resolve().parents[1]
GUI = Path(os.environ.get("SAVAGE_GUI", ROOT / ".build/linux-gui/savage-mod-player"))
ENGINE = Path(os.environ.get("SAVAGE_DESKTOP_ENGINE", ROOT / ".build/linux-gui/savage-desktop-engine"))


@unittest.skipUnless(sys.platform.startswith("linux"), "Linux-Installation")
class InstallationTests(unittest.TestCase):
    def test_installed_desktop_passes_multiple_reserved_paths_and_restores_cli(self):
        with tempfile.TemporaryDirectory(prefix="savage-gui-install-") as directory:
            root = Path(directory)
            prefix = root / 'space="quote" $dollar `tick` \\slash 50%'
            build = root / "build"
            build.mkdir()
            output = root / "arguments"
            # Echter ELF-Stub: prüft Startargumente über die Desktopdatei,
            # während der Installer seine Linux-/Startgrenzen beibehält.
            stub = root / "stub.c"
            stub.write_text(r'''#include <stdio.h>
#include <string.h>
int main(int argc,char **argv) {
 if(argc==2 && !strcmp(argv[1],"--version")) { puts("Savage Mod Player VERSION"); return 0; }
 if(argc==1) { puts("{\"event\":\"ready\"}"); return 0; }
 for(int i=1;i+1<argc;i++) if(!strcmp(argv[i],"--screenshot")) { FILE *f=fopen(argv[i+1],"wb"); if(f)fclose(f); return 0; }
 FILE *f=fopen(OUTPUT,"w"); if(!f)return 2;
 for(int i=1;i<argc;i++)fprintf(f,"%s\n",argv[i]); fclose(f); return 0;
}
'''.replace('VERSION', (ROOT / 'VERSION').read_text().strip()).replace('OUTPUT', json.dumps(str(output))))
            for name in ("savage-mod-player", "savage-desktop-engine"):
                subprocess.run(["cc", str(stub), "-o", str(build / name)], check=True, capture_output=True)
            appdir = prefix / "share/applications"
            appdir.mkdir(parents=True)
            original = "[Desktop Entry]\nType=Application\nName=CLI\nExec=savage-desktop\nTerminal=true\n"
            (appdir / "savage-cli.desktop").write_text(original)
            subprocess.run(["bash", str(ROOT / "linux/install-gui.sh"), "--prefix", str(prefix),
                            "--build-dir", str(build)], check=True, capture_output=True, timeout=15)
            desktop = appdir / "savage-mod-player.desktop"
            if shutil.which("desktop-file-validate"):
                subprocess.run(["desktop-file-validate", str(desktop)], check=True, capture_output=True)
            config = configparser.ConfigParser(interpolation=None)
            config.read(desktop)
            self.assertEqual(config["Desktop Entry"]["Terminal"], "false")
            try:
                from gi.repository import Gio
            except ImportError:
                self.skipTest("GIO-Python-Anbindung fehlt für den echten Desktop-Start")
            files = [str(root / "first $file.mod"), str(root / "second file.xm")]
            app = Gio.DesktopAppInfo.new_from_filename(str(desktop))
            self.assertIsNotNone(app)
            app.launch([Gio.File.new_for_path(p) for p in files], None)
            deadline = time.monotonic()+5
            while not output.exists() and time.monotonic()<deadline:
                time.sleep(.05)
            self.assertEqual(output.read_text().splitlines(), files)
            self.assertIn("NoDisplay=true", (appdir / "savage-cli.desktop").read_text())
            subprocess.run(["bash", str(ROOT / "linux/install-gui.sh"), "--prefix", str(prefix), "--uninstall"],
                           check=True, capture_output=True, timeout=10)
            self.assertEqual((appdir / "savage-cli.desktop").read_text(), original)
            self.assertFalse((prefix / "bin/savage-mod-player").exists())


@unittest.skipUnless(sys.platform.startswith("linux") and GUI.is_file() and ENGINE.is_file()
                     and shutil.which("gdbus") and os.environ.get("DBUS_SESSION_BUS_ADDRESS"),
                     "Qt-App, Engine und isolierter Sitzungsbus erforderlich")
class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="savage-gui-desktop-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("01.mod", "02.mod"):
            (self.root / name).write_bytes(silent_mod())
        config = self.root / "alsa.conf"
        config.write_text("pcm.!default { type null }\n")
        self.env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                        SAVAGE_DESKTOP_DATA=str(self.root / "data"), ALSA_CONFIG_PATH=str(config))
        self.process = subprocess.Popen([str(GUI), "--engine", str(ENGINE), str(self.root)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=self.env)
        self.addCleanup(self.close)
        self.name = "org.mpris.MediaPlayer2.savage"
        self.wait_status("Playing")

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        self.process.stderr.close()

    def call(self, method, *args, interface=PLAYER, check=True):
        return subprocess.run(["gdbus", "call", "--session", "--dest", self.name,
                               "--object-path", PATH, "--method", interface+"."+method, *args],
                              check=check, capture_output=True, text=True, timeout=3)

    def get(self, prop):
        return self.call("Get", PLAYER, prop, interface=PROPS).stdout

    def wait_status(self, status):
        deadline = time.monotonic()+10
        while time.monotonic()<deadline:
            if self.process.poll() is not None:
                self.fail(self.process.stderr.read().decode())
            result = self.call("Get", PLAYER, "PlaybackStatus", interface=PROPS, check=False)
            if "'"+status+"'" in result.stdout:
                return
            time.sleep(.05)
        os.set_blocking(self.process.stderr.fileno(), False)
        diagnostic = (self.process.stderr.read() or b"").decode(errors="replace")
        self.fail(f"Desktop-Status fehlt: {status}: {result.stdout} {result.stderr} {diagnostic}")

    def test_mpris_transport_and_second_instance_file_delivery(self):
        self.call("Pause")
        self.wait_status("Paused")
        paused = self.get("Position")
        time.sleep(.15)
        self.assertEqual(self.get("Position"), paused)
        self.call("Seek", "1000000")
        self.wait_status("Paused")
        self.call("Stop")
        self.wait_status("Stopped")
        result = subprocess.run([str(GUI), "--engine", str(ENGINE), str(self.root / "02.mod")],
                                env=self.env, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        deadline = time.monotonic()+5
        while time.monotonic()<deadline and "02.mod" not in self.get("Metadata"):
            time.sleep(.05)
        self.assertIn("02.mod", self.get("Metadata"))
        self.wait_status("Playing")
        self.call("Set", PLAYER, "Volume", "<0.25>", interface=PROPS)
        # Der D-Bus-Aufruf bestätigt die Übergabe; die Engine meldet den Wert asynchron zurück.
        deadline = time.monotonic()+5
        volume = self.get("Volume")
        while "0.25" not in volume and time.monotonic()<deadline:
            time.sleep(.05)
            volume = self.get("Volume")
        self.assertIn("0.25", volume)
        self.call("Quit", interface="org.mpris.MediaPlayer2")
        self.assertEqual(self.process.wait(timeout=5), 0)

    def test_media_keys_pause_resume_stop_and_track_changes(self):
        for prop in ("CanPlay", "CanPause", "CanGoNext", "CanGoPrevious", "CanSeek"):
            self.assertIn("true", self.get(prop))
        time.sleep(.2)
        position = int(re.search(r"int64 (\d+)", self.get("Position"))[1])
        self.call("Play")
        self.call("Play")
        self.wait_status("Playing")
        self.assertGreaterEqual(int(re.search(r"int64 (\d+)", self.get("Position"))[1]), position)
        self.call("PlayPause")
        self.wait_status("Paused")
        self.call("Pause")
        self.call("Pause")
        time.sleep(.1)
        position = self.get("Position")
        time.sleep(.15)
        self.assertEqual(self.get("Position"), position)
        self.call("Next")
        self.wait_metadata("02.mod")
        self.wait_status("Paused")
        self.call("Previous")
        self.wait_metadata("01.mod")
        self.wait_status("Paused")
        self.call("PlayPause")
        self.wait_status("Playing")
        self.call("Stop")
        self.wait_status("Stopped")
        self.call("Stop")
        self.wait_status("Stopped")
        self.call("Next")
        self.wait_metadata("02.mod")
        self.wait_status("Stopped")
        self.call("PlayPause")
        self.wait_status("Playing")

    def wait_metadata(self, filename):
        deadline = time.monotonic()+5
        while time.monotonic()<deadline:
            metadata = self.get("Metadata")
            if filename in metadata:
                return
            time.sleep(.05)
        self.fail(f"Titel fehlt: {filename}: {metadata}")

    def test_initial_capabilities_and_notifications_on_first_track(self):
        self.close()
        self.env["SAVAGE_DESKTOP_DATA"] = str(self.root / "empty-data")
        self.process = subprocess.Popen([str(GUI), "--engine", str(ENGINE)], env=self.env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.wait_status("Stopped")
        properties = self.call("GetAll", PLAYER, interface=PROPS).stdout
        for prop in ("CanPlay", "CanPause", "CanGoNext", "CanGoPrevious", "CanSeek"):
            self.assertIn(f"'{prop}': <false>", properties)
        monitor = subprocess.Popen(
            ["gdbus", "monitor", "--session", "--dest", self.name, "--object-path", PATH],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            # Die erste Monitorzeile bestätigt das aktive Signal-Abonnement.
            self.assertTrue(select.select([monitor.stdout], [], [], 5)[0], "MPRIS-Monitor startet nicht")
            self.assertIn("Monitoring", monitor.stdout.readline())
            self.call("OpenUri", (self.root / "01.mod").as_uri())
            self.wait_status("Playing")
            self.call("PlayPause")
            self.wait_status("Paused")
        finally:
            monitor.terminate()
            output, errors = monitor.communicate(timeout=3)
        self.assertEqual(errors, "")
        for prop in ("CanPlay", "CanPause", "CanGoNext", "CanGoPrevious", "CanSeek"):
            self.assertIn(f"'{prop}': <true>", output)
        self.assertIn("PlaybackStatus", output)
        self.assertIn("Metadata", output)

    def test_independent_instance_registration(self):
        environment = dict(self.env, SAVAGE_DESKTOP_DATA=str(self.root / "other-data"))
        other = subprocess.Popen([str(GUI), "--engine", str(ENGINE), str(self.root / "02.mod")],
                                 env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            original_name = self.name
            self.name = f"org.mpris.MediaPlayer2.savage.desktop{other.pid}"
            self.wait_status("Playing")
            self.call("PlayPause")
            self.wait_status("Paused")
            self.name = original_name
            self.wait_status("Playing")
        finally:
            self.name = original_name
            other.terminate()
            other.communicate(timeout=5)

    def test_unavailable_bus_preserves_normal_start(self):
        screenshot = self.root / "without-bus.png"
        environment = dict(self.env, SAVAGE_DESKTOP_DATA=str(self.root / "no-bus-data"),
                           DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent/savage-test-bus")
        result = subprocess.run(
            [str(GUI), "--engine", str(ENGINE), "--screenshot", str(screenshot),
             "--capture-delay", "200", str(self.root / "01.mod")], env=environment,
            capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertTrue(screenshot.is_file())
        self.assertIn("MPRIS-Registrierung fehlgeschlagen", result.stderr.decode(errors="replace"))


if __name__ == "__main__":
    unittest.main()

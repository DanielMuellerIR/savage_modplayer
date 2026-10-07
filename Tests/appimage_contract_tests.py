"""Prüft das reale AppImage; SAVAGE_APPIMAGE benennt das gebaute Artefakt."""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

from mpris_contract_tests import silent_mod

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform.startswith("linux"), "AppImage benötigt Linux")
class AppImageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.environ.get("SAVAGE_APPIMAGE"):
            raise unittest.SkipTest("SAVAGE_APPIMAGE fehlt")
        cls.image = Path(os.environ["SAVAGE_APPIMAGE"]).resolve()
        cls.binary = ROOT / ".build/release/savage-cli"
        if not cls.image.is_file() or not cls.binary.is_file():
            raise unittest.SkipTest("AppImage oder Vergleichsbinary fehlt")

    def run_image(self, *args, cwd):
        return subprocess.run([str(self.image), *args], cwd=cwd,
                              capture_output=True, timeout=15, check=True)

    def test_native_start_relative_input_and_identical_render(self):
        with tempfile.TemporaryDirectory(prefix="appimage test ") as temp:
            directory = Path(temp)
            (directory / "probe space.mod").write_bytes(silent_mod())
            self.run_image("--help", cwd=temp)
            result = self.run_image("probe space.mod", "--info", cwd=temp)
            self.assertIn(b"MPRIS silent 01", result.stdout)
            args = ["probe space.mod", "--seconds", "0.1", "--out", "image.wav", "--quiet"]
            self.run_image(*args, cwd=temp)
            args[-2] = "direct.wav"
            subprocess.run([str(self.binary), *args], cwd=temp, check=True,
                           capture_output=True, timeout=15)
            self.assertEqual((directory / "image.wav").read_bytes(),
                             (directory / "direct.wav").read_bytes())

    def test_extraction_fallback_resources_and_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            self.run_image("--appimage-extract-and-run", "--help", cwd=temp)
            version = self.run_image("--appimage-version", cwd=temp)
            self.assertIn(b"caf24f9", version.stdout + version.stderr)
            self.run_image("--appimage-extract", cwd=temp)
            appdir = Path(temp) / "squashfs-root"
            doc = appdir / "usr/share/doc/savage-cli"
            self.assertEqual((doc / "VERSION").read_text(), (ROOT / "VERSION").read_text())
            self.assertIn("Terminal=true", (appdir / "savage-cli.desktop").read_text())
            self.assertIn("Icon=savage-cli", (appdir / "savage-cli.desktop").read_text())
            self.assertEqual((appdir / "savage-cli.png").read_bytes(),
                             (ROOT / "src/AppIcon.png").read_bytes())
            for name in ["LICENSE", "README.md", "README.de.md", "build-info.txt",
                         "licenses/AppImage-runtime-LICENSE.txt", "licenses/Swift-LICENSE.txt"]:
                self.assertTrue((doc / name).is_file(), name)
            self.assertIn("appimagetool: 1.9.1", (doc / "build-info.txt").read_text())

    def test_corrupt_cached_tool_is_not_executed(self):
        with tempfile.TemporaryDirectory() as temp:
            fixture = Path(temp)
            (fixture / "linux").mkdir()
            shutil.copy(ROOT / "linux/build-appimage.sh", fixture / "linux/build-appimage.sh")
            (fixture / "VERSION").write_text("0.0.0\n")
            tools = fixture / "build/tools"
            tools.mkdir(parents=True)
            tool = tools / "appimagetool-1.9.1-x86_64.AppImage"
            tool.write_text("#!/bin/sh\ntouch executable-was-run\n")
            tool.chmod(0o755)
            result = subprocess.run(
                ["bash", str(fixture / "linux/build-appimage.sh"), "--binary", str(self.binary)],
                capture_output=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((fixture / "executable-was-run").exists())
            self.assertFalse(list((fixture / "build").glob("appimage.*")))

    def test_output_cannot_replace_input_binary(self):
        before = hashlib.sha256(self.binary.read_bytes()).digest()
        result = subprocess.run(
            ["bash", str(ROOT / "linux/build-appimage.sh"), "--binary", str(self.binary),
             "--output", str(self.binary)], capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(hashlib.sha256(self.binary.read_bytes()).digest(), before)


if __name__ == "__main__":
    unittest.main()

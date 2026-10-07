"""Fehlerpfade des Start-Smokes ohne Appstart oder GUI prüfen."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Tests/launch_argument_smoke.sh"


class LaunchSmokeContractTests(unittest.TestCase):
    def run_failure(self, export_fails):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "Fixture.app/Contents/MacOS/SavageModPlayerApp"
            app.parent.mkdir(parents=True)
            app.write_text("#!/bin/sh\nexit 0\n")
            app.chmod(0o755)
            binary = root / "bin"
            binary.mkdir()
            defaults = binary / "defaults"
            defaults.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$DEFAULTS_LOG"
case "$1" in
 domains) echo com.viben.SavageModPlayer ;;
 export) printf backup > "$3"; exit "$EXPORT_FAIL" ;;
 import) exit 9 ;;
esac
''')
            defaults.chmod(0o755)
            for name, content in {"swiftc": "exit 7", "uuidgen": "echo unique-test-run"}.items():
                tool = binary / name
                tool.write_text("#!/bin/sh\n" + content + "\n")
                tool.chmod(0o755)
            env = os.environ.copy()
            env.update(PATH=str(binary) + os.pathsep + env["PATH"], TMPDIR=str(root),
                       DEFAULTS_LOG=str(root / "defaults.log"), EXPORT_FAIL=str(int(export_fails)))
            result = subprocess.run(["bash", str(SCRIPT), str(root / "Fixture.app")],
                                    env=env, capture_output=True, text=True, timeout=10)
            calls = (root / "defaults.log").read_text()
            if export_fails:
                self.assertNotIn("write ", calls)
                self.assertNotIn("delete ", calls)
                self.assertNotIn("import ", calls)
            else:
                match = re.search(r"Sicherung bleibt unter (.+)", result.stderr)
                self.assertIsNotNone(match, result.stderr)
                self.assertEqual(Path(match.group(1)).read_text(), "backup")
            self.assertNotEqual(result.returncode, 0)

    def test_failed_export_leaves_existing_defaults_untouched(self):
        self.run_failure(True)

    def test_failed_restore_preserves_backup(self):
        self.run_failure(False)

    def test_cleanup_does_not_kill_unrelated_process(self):
        source = SCRIPT.read_text()
        function = source[source.index("stop_test_processes() {"):source.index("cleanup() {")]
        child = subprocess.Popen(["sleep", "30"])
        try:
            script = function + '\nTEST_PIDS=("$1"); RUN_ID=unrelated-smoke-marker; stop_test_processes\n'
            result = subprocess.run(["bash", "-c", script, "test", str(child.pid)],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIsNone(child.poll())
        finally:
            child.terminate()
            child.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()

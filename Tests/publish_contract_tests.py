"""Prüft Veröffentlichungsziele ohne Netzwerk, Push oder Accountzugriff."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "1" * 40


class PublishContractTests(unittest.TestCase):
    def run_publish(self, appimage=False, checksum=True, **variables):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "build").mkdir()
            (root / "build/Savage Mod Player.dmg").touch()
            if appimage:
                asset = root / "build/Savage-Mod-Player-1.2.3-x86_64.AppImage"
                asset.write_bytes(b"synthetic AppImage")
                if checksum:
                    asset.with_suffix(asset.suffix + ".sha256").write_text(
                        hashlib.sha256(asset.read_bytes()).hexdigest() + "  " + asset.name + "\n")
            (root / "VERSION").write_text("1.2.3\n")
            (root / "build.py").write_text("")
            (root / "RELEASE_NOTES.md").write_text("Test release")
            (root / "savage-mod-player.html").touch()
            script = root / "publish.sh"
            script.write_text((ROOT / "publish_github.sh").read_text())
            binary = root / "bin"
            binary.mkdir()
            tool = "#!" + sys.executable + "\n" + '''
import json, os, pathlib, sys
args=sys.argv[1:]
root=pathlib.Path(os.environ['FIXTURE'])
with (root/'calls.jsonl').open('a') as log:
 log.write(json.dumps([pathlib.Path(sys.argv[0]).name,*args])+'\\n')
if pathlib.Path(sys.argv[0]).name=='gh':
 sys.exit(1 if args[:2]==['release','view'] else 0)
if args[0]=='remote': print(os.environ.get('EFFECTIVE_URL','https://github.com/DanielMuellerIR/savage_modplayer.git'))
elif args[0]=='rev-parse': print(os.environ.get('LOCAL_TAG', '1'*40) if 'tags/' in args[1] else '1'*40)
elif args[0]=='symbolic-ref': print('refs/heads/main')
elif args[0]=='show-ref': sys.exit(0)
elif args[0]=='ls-remote': print(os.environ.get('REMOTE_TAG','1'*40)+'\\trefs/tags/v1.2.3^{}')
'''
            for name in ["git", "gh"]:
                file = binary / name
                file.write_text(tool)
                file.chmod(0o755)
            environment = os.environ.copy()
            environment.update(PATH=str(binary) + os.pathsep + environment["PATH"],
                               FIXTURE=str(root), GH_REPO="unrelated/project")
            environment.update(variables)
            result = subprocess.run(["bash", str(script), "--release"], cwd=root,
                                    env=environment, capture_output=True, text=True, timeout=10)
            calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
            return result, calls

    def test_real_git_resolves_configured_destination_and_rejects_rewrite(self):
        git = shutil.which("git")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run([git, "init", "-q", str(root)], check=True)
            for key, value in [("user.name", "Test"), ("user.email", "test@example.com"),
                               ("remote.github.url", "https://github.com/DanielMuellerIR/savage_modplayer.git")]:
                subprocess.run([git, "-C", str(root), "config", key, value], check=True)
            for name, content in {"VERSION": "1.2.3\n", "build.py": "", "savage-mod-player.html": ""}.items():
                (root / name).write_text(content)
            subprocess.run([git, "-C", str(root), "add", "VERSION", "build.py", "savage-mod-player.html"], check=True)
            subprocess.run([git, "-C", str(root), "commit", "-qm", "Fixture"], check=True)
            command = ["bash", str(ROOT / "publish_github.sh"), "--dry-run"]
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("DRY-RUN: git push --no-follow-tags", result.stdout)
            subprocess.run([git, "-C", str(root), "config", "url.ssh://example.invalid/.pushInsteadOf",
                            "https://github.com/"], check=True)
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("DRY-RUN: git push", result.stdout)

    def test_push_and_release_use_explicit_destination_and_refs(self):
        result, calls = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        pushes = [call for call in calls if call[:2] == ["git", "push"]]
        self.assertEqual(len(pushes), 2)
        for push in pushes:
            self.assertIn("--no-follow-tags", push)
            self.assertIn("https://github.com/DanielMuellerIR/savage_modplayer.git", push)
            self.assertNotIn("origin", push)
        self.assertIn("refs/heads/main:refs/heads/main", pushes[0])
        self.assertIn("refs/tags/v1.2.3:refs/tags/v1.2.3", pushes[1])
        gh = [call for call in calls if call[0] == "gh"]
        for call in gh:
            self.assertEqual(call[call.index("-R") + 1], "DanielMuellerIR/savage_modplayer")
        self.assertIn("--verify-tag", next(call for call in gh if call[1:3] == ["release", "create"]))

    def test_appimage_at_builder_default_is_uploaded_with_checksum(self):
        result, calls = self.run_publish(appimage=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        release = next(call for call in calls if call[:3] == ["gh", "release", "create"])
        asset = "build/Savage-Mod-Player-1.2.3-x86_64.AppImage"
        self.assertIn(asset, release)
        self.assertIn(asset + ".sha256", release)

    def test_appimage_without_checksum_aborts_before_push(self):
        result, calls = self.run_publish(appimage=True, checksum=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[:2] == ["git", "push"] for call in calls))

    def test_mismatched_local_or_remote_tag_aborts_before_push(self):
        for key in ["LOCAL_TAG", "REMOTE_TAG"]:
            with self.subTest(key=key):
                result, calls = self.run_publish(**{key: "2" * 40})
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(call[:2] == ["git", "push"] for call in calls))
                self.assertFalse(any(call[0] == "gh" for call in calls))

    def test_git_url_rewrite_cannot_redirect_push(self):
        result, calls = self.run_publish(EFFECTIVE_URL="ssh://other.invalid/project")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[:2] == ["git", "push"] for call in calls))


if __name__ == "__main__":
    unittest.main()

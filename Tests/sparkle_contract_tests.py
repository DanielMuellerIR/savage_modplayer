"""Update-Signaturen und Release-Auswahl ohne Netzwerk oder Schlüsselbund prüfen."""
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FeedSignatureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix="savage-sparkle-")
        cls.folder = Path(cls.work.name)
        cls.verifier = cls.folder / "verify-feed"
        subprocess.run(["swiftc", str(ROOT / "scripts/verify-sparkle-feed.swift"),
                        "-o", str(cls.verifier)], check=True, capture_output=True)
        # Schlüssel bleiben im Speicher; nur öffentlicher Teil und Signaturen
        # werden als Testdaten geschrieben. Kein Zugriff auf Produktionskeys.
        fixture = cls.folder / "fixture.swift"
        fixture.write_text(r'''
import CryptoKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
let archive = Data("Synthetic update archive".utf8)
let archiveSignature = try key.signature(for: archive).base64EncodedString()
let xml = Data("""
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><title>Version 1.6.32</title><enclosure length="\(archive.count)" sparkle:edSignature="\(archiveSignature)" /></item></channel></rss>
""".utf8)
let block = "<!-- sparkle-signatures:\nedSignature: \(try key.signature(for: xml).base64EncodedString())\nlength: \(xml.count)\n-->\n"
try (xml + Data(block.utf8)).write(to: root.appendingPathComponent("appcast.xml"))
try archive.write(to: root.appendingPathComponent("update.dmg"))
let plist = ["SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString()]
try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    .write(to: root.appendingPathComponent("Info.plist"))
''')
        subprocess.run(["swift", str(fixture), str(cls.folder)], check=True,
                       capture_output=True)
        cls.feed = (cls.folder / "appcast.xml").read_bytes()
        cls.archive = (cls.folder / "update.dmg").read_bytes()
        cls.plist = (cls.folder / "Info.plist").read_bytes()

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def check(self, feed=None, archive=None, plist=None):
        (self.folder / "appcast.xml").write_bytes(self.feed if feed is None else feed)
        (self.folder / "update.dmg").write_bytes(self.archive if archive is None else archive)
        (self.folder / "Info.plist").write_bytes(self.plist if plist is None else plist)
        return subprocess.run([str(self.verifier), str(self.folder / "appcast.xml"),
                               str(self.folder / "Info.plist"), str(self.folder / "update.dmg")],
                              capture_output=True, timeout=10)

    def test_signed_feed_and_archive(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_changed_release_notes_are_rejected(self):
        self.assertNotEqual(self.check(feed=self.feed.replace(b"Version", b"Changed")).returncode, 0)

    def test_archive_with_same_length_but_different_content_is_rejected(self):
        self.assertNotEqual(self.check(archive=b"X" + self.archive[1:]).returncode, 0)

    def test_truncated_archive_is_rejected(self):
        self.assertNotEqual(self.check(archive=self.archive[:-1]).returncode, 0)

    def test_wrong_bundle_key_is_rejected(self):
        wrong = plistlib.dumps({"SUPublicEDKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="})
        self.assertNotEqual(self.check(plist=wrong).returncode, 0)

    def test_unsigned_feed_is_rejected(self):
        self.assertNotEqual(self.check(feed=self.feed.split(b"<!-- sparkle-signatures:")[0]).returncode, 0)

    def test_wrong_signed_length_is_rejected(self):
        changed = re.sub(rb"length: [0-9]+", b"length: 1", self.feed)
        self.assertNotEqual(self.check(feed=changed).returncode, 0)

    def test_trailing_unsigned_content_is_rejected(self):
        self.assertNotEqual(self.check(feed=self.feed + b"<item>unsigned</item>").returncode, 0)


class ReleaseSelectionTests(unittest.TestCase):
    def run_selection(self, *, draft=False, prerelease=False, latest="v1.6.32", tag="v1.6.32"):
        workflow = (ROOT / ".github/workflows/publish-appcast.yml").read_text()
        step = workflow.split("- name: Verify latest stable release\n", 1)[1].split("\n      - name:", 1)[0]
        body = step.split("        run: |\n", 1)[1]
        script = "\n".join(line[10:] for line in body.splitlines())
        with tempfile.TemporaryDirectory(prefix="savage-release-selection-") as temporary:
            folder = Path(temporary)
            gh = folder / "gh"
            gh.write_text("#!/bin/bash\nif [[ $1 == release ]]; then printf '%s\\n' \"$STATE\"; "
                          "else printf '%s\\n' \"$LATEST\"; fi\n")
            git = folder / "git"
            git.write_text("#!/bin/bash\nprintf '%s\\n' same-commit\n")
            gh.chmod(0o755)
            git.chmod(0o755)
            env = os.environ.copy()
            env.update(PATH=str(folder) + os.pathsep + env["PATH"], RELEASE_TAG=tag,
                       GITHUB_REPOSITORY="example/savage", LATEST=latest,
                       STATE=f"{str(draft).lower()}\t{str(prerelease).lower()}")
            return subprocess.run(["bash", "-c", script], env=env, capture_output=True, timeout=10)

    def test_latest_stable_is_accepted(self):
        self.assertEqual(self.run_selection().returncode, 0)

    def test_draft_is_rejected(self):
        self.assertNotEqual(self.run_selection(draft=True).returncode, 0)

    def test_prerelease_is_rejected(self):
        self.assertNotEqual(self.run_selection(prerelease=True).returncode, 0)

    def test_older_release_is_rejected(self):
        self.assertNotEqual(self.run_selection(latest="v1.6.33").returncode, 0)

    def test_invalid_tag_is_rejected(self):
        self.assertNotEqual(self.run_selection(tag="main").returncode, 0)


if __name__ == "__main__":
    unittest.main()

"""Prüft die beiden JavaScript-Programme im gebauten Single-File-Player."""
from html.parser import HTMLParser
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InlineScripts(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.scripts = []
        self.active = False
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        if tag == "script":
            self.active = True
            self.scripts.append("")

    def handle_data(self, data):
        if self.active:
            self.scripts[-1] += data

    def handle_endtag(self, tag):
        if tag == "script":
            self.active = False


class WebBundleTests(unittest.TestCase):
    def test_shipped_inline_program_and_worklet_parse(self):
        html = (ROOT / "savage-mod-player.html").read_text(encoding="utf-8")
        script, = InlineScripts(html).scripts
        self.assertNotIn("__savageDebug", script)
        self.assertNotIn("testDropAutoplay", script)

        prefix = "const WORKLET_SOURCE="
        self.assertTrue(script.startswith(prefix))
        worklet, _ = json.JSONDecoder().raw_decode(script[len(prefix):])
        self.assertIn("registerProcessor(", worklet)
        subprocess.run(["node", "--check"], input=script, text=True, check=True)
        subprocess.run(["node", "--input-type=module", "--check"], input=worklet, text=True, check=True)
        with tempfile.TemporaryDirectory(prefix="savage-bundle-") as directory:
            bundled_worklet = Path(directory) / "worklet.js"
            bundled_worklet.write_text(worklet, encoding="utf-8")
            subprocess.run(
                ["node", str(ROOT / "Tests/js/worklet-timing.mjs"), str(bundled_worklet)],
                stdout=subprocess.DEVNULL, check=True,
            )


if __name__ == "__main__":
    unittest.main()

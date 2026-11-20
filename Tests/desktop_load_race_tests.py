"""Befehlsreihenfolge und Scan-Ablösung am echten Desktop-Engineprozess."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from mpris_contract_tests import silent_mod


class DesktopLoadRaceTests(unittest.TestCase):
    def test_preference_burst_is_ordered_and_persisted_at_eof(self):
        from desktop_engine_tests import BINARY
        self.assertTrue(BINARY.is_file(), str(BINARY))
        with tempfile.TemporaryDirectory(prefix="savage-command-order-") as temp:
            root = Path(temp)
            widths = list(range(300, 420))
            commands = "".join(
                json.dumps({"command": "option", "text": "sidebarWidth", "setting": width}) + "\n"
                for width in widths
            )
            result = subprocess.run(
                [str(BINARY)], input=commands, capture_output=True, text=True,
                env=dict(os.environ, SAVAGE_DESKTOP_DATA=str(root)), timeout=15, check=True,
            )
            events = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual([event["sidebarWidth"] for event in events if event["event"] == "preferences"], widths)
            self.assertEqual(json.loads((root / "preferences.json").read_text())["sidebarWidth"], widths[-1])
            restarted = subprocess.run(
                [str(BINARY)], input="", capture_output=True, text=True,
                env=dict(os.environ, SAVAGE_DESKTOP_DATA=str(root)), timeout=15, check=True,
            )
            ready = next(event for event in map(json.loads, restarted.stdout.splitlines()) if event["event"] == "ready")
            self.assertEqual(ready["preferences"]["sidebarWidth"], widths[-1])

    def test_eof_cancels_a_blocked_scan(self):
        from desktop_engine_tests import Engine
        with tempfile.TemporaryDirectory(prefix="savage-scan-eof-") as temp:
            root = Path(temp)
            source = root / "source.mod"
            source.write_bytes(silent_mod())
            engine = Engine(root, environment={"SAVAGE_DESKTOP_TEST_SCAN_GATE": str(root)})
            try:
                self.assertTrue(engine.ready.get("testScanGate"), "Debug-Build mit Scanbarriere erforderlich")
                engine.send("open", paths=[str(source)])
                engine.wait("testScanWaiting")
                engine.send("option", text="sidebarWidth", setting=480)
                stdout, stderr = engine.process.communicate(timeout=5)
                self.assertEqual(engine.process.returncode, 0, stderr.decode(errors="replace"))
                events = [json.loads(line) for line in (engine.buffer + stdout).splitlines()]
                self.assertNotIn("module", [event["event"] for event in events])
                self.assertEqual(json.loads((engine.data / "preferences.json").read_text())["sidebarWidth"], 480)
            finally:
                engine.close()

    def test_result_selection_supersedes_delayed_open(self):
        from desktop_engine_tests import BINARY, Engine
        if not BINARY.is_file():
            self.skipTest("savage-desktop-engine fehlt")
        with tempfile.TemporaryDirectory(prefix="savage-load-race-") as temp:
            root = Path(temp)
            gate = root / "gate"
            gate.mkdir()
            delayed = gate / "source.mod"
            delayed.write_bytes(silent_mod())
            tracks = [root / f"track-{i}.mod" for i in range(3)]
            for track in tracks:
                track.write_bytes(silent_mod())
            engine = Engine(root, environment={"SAVAGE_DESKTOP_TEST_SCAN_GATE": str(gate)})
            try:
                self.assertTrue(engine.ready.get("testScanGate"), "Debug-Build mit Scanbarriere erforderlich")
                engine.send("option", text="loop", setting="track")
                engine.wait("preferences", lambda v: v.get("loop") == "track")
                engine.send("open", paths=[str(t) for t in tracks], autoPlay=False)
                engine.wait("module")
                library = engine.wait("library", lambda v: len(v["tracks"]) == 3 and bool(v["currentID"]))
                original_ids = [t["id"] for t in library["tracks"]]
                selected = original_ids[1:]
                engine.send("open", paths=[str(delayed)])
                engine.wait("testScanWaiting")
                engine.send("selection", ids=selected)
                engine.wait("module", lambda v: v["sourceID"] == selected[0])
                engine.wait("state", lambda v: v["playing"] and not v["paused"])
                (gate / "release").touch()
                engine.wait("testScanReturned")
                # Die gespeicherte Liste quittiert einen Auftrag nach Rückkehr des alten open.
                engine.send("playlistSave", text="after-scan")
                library = engine.wait("library", lambda v: any(p["name"] == "after-scan" for p in v["playlists"]))
                self.assertEqual([t["id"] for t in library["tracks"]], original_ids)
                self.assertEqual(library["selection"], selected)
                self.assertEqual(library["currentID"], selected[0])
                engine.send("next")
                engine.wait("module", lambda v: v["sourceID"] == selected[1])
                engine.send("previous")
                engine.wait("module", lambda v: v["sourceID"] == selected[0])
            finally:
                (gate / "release").touch()
                engine.close()


if __name__ == "__main__":
    unittest.main()

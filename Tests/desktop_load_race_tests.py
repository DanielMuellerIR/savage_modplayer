"""Deterministische Ladeauftragsregression am Debug-Engineprozess, nur Nullsamples."""
from pathlib import Path
import tempfile
import unittest

from mpris_contract_tests import silent_mod


class DesktopLoadRaceTests(unittest.TestCase):
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
                if not engine.ready.get("testScanGate"):
                    self.skipTest("Scanbarriere benötigt einen Debug-Build")
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

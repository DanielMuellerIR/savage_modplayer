"""Prüft Linux-GUI-Abläufe am echten Swift-Prozess, ohne Desktop-Fokus."""
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import time
import unittest

from mpris_contract_tests import silent_mod

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("SAVAGE_DESKTOP_ENGINE", ROOT / ".build/debug/savage-desktop-engine"))


class Engine:
    def __init__(self, root, data=None, environment=None):
        self.root = Path(root)
        self.data = data or self.root / "data"
        config = self.root / "alsa-null.conf"
        config.write_text("pcm.!default { type null }\n")
        env = dict(os.environ, SAVAGE_DESKTOP_DATA=str(self.data), ALSA_CONFIG_PATH=str(config))
        env.update(environment or {})
        self.process = subprocess.Popen([str(BINARY)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, env=env)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = b""
        self.events = []
        self.visualizer_count = 0
        self.library = {}
        self.ready = self.wait("ready")

    def send(self, command, **values):
        self.process.stdin.write((json.dumps(dict(command=command, **values)) + "\n").encode())
        self.process.stdin.flush()

    def wait(self, event, predicate=lambda value: True, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for i, message in enumerate(self.events):
                if message.get("event") == event and predicate(message):
                    return self.events.pop(i)
            if not self.selector.select(min(0.2, max(0, deadline - time.monotonic()))):
                continue
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise AssertionError("Desktop engine exited: " + self.process.stderr.read().decode(errors="replace"))
            self.buffer += chunk
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                try:
                    message = json.loads(line)
                except ValueError as error:
                    raise AssertionError("Nicht-JSON auf dem Desktop-Protokoll: "+repr(line[:200])) from error
                if message.get("event") == "visualizer":
                    self.visualizer_count += 1
                if message.get("event") == "libraryBegin":
                    self.library = dict(message, tracks=[], visible=[])
                elif message.get("event") == "libraryTracks":
                    self.library["tracks"].extend(message["tracks"])
                elif message.get("event") == "libraryVisible":
                    self.library["visible"].extend(message["ids"])
                elif message.get("event") == "libraryEnd":
                    message = dict(self.library, event="library")
                if message.get("event", "").startswith("library") and message.get("event") != "library":
                    continue
                if message.get("event") == event and predicate(message):
                    return message
                if message.get("event") not in ("state", "visualizer"):
                    self.events.append(message)
            assert len(self.buffer) < 32 * 1024 * 1024
        summary = [(v.get("event"), v.get("message", "")) for v in self.events if v.get("event") != "pattern"]
        raise AssertionError(f"Missing {event}: {summary[-12:]}")

    def close(self):
        if self.process.poll() is None:
            try:
                self.send("quit")
                self.process.communicate(timeout=5)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                self.process.kill()
                self.process.communicate(timeout=3)
        self.selector.close()
        for pipe in (self.process.stdin, self.process.stdout, self.process.stderr):
            pipe.close()


@unittest.skipUnless(BINARY.is_file(), "savage-desktop-engine fehlt")
class DesktopEngineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="savage-desktop-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.track = self.root / "fixture space.mod"
        self.track.write_bytes(silent_mod())
        self.engine = Engine(self.root)
        self.addCleanup(self.engine.close)

    def open(self):
        self.engine.send("open", paths=[str(self.track)])
        module = self.engine.wait("module")
        self.assertEqual(module["title"], "MPRIS silent 01")
        library = self.engine.wait("library", lambda v: bool(v.get("currentID")))
        return library["currentID"]

    def test_visualizer_rate_live_changes_hidden_pause_and_restart(self):
        self.engine.send("option", text="loop", setting="track")
        self.open()
        self.engine.wait("state", lambda v: v["playing"])

        def rate():
            self.engine.wait("visualizer", lambda v: bool(v["waves"]))
            start = time.monotonic()
            for _ in range(12):
                frame = self.engine.wait("visualizer", lambda v: bool(v["waves"]))
                self.assertEqual(len(frame["waves"]), 4)
                self.assertNotIn("elapsed", frame)
            return 12 / (time.monotonic() - start)

        self.assertGreater(rate(), 40, "Vorgabe muss 60 statt 30 FPS sein")
        self.engine.send("option", text="visualizerHz", setting=15)
        self.engine.wait("preferences", lambda v: v.get("visualizerHz") == 15)
        self.assertTrue(10 < rate() < 22, "Sparmodus muss während der Wiedergabe wirken")
        self.engine.send("compact", enabled=True)
        self.engine.wait("visualizer", lambda v: v.get("waves") == [])
        # Die Bestätigung liegt nach allen vorherigen Bilddaten im selben Kanal.
        count = self.engine.visualizer_count
        for _ in range(3):
            self.engine.wait("state", lambda v: v["playing"])
        self.assertEqual(self.engine.visualizer_count, count)
        self.engine.send("compact", enabled=False)
        self.engine.wait("visualizer", lambda v: bool(v["waves"]))
        self.engine.send("pause")
        self.engine.wait("state", lambda v: v["paused"])
        self.engine.wait("state", lambda v: v["paused"])
        count = self.engine.visualizer_count
        for _ in range(3):
            self.engine.wait("state", lambda v: v["paused"])
        self.assertEqual(self.engine.visualizer_count, count)
        self.engine.close()
        other = Engine(self.root, self.engine.data)
        self.addCleanup(other.close)
        other.send("open", paths=[str(self.track)])
        other.wait("module")
        other.wait("state", lambda v: v["playing"])
        self.assertEqual(json.loads(other.data.joinpath("preferences.json").read_text())["visualizerHz"], 15)

    def test_selection_starts_first_result_and_playlist_reindexes_after_restart(self):
        source = self.open()
        self.engine.send("pause")
        self.engine.wait("state", lambda v: v["paused"])
        self.engine.send("selection", ids=[source])
        self.engine.wait("state", lambda v: v["playing"] and not v["paused"])
        self.engine.send("playlistSave", text="Reindex fixture")
        library = self.engine.wait("library", lambda v: bool(v["playlists"]))
        playlist = library["playlists"][0]["id"]
        self.engine.close()
        other = Engine(self.root, self.engine.data)
        self.addCleanup(other.close)
        other.send("playlistOpen", text=playlist)
        library = other.wait("library", lambda v: bool(v["tracks"]) and bool(v["tracks"][0].get("metadata")))
        self.assertTrue(library["tracks"][0]["metadata"])

    def test_real_transport_and_read_only_inspection(self):
        self.assertIsNone(self.engine.process.poll())
        self.open()
        self.engine.wait("state", lambda v: v["playing"])
        self.engine.send("play")
        self.engine.wait("state", lambda v: v["paused"])
        self.engine.send("seek", index=0, row=12)
        self.engine.wait("state", lambda v: v["row"] == 12 and v["paused"])
        self.engine.send("mute", index=0)
        self.engine.wait("state", lambda v: v["muted"][0])
        self.engine.send("timer", index=1)
        self.engine.wait("state", lambda v: v["timerActive"] and v["timerSeconds"] <= 60)
        self.engine.send("timer", index=0)
        self.engine.send("inspect")
        inspection = self.engine.wait("inspection")
        self.assertEqual(inspection["orders"][0]["rows"], 64)
        self.engine.send("sample", text=inspection["samples"][0]["id"], index=1)
        sample = self.engine.wait("sample")
        self.assertTrue(sample["left"])
        self.engine.send("stop")
        self.engine.wait("state", lambda v: not v["playing"])

    def test_playlist_markers_track_settings_and_restart(self):
        source = self.open()
        self.engine.send("favorite", text=source)
        self.engine.wait("library", lambda v: bool(v["tracks"]) and v["tracks"][0]["favorite"])
        self.engine.send("playlistSave", text="Saved fixture")
        self.engine.wait("library", lambda v: len(v["playlists"]) == 1)
        self.engine.send("markerAdd", text="Introduction")
        module = self.engine.wait("module", lambda v: len(v["markers"]) == 1)
        self.engine.send("markerRename", id=module["markers"][0]["id"], text="Renamed")
        self.engine.wait("module", lambda v: bool(v["markers"]) and v["markers"][0]["name"] == "Renamed")
        self.engine.send("trackSettings", settings={"useInterpolation": False})
        self.engine.wait("module", lambda v: v["trackSettings"].get("useInterpolation") is False)
        self.engine.close()
        other = Engine(self.root)
        self.addCleanup(other.close)
        library = other.wait("library", lambda v: len(v["playlists"]) == 1)
        self.assertEqual(library["playlists"][0]["name"], "Saved fixture")
        other.send("open", paths=[str(self.track)])
        module = other.wait("module")
        self.assertEqual(module["markers"][0]["name"], "Renamed")
        self.assertFalse(module["trackSettings"]["useInterpolation"])

    def test_exports_and_collection_round_trip(self):
        source = self.open()
        self.engine.send("prepareExport")
        self.engine.wait("exportPrepared")
        output = self.root / "mix.wav"
        self.engine.send("export", path=str(output), seconds=0.05)
        self.engine.wait("complete")
        self.assertTrue(output.is_file())
        self.engine.send("export", path=str(output), seconds=0.05)
        self.engine.wait("error")
        output.write_bytes(b"existing WAV stays safe")
        self.engine.send("export", path=str(output), seconds=601, overwrite=True)
        self.engine.wait("error")
        self.assertEqual(output.read_bytes(), b"existing WAV stays safe")
        self.engine.send("export", path=str(output), seconds=0.05, overwrite=True)
        self.engine.wait("complete")
        self.assertEqual(output.read_bytes()[:4], b"RIFF")
        self.engine.send("favorite", text=source)
        self.engine.wait("library", lambda v: bool(v["tracks"]) and v["tracks"][0]["favorite"])
        self.engine.send("playlistSave", text="Transfer")
        self.engine.wait("library", lambda v: len(v["playlists"]) == 1)
        collection = self.root / "test.savagecollection"
        self.engine.send("collectionExport", path=str(collection))
        self.engine.wait("complete")
        document = json.loads(collection.read_text())
        self.assertEqual(len(document["playlists"]), 1)
        self.assertNotIn(str(self.root), collection.read_text())
        self.engine.send("collectionImport", path=str(collection))
        preview = self.engine.wait("collectionPreview")
        self.assertTrue(preview["ready"], preview)
        self.engine.send("collectionApply")
        self.engine.wait("collectionApplied")

    def test_queue_survives_library_change_and_preserves_pause(self):
        self.open()
        second = self.root / "second.mod"
        second.write_bytes(silent_mod())
        self.engine.send("open", paths=[str(self.track), str(second)])
        self.engine.wait("module")
        library = self.engine.wait("library", lambda v: len(v["tracks"]) == 2)
        first_id = library["tracks"][0]["id"]
        second_id = library["tracks"][1]["id"]
        self.engine.send("enqueue", text=second_id)
        self.engine.wait("library", lambda v: len(v["queue"]) == 1)
        self.engine.send("open", paths=[str(self.track)])
        self.engine.wait("module")
        self.engine.send("pause")
        self.engine.wait("state", lambda v: v["paused"])
        self.engine.send("next")
        self.engine.wait("module", lambda v: v["sourceID"] == second_id)
        self.engine.wait("state", lambda v: v["playing"] and v["paused"])
        self.engine.send("previous")
        self.engine.wait("module", lambda v: v["sourceID"] == first_id)
        self.engine.wait("state", lambda v: v["paused"])

    def test_history_load_does_not_change_the_current_playlist(self):
        first = self.open()
        second = self.root / "current.mod"
        second.write_bytes(silent_mod())
        self.engine.send("open", paths=[str(second)])
        self.engine.wait("module", lambda v: v["sourceID"] != first)
        self.engine.wait("library", lambda v: v["tracks"] and v["tracks"][0]["name"] == "current.mod")
        self.engine.send("recentLoad", text=first)
        self.engine.wait("module", lambda v: v["sourceID"] == first)
        library = self.engine.wait("library", lambda v: v["currentID"] == first and v["tracks"])
        self.assertEqual([t["name"] for t in library["tracks"]], ["current.mod"])
        self.assertEqual(library["recent"][0]["id"], first)

    def test_dialog_load_is_stopped_and_heard_status_can_be_reset(self):
        self.engine.send("open", paths=[str(self.track)], autoPlay=False)
        self.engine.wait("module")
        library = self.engine.wait("library", lambda v: bool(v.get("currentID")))
        source = library["currentID"]
        self.assertFalse(library["tracks"][0]["heard"])
        self.engine.wait("state", lambda v: not v["playing"])
        self.engine.send("resume")
        self.engine.wait("library", lambda v: bool(v["tracks"]) and v["tracks"][0]["heard"])
        self.engine.send("markUnheard", text=source)
        self.engine.wait("library", lambda v: bool(v["tracks"]) and not v["tracks"][0]["heard"])

    def test_archive_diagnostics_do_not_corrupt_the_protocol(self):
        archive = self.root / "invalid.zip"
        archive.write_bytes(b"not a zip archive")
        self.engine.send("open", paths=[str(archive), str(self.track)])
        self.engine.wait("module")
        self.engine.wait("state", lambda v: v["playing"])

    def test_sample_export_keeps_the_module_captured_before_the_dialog(self):
        from gui_fixture import module
        self.open()
        self.engine.send("inspect")
        self.engine.wait("inspection")
        self.engine.send("pause")
        self.engine.wait("state", lambda v: v["paused"])
        self.engine.send("trackSettings", settings={})
        current = self.engine.wait("module")
        self.engine.send("prepareSampleExport", index=1, revision=current["revision"])
        captured = self.engine.wait("sampleExportPrepared")
        second = self.root / "different.mod"
        second.write_bytes(module())
        self.engine.send("open", paths=[str(second)])
        self.engine.wait("module", lambda v: v["title"].startswith("GUI signal"))
        output = self.root / "captured.wav"
        self.engine.send("sampleExport", token=captured["token"], path=str(output))
        self.engine.wait("complete")
        data = output.read_bytes()
        self.assertEqual(data[:4], b"RIFF")
        self.assertEqual(int.from_bytes(data[40:44], "little"), 4*4)

    def test_explicit_marker_address_and_section_loop(self):
        self.open()
        self.engine.send("pause")
        self.engine.wait("state", lambda v: v["paused"])
        self.engine.send("markerAdd", text="Chosen address", position=0, row=17)
        module = self.engine.wait("module", lambda v: len(v["markers"]) == 1)
        self.assertEqual(module["markers"][0]["address"], {"position": 0, "row": 17})
        self.engine.send("section", start={"position": 0, "row": 0}, end={"position": 0, "row": 1})
        self.engine.wait("state", lambda v: v["sectionActive"], timeout=30)
        self.engine.send("sectionCancel")
        self.engine.wait("state", lambda v: not v["sectionActive"] and not v["sectionPreparing"])

    def test_title_override_controls_and_playlist_track_editing(self):
        source = self.open()
        self.engine.send("trackSettings", settings={"useInterpolation": False, "stereoSeparation": 0.0})
        self.engine.wait("module", lambda v: v["trackSettings"].get("stereoSeparation") == 0.0)
        self.engine.send("option", text="useInterpolation", setting=True)
        module = self.engine.wait("module", lambda v: v["trackSettings"].get("useInterpolation") is True)
        self.assertEqual(module["trackSettings"]["stereoSeparation"], 0.0)
        self.engine.wait("state", lambda v: v["sound"]["useInterpolation"] and v["sound"]["stereoSeparation"] == 0.0)
        self.engine.send("defaultOption", text="stereoSeparation", setting=0.4)
        self.engine.wait("preferences", lambda v: v.get("stereoSeparation") == 0.4)
        self.engine.wait("state", lambda v: v["sound"]["stereoSeparation"] == 0.0)
        self.engine.send("trackSettings", settings={})
        self.engine.wait("state", lambda v: abs(v["sound"]["stereoSeparation"]-0.4) < 0.0001)
        self.engine.send("playlistSave", text="Editable")
        library = self.engine.wait("library", lambda v: len(v["playlists"]) == 1)
        playlist = library["playlists"][0]["id"]
        self.engine.send("playlistTrackRemove", playlist=playlist, text=source)
        self.engine.wait("library", lambda v: len(v["playlists"]) == 1 and not v["playlists"][0]["tracks"])

    def test_corrupt_preferences_are_preserved(self):
        protected = self.root / "protected"
        protected.mkdir()
        content = b"{broken collection preferences"
        (protected / "preferences.json").write_bytes(content)
        engine = Engine(self.root, data=protected)
        self.addCleanup(engine.close)
        engine.send("playlistSave", text="Must not overwrite")
        engine.wait("error")
        self.assertEqual((protected / "preferences.json").read_bytes(), content)
        self.assertFalse((protected / "playlists.json").exists())

    def test_stale_collection_decision_is_rejected(self):
        source = self.open()
        self.engine.send("playlistSave", text="Transfer")
        self.engine.wait("library", lambda v: len(v["playlists"]) == 1)
        path = self.root / "stale.savagecollection"
        self.engine.send("collectionExport", path=str(path))
        self.engine.wait("complete")
        self.engine.send("open", paths=[str(path)])
        self.engine.wait("collectionPreview", lambda v: v["ready"])
        self.engine.send("favorite", text=source)
        self.engine.wait("library", lambda v: bool(v["tracks"]) and v["tracks"][0]["favorite"])
        self.engine.send("collectionApply")
        self.engine.wait("error", lambda v: v.get("command") == "collectionApply")

    def test_mixed_collection_drop_and_cancel_release_deferred_audio(self):
        self.open()
        path = self.root / "mixed.savagecollection"
        self.engine.send("collectionExport", path=str(path))
        self.engine.wait("complete")
        self.engine.send("open", paths=[str(self.track), str(path)])
        self.engine.wait("collectionPreview")
        second = self.root / "deferred.mod"
        second.write_bytes(silent_mod())
        self.engine.send("open", paths=[str(second)], autoPlay=False)
        self.engine.send("collectionCancel")
        library = self.engine.wait("library", lambda v: bool(v["tracks"]) and v["tracks"][0]["name"] == "deferred.mod")
        self.assertEqual(len(library["tracks"]), 1)

    @unittest.skipUnless(os.environ.get("SAVAGE_VIDEO_RENDERER") and shutil.which("ffprobe"), "Qt-Videoencoder/ffprobe fehlt")
    def test_video_ends_at_the_exact_audio_sample(self):
        self.open()
        self.engine.send("prepareExport")
        self.engine.wait("exportPrepared")
        for fps in (24, 25, 30, 60):
            with self.subTest(fps=fps):
                output = self.root / f"probe-{fps}.mov"
                self.engine.send("videoExport", path=str(output), width=320, height=180, fps=fps, seconds=0.105)
                result = self.engine.wait("complete", timeout=30)
                self.assertEqual(result["report"]["audioFrameCount"], 5040)
                info = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(output)],
                                      check=True, capture_output=True, text=True, timeout=10)
                streams = json.loads(info.stdout)["streams"]
                self.assertEqual({s["codec_type"] for s in streams}, {"audio", "video"})
                for stream in streams:
                    self.assertEqual(stream["time_base"], "1/48000")
                    self.assertEqual(int(stream["duration_ts"]), 5040, stream)
        # wait() hält nicht abgeholte Ereignisse vor. Fortschritt der bereits
        # abgeschlossenen Exporte darf den Start des neuen Exports nicht quittieren.
        self.engine.events = [message for message in self.engine.events if message.get("event") != "progress"]
        output = self.root / "cancelled.mov"
        self.engine.send("videoExport", path=str(output), width=1920, height=1080, fps=60, seconds=600)
        self.engine.wait("progress", timeout=30)
        self.engine.send("exportCancel")
        self.engine.wait("cancelled", timeout=15)
        self.assertFalse(output.exists())

    @unittest.skipUnless(os.environ.get("SAVAGE_VIDEO_RENDERER"), "Qt-Videoencoder fehlt")
    def test_missing_ffmpeg_reports_the_cause_and_preserves_destination(self):
        empty = self.root / "empty-bin"
        empty.mkdir()
        engine = Engine(self.root, data=self.root / "no-ffmpeg", environment={"PATH": str(empty)})
        self.addCleanup(engine.close)
        engine.send("open", paths=[str(self.track)])
        engine.wait("module")
        output = self.root / "missing.mov"
        engine.send("videoExport", path=str(output), width=320, height=180, fps=30, seconds=0.05)
        error = engine.wait("error", timeout=15)
        self.assertIn("FFmpeg fehlt", error["message"])
        self.assertFalse(output.exists())



# Auch im bestehenden Prozess-Gate ausführen; separat startbar für den Red/Green-Nachweis.
from desktop_load_race_tests import DesktopLoadRaceTests

if __name__ == "__main__":
    unittest.main()

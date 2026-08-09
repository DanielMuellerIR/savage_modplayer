"""Headless-Regressionsprüfungen für macOS-SwiftUI-Bedienelemente.

Das Swift-Testtarget hängt absichtlich nur vom plattformneutralen Core ab und
kann MainView deshalb nicht instanziieren. Diese Tests schützen kleine, aber
wesentliche View-Invarianten; der signierte App-Build bleibt das Layout-Gate.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CompactTransportSourceTests(unittest.TestCase):
    def test_compact_footer_keeps_required_transport_actions(self):
        source = (
            ROOT
            / "Sources/SavageModPlayerApp/UI/MainView+ControlPanel.swift"
        ).read_text(encoding="utf-8")
        compact_footer = source.split("var compactControlPanelView:", maxsplit=1)[1]

        for action in (
            "coordinator.seek(bySeconds: -30)",
            "coordinator.seek(bySeconds: 30)",
            "shuffleEnabled.toggle()",
        ):
            with self.subTest(action=action):
                self.assertIn(action, compact_footer)

    def test_macos_track_loop_resets_elapsed_time_and_now_playing(self):
        source = (
            ROOT
            / "Sources/SavageModPlayerApp/UI/MainView+Playback.swift"
        ).read_text(encoding="utf-8")
        track_case = source.split("case .track:", maxsplit=1)[1].split(
            "case .playlist:", maxsplit=1)[0]

        self.assertIn("coordinator.resetElapsedToLoopStart()", track_case)
        self.assertIn("updateNowPlayingInfo()", track_case)


if __name__ == "__main__":
    unittest.main()

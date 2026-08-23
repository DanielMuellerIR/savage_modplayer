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


class VisualizerFrameRateSourceTests(unittest.TestCase):
    """Die Bildrate-Einstellung muss durchgereicht werden, nicht nur existieren.

    Der Wert liegt in `@AppStorage("savage.visualizerHz")` und muss an zwei
    Stellen ankommen: beim Start und bei jeder Aenderung im
    Einstellungs-Fenster. Fehlt eine davon, wirkt die Einstellung erst beim
    naechsten Start — sichtbar wird das nur, wenn jemand sie ausprobiert.
    """

    KEY = '"savage.visualizerHz"'

    def test_setting_reaches_the_coordinator_at_launch_and_on_change(self):
        source = (ROOT / "Sources/SavageModPlayerApp/UI/MainView.swift").read_text(encoding="utf-8")
        self.assertIn(self.KEY, source, "MainView muss den gespeicherten Wert lesen")
        self.assertIn("coordinator.visualizerFrameRate = visualizerHz", source,
                      "Beim Start muss der Wert in den Coordinator")
        self.assertIn(".onChange(of: visualizerHz)", source,
                      "Eine Aenderung muss sofort wirken, nicht erst beim Neustart")

    def test_settings_window_offers_the_documented_steps(self):
        source = (ROOT / "Sources/SavageModPlayerApp/UI/SettingsView.swift").read_text(encoding="utf-8")
        self.assertIn(self.KEY, source)
        self.assertIn("frameRates: [Double] = [30, 24, 15, 10]", source)

    # Die Klemmung auf 1…60 Hz prueft nicht dieser Quelltest, sondern
    # `CoordinatorSequencingTests.testVisualizerIntervalIsClampedToASensibleRange`
    # — dort laeuft die Rechnung wirklich, statt nur im Text zu stehen.


if __name__ == "__main__":
    unittest.main()

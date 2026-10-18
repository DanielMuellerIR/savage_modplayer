"""Headless-Regressionsprüfungen für SwiftUI-Bedienelemente (Mac und iOS).

Das Swift-Testtarget hängt absichtlich nur vom plattformneutralen Core ab und
kann MainView deshalb nicht instanziieren. Für die iPhone-App gibt es zwar ein
eigenes Testtarget, aber auch dort lässt sich nicht prüfen, ob eine Ansicht
einen bestimmten Modifier trägt — nur, was der Code dahinter tut.

Diese Tests schützen deshalb genau die Stellen, an denen eine geprüfte Funktion
mit der Oberfläche verbunden ist. Die Funktionen selbst prüfen die Swift-Tests;
der signierte App-Build und der Simulator-Lauf bleiben die Layout-Gates.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class TrackerGridSourceTests(unittest.TestCase):
    """Der Zellen-Canvas darf nicht wieder alle Zeilen zeichnen.

    Der Canvas ist so hoch wie das ganze Pattern, sichtbar ist aber immer nur
    eine Kachel (gemessen 519 von 1152 Punkten). Ohne die Begrenzung wurden
    rund 35 von 64 Zeilen gesetzt, ohne je sichtbar zu sein. Die Rechnung
    selbst prueft TrackerGridGeometryTests; hier steht nur, dass die View sie
    auch benutzt.
    """

    def test_channel_canvas_draws_only_the_clipped_rows(self):
        source = (
            ROOT / "Sources/SavageModPlayerApp/UI/TrackerGridView.swift"
        ).read_text(encoding="utf-8")
        canvas = source.split("struct ChannelCellsCanvas", maxsplit=1)[1]
        draw = canvas.split("return Canvas", maxsplit=1)[1]

        self.assertIn("ctx.clipBoundingRect", draw)
        self.assertIn("TrackerGridGeometry.visibleRowRange", draw)
        self.assertNotIn("for r in 0..<rowCount", draw)


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


class IOSLibraryWiringTests(unittest.TestCase):
    """Die iPad-Ergänzungen hängen wirklich an der Bibliotheksansicht.

    `DroppedFilesTests` prüft, was `importDropped` tut, und
    `PlaybackShortcutTests` prüft die Kürzel. Beides nützt nichts, wenn die
    Ansicht sie nicht aufruft — und genau diese Verbindung sieht kein
    Swift-Test.
    """

    def _library_view(self):
        return (
            ROOT / "ios/SavageModPlayer/UI/LibraryView.swift"
        ).read_text(encoding="utf-8")

    def test_files_dropped_on_the_library_reach_the_import(self):
        source = self._library_view()
        self.assertIn("dropDestination(for: URL.self)", source)
        self.assertIn("model.importDropped(urls)", source)

    def test_search_state_is_reported_from_inside_the_searchable_area(self):
        """Der Melder muss VOR `searchable` stehen.

        Nur dann liegt er innerhalb des durchsuchbaren Bereichs und bekommt
        `isSearching`. Stünde er danach, wäre er ein Geschwister davon — der
        Wert bliebe für immer falsch, und die Leertaste bliebe beim Suchen
        blockiert.
        """
        source = self._library_view()
        reporter = source.index("SearchStateReporter(onChange:")
        searchable = source.index(".searchable(text:")
        self.assertLess(reporter, searchable)

    def test_playback_commands_are_attached_to_the_scene(self):
        source = (
            ROOT / "ios/SavageModPlayer/SavageModPlayerApp.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(".commands { PlaybackCommands(model: model) }", source)


if __name__ == "__main__":
    unittest.main()

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


if __name__ == "__main__":
    unittest.main()

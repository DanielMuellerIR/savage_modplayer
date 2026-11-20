#if canImport(SwiftUI) && canImport(Combine)
import SwiftUI

public extension SleepTimerSnapshot {
    var toolbarCountdown: String? {
        guard isActive else { return nil }
        return String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var accessibilityStatus: Text {
        if let toolbarCountdown { return Text(verbatim: toolbarCountdown) }
        return phase == .expired ? Text("Wiedergabe beendet") : Text("Ausgeschaltet")
    }
}

public extension TrackPlaybackSettingsModel {
    func presentationContext(title: String) -> TrackPlaybackSettingsContext {
        .init(sourceID: sourceID, title: title, format: format, sourceDescription: sourceDescription)
    }

    var accessibilityStatus: Text {
        overrides(for: sourceID).isEmpty ? Text("Globale Vorgaben") : Text("Titel-Overrides")
    }
}
#endif

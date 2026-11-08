import Foundation

// SwiftUI beobachtet diesen Zustand; die Linux-Oberfläche erhält Snapshots.
// Der Renderkern schreibt weiterhin ausschließlich in rohe Float-Puffer.
#if canImport(Combine)
import Combine
#endif

// Scope-/VU-/Zeit-Views beobachten diesen Zustand getrennt vom Coordinator.
// Bildaktualisierungen lösen dadurch keinen Neuaufbau der übrigen Oberfläche aus.
@MainActor
public final class VisualizerState: ObservableObject {
    // Geglättete VU-Pegel je Kanal (0..1). Länge = Kanalzahl des aktiven Moduls.
    @Published public var vuLevels: [Float] = []
    // Rollende Kanal-Oszilloskope: je Kanal 32 zuletzt ausgegebene Samples.
    @Published public var channelWaveforms: [[Float]] = []
    // Master-Oszilloskop: 128 zuletzt gemischte (L+R)/2-Samples.
    @Published public var masterSamples: [Float] = [Float](repeating: 0, count: 128)
    // Verstrichene Spielzeit / geschätzte Gesamtdauer in Sekunden.
    @Published public var elapsedTime: Double = 0.0
    @Published public var totalDuration: Double = 0.0

    public init() {}

    // Kanal-abhängige Puffer beim Songwechsel passend dimensionieren. Im
    // ausgeblendeten Visualizer bleiben die Wellenformen leer, bis die
    // Oszilloskope wieder sichtbar werden.
    public func resize(channelCount: Int, includeWaveforms: Bool = true) {
        vuLevels = [Float](repeating: 0, count: channelCount)
        if includeWaveforms {
            channelWaveforms = (0..<channelCount).map { _ in [Float](repeating: 0, count: 32) }
            masterSamples = [Float](repeating: 0, count: 128)
        } else {
            releaseWaveformBuffers()
        }
    }

    // Die letzten Scope-Bilder sind reine Anzeige-Caches. Sobald kein
    // Oszilloskop sichtbar ist, duerfen sie ihren Speicher freigeben; Spielzeit,
    // Gesamtdauer und die billigen VU-Pegel werden separat verwaltet.
    public func releaseWaveformBuffers() {
        if !channelWaveforms.isEmpty { channelWaveforms = [] }
        if !masterSamples.isEmpty { masterSamples = [] }
    }

    // Signalisiert den beobachtenden Subviews eine Änderung, die nicht über die
    // Visualizer-Puffer läuft (z.B. Mute/Solo-Umschalten im gestoppten Zustand, wenn der
    // VU-Timer nicht tickt) — sonst aktualisierte sich die Streifen-Optik erst beim
    // nächsten Play.
    public func nudge() {
        objectWillChange.send()
    }
}

// Song-Position (Pattern-Order-Index) und aktuelle Zeile — die zweite hochfrequente
// Achse, ebenfalls vom Coordinator GETRENNT. currentRow ändert sich im Zeilentakt
// (bei schnellen Songs ~20×/s). Lägen die Werte als @Published auf dem Coordinator,
// würde JEDE Zeile die GESAMTE MainView.body neu evaluieren (Sidebar, Header,
// Marker-Map, Regler) — DAS war die eigentliche CPU-Grundlast (2026-07-09, gemessen:
// ~74 % „Floor" auch ohne Grid/Oszilloskope). Nur die wenigen positionsabhängigen
// Subviews (Tracker-Grid, Positions-Slider, PAT-Anzeige, Marker-Map) beobachten
// diesen State; MainView selbst rendert dann nur noch bei seltenen Änderungen
// (Songwechsel, Play/Pause, Theme) neu.
@MainActor
public final class TransportState: ObservableObject {
    @Published public var currentPosition = 0
    @Published public var currentRow = 0
    public init() {}
}

import SavageModPlayerCore
import SwiftUI

// Die kleinen Ansichten des Wiedergabe-Tabs, die sich schnell aendern.
//
// Sie sind aus einem einzigen Grund eigene Views: Der Core meldet Spielzeit,
// Song-Position, VU-Pegel und Wellenformen bis zu 30-mal pro Sekunde. Wuerde die
// grosse Wiedergabe-Ansicht diese Zustaende beobachten, wertete SwiftUI 30-mal
// pro Sekunde ihren gesamten Aufbau neu aus — Titelbild, Transport, Regler,
// Einstellungen. Genau das war in der Mac-App die Haupt-CPU-Last (2026-07-09),
// nachzulesen im Kommentar zu `visualizersVisible` in ModPlayerCoordinator.swift.
//
// Deshalb gilt hier durchgehend: Wer den hochfrequenten Zustand beobachtet,
// zeichnet auch nur ein paar Buchstaben oder eine einzige Zeichenflaeche.

// MARK: - Zeitanzeige

// Verstrichene Zeit und Gesamtdauer. Beobachtet den Visualisierungs-Zustand —
// das ist der einzige Ort, an dem beides steht.
struct PlaybackTimeRow: View {
    @ObservedObject var visualizer: VisualizerState

    var body: some View {
        HStack {
            Text(verbatim: formatPlaybackTime(visualizer.elapsedTime))
            Spacer()
            Text(verbatim: formatPlaybackTime(visualizer.totalDuration))
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

// MARK: - Positionsregler

// Regler ueber die Song-Positionen (nicht ueber Sekunden — ein Tracker-Modul
// besteht aus einer Liste von Patterns, und genau die springt der Core an).
//
// Er beobachtet `TransportState`, der sich im Zeilentakt aendert. Deshalb steht
// er hier allein und nicht in der grossen Ansicht.
struct PositionSliderView: View {
    @ObservedObject var transport: TransportState
    let positionCount: Int
    let onSeek: (Int) -> Void

    var body: some View {
        // Die Arithmetik liegt im Core und ist dort headless getestet: Bei einem
        // Modul mit nur EINER Position waere der Bereich 0...0 leer, und SwiftUIs
        // Slider beendet den Prozess. `SongPositionScale` haelt fest, dass der
        // Bereich nie leer ist.
        let bounds = SongPositionScale.bounds(positionCount: positionCount, current: transport.currentPosition)
        Slider(
            value: Binding(get: { bounds.value }, set: { onSeek(Int($0)) }),
            in: bounds.range,
            step: 1
        )
        .disabled(!bounds.isEnabled)
        .accessibilityLabel("transport.position")
        .accessibilityValue(Text("player.status.position \(transport.currentPosition + 1) \(max(1, positionCount))"))
    }
}

// MARK: - Statuszeile

// BPM, Geschwindigkeit, Position und Kanalzahl. Beobachtet den Coordinator;
// dessen BPM/Speed aendern sich nur, wenn das Modul es befiehlt — also selten.
struct PlaybackStatusRow: View {
    @ObservedObject var coordinator: ModPlayerCoordinator
    let positionCount: Int
    let channelCount: Int

    var body: some View {
        HStack(spacing: 10) {
            statusChip("player.status.bpm \(coordinator.bpm)")
            statusChip("player.status.speed \(coordinator.speed)")
            // Die Position steckt in einem eigenen Beobachter, damit der
            // Zeilentakt nicht auch BPM und Kanalzahl neu zeichnet.
            PositionChip(transport: coordinator.transport, positionCount: positionCount)
            statusChip("player.status.channels \(channelCount)")
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func statusChip(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

// "PAT 3/42" — die einzige Stelle, die im Zeilentakt neu gezeichnet wird.
private struct PositionChip: View {
    @ObservedObject var transport: TransportState
    let positionCount: Int

    var body: some View {
        Text("player.status.position \(transport.currentPosition + 1) \(max(1, positionCount))")
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

// MARK: - Favoriten-Schalter

// Eigene Ansicht, weil sie als Einzige die Bibliothek beobachten muss. Sonst
// wuerde jeder Import-Fortschritt den ganzen Wiedergabe-Tab neu zeichnen.
struct FavoriteToggleButton: View {
    @ObservedObject var library: LibraryStore
    let relativePath: String

    var body: some View {
        let isFavorite = library.isFavorite(relativePath)
        Button {
            library.toggleFavorite(relativePath)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
        }
        .accessibilityLabel("transport.favorite")
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }
}

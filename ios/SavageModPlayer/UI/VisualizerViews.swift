import SavageModPlayerCore
import SwiftUI

// Die Visualisierungen: Master-Oszilloskop, VU-Meter und Kanal-Oszilloskope.
//
// Sie sind auf dem iPhone eine Zugabe, kein Traeger der Oberflaeche. Sie werden
// nur gezeichnet, wenn sie in den Einstellungen eingeschaltet sind UND die App
// gerade sichtbar ist. Der uebliche Fall auf einem Telefon ist "Musik laeuft,
// Bildschirm ist aus" — dann soll nichts berechnet werden, was niemand sieht.
//
// Zwei Entscheidungen bestimmen den Aufbau:
//
// 1. **Gezeichnet wird in `Canvas`, nicht in Dutzenden Einzel-Views.** Ein
//    IT-Modul hat bis zu 64 Kanaele. Als je eigene View mit eigenem VU-Balken
//    waeren das mehrere hundert SwiftUI-Knoten, die 20-mal pro Sekunde neu
//    gebaut werden. In einem Canvas ist es ein Knoten und eine Zeichenroutine.
//
// 2. **Der Takt kommt von `TimelineView`, nicht vom Zustand.** Diese Views
//    beobachten `VisualizerState` ausdruecklich NICHT (kein @ObservedObject).
//    Sie lesen die Werte im eigenen, in den Einstellungen gewaehlten Takt. Damit
//    schiebt der 30-Hz-Tick des Cores keine Aktualisierungen durch SwiftUI, und
//    die eingestellte Bildrate ist wirklich die Bildrate.
//
// Die ausfuehrliche Begruendung, warum die Update-FREQUENZ und nicht das
// Zeichnen die eigentliche Last ist, steht im Kommentar zu `visualizersVisible`
// in ModPlayerCoordinator.swift.

// MARK: - Master-Oszilloskop

struct MasterScopeView: View {
    // Bewusst `let` statt @ObservedObject: siehe Kopfkommentar.
    let visualizer: VisualizerState
    let frameRate: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / Double(max(1, frameRate)))) { _ in
            Canvas { context, size in
                let samples = visualizer.masterSamples
                guard samples.count > 1, size.width > 0 else { return }
                var path = Path()
                let step = size.width / CGFloat(samples.count - 1)
                path.move(to: CGPoint(x: 0, y: level(samples[0], size.height)))
                for index in 1..<samples.count {
                    path.addLine(to: CGPoint(x: CGFloat(index) * step, y: level(samples[index], size.height)))
                }
                context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
            }
        }
        .frame(height: 64)
        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    // Sample (-1 … +1) auf eine Bildkoordinate abbilden: 0 liegt in der Mitte.
    private func level(_ sample: Float, _ height: CGFloat) -> CGFloat {
        height * CGFloat(0.5 - max(-1, min(1, sample)) * 0.5)
    }
}

// MARK: - Kanaele

// VU-Meter und Oszilloskop je Kanal, alles in einer einzigen Zeichenflaeche.
// `channelIndices` ist bereits begrenzt (Einstellung "Kanal-Oszilloskope") —
// 64 Kanaele nebeneinander waeren auf einem Telefon weder lesbar noch bezahlbar.
struct ChannelScopesView: View {
    let visualizer: VisualizerState
    let channelIndices: [Int]
    let frameRate: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / Double(max(1, frameRate)))) { _ in
            Canvas { context, size in
                let levels = visualizer.vuLevels
                let waves = visualizer.channelWaveforms
                let count = channelIndices.count
                guard count > 0, size.width > 0 else { return }

                let spacing: CGFloat = count > 8 ? 3 : 6
                let columnWidth = (size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
                guard columnWidth > 2 else { return }

                let vuWidth = min(10, max(3, columnWidth * 0.22))
                let innerGap: CGFloat = columnWidth > 20 ? 3 : 1
                let scopeWidth = max(1, columnWidth - vuWidth - innerGap)

                for (column, channel) in channelIndices.enumerated() {
                    let originX = CGFloat(column) * (columnWidth + spacing)

                    // VU-Meter: acht Segmente, von unten gefuellt.
                    let level = channel < levels.count ? levels[channel] : 0
                    let segments = 8
                    let gap: CGFloat = 2
                    let segmentHeight = (size.height - gap * CGFloat(segments - 1)) / CGFloat(segments)
                    if segmentHeight > 0 {
                        for segment in 0..<segments {
                            // Schwelle ab 1/8, nicht ab 0: sonst leuchtet auch
                            // bei voelliger Stille das unterste Segment.
                            let threshold = Float(segment + 1) / Float(segments)
                            let y = size.height - CGFloat(segment + 1) * segmentHeight - CGFloat(segment) * gap
                            let rect = CGRect(x: originX, y: y, width: vuWidth, height: segmentHeight)
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 1),
                                with: .color(level >= threshold ? Self.segmentColor(threshold) : Self.idleColor))
                        }
                    }

                    // Oszilloskop: die zuletzt ausgegebenen Samples des Kanals.
                    let scopeX = originX + vuWidth + innerGap
                    let box = CGRect(x: scopeX, y: 0, width: scopeWidth, height: size.height)
                    context.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(Self.idleColor))
                    guard channel < waves.count else { continue }
                    let history = waves[channel]
                    guard history.count > 1, scopeWidth > 1 else { continue }
                    var path = Path()
                    let step = scopeWidth / CGFloat(history.count - 1)
                    path.move(to: CGPoint(x: scopeX, y: size.height * CGFloat(0.5 - Double(history[0]) * 0.5)))
                    for index in 1..<history.count {
                        path.addLine(to: CGPoint(
                            x: scopeX + CGFloat(index) * step,
                            y: size.height * CGFloat(0.5 - Double(history[index]) * 0.5)))
                    }
                    context.stroke(path, with: .color(.accentColor), lineWidth: 1)
                }
            }
        }
        .frame(height: 72)
        .accessibilityHidden(true)
    }

    // Laute Kanaele werden oben gelb und rot — die vertraute Optik eines
    // Mischpults.
    private static func segmentColor(_ threshold: Float) -> Color {
        if threshold > 0.85 { return .red }
        if threshold > 0.6 { return .orange }
        return .accentColor
    }

    private static let idleColor = Color.gray.opacity(0.2)
}

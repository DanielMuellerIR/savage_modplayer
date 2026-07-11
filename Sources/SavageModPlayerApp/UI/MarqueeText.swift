import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// Laufschrift (Marquee) fuer zu lange Titel inkl. Mess-Preference-Keys.

// MARK: - Laufschrift (Marquee) fuer zu lange Titel

// Preference-Keys zum Messen von Textgroesse und Container-Breite (ohne das
// Layout zu beeinflussen — die Messung laeuft ueber transparente GeometryReader).
private struct MarqueeTextSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
private struct MarqueeContainerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// Einzeiliger Titel, der als Laufschrift scrollt, wenn er breiter als der
// verfuegbare Platz ist. Ablauf pro Runde: 4 s am Anfang stehen, gleichmaessig
// nach links bis zum Ende scrollen, 4 s am Ende stehen, ohne Animation an den
// Anfang zurueckspringen, wieder 4 s stehen — und von vorn.
// Diese View wird nur im Ueberlauf-Fall verwendet (ViewThatFits zeigt sonst den
// statischen Text), deshalb wird hier immer gescrollt, sobald gemessen ist.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State var textWidth: CGFloat = 0
    @State var textHeight: CGFloat = 24  // vernuenftiger Startwert gegen Flackern
    @State var containerWidth: CGFloat = 0
    @State var offset: CGFloat = 0
    @State var scrollTask: Task<Void, Never>? = nil

    // Scroll-Tempo (Punkte pro Sekunde) und Steh-Dauer an den Enden.
    let pointsPerSecond: Double = 40
    let dwellNanos: UInt64 = 4_000_000_000  // 4 Sekunden

    var body: some View {
        // Color.clear ist die flexible Basis: sie fuellt die verfuegbare Breite,
        // FORDERT sie aber nicht als Ideal-Breite. Ein fixedSize-Text als Basis
        // wuerde dagegen seine volle Breite als Ideal melden und die Kopfzeile
        // aufblaehen (rechte Bedienelemente/Sidebar aus dem Fenster gedrueckt).
        // Der eigentliche Titel liegt als linksbuendiges Overlay darueber, laeuft
        // bei Ueberlaenge nach links heraus (offset) und wird geclippt.
        Color.clear
            .frame(maxWidth: .infinity, minHeight: textHeight, maxHeight: textHeight)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .fixedSize()  // volle Breite/Hoehe, kein Kuerzen
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: MarqueeTextSizeKey.self, value: g.size)
                        }
                    )
                    .offset(x: offset)
            }
            .clipped()  // ueberstehenden Titel abschneiden
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: MarqueeContainerWidthKey.self, value: g.size.width)
                }
            )
            .onPreferenceChange(MarqueeTextSizeKey.self) { s in
                textWidth = s.width
                textHeight = s.height
                restartScroll()
            }
            .onPreferenceChange(MarqueeContainerWidthKey.self) { w in
                containerWidth = w
                restartScroll()
            }
            .onChange(of: text) { _ in restartScroll() }
            .onDisappear { scrollTask?.cancel() }
    }

    // Startet die Scroll-Schleife neu (nach Mess- oder Titelaenderung). Passt der
    // Text (kein Ueberlauf), bleibt er einfach stehen.
    func restartScroll() {
        scrollTask?.cancel()
        offset = 0
        let distance = textWidth - containerWidth
        guard distance > 1, containerWidth > 0 else { return }

        let duration = Double(distance) / pointsPerSecond
        scrollTask = Task { @MainActor in
            while !Task.isCancelled {
                // 4 s am Anfang stehen
                try? await Task.sleep(nanoseconds: dwellNanos)
                if Task.isCancelled { break }
                // gleichmaessig nach links bis zum Ende scrollen
                withAnimation(.linear(duration: duration)) { offset = -distance }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if Task.isCancelled { break }
                // 4 s am Ende stehen
                try? await Task.sleep(nanoseconds: dwellNanos)
                if Task.isCancelled { break }
                // ohne Animation an den Anfang zurueckspringen; die naechste
                // Schleifenrunde beginnt wieder mit der 4-s-Startpause
                offset = 0
            }
        }
    }
}


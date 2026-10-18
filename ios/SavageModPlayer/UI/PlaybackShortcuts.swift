import SwiftUI

// Tastaturkuerzel fuer die Wiedergabe.
//
// Warum das hier steht: Ein iPad mit Tastatur ist ein Arbeitsgeraet, und wer
// nebenher Musik hoert, will nicht fuer jedes Pausieren zur App wechseln und
// tippen. Auf dem iPhone mit angeschlossener Tastatur gelten dieselben
// Kuerzel — sie stoeren dort niemanden, der keine Tastatur hat.
//
// Die Liste steht als Aufzaehlung und nicht direkt in der Ansicht, damit Tests
// sie pruefen koennen: dass jedes Kuerzel eine Beschriftung hat, dass keine
// Taste doppelt belegt ist und dass jedes wirklich das tut, was draufsteht.
enum PlaybackShortcut: CaseIterable {
    case playPause
    case nextTrack
    case previousTrack
    case skipForward
    case skipBackward

    /// Wie viele Sekunden die beiden Sprungkuerzel ueberspringen.
    static let skipSeconds: Double = 10

    var key: KeyEquivalent {
        switch self {
        case .playPause: return .space
        case .nextTrack, .skipForward: return .rightArrow
        case .previousTrack, .skipBackward: return .leftArrow
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .playPause: return []
        case .nextTrack, .previousTrack: return [.command]
        case .skipForward, .skipBackward: return [.command, .shift]
        }
    }

    /// Beschriftung im Kuerzel-Fenster, das iPadOS beim Halten von Cmd zeigt.
    var titleKey: LocalizedStringKey {
        switch self {
        case .playPause: return "shortcut.playPause"
        case .nextTrack: return "transport.next"
        case .previousTrack: return "transport.previous"
        case .skipForward: return "shortcut.skipForward"
        case .skipBackward: return "shortcut.skipBackward"
        }
    }

    /// Kuerzel ohne Zusatztaste kollidieren mit der Texteingabe.
    ///
    /// Solange das Suchfeld aktiv ist, muss die Leertaste ein Leerzeichen
    /// tippen. Die Kuerzel mit Cmd sind davon nicht betroffen — die tippt
    /// niemand versehentlich in ein Suchfeld.
    func isBlocked(searchFieldActive: Bool) -> Bool {
        searchFieldActive && modifiers.isEmpty
    }

    @MainActor
    func perform(on player: PlaybackEngine) {
        switch self {
        case .playPause: player.togglePlayPause()
        case .nextTrack: player.next()
        case .previousTrack: player.previous()
        case .skipForward: player.skip(bySeconds: Self.skipSeconds)
        case .skipBackward: player.skip(bySeconds: -Self.skipSeconds)
        }
    }
}

// Die Kuerzel als Menuebefehle der Szene.
//
// `commands` statt versteckter Knoepfe in der Ansicht: Nur so landen sie
// zuverlaessig im Kuerzel-Fenster von iPadOS und gelten unabhaengig davon,
// welcher Teil der Oberflaeche gerade vorn ist.
struct PlaybackCommands: Commands {
    // Die Szene lebt laenger als jede Ansicht; das Modell kommt deshalb direkt
    // herein und nicht ueber die Umgebung.
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu("shortcut.menu") {
            ForEach(Array(PlaybackShortcut.allCases.enumerated()), id: \.offset) { _, shortcut in
                Button(shortcut.titleKey) {
                    shortcut.perform(on: model.player)
                }
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                .disabled(shortcut.isBlocked(searchFieldActive: model.isTextEntryActive))
            }
        }
    }
}

// Meldet, ob das Suchfeld gerade aktiv ist.
//
// `isSearching` steht nur Ansichten INNERHALB des durchsuchbaren Bereichs zur
// Verfuegung. Diese Ansicht zeichnet nichts; sie sitzt als Hintergrund der
// Liste, damit sie innerhalb dieses Bereichs liegt, und reicht den Zustand nach
// oben. Ohne sie wuesste das Kuerzel-Menue der Szene nichts von der Texteingabe.
struct SearchStateReporter: View {
    @Environment(\.isSearching) private var isSearching
    let onChange: (Bool) -> Void

    var body: some View {
        Color.clear
            .onChange(of: isSearching) { _, active in onChange(active) }
            // Beim Verlassen der Ansicht darf kein aktiver Zustand
            // zurueckbleiben — sonst bliebe die Leertaste dauerhaft tot.
            .onDisappear { onChange(false) }
            .accessibilityHidden(true)
    }
}

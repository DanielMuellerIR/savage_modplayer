import Foundation
import SwiftUI

// Typen, die Wiedergabe, Bibliothek und Oberflaeche gemeinsam benutzen. Sie
// liegen bewusst in einer eigenen, kleinen Datei: so muss keiner der drei
// Bereiche in die Innereien eines anderen greifen, nur um einen Aufzaehlungswert
// zu kennen.

// Was am Songende passiert. Gleiche Semantik wie in der Mac-App.
enum LoopMode: String, CaseIterable, Identifiable, Sendable {
    case playlist   // naechster Titel (am Listenende wieder von vorn)
    case track      // denselben Titel wiederholen
    case none       // stehen bleiben

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .playlist: return "repeat"
        case .track: return "repeat.1"
        case .none: return "play.slash"
        }
    }

    var localizedName: LocalizedStringKey {
        switch self {
        case .playlist: return "loop.playlist"
        case .track: return "loop.track"
        case .none: return "loop.once"
        }
    }
}

// Farbwelt der Oberflaeche. Die Mac-App hat mehrere Themes; auf dem iPhone
// bleiben zwei uebrig, damit die Auswahl nicht groesser ist als der Nutzen.
enum PlayerTheme: String, CaseIterable, Identifiable, Sendable {
    case cyber      // dunkel, gruen-tuerkis — die Hausfarbe des Players
    case light      // hell, fuer Tageslicht

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .cyber: return "theme.cyber"
        case .light: return "theme.light"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .cyber: return .dark
        case .light: return .light
        }
    }
}

// Ein abspielbarer Eintrag, wie ihn die Oberflaeche kennt: Datei-URL plus der
// Ordnerpfad, unter dem er in der Bibliothek haengt. Die URL zeigt in den
// App-Container und ist NICHT stabil ueber Neuinstallationen hinweg — stabil ist
// nur `relativePath` (das ist die ID aus dem Bibliotheks-Index).
struct TrackRef: Identifiable, Hashable, Sendable {
    let relativePath: String
    let displayName: String
    let folderPath: [String]
    let url: URL

    var id: String { relativePath }
}

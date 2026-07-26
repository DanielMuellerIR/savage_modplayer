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

// Erscheinungsbild der Oberflaeche: hell, dunkel oder das, was das System
// gerade vorgibt. Bewusst kein eigener Farbwelt-Zoo wie in der Mac-App — auf
// dem iPhone erwartet man die Systemeinstellung, und mehr Auswahl bringt hier
// keinen Nutzen.
enum PlayerTheme: String, CaseIterable, Identifiable, Sendable {
    case system     // folgt der Systemeinstellung (Standard)
    case light
    case dark

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .system: return "theme.system"
        case .light: return "theme.light"
        case .dark: return "theme.dark"
        }
    }

    // Was `.preferredColorScheme(_:)` bekommt. `nil` heisst "nicht erzwingen",
    // also folgt die App dem System.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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

import Foundation
import SavageModPlayerCore
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
    let addedAt: Date?

    init(relativePath: String, displayName: String, folderPath: [String], url: URL, addedAt: Date? = nil) {
        self.relativePath = relativePath; self.displayName = displayName
        self.folderPath = folderPath; self.url = url; self.addedAt = addedAt
    }

    var id: String { relativePath }

    var playlistReference: PlaylistTrackReference? {
        guard let source = PlaylistTrackSource(libraryRelativePath: relativePath) else { return nil }
        return PlaylistTrackReference(source: source, displayName: displayName)
    }
}

// Aus welcher Auswahl der Bibliothek die Abspielliste stammt.
//
// Ohne diese Angabe ersetzte jede Aenderung der Bibliothek die Abspielliste
// durch den Gesamtbestand — auch wenn die Wiedergabe bewusst aus einer Suche
// oder aus den Favoriten gestartet worden war. Ein Favorit mehr, und "weiter"
// lief plotzlich durch die ganze Sammlung.
//
// Leerer Suchbegriff ohne Favoritenfilter heisst: die ganze Bibliothek. Das ist
// derselbe Fall, den `LibraryStore.filteredTracks` ohnehin abkuerzt.
struct QueueFilter: Equatable {
    var search: String = ""
    var favoritesOnly: Bool = false

    var isWholeLibrary: Bool {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !favoritesOnly
    }
}

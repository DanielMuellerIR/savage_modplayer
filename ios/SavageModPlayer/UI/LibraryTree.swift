import SavageModPlayerCore

// Der Ordnerbaum der Bibliothek, flach ausgerollt.
//
// Warum flach? SwiftUI kann eine View nicht ohne Weiteres rekursiv aus sich
// selbst aufbauen, und `OutlineGroup` gibt die Auf-/Zuklapp-Zustaende nicht
// heraus — wir brauchen sie aber, weil der Pfad zum laufenden Titel automatisch
// aufklappen soll. Deshalb wird der Baum vor dem Zeichnen in eine schlichte
// Liste sichtbarer Zeilen mit Tiefenangabe verwandelt. Das ist zugleich das
// schnellere Verfahren: eine zugeklappte Sammlung erzeugt genau so viele Zeilen,
// wie man sieht — nicht eine je Titel.
struct LibraryRow: Identifiable {

    enum Kind {
        // Ordner mit seinem Pfad (stabile ID fuers Auf-/Zuklappen) und der Zahl
        // der enthaltenen Titel, Unterordner eingerechnet.
        case folder(name: String, path: String, trackCount: Int)
        // Titel mit seinem relativen Pfad — der stabilen ID des Index.
        case track(relativePath: String, displayName: String)
    }

    let id: String
    let depth: Int
    let kind: Kind
}

enum LibraryTree {

    // Sichtbare Zeilen eines (bereits gefilterten) Baums.
    //
    // `expanded` enthaelt die Pfade der aufgeklappten Ordner. `expandAll` gilt
    // waehrend einer Suche oder im Favoritenfilter: dann sind ohnehin nur noch
    // Treffer im Baum, und zugeklappte Ordner wuerden sie verstecken.
    static func rows(
        of root: PlaylistScanner.FolderNode?,
        expanded: Set<String>,
        expandAll: Bool
    ) -> [LibraryRow] {
        guard let root else { return [] }
        var result: [LibraryRow] = []
        appendChildren(of: root, depth: 0, expanded: expanded, expandAll: expandAll, into: &result)
        return result
    }

    // Reihenfolge wie im Core: erst die Unterordner, dann die eigenen Dateien.
    // Das ist genau die Reihenfolge von `PlaylistScanner.flattenedFiles` und
    // damit die Abspielreihenfolge — Weiter/Zurueck folgt also dem, was auf dem
    // Bildschirm steht.
    private static func appendChildren(
        of node: PlaylistScanner.FolderNode,
        depth: Int,
        expanded: Set<String>,
        expandAll: Bool,
        into result: inout [LibraryRow]
    ) {
        for folder in node.subfolders {
            result.append(LibraryRow(
                id: "folder:" + folder.path,
                depth: depth,
                kind: .folder(name: folder.name, path: folder.path, trackCount: trackCount(of: folder))))
            if expandAll || expanded.contains(folder.path) {
                appendChildren(
                    of: folder, depth: depth + 1,
                    expanded: expanded, expandAll: expandAll, into: &result)
            }
        }
        for file in node.files {
            let relativePath = (file.folderPath + [file.displayName]).joined(separator: "/")
            result.append(LibraryRow(
                id: "track:" + relativePath,
                depth: depth,
                kind: .track(relativePath: relativePath, displayName: file.displayName)))
        }
    }

    // Titel in diesem Ordner samt aller Unterordner.
    static func trackCount(of node: PlaylistScanner.FolderNode) -> Int {
        node.files.count + node.subfolders.reduce(0) { $0 + trackCount(of: $1) }
    }

    // Alle Ordnerpfade auf dem Weg zu einem Titel: ["A", "A/B", "A/B/C"].
    // Genau diese Ordner werden aufgeklappt, damit der laufende Titel sichtbar
    // wird, ohne die ganze Sammlung aufzuklappen.
    static func ancestorPaths(of folderPath: [String]) -> [String] {
        var result: [String] = []
        var current = ""
        for component in folderPath {
            current = current.isEmpty ? component : current + "/" + component
            result.append(current)
        }
        return result
    }
}

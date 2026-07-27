import Foundation

// "Bibliothek zuruecksetzen" aus den Einstellungen: raeumt Inhalt, Index und
// die uebergebenen Temp-/Cache-Verzeichnisse ab.
//
// Zwei Dinge sind hier wichtig:
// - **Idempotent.** Ein zweiter Aufruf darf nicht scheitern. Wer zweimal auf
//   den Knopf tippt (oder die App mittendrin beendet), soll keinen Fehler
//   sehen, sondern schlicht eine leere Bibliothek.
// - **Der Core kennt die Favoriten nicht.** Wo sie gespeichert sind, weiss nur
//   die App; deshalb ruft `clearFavorites` lediglich einen uebergebenen Haken
//   auf, statt selbst irgendwo herumzuraeumen.
public enum LibraryReset {

    public struct Options: Sendable {
        // Indexdatei loeschen (true) oder durch einen leeren Index ersetzen (false).
        public var removeIndex: Bool
        // Favoriten mitloeschen — dafuer muss ein `favoritesCleaner` uebergeben werden.
        public var clearFavorites: Bool

        public init(removeIndex: Bool = true, clearFavorites: Bool = false) {
            self.removeIndex = removeIndex
            self.clearFavorites = clearFavorites
        }
    }

    public struct ResetReport: Sendable {
        public let removedFiles: Int
        public let removedDirectories: Int
        public let failures: [ImportFailure]

        public init(removedFiles: Int, removedDirectories: Int, failures: [ImportFailure]) {
            self.removedFiles = removedFiles
            self.removedDirectories = removedDirectories
            self.failures = failures
        }
    }

    // Leert die Bibliothek. Die Wurzel selbst bleibt bestehen, damit direkt
    // danach wieder importiert werden kann.
    @discardableResult
    public static func reset(
        library: MusicLibrary,
        temporaryDirectories: [URL] = [],
        options: Options = Options(),
        favoritesCleaner: (() -> Void)? = nil
    ) throws -> ResetReport {
        let fileManager = FileManager.default
        var removedFiles = 0
        var removedDirectories = 0
        var failures: [ImportFailure] = []

        // Inhalt eines Verzeichnisses loeschen, das Verzeichnis selbst behalten.
        // Ohne `.skipsHiddenFiles`, damit auch unsichtbarer Beifang (z.B.
        // `.DS_Store`) verschwindet.
        func wipeContents(of directory: URL) {
            guard fileManager.fileExists(atPath: directory.path) else { return }
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [])
            else { return }
            for child in children {
                let counted = count(child)
                do {
                    try fileManager.removeItem(at: child)
                    removedFiles += counted.files
                    removedDirectories += counted.directories
                } catch {
                    failures.append(ImportFailure(
                        path: child.lastPathComponent,
                        reason: "Konnte nicht geloescht werden: \((error as NSError).localizedDescription)"))
                }
            }
        }

        wipeContents(of: library.rootURL)
        for temporary in temporaryDirectories {
            wipeContents(of: temporary)
        }

        try library.clearIndex(removeFile: options.removeIndex)

        if options.clearFavorites {
            favoritesCleaner?()
        }

        return ResetReport(
            removedFiles: removedFiles,
            removedDirectories: removedDirectories,
            failures: failures)
    }

    // Zaehlt, was hinter einem Eintrag steckt: eine Datei zaehlt als eine
    // Datei, ein Ordner als ein Verzeichnis plus alles darin. Gezaehlt wird
    // vor dem Loeschen — danach ist nichts mehr da, was man zaehlen koennte.
    private static func count(_ url: URL) -> (files: Int, directories: Int) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return (0, 0)
        }
        guard isDirectory.boolValue else { return (1, 0) }

        var files = 0
        var directories = 1
        if let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            while let child = enumerator.nextObject() as? URL {
                let childIsDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if childIsDirectory {
                    directories += 1
                } else {
                    files += 1
                }
            }
        }
        return (files, directories)
    }
}

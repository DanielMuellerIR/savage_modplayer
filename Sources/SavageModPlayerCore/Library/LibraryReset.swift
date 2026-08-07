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
        // Nach Teilfehlern: Archive, die im verbliebenen Bestand liegen (aus
        // dem Wiederaufbau-Rescan). Bei vollstaendigem Erfolg leer.
        public let remainingArchives: [String]

        public init(
            removedFiles: Int,
            removedDirectories: Int,
            failures: [ImportFailure],
            remainingArchives: [String] = []
        ) {
            self.removedFiles = removedFiles
            self.removedDirectories = removedDirectories
            self.failures = failures
            self.remainingArchives = remainingArchives
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
        // Fehler der Bibliothekswurzel und der Temp-/Cache-Verzeichnisse werden
        // GETRENNT gesammelt. Nur ein Rest in der Bibliothek rechtfertigt, den
        // Index wieder aufzubauen; ein sachfremder Temp-Fehler darf die Option
        // „Indexdatei loeschen" nicht aushebeln.
        var rootFailures: [ImportFailure] = []
        var temporaryFailures: [ImportFailure] = []

        // Inhalt eines Verzeichnisses loeschen, das Verzeichnis selbst behalten.
        // Ohne `.skipsHiddenFiles`, damit auch unsichtbarer Beifang (z.B.
        // `.DS_Store`) verschwindet.
        func wipeContents(of directory: URL, isLibraryRoot: Bool) {
            guard fileManager.fileExists(atPath: directory.path) else { return }
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil, options: [])
            } catch {
                // Ein nicht auflistbares Verzeichnis ist kein leeres
                // Verzeichnis. Ohne diesen Fehler blieb `failures` leer, der
                // Index wurde geleert und der Wiederaufbau unterblieb — Bericht
                // und Oberflaeche meldeten einen vollstaendigen Reset, waehrend
                // real jede Datei liegen blieb.
                let failure = ImportFailure(
                    path: directory.lastPathComponent,
                    reason: "Inhalt konnte nicht aufgelistet werden: "
                        + "\((error as NSError).localizedDescription)")
                if isLibraryRoot { rootFailures.append(failure) } else { temporaryFailures.append(failure) }
                return
            }
            for child in children {
                let counted = count(child)
                do {
                    try fileManager.removeItem(at: child)
                    removedFiles += counted.files
                    removedDirectories += counted.directories
                } catch {
                    let failure = ImportFailure(
                        path: child.lastPathComponent,
                        reason: "Konnte nicht geloescht werden: \((error as NSError).localizedDescription)")
                    if isLibraryRoot { rootFailures.append(failure) } else { temporaryFailures.append(failure) }
                }
            }
        }

        wipeContents(of: library.rootURL, isLibraryRoot: true)
        for temporary in temporaryDirectories {
            wipeContents(of: temporary, isLibraryRoot: false)
        }

        // Teilfehler in der Bibliothek: Es liegen noch Dateien dort. Ein leerer
        // Index waere eine Luege — die Oberflaeche zeigte eine leere
        // Bibliothek, obwohl Dateien (und offene Archive) real erhalten
        // blieben. Deshalb wird der bisherige Index NICHT geleert, sondern der
        // verbliebene Bestand daruebergelegt: `rescan` traegt Gefundenes nach
        // und entfernt Verschwundenes nur nach einem nachweislich
        // vollstaendigen Durchlauf. Bei einem Teilscan bleiben die Eintraege
        // nicht besuchter Teilbaeume erhalten, statt still zu verschwinden.
        var remainingArchives: [String] = []
        if rootFailures.isEmpty {
            try library.clearIndex(removeFile: options.removeIndex)
        } else if let rescan = try? library.rescan() {
            remainingArchives = rescan.archivesFound
        }

        if options.clearFavorites {
            favoritesCleaner?()
        }

        return ResetReport(
            removedFiles: removedFiles,
            removedDirectories: removedDirectories,
            failures: rootFailures + temporaryFailures,
            remainingArchives: remainingArchives)
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

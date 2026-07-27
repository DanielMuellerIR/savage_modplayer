import Foundation

// Bringt Moduldateien von aussen in die Bibliothek: rekursiv, mit Fortschritt,
// abbrechbar, ohne etwas zu ueberschreiben.
//
// Regeln in Kurzform:
// - Die Ordnerstruktur der Quelle bleibt erhalten.
// - Schon vorhandene, inhaltsgleiche Dateien werden uebersprungen (Dedupe).
// - Namensgleiche Dateien mit anderem Inhalt bekommen einen Zaehler-Suffix.
// - Archive werden ausgepackt und wie ein Ordner einsortiert.
// - Nicht spielbare Dateien werden stillschweigend uebergangen.

// Zwischenstand fuer die Fortschrittsanzeige.
public struct ImportProgress: Sendable {
    public let processedFiles: Int
    // Vorabzaehlung aller spielbaren Quellen; 0 wenn noch unbekannt. Ein Archiv
    // zaehlt dabei als eine Einheit — was darin steckt, weiss man erst danach.
    public let totalFiles: Int
    public let currentName: String
    public let importedBytes: Int64

    public init(processedFiles: Int, totalFiles: Int, currentName: String, importedBytes: Int64) {
        self.processedFiles = processedFiles
        self.totalFiles = totalFiles
        self.currentName = currentName
        self.importedBytes = importedBytes
    }
}

// Eine einzelne gescheiterte Datei bzw. ein gescheitertes Archiv. Ein Fehler
// bricht den Import nie ab — ein kaputtes Archiv darf 500 gute Dateien nicht
// verhindern.
public struct ImportFailure: Sendable {
    public let path: String
    // Fuer den Nutzer lesbar formuliert.
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct ImportReport: Sendable {
    public let imported: [String]
    public let duplicates: [String]
    public let failures: [ImportFailure]
    public let wasCancelled: Bool

    public init(imported: [String], duplicates: [String], failures: [ImportFailure], wasCancelled: Bool) {
        self.imported = imported
        self.duplicates = duplicates
        self.failures = failures
        self.wasCancelled = wasCancelled
    }
}

public final class LibraryImporter: @unchecked Sendable {

    // Wie eine Quelldatei geoeffnet wird. Voreinstellung: direkter Zugriff.
    // iOS ersetzt das durch koordiniertes Lesen (`NSFileCoordinator`), weil
    // Dateien aus einem File Provider (Nextcloud & Co.) erst geladen werden
    // muessen. Der Core kennt diese Klassen nicht und bleibt damit
    // plattformneutral.
    public typealias CoordinatedRead = (URL, (URL) throws -> Void) throws -> Void

    private let library: MusicLibrary
    private let coordinatedRead: CoordinatedRead
    private let fileManager = FileManager.default

    public init(
        library: MusicLibrary,
        coordinatedRead: @escaping CoordinatedRead = { url, body in try body(url) }
    ) {
        self.library = library
        self.coordinatedRead = coordinatedRead
    }

    // MARK: - Oeffentlicher Einstieg

    // Importiert die uebergebenen Quellen rekursiv.
    //
    // Wurzelordner-Namensgebung: **jede** Quelle wird unter ihrem eigenen
    // Ordnernamen einsortiert. Wer genau einen Sammlungsordner auswaehlt,
    // erwartet ihn in der Bibliothek genau so wieder — und bei mehreren
    // Quellen verhindert dieselbe Regel, dass sich gleichnamige Unterordner
    // aus verschiedenen Sammlungen vermischen. Einzelne Dateien landen direkt
    // in der Wurzel.
    public func importContents(
        of sources: [URL],
        progress: (ImportProgress) -> Void = { _ in },
        isCancelled: () -> Bool = { false }
    ) throws -> ImportReport {
        // Die beiden Closures sind hier nicht-escapend, werden aber weiter
        // unten in Closures hineingereicht (z.B. beim koordinierten Lesen).
        // `withoutActuallyEscaping` erlaubt genau das fuer die Dauer des
        // Aufrufs, ohne sie wirklich zu speichern.
        try withoutActuallyEscaping(progress) { progress in
            try withoutActuallyEscaping(isCancelled) { isCancelled in
                try runImport(sources: sources, progress: progress, isCancelled: isCancelled)
            }
        }
    }

    // Packt Archive aus, die der Nutzer per Finder-Dateifreigabe oder
    // Dateien-App direkt in die Bibliothek gelegt hat (von `rescan` als
    // `archivesFound` gemeldet). Erfolgreich ausgepackte Archive werden
    // danach entfernt; ein fehlgeschlagenes bleibt liegen, damit der Nutzer
    // sieht, worum es geht.
    public func unpackPendingArchives(
        progress: (ImportProgress) -> Void = { _ in },
        isCancelled: () -> Bool = { false }
    ) throws -> ImportReport {
        try withoutActuallyEscaping(progress) { progress in
            try withoutActuallyEscaping(isCancelled) { isCancelled in
                try runUnpackPending(progress: progress, isCancelled: isCancelled)
            }
        }
    }

    // MARK: - Ablauf

    private func runImport(
        sources: [URL],
        progress: @escaping (ImportProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> ImportReport {
        try fileManager.createDirectory(at: library.rootURL, withIntermediateDirectories: true)
        let session = Session()
        session.totalFiles = countPlayable(in: sources, isCancelled: isCancelled)

        for source in sources {
            if session.cancelled || isCancelled() {
                session.cancelled = true
                break
            }
            withAccess(to: source) {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
                    session.failures.append(ImportFailure(
                        path: source.lastPathComponent, reason: "Quelle nicht gefunden."))
                    return
                }
                if isDirectory.boolValue {
                    importDirectory(
                        source, targetFolder: [source.lastPathComponent],
                        session: session, progress: progress, isCancelled: isCancelled)
                } else {
                    importFile(
                        source, targetFolder: [],
                        session: session, progress: progress, isCancelled: isCancelled)
                }
            }
        }

        // Auch nach einem Abbruch wird gespeichert: was kopiert wurde, steht
        // korrekt im Index — kein halber Zustand.
        try library.save()
        return session.report
    }

    private func runUnpackPending(
        progress: @escaping (ImportProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> ImportReport {
        let session = Session()
        let archives = archivesInLibrary()
        session.totalFiles = archives.count

        for archive in archives {
            if isCancelled() {
                session.cancelled = true
                break
            }
            let relative = library.relativePath(for: archive) ?? archive.lastPathComponent
            var folder = relative.split(separator: "/").map(String.init)
            folder.removeLast()

            let failuresBefore = session.failures.count
            unpackArchive(
                archive, targetFolder: folder,
                session: session, progress: progress, isCancelled: isCancelled)
            if session.failures.count == failuresBefore {
                try? fileManager.removeItem(at: archive)
            }
        }

        try library.save()
        return session.report
    }

    // MARK: - Rekursion

    private func importDirectory(
        _ directory: URL,
        targetFolder: [String],
        session: Session,
        progress: @escaping (ImportProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) {
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return }
        // Feste Reihenfolge: dasselbe Quellverzeichnis ergibt immer denselben
        // Ablauf — wichtig fuer nachvollziehbare Berichte und Tests.
        let sorted = children.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        for child in sorted {
            if session.cancelled { return }
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                importDirectory(
                    child, targetFolder: targetFolder + [child.lastPathComponent],
                    session: session, progress: progress, isCancelled: isCancelled)
            } else {
                importFile(
                    child, targetFolder: targetFolder,
                    session: session, progress: progress, isCancelled: isCancelled)
            }
        }
    }

    private func importFile(
        _ fileURL: URL,
        targetFolder: [String],
        session: Session,
        progress: @escaping (ImportProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) {
        if PlaylistScanner.isModFile(fileURL) {
            ingestModule(fileURL, targetFolder: targetFolder, session: session,
                         progress: progress, isCancelled: isCancelled)
        } else if PlaylistScanner.isArchive(fileURL) {
            unpackArchive(fileURL, targetFolder: targetFolder, session: session,
                          progress: progress, isCancelled: isCancelled)
        }
        // Alles andere ist kein Fehler, sondern schlicht nichts fuer uns.
    }

    // Eine Moduldatei aus einer externen Quelle uebernehmen.
    private func ingestModule(
        _ source: URL,
        targetFolder: [String],
        session: Session,
        progress: @escaping (ImportProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) {
        if isCancelled() { session.cancelled = true; return }
        let name = source.lastPathComponent
        session.processedFiles += 1
        progress(session.progress(currentName: name))
        do {
            try coordinatedRead(source) { readable in
                try self.place(readable, name: name, targetFolder: targetFolder,
                               consume: false, session: session)
            }
        } catch {
            session.failures.append(ImportFailure(
                path: Self.joined(targetFolder + [name]),
                reason: "Datei konnte nicht uebernommen werden: \(Self.reason(for: error))"))
        }
    }

    // Ein Archiv auspacken und seinen Inhalt einsortieren. Der Archivname ohne
    // Endung wird zum Ordnernamen: `A/sammlung.zip` landet unter `A/sammlung/`.
    private func unpackArchive(
        _ archive: URL,
        targetFolder: [String],
        session: Session,
        progress: @escaping (ImportProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) {
        if isCancelled() { session.cancelled = true; return }
        let name = archive.lastPathComponent
        session.processedFiles += 1
        progress(session.progress(currentName: name))

        // Zwischenlager im Temp-Verzeichnis: erst dorthin auspacken, dann
        // Datei fuer Datei mit derselben Dedupe-Logik einsortieren wie bei
        // einer normalen Quelle. Da beides auf demselben Volume liegt, ist das
        // spaetere Verschieben nur ein Umhaengen und kostet keinen Platz.
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("savage-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }

        do {
            try coordinatedRead(archive) { readable in
                try PlaylistScanner.unpackArchive(readable, into: staging, isCancelled: isCancelled)
            }
        } catch {
            session.failures.append(ImportFailure(
                path: Self.joined(targetFolder + [name]),
                reason: "Archiv konnte nicht entpackt werden: \(Self.reason(for: error))"))
            return
        }
        if isCancelled() { session.cancelled = true; return }

        let nodeName = (name as NSString).deletingPathExtension
        ingestStaged(staging, targetFolder: targetFolder + [nodeName],
                     session: session, progress: progress, isCancelled: isCancelled)
    }

    // Ausgepackten Inhalt einsortieren. Dateien werden verschoben statt
    // kopiert — das Zwischenlager wird ohnehin geloescht.
    private func ingestStaged(
        _ directory: URL,
        targetFolder: [String],
        session: Session,
        progress: @escaping (ImportProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) {
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return }
        let sorted = children.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        for child in sorted {
            if session.cancelled { return }
            if isCancelled() { session.cancelled = true; return }
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                ingestStaged(child, targetFolder: targetFolder + [child.lastPathComponent],
                             session: session, progress: progress, isCancelled: isCancelled)
            } else if PlaylistScanner.isModFile(child) {
                let name = child.lastPathComponent
                session.processedFiles += 1
                progress(session.progress(currentName: name))
                do {
                    try place(child, name: name, targetFolder: targetFolder,
                              consume: true, session: session)
                } catch {
                    session.failures.append(ImportFailure(
                        path: Self.joined(targetFolder + [name]),
                        reason: "Datei aus dem Archiv konnte nicht uebernommen werden: \(Self.reason(for: error))"))
                }
            }
        }
    }

    // MARK: - Einsortieren mit Dedupe

    // Legt `source` unter `targetFolder` ab und traegt sie in den Index ein.
    //
    // - Liegt dort schon eine inhaltsgleiche Datei, gilt sie als Duplikat und
    //   wird uebersprungen (kein erneutes Kopieren, kein Ueberschreiben).
    // - Liegt dort eine andere Datei mit demselben Namen, wird der naechste
    //   freie Name mit Zaehler gesucht.
    private func place(
        _ source: URL,
        name: String,
        targetFolder: [String],
        consume: Bool,
        session: Session
    ) throws {
        let fingerprint = try ContentHasher.fingerprint(of: source)
        var candidate = name
        var counter = 1

        while true {
            let relative = Self.joined(targetFolder + [candidate])
            let destination = library.rootURL.appendingPathComponent(relative)

            if fileManager.fileExists(atPath: destination.path) {
                let existing = try fingerprintOfExisting(at: destination, relativePath: relative)
                if existing.size == fingerprint.size && existing.hash == fingerprint.hash {
                    session.duplicates.append(relative)
                    // Kam die Datei per Finder in die Bibliothek, fehlt sie
                    // vielleicht noch im Index — dann jetzt nachtragen.
                    if library.item(withRelativePath: relative) == nil {
                        library.upsert(LibraryItem(
                            relativePath: relative, displayName: candidate,
                            fileSize: existing.size, contentHash: existing.hash,
                            addedAt: Date(), modifiedAt: modificationDate(of: destination)))
                    }
                    if consume { try? fileManager.removeItem(at: source) }
                    return
                }
                counter += 1
                candidate = Self.numberedName(for: name, counter: counter)
                continue
            }

            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if consume {
                try fileManager.moveItem(at: source, to: destination)
            } else {
                try fileManager.copyItem(at: source, to: destination)
            }
            library.upsert(LibraryItem(
                relativePath: relative, displayName: candidate,
                fileSize: fingerprint.size, contentHash: fingerprint.hash,
                addedAt: Date(), modifiedAt: modificationDate(of: destination)))
            session.imported.append(relative)
            session.importedBytes += fingerprint.size
            return
        }
    }

    // Fingerabdruck einer bereits in der Bibliothek liegenden Datei. Passen
    // Groesse und Aenderungsdatum zum Index, wird der gespeicherte Wert
    // wiederverwendet — sonst wuerde ein zweiter Import der gleichen Sammlung
    // die halbe Bibliothek erneut durchlesen.
    private func fingerprintOfExisting(at url: URL, relativePath: String) throws -> ContentFingerprint {
        if let known = library.item(withRelativePath: relativePath),
           let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           Int64(values.fileSize ?? -1) == known.fileSize,
           let modified = values.contentModificationDate,
           let indexed = known.modifiedAt,
           abs(modified.timeIntervalSince(indexed)) < 1 {
            return ContentFingerprint(hash: known.contentHash, size: known.fileSize)
        }
        return try ContentHasher.fingerprint(of: url)
    }

    // Freier Name mit Zaehler: `song.mod` wird zu `song-2.mod`.
    //
    // Der Zaehler wandert nur dann vor die Endung, wenn diese wirklich eine
    // Modul-Endung ist. Bei der Amiga-Schreibweise `mod.tune` haengt er hinten
    // an (`mod.tune-2`) — `mod-2.tune` wuerde die Datei unspielbar aussehen
    // lassen, weil dann weder Endung noch `mod.`-Praefix stimmen.
    static func numberedName(for name: String, counter: Int) -> String {
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, ModuleLoader.supportedExtensions.contains(ext.lowercased()) {
            let base = (name as NSString).deletingPathExtension
            return "\(base)-\(counter).\(ext)"
        }
        return "\(name)-\(counter)"
    }

    // MARK: - Helfer

    // Zaehlt vorab, wie viele spielbare Dateien und Archive anstehen — nur
    // dafuer, dass die Fortschrittsanzeige ein Ziel hat.
    private func countPlayable(in sources: [URL], isCancelled: () -> Bool) -> Int {
        var total = 0
        for source in sources {
            if isCancelled() { break }
            withAccess(to: source) {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else { return }
                if isDirectory.boolValue {
                    guard let enumerator = fileManager.enumerator(
                        at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    else { return }
                    while let url = enumerator.nextObject() as? URL {
                        if isCancelled() { return }
                        if PlaylistScanner.isModFile(url) || PlaylistScanner.isArchive(url) { total += 1 }
                    }
                } else if PlaylistScanner.isModFile(source) || PlaylistScanner.isArchive(source) {
                    total += 1
                }
            }
        }
        return total
    }

    // Archive, die direkt in der Bibliothek liegen (per Finder oder
    // Dateien-App abgelegt).
    private func archivesInLibrary() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: library.rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        var result: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if PlaylistScanner.isArchive(url) { result.append(url) }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // Ordner-Auswahl per Dateiauswahl liefert auf Apple-Plattformen eine
    // security-scoped URL; der Zugriff muss geoeffnet und wieder geschlossen
    // werden. Unter Linux gibt es weder Sandbox noch diese Aufrufe.
    private func withAccess(to url: URL, _ body: () -> Void) {
        #if canImport(Darwin)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        #endif
        body()
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func joined(_ components: [String]) -> String {
        components.joined(separator: "/")
    }

    private static func reason(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return (error as NSError).localizedDescription
    }

    // Laufender Stand eines Imports. Bewusst eine Klasse: der Stand wird auch
    // aus Closures heraus fortgeschrieben (koordiniertes Lesen), und ein
    // `inout`-Wert waere dort nicht erlaubt.
    private final class Session {
        var imported: [String] = []
        var duplicates: [String] = []
        var failures: [ImportFailure] = []
        var processedFiles = 0
        var totalFiles = 0
        var importedBytes: Int64 = 0
        var cancelled = false

        func progress(currentName: String) -> ImportProgress {
            ImportProgress(
                processedFiles: processedFiles, totalFiles: totalFiles,
                currentName: currentName, importedBytes: importedBytes)
        }

        var report: ImportReport {
            ImportReport(
                imported: imported, duplicates: duplicates,
                failures: failures, wasCancelled: cancelled)
        }
    }
}

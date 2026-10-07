import Foundation

// Nur fuer die asynchrone stdout-Drainage des bsdtar-Vorabchecks. Dieser Lock
// liegt auf dem Import-Worker, niemals im Audio-Renderblock.
private final class LockedInt64: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 0

    func add(_ increment: Int64) {
        lock.lock()
        value += increment
        lock.unlock()
    }

    func load() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// Sammelt Mod-Dateien aus gedroppten URLs bzw. dem Start-Ordner ein und baut
// daraus eine hierarchische Ordner-Struktur fuer die Playlist-Anzeige.
//
// Kernideen:
// - Jede gefundene Datei wird (wie bisher) in ein Temp-Verzeichnis kopiert,
//   merkt sich aber zusaetzlich ihren relativen Ordner-Pfad (`folderPath`).
//   Daraus baut `buildTree` den Anzeigebaum; `flattenedFiles` liefert die
//   flache Abspiel-Reihenfolge (Tiefensuche) — damit funktionieren
//   Weiter/Zurueck, Shuffle und Playlist-Loop unveraendert ueber alle
//   Ordner hinweg.
// - Archive (.zip/.7z) werden unsichtbar per System-`bsdtar` ins
//   Temp-Verzeichnis entpackt und wie ein Ordner behandelt (Knoten-Name =
//   Archivname ohne Endung). Der Nutzer sieht nie entpackte Dateien im
//   Quell-Ordner; aufgeraeumt wird das Temp-Verzeichnis von der App
//   (Start + Beenden).
public enum PlaylistScanner {

    // Gemeinsame Restgrenzen fuer EINEN Archiv-Aufruf. Der LibraryImporter
    // zieht daraus pro Rekursionsstufe das noch freie Session-Budget ab; so
    // starten innere Archive nicht wieder mit frischen 2 GiB/50.000 Eintraegen.
    public struct ArchiveUnpackLimits: Sendable {
        public let maxUncompressedBytes: Int64
        public let maxEntries: Int

        public init(maxUncompressedBytes: Int64, maxEntries: Int) {
            self.maxUncompressedBytes = maxUncompressedBytes
            self.maxEntries = maxEntries
        }

        public static let `default` = ArchiveUnpackLimits(
            maxUncompressedBytes: ZipArchiveReaderDefaultLimits.maxTotalUncompressedBytes,
            maxEntries: ZipArchiveReaderDefaultLimits.maxEntryCount)
    }

    public struct ArchiveUnpackResult: Sendable {
        public let unsupportedEntries: Int
        public let totalUncompressedBytes: Int64
        public let entryCount: Int
    }

    // Die ZipArchiveReader-Vorgaben muessen auch in Linux-Builds verfuegbar
    // sein, wo Apples Compression-Modul (und damit der Reader-Typ) fehlt.
    private enum ZipArchiveReaderDefaultLimits {
        static let maxTotalUncompressedBytes: Int64 = 2 * 1024 * 1024 * 1024
        static let maxEntryCount = 50_000
    }

    // Eine gefundene Mod-Datei: Temp-Kopie + Original-Anzeigename + Ordner-Pfad
    // relativ zur Drop-/Scan-Wurzel (z.B. ["Chiptunes", "4mat"]).
    public struct Entry: Sendable {
        public let url: URL
        public let displayName: String
        public let folderPath: [String]

        public init(url: URL, displayName: String, folderPath: [String]) {
            self.url = url
            self.displayName = displayName
            self.folderPath = folderPath
        }
    }

    // Ein Ordner-Knoten des Anzeigebaums. `path` ist die mit "/" verbundene
    // Komponenten-Kette und dient als stabile ID fuers Auf-/Zuklappen.
    public struct FolderNode: Sendable {
        public let name: String
        public let path: String
        public var subfolders: [FolderNode]
        public var files: [Entry]
    }

    // Archiv-Endungen, die wie Ordner behandelt werden.
    public static let archiveExtensions: Set<String> = ["zip", "7z"]

    // Wie viele Archiv-Ebenen tief geoeffnet wird. Ein Archiv im Archiv ist in
    // Modul-Sammlungen normal; unbegrenzte Rekursion waere ein Angriffspunkt.
    // `LibraryImporter` benutzt denselben Wert, damit Playlist und Bibliothek
    // gleich tief schauen.
    public static let maxArchiveDepth = 3

    // Mod-Erkennung: bekannte Endungen oder Amiga-Konvention "mod.<name>".
    public static func isModFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        return ModuleLoader.supportedExtensions.contains(ext) || name.hasPrefix("mod.")
    }

    public static func isArchive(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }

    // Schneller Vorab-Check fuer den Start-Ordner: enthaelt das Verzeichnis
    // (rekursiv) mindestens eine Mod-Datei oder ein Archiv?
    public static func directoryContainsPlayableContent(_ dir: URL) -> Bool {
        let fm = FileManager.default
        var visitedDirectories = Set<String>()

        func containsPlayableContent(_ directory: URL) -> Bool {
            let resolved = directory.resolvingSymlinksInPath().standardizedFileURL.path
            guard visitedDirectories.insert(resolved).inserted,
                  let children = try? fm.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey
                    ],
                    options: [.skipsHiddenFiles]) else { return false }
            for child in children {
                let values = try? child.resourceValues(forKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey
                ])
                let readableURL = values?.isSymbolicLink == true
                    ? child.resolvingSymlinksInPath()
                    : child
                let readableValues = values?.isSymbolicLink == true
                    ? try? readableURL.resourceValues(forKeys: [
                        .isDirectoryKey, .isRegularFileKey
                    ])
                    : values
                if readableValues?.isRegularFile == true,
                   isModFile(child) || isArchive(child) {
                    return true
                }
                if readableValues?.isDirectory == true,
                   containsPlayableContent(readableURL) { return true }
            }
            return false
        }
        return containsPlayableContent(dir)
    }

    // MARK: - Einsammeln

    // Kopiert alle Mod-Dateien aus den URLs (Dateien, Ordner rekursiv, Archive
    // entpackt) nach `tempDir` und liefert die Eintraege samt Ordner-Pfad.
    // Beruehrt keinen UI-State — laeuft sicher abseits des Main-Threads.
    public static func collectEntries(from urls: [URL], tempDir: URL) -> [Entry] {
        collectEntries(from: urls, tempDir: tempDir, archiveLimits: .default, maxArchives: 128)
    }

    static func collectEntries(from urls: [URL], tempDir: URL,
                               archiveLimits: ArchiveUnpackLimits, maxArchives: Int) -> [Entry] {
        var remainingBytes = archiveLimits.maxUncompressedBytes
        var remainingEntries = archiveLimits.maxEntries
        var remainingArchives = maxArchives
        let fm = FileManager.default
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        var entries: [Entry] = []
        var activeDirectories = Set<String>()

        // Eine einzelne Datei einsortieren: Mods kopieren, Archive entpacken
        // und deren Inhalt als Unterordner scannen. `archiveDepth` begrenzt
        // Archiv-in-Archiv-Rekursion.
        func handleFile(
            _ fileURL: URL,
            sourceURL: URL? = nil,
            folderPath: [String],
            archiveDepth: Int
        ) {
            // Klassifikation und Anzeigename gehoeren zum vom Nutzer
            // ausgewaehlten Link. Gelesen wird dagegen dessen Ziel, damit die
            // Temp-Kopie nach Ende des Security-Scopes eine echte Datei ist.
            let readableURL = sourceURL ?? fileURL
            // Namen klassifizieren nur regulaere Dateien. Ein leerer Ordner
            // `sammlung.mod`, eine FIFO oder ein toter Link sind trotz passender
            // Endung nicht spielbar; die FIFO duerfte insbesondere nie in einen
            // spaeteren Data(contentsOf:)-Zugriff gelangen.
            let readableValues = try? readableURL.resourceValues(
                forKeys: [.isRegularFileKey])
            guard readableValues?.isRegularFile == true else { return }
            // Archive ZUERST klassifizieren: `mod.collection.zip` matcht sonst
            // die Amiga-Namenskonvention `mod.<name>` und wuerde als
            // unspielbare "Moduldatei" kopiert statt entpackt.
            //
            // Die Tiefengrenze gehoert INNERHALB dieses Zweigs geprueft, nicht
            // in seine Bedingung: Stand sie dort, fiel ein zu tief liegendes
            // Archiv in den Modul-Zweig darunter — und ein `mod.sammlung.zip`
            // landete als unspielbare "Moduldatei" in der Playlist, genau der
            // Fall, den die Reihenfolge oben verhindern soll. `LibraryImporter`
            // trennt beides bereits so.
            if isArchive(fileURL) {
                guard archiveDepth < maxArchiveDepth else { return }
                guard remainingArchives > 0, remainingBytes > 0, remainingEntries > 0 else { return }
                remainingArchives -= 1
                let limits = ArchiveUnpackLimits(maxUncompressedBytes: remainingBytes,
                                                maxEntries: remainingEntries)
                if let (extractedDir, result) = extractArchive(readableURL, tempDir: tempDir, limits: limits) {
                    remainingBytes -= result.totalUncompressedBytes
                    remainingEntries -= result.entryCount
                    // Nach dem Scan bleiben nur die eigenständigen Modul-Kopien.
                    defer { try? fm.removeItem(at: extractedDir) }
                    // Archivname ohne Endung als Ordner-Name — dass es ein
                    // Archiv war, soll man in der Playlist nicht merken.
                    let nodeName = (fileURL.lastPathComponent as NSString).deletingPathExtension
                    scanDirectory(
                        extractedDir,
                        folderPath: folderPath + [nodeName],
                        archiveDepth: archiveDepth + 1,
                        insideExtractedArchive: true)
                }
            } else if isModFile(fileURL) {
                // UUID-Praefix vermeidet Namens-Kollisionen im flachen Temp-Ziel;
                // die UI blendet ihn beim Anzeigen wieder aus (cleanFilename).
                let destURL = tempDir.appendingPathComponent("\(UUID().uuidString)_\(fileURL.lastPathComponent)")
                do {
                    try fm.copyItem(at: readableURL, to: destURL)
                    entries.append(Entry(url: destURL, displayName: fileURL.lastPathComponent, folderPath: folderPath))
                } catch {
                    print("Fehler beim Kopieren: \(error)")
                }
            }
        }

        // Ordner rekursiv absteigen und dabei die relativen Pfad-Komponenten
        // mitfuehren (der fruehere flache enumerator verlor die Hierarchie).
        func scanDirectory(
            _ dir: URL,
            folderPath: [String],
            archiveDepth: Int,
            insideExtractedArchive: Bool
        ) {
            // Nutzer-Symlinks duerfen Ordner verbinden, aber Zyklen nicht zu
            // endloser Rekursion fuehren. Im Entpackverzeichnis erreichen
            // Symlinks diesen Punkt gar nicht, weil der Elterneintrag sie
            // vorher ablehnt.
            let resolved = dir.resolvingSymlinksInPath().standardizedFileURL.path
            guard activeDirectories.insert(resolved).inserted else { return }
            defer { activeDirectories.remove(resolved) }
            guard let children = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: insideExtractedArchive ? [] : [.skipsHiddenFiles]
            ) else { return }
            for child in children {
                // Das eigene Temp-Wurzelverzeichnis nie als Kind mitscannen —
                // sonst wuerden frisch angelegte Kopien erneut eingesammelt,
                // falls tempDir (wie in Tests) innerhalb der Scan-Wurzel liegt.
                // (Die extracted-Unterverzeichnisse DARUNTER werden dagegen
                // gezielt per scanDirectory betreten — nicht ausschliessen.)
                if child.standardizedFileURL.path == tempDir.standardizedFileURL.path { continue }
                let values = try? child.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                // Nur Links aus einem fremden Archiv sind untrusted. Links in
                // der vom Nutzer gewaehlten Sammlung bleiben normale Quellen.
                if insideExtractedArchive, values?.isSymbolicLink == true { continue }
                var followsToDirectory: ObjCBool = false
                let directoryCandidate = values?.isSymbolicLink == true
                    ? child.resolvingSymlinksInPath()
                    : child
                let isDirectory = fm.fileExists(
                    atPath: directoryCandidate.path, isDirectory: &followsToDirectory)
                    && followsToDirectory.boolValue
                if isDirectory {
                    scanDirectory(
                        directoryCandidate,
                        folderPath: folderPath + [child.lastPathComponent],
                        archiveDepth: archiveDepth,
                        insideExtractedArchive: insideExtractedArchive)
                } else {
                    handleFile(
                        child,
                        sourceURL: values?.isSymbolicLink == true
                            ? child.resolvingSymlinksInPath()
                            : nil,
                        folderPath: folderPath,
                        archiveDepth: archiveDepth)
                }
            }
        }

        for url in urls {
            // Drag&Drop liefert ggf. security-scoped URLs (Sandbox) — Zugriff
            // pro Wurzel-URL oeffnen und wieder schliessen. Die API gibt es nur
            // auf Apple-Plattformen; unter Linux existiert weder die Sandbox noch
            // der Aufruf, und der Pfad ist ohnehin direkt lesbar.
            #if canImport(Darwin)
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            #endif
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    scanDirectory(
                        url, folderPath: [], archiveDepth: 0,
                        insideExtractedArchive: false)
                } else {
                    let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
                    handleFile(
                        url,
                        sourceURL: values?.isSymbolicLink == true
                            ? url.resolvingSymlinksInPath()
                            : nil,
                        folderPath: [],
                        archiveDepth: 0)
                }
            }
        }
        return entries
    }

    // Entpackt ein Archiv in ein frisches Unterverzeichnis von `tempDir` und
    // liefert dessen URL (nil bei Fehler).
    //
    // Zwei Wege, eine Weiche:
    // - macOS und Linux nutzen das System-`bsdtar` (libarchive). Das liest Zip
    //   UND 7-Zip, ohne dass das Projekt eine Abhaengigkeit mitschleppt.
    // - iOS hat weder `Process` noch ein Kommandozeilen-Werkzeug. Dort
    //   uebernimmt der eigene `ZipArchiveReader` (reines Swift); `.7z` bleibt
    //   dort unlesbar und wird sauber gemeldet statt still zu scheitern.
    private static func extractArchive(_ archive: URL, tempDir: URL,
                                       limits: ArchiveUnpackLimits) -> (URL, ArchiveUnpackResult)? {
        let dest = tempDir.appendingPathComponent("extracted-\(UUID().uuidString)", isDirectory: true)
        do {
            let result = try unpackArchive(archive, into: dest, limits: limits, isCancelled: { false })
            return (dest, result)
        } catch {
            print("Archiv-Entpacken fehlgeschlagen: \(error)")
            try? FileManager.default.removeItem(at: dest)
            return nil
        }
    }

    // Oeffentlicher Einstieg fuers Entpacken: legt `destination` an und schreibt
    // die spielbaren Eintraege des Archivs dorthin. Wirft bei Fehlern, damit der
    // Aufrufer (z.B. der Bibliotheks-Import) dem Nutzer einen Grund nennen kann.
    // `isCancelled` wird waehrend laengerer Archive regelmaessig abgefragt; ein
    // Abbruch wirft `ArchiveError.cancelled` bzw. `ZipArchiveError.cancelled`.
    //
    // Rueckgabe: Anzahl GEWOLLTER Eintraege, die wegen einer nicht
    // unterstuetzten Kompressionsmethode uebersprungen wurden. Der Aufrufer
    // kann damit ein nur teilweise entpacktes Archiv von einem vollstaendig
    // uebernommenen unterscheiden (und z.B. das Quellarchiv behalten). Auf dem
    // bsdtar-Pfad immer 0 — dort scheitert ein nicht lesbarer Eintrag als
    // ganzer Lauf.
    @discardableResult
    public static func unpackArchive(
        _ archive: URL,
        into destination: URL,
        limits: ArchiveUnpackLimits = .default,
        isCancelled: () -> Bool = { false }
    ) throws -> ArchiveUnpackResult {
        guard limits.maxUncompressedBytes > 0 else {
            throw ArchiveError.archiveTooLarge
        }
        guard limits.maxEntries > 0 else {
            throw ArchiveError.tooManyEntries
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)

        // Weiche nach FORMAT, nicht nach Plattform (seit 1.6.10):
        //
        // `.zip` uebernimmt ueberall der eigene `ZipArchiveReader`. Er braucht
        // keinen Hilfsprozess, und sein Vorfilter schreibt nur Moduldateien und
        // verschachtelte Archive auf die Platte — bei einer 100-MB-Sammlung
        // spart das den Loewenanteil. Zip-Slip, Symlinks, Verschluesselung,
        // Zip64 und unplausible Kompressionsverhaeltnisse lehnt er ab, statt
        // sie zu bereinigen. Frueher galt das nur auf iOS; macOS und Linux
        // liefen ueber `bsdtar` und bekamen von alldem nichts.
        //
        // `.7z` kann der eigene Leser nicht (ein LZMA-Dekoder waere ein eigenes
        // Vorhaben). Dafuer bleibt `bsdtar` — wo es `Process` gibt und das
        // Werkzeug installiert ist. Damit ist die externe Abhaengigkeit von
        // Pflicht zu Kuer geworden: Ohne `bsdtar` laeuft alles weiter, nur
        // `.7z` nicht.
        #if canImport(Compression) || canImport(CZlib)
        if archive.pathExtension.lowercased() == "zip" {
            return try unpackUsingZipReader(
                archive, into: destination, limits: limits, isCancelled: isCancelled)
        }
        #endif
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        // Kein `Process` auf iOS — hier endet der Weg fuer alles, was nicht ZIP ist.
        throw ArchiveError.unsupportedFormat(archive.lastPathComponent)
        #else
        return try unpackUsingBsdtar(
            archive, into: destination, limits: limits, isCancelled: isCancelled)
        #endif
    }

    // Fehler, die beim Entpacken ausserhalb des eigentlichen ZIP-Lesers
    // entstehen koennen (fehlendes Werkzeug, nicht unterstuetztes Format,
    // Nutzerabbruch waehrend des bsdtar-Laufs).
    public enum ArchiveError: Error, LocalizedError {
        case unsupportedFormat(String)
        case toolMissing
        case toolFailed(String, Int32)
        case cancelled
        case archiveTooLarge
        case tooManyEntries

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let name):
                return "Archivformat wird auf dieser Plattform nicht unterstuetzt: \(name)"
            case .toolMissing:
                return "Zum Entpacken fehlt das Systemwerkzeug bsdtar (libarchive)."
            case .toolFailed(let name, let status):
                return "Archiv nicht lesbar (bsdtar Exit \(status)): \(name)"
            case .cancelled:
                return "Entpacken abgebrochen."
            case .archiveTooLarge:
                return "Die gemeinsame Obergrenze fuer entpackte Archivdaten wurde erreicht."
            case .tooManyEntries:
                return "Die gemeinsame Obergrenze fuer Archiveintraege wurde erreicht."
            }
        }
    }

    #if canImport(Compression) || canImport(CZlib)
    // Entpacken ohne Hilfsprozess. Nur ZIP; alles andere (insbesondere `.7z`)
    // wird abgelehnt, damit der Aufrufer den Unterschied melden kann.
    private static func unpackUsingZipReader(
        _ archive: URL,
        into destination: URL,
        limits: ArchiveUnpackLimits,
        isCancelled: () -> Bool
    ) throws -> ArchiveUnpackResult {
        guard archive.pathExtension.lowercased() == "zip" else {
            throw ArchiveError.unsupportedFormat(archive.lastPathComponent)
        }
        // Vorfilter: nur Moduldateien und Archive landen auf der Platte. Bei den
        // grossen Sammlungsarchiven spart das den Loewenanteil an Zeit und
        // Platz. Verschachtelte Archive muessen mit heraus, sonst waere ihr
        // Inhalt auf iOS unerreichbar — und der Bibliotheks-Import haette das
        // aeussere Quellarchiv geloescht, obwohl ein Teil nie ankam.
        let result = try ZipArchiveReader.extract(
            archive: archive,
            to: destination,
            shouldExtract: { isModFile($0) || isArchive($0) },
            limits: ZipArchiveReader.Limits(
                maxTotalUncompressedBytes: limits.maxUncompressedBytes,
                maxEntryUncompressedBytes: min(
                    limits.maxUncompressedBytes,
                    ZipArchiveReader.Limits.default.maxEntryUncompressedBytes),
                maxCompressionRatio: ZipArchiveReader.Limits.default.maxCompressionRatio,
                maxEntryCount: limits.maxEntries),
            isCancelled: isCancelled
        )
        return ArchiveUnpackResult(
            unsupportedEntries: result.unsupportedEntries,
            totalUncompressedBytes: result.totalUncompressedBytes,
            entryCount: result.entryCount)
    }
    #endif

    #if !(os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
    // bsdtar liegt auf macOS und den meisten Linux-Distributionen unter
    // /usr/bin (dort aus dem Paket libarchive-tools). Seit 1.6.10 nur noch fuer
    // `.7z` zustaendig.
    private static func unpackUsingBsdtar(
        _ archive: URL,
        into destination: URL,
        limits: ArchiveUnpackLimits,
        isCancelled: () -> Bool
    ) throws -> ArchiveUnpackResult {
        guard let bsdtar = bsdtarURL else { throw ArchiveError.toolMissing }
        if isCancelled() { throw ArchiveError.cancelled }

        // bsdtar selbst kennt kein Groessenlimit. Deshalb laeuft vor dem
        // Schreiben eine streamende Probe: `-tf` zaehlt alle Archiveintraege,
        // `-xOf` dekomprimiert regulaere Dateidaten nur nach stdout. Der
        // Speicher bleibt blockweise konstant, und ein Limitfehler entsteht,
        // bevor das Zielverzeichnis wachsen kann.
        let entryCount = try countBsdtarOutput(
            executable: bsdtar,
            arguments: ["-t", "-f", archive.path],
            countLines: true,
            limit: Int64(limits.maxEntries),
            archiveName: archive.lastPathComponent,
            isCancelled: isCancelled)
        let totalBytes = try countBsdtarOutput(
            executable: bsdtar,
            arguments: ["-x", "-O", "-f", archive.path],
            countLines: false,
            limit: limits.maxUncompressedBytes,
            archiveName: archive.lastPathComponent,
            isCancelled: isCancelled)

        let process = Process()
        process.executableURL = bsdtar
        process.arguments = ["-x", "-f", archive.path, "-C", destination.path]
        // Fehlermeldungen nicht ins App-Log spammen; Erfolg zaehlt per Exit-Code.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Abbruchfaehig warten statt `waitUntilExit` allein: Das blockierte
        // frueher den Import-Worker bis zum Prozessende, ein grosses oder
        // haengendes Archiv liess sich nicht abbrechen. Der 50-ms-Takt haelt
        // "Abbrechen" fuehlbar sofort, ohne messbare Kosten im Normallauf.
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                throw ArchiveError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // `isRunning` kann kurz vor dem endgueltigen Exit schon false sein —
        // erst waitUntilExit garantiert einen gueltigen terminationStatus.
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ArchiveError.toolFailed(archive.lastPathComponent, process.terminationStatus)
        }
        return ArchiveUnpackResult(
            unsupportedEntries: 0,
            totalUncompressedBytes: totalBytes,
            entryCount: Int(entryCount))
    }

    // Zaehlt bsdtar-stdout ohne ihn vollstaendig in den Speicher zu laden.
    // Der Lesekanal wird asynchron geleert, damit ein volles Pipe-Buffer den
    // Kindprozess nicht blockiert; die Warteschleife kann ihn dadurch auch
    // bei einer FIFO oder einem Nutzerabbruch sicher beenden.
    private static func countBsdtarOutput(
        executable: URL,
        arguments: [String],
        countLines: Bool,
        limit: Int64,
        archiveName: String,
        isCancelled: () -> Bool
    ) throws -> Int64 {
        let process = Process()
        let pipe = Pipe()
        let observed = LockedInt64()
        let outputFinished = DispatchSemaphore(value: 0)

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                outputFinished.signal()
                return
            }
            let increment = countLines
                ? data.reduce(into: Int64(0)) { count, byte in
                    if byte == 0x0A { count += 1 }
                }
                : Int64(data.count)
            observed.add(increment)
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        var exceeded = false
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                throw ArchiveError.cancelled
            }
            if observed.load() > limit {
                exceeded = true
                process.terminate()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        _ = outputFinished.wait(timeout: .now() + 2)
        pipe.fileHandleForReading.readabilityHandler = nil

        let count = observed.load()
        if exceeded || count > limit {
            throw countLines ? ArchiveError.tooManyEntries : ArchiveError.archiveTooLarge
        }
        guard process.terminationStatus == 0 else {
            throw ArchiveError.toolFailed(archiveName, process.terminationStatus)
        }
        return count
    }

    // Vorhandenes System-bsdtar (libarchive), oder nil. Frueher lief der ganze
    // Zweig unter `#if os(macOS)` mit der Begruendung, ausserhalb gebe es kein
    // Process/bsdtar — das stimmt nicht: swift-corelibs-foundation hat Process,
    // und bsdtar liegt unter Linux an derselben Stelle. Statt der Plattform wird
    // jetzt die tatsaechliche Verfuegbarkeit geprueft.
    public static var bsdtarURL: URL? {
        let candidate = URL(fileURLWithPath: "/usr/bin/bsdtar")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }
    #endif

    // MARK: - Baum bauen & abflachen

    // Baut aus den Eintraegen den Anzeigebaum. Sortierung pro Ebene:
    // erst Unterordner (alphabetisch), dann Dateien (alphabetisch) —
    // klassische Baumansicht. Diese Reihenfolge ist zugleich die
    // Abspiel-Reihenfolge (siehe flattenedFiles).
    public static func buildTree(_ entries: [Entry]) -> FolderNode {
        // Zwischenstruktur mit Referenz-Semantik, damit das Einsortieren ohne
        // umstaendliches Kopieren verschachtelter Value-Types auskommt.
        final class MutableNode {
            let name: String
            let path: String
            var subfolders: [String: MutableNode] = [:]
            var files: [Entry] = []
            init(name: String, path: String) {
                self.name = name
                self.path = path
            }
        }

        let root = MutableNode(name: "", path: "")
        for entry in entries {
            var node = root
            for component in entry.folderPath {
                let childPath = node.path.isEmpty ? component : "\(node.path)/\(component)"
                if let existing = node.subfolders[component] {
                    node = existing
                } else {
                    let child = MutableNode(name: component, path: childPath)
                    node.subfolders[component] = child
                    node = child
                }
            }
            node.files.append(entry)
        }

        func freeze(_ node: MutableNode) -> FolderNode {
            let sortedFolders = node.subfolders.values
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map(freeze)
            let sortedFiles = node.files
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            return FolderNode(name: node.name, path: node.path, subfolders: sortedFolders, files: sortedFiles)
        }
        return freeze(root)
    }

    // Flache Abspiel-Reihenfolge: Tiefensuche durch den Baum in Anzeige-
    // Reihenfolge. Index-basierte Logik (Weiter/Zurueck/Shuffle) laeuft damit
    // automatisch ueber Ordner-Grenzen hinweg.
    public static func flattenedFiles(_ node: FolderNode) -> [Entry] {
        var result: [Entry] = []
        for sub in node.subfolders {
            result.append(contentsOf: flattenedFiles(sub))
        }
        result.append(contentsOf: node.files)
        return result
    }
}

import Foundation

// Die Musikbibliothek des Players: ein Ordner voller Moduldateien plus ein
// schlanker Index daneben.
//
// Kernideen:
// - **Der relative Pfad ist die ID.** Auf dem iPhone liegt die Bibliothek im
//   `Documents`-Ordner der App, und dessen absoluter Pfad enthaelt eine UUID,
//   die sich bei jeder Neuinstallation aendert. Ein absoluter Pfad im Index
//   waere danach wertlos; `Chiptunes/4mat/tune.mod` bleibt dagegen gueltig.
// - **Der Index ist nie die einzige Wahrheit.** `Documents` ist ueber die
//   Finder-Dateifreigabe und die Dateien-App sichtbar: Nutzer legen dort
//   Dateien ab und loeschen sie wieder. Deshalb ist `rescan()` Pflichtprogramm
//   und kein Extra — es gleicht Index und Dateisystem ab.
// - **Der Index liegt nicht in der Bibliothek**, sondern in
//   `Application Support`. Was der Nutzer sieht, kann er auch loeschen; eine
//   fremde `.json` zwischen den Modulen waere nur verwirrend.
//
// Die Klasse ist bewusst schlicht gehalten und nicht fuer gleichzeitige
// Schreibzugriffe aus mehreren Threads gedacht (daher `@unchecked Sendable`):
// Import und Abgleich laufen jeweils auf genau einer Hintergrundschlange, die
// UI liest den Stand danach.

// MARK: - Datenmodell

// Ein Eintrag der Bibliothek.
public struct LibraryItem: Codable, Sendable, Hashable {
    // Stabile ID: Pfad relativ zur Bibliothekswurzel, immer mit "/" getrennt.
    public let relativePath: String
    // Reiner Dateiname, so wie er in der Liste erscheint.
    public let displayName: String
    public let fileSize: Int64
    // Hex-Fingerabdruck des Inhalts (siehe `ContentHasher`) fuer Dedupe und
    // die Erkennung von Fremdaenderungen.
    public let contentHash: String
    public let addedAt: Date
    // Aenderungsdatum der Datei zum Zeitpunkt des Indizierens. Optional, damit
    // aeltere Indexdateien ohne dieses Feld weiterhin lesbar bleiben; `rescan`
    // spart damit das erneute Hashen unveraenderter Dateien.
    public let modifiedAt: Date?

    public init(
        relativePath: String,
        displayName: String,
        fileSize: Int64,
        contentHash: String,
        addedAt: Date,
        modifiedAt: Date? = nil
    ) {
        self.relativePath = relativePath
        self.displayName = displayName
        self.fileSize = fileSize
        self.contentHash = contentHash
        self.addedAt = addedAt
        self.modifiedAt = modifiedAt
    }

    // Ordner-Komponenten ohne den Dateinamen, z.B. ["Chiptunes", "4mat"].
    // Passt direkt auf `PlaylistScanner.Entry.folderPath`.
    public var folderPath: [String] {
        var components = relativePath.split(separator: "/").map(String.init)
        if !components.isEmpty { components.removeLast() }
        return components
    }

    // Gilt die Datei auf der Platte als unveraendert gegenueber diesem
    // Indexeintrag?
    //
    // Die Heuristik: Groesse **und** Aenderungsdatum muessen passen, dann wird
    // nicht neu gehasht. Zeitstempel gelten als gleich, wenn sie weniger als
    // eine Sekunde auseinanderliegen — manche Dateisysteme speichern nur ganze
    // Sekunden. Das kann eine Aenderung uebersehen, die Groesse und Zeitstempel
    // exakt erhaelt; beim Ablegen ueber Finder oder Dateien-App kommt das
    // praktisch nicht vor und waere den Preis nicht wert, jede Datei bei jedem
    // Start komplett zu lesen.
    //
    // Ist eines der beiden Merkmale unbekannt (`nil`), gilt die Datei als
    // veraendert — lieber einmal zu viel hashen als eine Aenderung verschlucken.
    // Der Abgleich in `MusicLibrary.rescan` und die Dedupe-Pruefung in
    // `LibraryImporter` haben diese Regel frueher getrennt umgesetzt; liefen sie
    // auseinander, haette derselbe Bestand je nach Weg als geaendert oder als
    // unveraendert gegolten.
    func matchesFileOnDisk(size: Int64?, modifiedAt fileModifiedAt: Date?) -> Bool {
        guard let size, size == fileSize else { return false }
        guard let fileModifiedAt, let indexed = modifiedAt else { return false }
        return abs(fileModifiedAt.timeIntervalSince(indexed)) < 1
    }
}

// Der gespeicherte Index. `formatVersion` erlaubt spaetere Formatwechsel:
// ein neuerer Index wird von einer aelteren App-Version nicht falsch gelesen,
// sondern verworfen (und beim naechsten `rescan` neu aufgebaut).
public struct LibraryIndex: Codable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var items: [LibraryItem]

    public init(formatVersion: Int = LibraryIndex.currentFormatVersion, items: [LibraryItem] = []) {
        self.formatVersion = formatVersion
        self.items = items
    }
}

// Ergebnis des Abgleichs zwischen Index und Dateisystem.
public struct RescanReport: Sendable {
    // Im Dateisystem gefunden, im Index gefehlt (z.B. per Finder abgelegt).
    public let added: [String]
    // Im Index, aber nicht mehr auf der Platte (z.B. in der Dateien-App geloescht).
    public let removed: [String]
    // Bekannt und unveraendert.
    public let unchanged: Int
    // Bekannt, aber Inhalt hat sich geaendert (neu gehasht und aktualisiert).
    public let changed: [String]
    // Per Finder abgelegte Archive, die noch auszupacken sind. Der Abgleich
    // packt bewusst nichts aus — das kann dauern und gehoert in einen
    // sichtbaren, abbrechbaren Vorgang (`LibraryImporter.unpackPendingArchives`).
    public let archivesFound: [String]
    // Wurde der Durchlauf abgebrochen? Dann fehlt der Loesch-Abgleich, weil
    // ueber nicht besuchte Dateien nichts bekannt ist.
    public let wasCancelled: Bool
    // Ist der Verzeichnis-Enumerator auf einen Fehler gestossen (z.B. ein
    // voruebergehend unlesbares Unterverzeichnis)? Der Lauf gilt dann wie ein
    // Abbruch als unvollstaendig: kein Loesch-Abgleich, und auch die
    // Archivliste kann Luecken haben. Der Text ist fuer die Oberflaeche
    // gedacht.
    public let enumerationError: String?

    public init(
        added: [String],
        removed: [String],
        unchanged: Int,
        changed: [String] = [],
        archivesFound: [String],
        wasCancelled: Bool = false,
        enumerationError: String? = nil
    ) {
        self.added = added
        self.removed = removed
        self.unchanged = unchanged
        self.changed = changed
        self.archivesFound = archivesFound
        self.wasCancelled = wasCancelled
        self.enumerationError = enumerationError
    }

    // Sah der Durchlauf garantiert den ganzen Bestand?
    public var isComplete: Bool { !wasCancelled && enumerationError == nil }
}

// MARK: - Bibliothek

public final class MusicLibrary: @unchecked Sendable {
    public let rootURL: URL
    public let indexURL: URL
    public private(set) var index: LibraryIndex

    private let fileManager: FileManager
    // Position jedes Eintrags in `index.items` — ohne diese Tabelle waere jeder
    // Import ein quadratisches Suchen ueber die ganze Bibliothek.
    private var positions: [String: Int] = [:]
    // Wurzelpfad in den Schreibweisen, die das Dateisystem liefern kann
    // (auf macOS ist z.B. /var ein Symlink auf /private/var).
    private let rootPathVariants: [String]

    public init(rootURL: URL, indexURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.indexURL = indexURL
        self.fileManager = fileManager
        self.index = LibraryIndex()
        let plain = rootURL.standardizedFileURL.path
        let resolved = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        self.rootPathVariants = plain == resolved ? [plain] : [plain, resolved]
    }

    // Bibliothek an den plattformueblichen Orten: Inhalt in `Documents`
    // (damit Finder-Dateifreigabe und Dateien-App darauf zeigen), Index in
    // `Application Support` (fuer den Nutzer unsichtbar). Der gespeicherte
    // Index wird gleich mitgeladen.
    public static func onDevice(fileManager: FileManager = .default) throws -> MusicLibrary {
        let documents = try fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let support = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        // Auf iOS ist `Application Support` app-eigen; auf dem Mac teilen sich
        // alle Programme den Ordner, deshalb ein eigenes Unterverzeichnis.
        let folderName = Bundle.main.bundleIdentifier ?? "SavageModPlayer"
        let indexDirectory = support.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        let library = MusicLibrary(
            rootURL: documents,
            indexURL: indexDirectory.appendingPathComponent("library-index.json"),
            fileManager: fileManager
        )
        try library.load()
        return library
    }

    // MARK: - Laden und Speichern

    // Laedt den Index. Fehlt er oder ist er unlesbar, startet die Bibliothek
    // leer — geworfen wird nicht: ein kaputter Index darf die App nicht am
    // Start hindern, `rescan()` baut ihn aus dem Dateisystem wieder auf.
    public func load() throws {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? Self.makeDecoder().decode(LibraryIndex.self, from: data),
              decoded.formatVersion <= LibraryIndex.currentFormatVersion
        else {
            index = LibraryIndex()
            rebuildPositions()
            return
        }
        index = decoded
        rebuildPositions()
    }

    // Schreibt den Index atomar, damit ein Absturz mittendrin keine halbe
    // Datei hinterlaesst.
    public func save() throws {
        try fileManager.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Zugriff

    public func url(for item: LibraryItem) -> URL {
        rootURL.appendingPathComponent(item.relativePath)
    }

    public func item(withRelativePath path: String) -> LibraryItem? {
        guard let position = positions[path], position < index.items.count else { return nil }
        return index.items[position]
    }

    // Anzeigebaum ueber den vorhandenen Playlist-Baum: Ordner alphabetisch vor
    // Dateien, und `PlaylistScanner.flattenedFiles` liefert daraus die
    // Abspielreihenfolge ueber alle Ordner hinweg.
    public func folderTree() -> PlaylistScanner.FolderNode {
        let entries = index.items.map {
            PlaylistScanner.Entry(url: url(for: $0), displayName: $0.displayName, folderPath: $0.folderPath)
        }
        return PlaylistScanner.buildTree(entries)
    }

    // MARK: - Abgleich mit dem Dateisystem

    // Findet Fremdablagen und Fremdloeschungen, aktualisiert den Index und
    // speichert ihn.
    //
    // Damit ein Abgleich ueber tausende Dateien nicht jedes Mal alles neu
    // liest, wird nur gehasht, was sich laut Groesse und Aenderungsdatum
    // geaendert haben koennte — die Regel dazu steht bei
    // `LibraryItem.matchesFileOnDisk`.
    @discardableResult
    public func rescan(isCancelled: () -> Bool = { false }) throws -> RescanReport {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var seen: Set<String> = []
        var added: [String] = []
        var changed: [String] = []
        var archives: [String] = []
        var unchanged = 0
        var cancelled = false
        // Falls der Index doch einmal in der Bibliothek liegt: nie als Inhalt zaehlen.
        let indexRelativePath = relativePath(for: indexURL)

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        // Der errorHandler faengt Enumerationsfehler (etwa ein voruebergehend
        // unlesbares Unterverzeichnis). Ohne ihn endete der Durchlauf still,
        // und alle nicht mehr besuchten Indexeintraege galten faelschlich als
        // geloescht. `true` laesst den Rest weiterlaufen, damit wenigstens
        // alles Erreichbare aktualisiert wird — der Lauf gilt aber als
        // unvollstaendig.
        var enumerationError: String?
        let enumerator = fileManager.enumerator(
            // Unterstützte Dateien aus Archiven duerfen auch in versteckten
            // Ordnern liegen. Der Importer uebernimmt sie vollstaendig; der
            // spaetere Abgleich muss sie deshalb ebenfalls sehen, sonst
            // verschwinden sie beim naechsten Start wieder aus dem Index.
            at: rootURL, includingPropertiesForKeys: keys, options: [],
            errorHandler: { url, error in
                if enumerationError == nil {
                    enumerationError =
                        "Bibliotheks-Abgleich unvollständig — \(url.lastPathComponent): \(error.localizedDescription)"
                }
                return true
            })
        // `enumerator(at:…)` liefert ein Optional: Laesst sich die Wurzel gar
        // nicht durchlaufen, kaeme unten kein einziger Treffer an — und der
        // Loeschabgleich haette JEDEN bekannten Eintrag als verschwunden
        // gewertet und den Index geleert, obwohl der Bestand unveraendert ist.
        // Ein fehlender Enumerator zaehlt deshalb wie ein Enumerationsfehler.
        if enumerator == nil {
            enumerationError =
                "Bibliotheks-Abgleich unvollständig — \(rootURL.lastPathComponent): "
                + "Verzeichnis konnte nicht durchlaufen werden."
        }

        while let fileURL = enumerator?.nextObject() as? URL {
            if isCancelled() { cancelled = true; break }
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            guard let relative = relativePath(for: fileURL), relative != indexRelativePath else { continue }

            if PlaylistScanner.isArchive(fileURL) {
                archives.append(relative)
                continue
            }
            guard PlaylistScanner.isModFile(fileURL) else { continue }

            seen.insert(relative)
            let size = values?.fileSize.map(Int64.init)
            let modified = values?.contentModificationDate

            if let known = item(withRelativePath: relative) {
                if known.matchesFileOnDisk(size: size, modifiedAt: modified) {
                    unchanged += 1
                    continue
                }
                guard let fingerprint = try? ContentHasher.fingerprint(of: fileURL) else { continue }
                if fingerprint.hash == known.contentHash {
                    // Nur der Zeitstempel wanderte (z.B. durch eine Kopie) —
                    // Eintrag auffrischen, damit der naechste Lauf schneller ist.
                    upsert(LibraryItem(
                        relativePath: relative, displayName: known.displayName,
                        fileSize: fingerprint.size, contentHash: fingerprint.hash,
                        addedAt: known.addedAt, modifiedAt: modified))
                    unchanged += 1
                } else {
                    upsert(LibraryItem(
                        relativePath: relative, displayName: known.displayName,
                        fileSize: fingerprint.size, contentHash: fingerprint.hash,
                        addedAt: known.addedAt, modifiedAt: modified))
                    changed.append(relative)
                }
            } else {
                guard let fingerprint = try? ContentHasher.fingerprint(of: fileURL) else { continue }
                upsert(LibraryItem(
                    relativePath: relative,
                    displayName: fileURL.lastPathComponent,
                    fileSize: fingerprint.size,
                    contentHash: fingerprint.hash,
                    addedAt: Date(),
                    modifiedAt: modified))
                added.append(relative)
            }
        }

        // Loeschungen darf nur ein vollstaendiger Durchlauf feststellen: nach
        // einem Abbruch ODER Enumerationsfehler ist ueber die nicht besuchten
        // Dateien nichts bekannt.
        var removed: [String] = []
        if !cancelled, enumerationError == nil {
            removed = index.items.map(\.relativePath).filter { !seen.contains($0) }
            if !removed.isEmpty {
                let gone = Set(removed)
                index.items.removeAll { gone.contains($0.relativePath) }
                rebuildPositions()
            }
        }

        try save()
        return RescanReport(
            added: added, removed: removed, unchanged: unchanged, changed: changed,
            archivesFound: archives, wasCancelled: cancelled,
            enumerationError: enumerationError)
    }

    // MARK: - Entfernen

    // Loescht die Datei, den Indexeintrag und leer gewordene Elternordner.
    public func remove(_ item: LibraryItem) throws {
        let fileURL = url(for: item)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        index.items.removeAll { $0.relativePath == item.relativePath }
        rebuildPositions()
        pruneEmptyDirectories(startingAt: fileURL.deletingLastPathComponent())
        try save()
    }

    // Leert die Bibliothek: alles unterhalb der Wurzel und den ganzen Index.
    // Die Wurzel selbst bleibt bestehen, damit sofort wieder importiert werden
    // kann. Der ausfuehrlichere Weg mit Bericht ist `LibraryReset.reset`.
    public func removeAll() throws {
        if let children = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil, options: []) {
            for child in children {
                try? fileManager.removeItem(at: child)
            }
        }
        try clearIndex(removeFile: false)
    }

    // MARK: - Interne Helfer (paketintern, von Importer und Reset genutzt)

    // Fuegt einen Eintrag ein oder ersetzt den vorhandenen mit demselben Pfad.
    func upsert(_ item: LibraryItem) {
        if let position = positions[item.relativePath], position < index.items.count {
            index.items[position] = item
        } else {
            index.items.append(item)
            positions[item.relativePath] = index.items.count - 1
        }
    }

    // Index leeren; `removeFile` entscheidet, ob die Indexdatei geloescht oder
    // durch einen leeren Index ersetzt wird.
    func clearIndex(removeFile: Bool) throws {
        index = LibraryIndex()
        positions = [:]
        if removeFile {
            if fileManager.fileExists(atPath: indexURL.path) {
                try fileManager.removeItem(at: indexURL)
            }
        } else {
            try save()
        }
    }

    // Pfad relativ zur Bibliothekswurzel, oder nil wenn die URL ausserhalb liegt.
    func relativePath(for url: URL) -> String? {
        if let match = matchRootPrefix(url.standardizedFileURL.path) { return match }
        // Erst wenn die guenstige Variante nicht passt, den teuren Weg ueber
        // aufgeloeste Symlinks gehen.
        return matchRootPrefix(url.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    private func matchRootPrefix(_ path: String) -> String? {
        for base in rootPathVariants where path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        return nil
    }

    private func rebuildPositions() {
        positions = [:]
        for (offset, item) in index.items.enumerated() {
            positions[item.relativePath] = offset
        }
    }

    // Nach dem Loeschen einer Datei leere Ordner bis zur Wurzel mitnehmen —
    // sonst bleiben in der Dateien-App leere Huellen stehen.
    private func pruneEmptyDirectories(startingAt directory: URL) {
        var current = directory.standardizedFileURL
        while relativePath(for: current) != nil {
            let contents = (try? fileManager.contentsOfDirectory(atPath: current.path)) ?? []
            guard contents.isEmpty else { return }
            try? fileManager.removeItem(at: current)
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }
}

// MARK: - Fingerabdruck

// Groesse und Inhalts-Fingerabdruck einer Datei.
struct ContentFingerprint {
    let hash: String
    let size: Int64
}

// Schneller 128-Bit-Fingerabdruck ueber den Dateiinhalt.
//
// Warum keine fertige Bibliothek: CryptoKit gibt es unter Linux nicht, und
// eine Fremdabhaengigkeit nur fuers Dedupe waere zu viel. Warum kein SHA-256
// von Hand: der Fingerabdruck ist kein Sicherheitsmerkmal, sondern beantwortet
// nur "ist das dieselbe Datei wie die, die schon da liegt?". Dafuer genuegt ein
// gut durchmischender 128-Bit-Wert, und der ist um ein Vielfaches schneller —
// auf einem Telefon mit einer grossen Sammlung ist das der Unterschied
// zwischen "laeuft" und "dauert ewig".
//
// Gelesen wird blockweise: eine 100-MB-Datei am Stueck in den Speicher zu
// ziehen, beendet die App auf einem iPhone.
enum ContentHasher {
    static let blockSize = 256 * 1024

    static func fingerprint(of url: URL) throws -> ContentFingerprint {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var state = State()
        while let chunk = try handle.read(upToCount: blockSize), !chunk.isEmpty {
            state.update(chunk)
        }
        return ContentFingerprint(hash: state.finalize(), size: Int64(state.byteCount))
    }

    // Zwei unabhaengige 64-Bit-Spuren, die je acht Bytes auf einmal
    // verarbeiten. Am Ende wird die Gesamtlaenge mit eingeruehrt, damit
    // gleiche Bytes bei unterschiedlicher Laenge nicht denselben Wert ergeben.
    private struct State {
        private static let prime1: UInt64 = 0x9E37_79B1_85EB_CA87
        private static let prime2: UInt64 = 0xC2B2_AE3D_27D4_EB4F

        var lane0: UInt64 = 0xCBF2_9CE4_8422_2325
        var lane1: UInt64 = 0x9E37_79B9_7F4A_7C15
        var byteCount: UInt64 = 0
        // Bytes, die am Blockende uebrig bleiben (immer weniger als acht).
        var pending: [UInt8] = []

        mutating func update(_ data: Data) {
            byteCount += UInt64(data.count)
            data.withUnsafeBytes { raw in
                var offset = 0
                // Erst den Rest des Vorgaengerblocks auf acht Bytes auffuellen.
                if !pending.isEmpty {
                    while pending.count < 8 && offset < raw.count {
                        pending.append(raw[offset])
                        offset += 1
                    }
                    if pending.count == 8 {
                        mix(word(from: pending))
                        pending.removeAll(keepingCapacity: true)
                    }
                }
                while offset + 8 <= raw.count {
                    // `littleEndian` haelt das Ergebnis plattformunabhaengig.
                    let value = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                    mix(UInt64(littleEndian: value))
                    offset += 8
                }
                while offset < raw.count {
                    pending.append(raw[offset])
                    offset += 1
                }
            }
        }

        mutating func finalize() -> String {
            if !pending.isEmpty {
                // Die Restlaenge in die oberen Bits schreiben, damit "ab" und
                // "ab\0" verschieden bleiben (bei unter acht Bytes sind die
                // Bits ab 56 garantiert frei).
                mix(word(from: pending) | (UInt64(pending.count) << 56))
            }
            mix(byteCount)
            return hex(avalanche(lane0)) + hex(avalanche(lane1))
        }

        private mutating func mix(_ word: UInt64) {
            lane0 = rotateLeft(lane0 ^ (word &* Self.prime1), by: 31) &* Self.prime2
            lane1 = (lane1 &+ (word ^ Self.prime2)) &* Self.prime1
            lane1 ^= lane1 >> 29
        }

        private func word(from bytes: [UInt8]) -> UInt64 {
            var value: UInt64 = 0
            for (offset, byte) in bytes.enumerated() {
                value |= UInt64(byte) << (8 * UInt64(offset))
            }
            return value
        }

        private func rotateLeft(_ value: UInt64, by amount: UInt64) -> UInt64 {
            (value << amount) | (value >> (64 - amount))
        }

        // Letztes Durchmischen: verteilt auch kleine Unterschiede ueber alle Bits.
        private func avalanche(_ value: UInt64) -> UInt64 {
            var z = value
            z ^= z >> 30
            z = z &* 0xBF58_476D_1CE4_E5B9
            z ^= z >> 27
            z = z &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return z
        }

        private func hex(_ value: UInt64) -> String {
            let digits = String(value, radix: 16)
            return String(repeating: "0", count: 16 - digits.count) + digits
        }
    }
}

import Foundation

// Der Reader braucht einen streamenden DEFLATE-Dekomprimierer. Den liefert auf
// Apple-Plattformen das Framework `Compression`, unter Linux die zlib des
// Systems (Modul `CZlib`, siehe Package.swift). Nur wenn beides fehlt, steuert
// diese Datei nichts bei — dann bleibt es beim externen `bsdtar`.
//
// Der Unterschied steckt in genau einer Funktion weiter unten (`inflate`);
// alles andere — Verzeichnis lesen, Grenzen pruefen, Zip-Slip und Symlinks
// abweisen, blockweise schreiben — ist plattformneutral.
#if canImport(Compression) || canImport(CZlib)
#if canImport(Compression)
import Compression
#else
import CZlib
#endif

// ZIP-Archive lesen und entpacken — ohne Hilfsprozess, ohne Fremdbibliothek.
//
// Warum ueberhaupt selbst gebaut: auf iOS gibt es weder `Process` noch
// `/usr/bin/bsdtar`. Der reale Bestand besteht aber ueberwiegend aus
// ZIP-Sammlungen (einzelne ueber 100 MB), also ist das Entpacken kein Randfall,
// sondern der Hauptweg, wie Musik auf das Geraet kommt.
//
// Aufbau einer ZIP-Datei (stark vereinfacht):
//
//   [Local File Header + Nutzdaten] [Local File Header + Nutzdaten] ...
//   [Central Directory: ein Eintrag je Datei]
//   [End of Central Directory (EOCD)]
//
// Gelesen wird streng von hinten nach vorn: erst das EOCD (es steht am
// Dateiende und verweist auf das Central Directory), dann das Central Directory
// (die verlaessliche Inhaltsliste), und erst dann pro Eintrag der Local File
// Header direkt vor den Nutzdaten. Das Central Directory ist die Wahrheit —
// der Local File Header wird nur gelesen, weil nur er verraet, wie lang sein
// Name und sein Extra-Feld wirklich sind (und damit, wo die Nutzdaten anfangen).
//
// Drei Dinge sind hier sicherheitsrelevant und deshalb ausfuehrlich kommentiert:
// Zip-Slip (Eintragsnamen, die aus dem Zielordner herausfuehren), Zip-Bomben
// (winzige Archive, die sich zu Gigabytes aufblasen) und der Speicherverbrauch
// (auf einem Telefon wird ein Prozess ohne Vorwarnung beendet). Deshalb wird
// grundsaetzlich in Bloecken gestreamt: der Speicherbedarf haengt nicht an der
// Archivgroesse.

// MARK: - Fehler

public enum ZipArchiveError: Error, LocalizedError {
    /// Datei laesst sich nicht oeffnen oder lesen.
    case cannotOpenArchive(String)
    /// Der Pfad zeigt nicht auf eine gewoehnliche Datei (etwa auf eine benannte
    /// Pipe oder ein Geraet).
    case notARegularFile(String)
    /// Kein EOCD gefunden — die Datei ist kein ZIP (oder abgeschnitten).
    case notAZipArchive
    /// Struktur passt nicht zusammen (Signatur, Laenge, Offset).
    case corruptArchive(String)
    /// ZIP64 erkannt. Bewusst nicht unterstuetzt, aber sauber gemeldet.
    case unsupportedZip64
    /// Eintrag ist passwortgeschuetzt.
    case encryptedEntry(String)
    /// Eintragsname fuehrt aus dem Zielordner heraus (Zip-Slip).
    case unsafeEntryPath(String)
    /// Zwei zu entpackende Eintraege treffen dieselbe Zieldatei — exakt
    /// gleicher Name oder nur auf case-/normalisierungs-insensitiven
    /// Dateisystemen (APFS auf iOS/macOS) kollidierende Schreibweisen.
    case duplicateEntryPath(String)
    /// Eintrag ist ein symbolischer Link — wird nie angelegt.
    case symbolicLinkEntry(String)
    /// Mehr Eintraege als erlaubt.
    case tooManyEntries(Int)
    /// Ein einzelner Eintrag sprengt die Groessengrenze.
    case entryTooLarge(String)
    /// Die Summe aller entpackten Daten sprengt die Grenze.
    case archiveTooLarge
    /// Ein Eintrag blaeht sich staerker auf als erlaubt (Zip-Bombe).
    case compressionRatioExceeded(String)
    /// CRC32 der entpackten Daten passt nicht zur Angabe im Archiv.
    case checksumMismatch(String)
    /// Der Deflate-Strom ist defekt.
    case decompressionFailed(String)
    /// Zieldatei liess sich nicht anlegen oder beschreiben.
    case writeFailed(String)
    /// Der Aufrufer hat abgebrochen.
    case cancelled
    /// Eine uebergebene Obergrenze aus `Limits` ist unbrauchbar (z.B. negativ).
    case invalidLimit(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenArchive(let name):
            return "Archiv „\(name)“ lässt sich nicht öffnen."
        case .notARegularFile(let name):
            return "„\(name)“ ist keine gewöhnliche Datei und wird nicht gelesen."
        case .notAZipArchive:
            return "Datei ist kein ZIP-Archiv (kein End-of-Central-Directory gefunden)."
        case .corruptArchive(let detail):
            return "ZIP-Archiv ist beschädigt: \(detail)"
        case .unsupportedZip64:
            return "ZIP64-Archive werden nicht unterstützt (Archiv oder Eintrag über 4 GB bzw. mehr als 65535 Einträge)."
        case .encryptedEntry(let name):
            return "Eintrag „\(name)“ ist passwortgeschützt und kann nicht entpackt werden."
        case .unsafeEntryPath(let name):
            return "Eintrag „\(name)“ hat einen unsicheren Pfad und wurde abgelehnt."
        case .duplicateEntryPath(let name):
            return "Eintrag „\(name)“ trifft dieselbe Zieldatei wie ein früherer Eintrag und wurde abgelehnt."
        case .symbolicLinkEntry(let name):
            return "Eintrag „\(name)“ ist ein symbolischer Link und wurde abgelehnt."
        case .tooManyEntries(let count):
            return "Archiv enthält zu viele Einträge (\(count))."
        case .entryTooLarge(let name):
            return "Eintrag „\(name)“ ist entpackt größer als erlaubt."
        case .archiveTooLarge:
            return "Das Archiv ist entpackt insgesamt größer als erlaubt."
        case .compressionRatioExceeded(let name):
            return "Eintrag „\(name)“ bläht sich beim Entpacken unplausibel stark auf (Verdacht auf ZIP-Bombe)."
        case .checksumMismatch(let name):
            return "Prüfsumme von „\(name)“ stimmt nicht — der Eintrag ist beschädigt."
        case .decompressionFailed(let name):
            return "Eintrag „\(name)“ lässt sich nicht entpacken (defekter Deflate-Strom)."
        case .writeFailed(let path):
            return "Zieldatei „\(path)“ lässt sich nicht schreiben."
        case .cancelled:
            return "Entpacken abgebrochen."
        case .invalidLimit(let detail):
            return "Ungültige Obergrenze für das Entpacken: \(detail)"
        }
    }
}

// MARK: - Reader

public enum ZipArchiveReader {

    // MARK: Grenzen

    /// Obergrenzen gegen ZIP-Bomben. Die Voreinstellungen sind auf ein iPhone
    /// mit einer grossen Modul-Sammlung ausgelegt: grosszuegig genug fuer
    /// echte Sammlungsarchive, eng genug, dass ein praeparierter Mini-ZIP den
    /// Speicher oder die Platte nicht fluten kann.
    public struct Limits: Sendable {
        /// Summe aller entpackten Bytes ueber alle Eintraege.
        public var maxTotalUncompressedBytes: Int64
        /// Entpackte Groesse eines einzelnen Eintrags.
        public var maxEntryUncompressedBytes: Int64
        /// Verhaeltnis entpackt/komprimiert je Eintrag. Wird waehrend des
        /// Entpackens laufend geprueft, nicht nur gegen die (leicht gefaelschte)
        /// Angabe im Archivkopf. Deflate schafft hoechstens rund 1032:1, ein
        /// Wert in dieser Groessenordnung waere also wirkungslos.
        public var maxCompressionRatio: Double
        /// Anzahl Eintraege im Central Directory. Ohne ZIP64 sind ohnehin nur
        /// 65535 moeglich.
        public var maxEntryCount: Int

        public init(
            maxTotalUncompressedBytes: Int64 = 2 * 1024 * 1024 * 1024,
            maxEntryUncompressedBytes: Int64 = 256 * 1024 * 1024,
            maxCompressionRatio: Double = 200,
            maxEntryCount: Int = 50_000
        ) {
            self.maxTotalUncompressedBytes = maxTotalUncompressedBytes
            self.maxEntryUncompressedBytes = maxEntryUncompressedBytes
            self.maxCompressionRatio = maxCompressionRatio
            self.maxEntryCount = maxEntryCount
        }

        public static let `default` = Limits()

        /// Prueft die Grenzen, bevor mit ihnen gerechnet wird. Alle Felder sind
        /// oeffentlich schreibbar; ein negativer `maxEntryCount` fuehrte zuvor
        /// zu einer negativen Reservierung und damit zu einem Abbruch des
        /// ganzen Prozesses statt zu einem normalen Fehler.
        func validated() throws {
            guard maxEntryCount >= 1 else {
                throw ZipArchiveError.invalidLimit("maxEntryCount \(maxEntryCount) (mindestens 1)")
            }
            guard maxEntryUncompressedBytes >= 1 else {
                throw ZipArchiveError.invalidLimit(
                    "maxEntryUncompressedBytes \(maxEntryUncompressedBytes) (mindestens 1)")
            }
            guard maxTotalUncompressedBytes >= 1 else {
                throw ZipArchiveError.invalidLimit(
                    "maxTotalUncompressedBytes \(maxTotalUncompressedBytes) (mindestens 1)")
            }
            guard maxCompressionRatio.isFinite, maxCompressionRatio >= 1 else {
                throw ZipArchiveError.invalidLimit(
                    "maxCompressionRatio \(maxCompressionRatio) (mindestens 1)")
            }
        }
    }

    // MARK: Ergebnistypen

    /// Metadaten eines Archiv-Eintrags — ohne ihn zu entpacken. Damit kann die
    /// Oberflaeche vorab zaehlen und einen Fortschritt anzeigen.
    public struct Entry: Sendable {
        /// Relativer Pfad im Archiv, z.B. "Coolpack/sub/beta.mod".
        public let path: String
        public let uncompressedSize: Int64
        public let compressedSize: Int64
        /// Verzeichniseintrag (Name endet im Archiv auf "/").
        public let isDirectory: Bool
        /// Methode 0 oder 8, unverschluesselt und kein symbolischer Link.
        public let isSupported: Bool
    }

    public struct ExtractionResult: Sendable {
        /// Absolute URLs der tatsaechlich geschriebenen Dateien.
        public let extractedFiles: [URL]
        /// Eintraege, die der Vorfilter aussortiert hat oder die nicht
        /// unterstuetzt sind (inklusive Verzeichniseintraege).
        public let skippedEntries: Int
        /// Teilmenge von `skippedEntries`: GEWOLLTE Eintraege, die nur wegen
        /// einer nicht unterstuetzten Kompressionsmethode (weder stored noch
        /// deflate) uebersprungen wurden. Der Aufrufer kann damit erkennen,
        /// dass das Archiv nicht vollstaendig uebernommen wurde.
        public let unsupportedEntries: Int
        /// Summe der geschriebenen Bytes.
        public let totalUncompressedBytes: Int64
        /// Zahl aller Eintraege im Central Directory, auch wenn der Vorfilter
        /// sie nicht schreiben wollte. Das gemeinsame rekursive Importbudget
        /// muss jede verschachtelte Inhaltsliste zaehlen.
        public let entryCount: Int
    }

    // MARK: Konstanten

    /// Blockgroesse fuer Lesen und Schreiben. 64 KiB ist der uebliche
    /// Kompromiss: gross genug fuer wenige Syscalls, klein genug, dass der
    /// Speicherbedarf konstant und winzig bleibt.
    private static let blockSize = 64 * 1024

    /// Das EOCD steht am Dateiende, kann aber bis zu 64 KB Kommentar hinter
    /// sich haben. Deshalb wird in diesem Fenster rueckwaerts gesucht.
    private static let eocdSearchWindow = 64 * 1024 + 22

    /// Obergrenze fuer das am Stueck gelesene Central Directory. Schuetzt
    /// davor, dass eine gefaelschte Laengenangabe den Speicher sprengt.
    private static let maxCentralDirectoryBytes = 64 * 1024 * 1024

    /// Bis zu dieser Ausgabemenge wird das Kompressionsverhaeltnis nicht
    /// geprueft. Kleine Dateien haben von Natur aus schraege Verhaeltnisse —
    /// eine 400 KB grosse Textdatei erreicht muehelos 400:1, ohne dass jemand
    /// etwas Boeses vorhat. Erst oberhalb dieser Schwelle wird ein hohes
    /// Verhaeltnis verdaechtig, und mehr als diese Menge kann eine Bombe bis
    /// zur Erkennung ohnehin nicht auf die Platte schreiben.
    private static let ratioGraceBytes: Int64 = 4 * 1024 * 1024

    // Signaturen der drei Strukturen, die gelesen werden, plus der beiden
    // ZIP64-Marker, die zur Ablehnung fuehren.
    private static let signatureLocalFileHeader: UInt32 = 0x0403_4B50
    private static let signatureCentralDirectory: UInt32 = 0x0201_4B50
    private static let signatureEOCD: UInt32 = 0x0605_4B50
    private static let signatureZip64Locator: UInt32 = 0x0706_4B50
    private static let signatureZip64EOCD: UInt32 = 0x0606_4B50
    /// Optionaler Digital-Signature-Record am Ende des Inhaltsverzeichnisses
    /// (ZIP APPNOTE 6.3.10, Abschnitt 4.3.13). Kein Dateieintrag.
    private static let signatureDigitalSignature: UInt32 = 0x0505_4B50

    // MARK: - Oeffentliche API

    /// Liest nur das Inhaltsverzeichnis. Es wird nichts entpackt und nichts
    /// geschrieben.
    public static func inspect(archive: URL, limits: Limits = .default) throws -> [Entry] {
        try limits.validated()
        let handle = try openForReading(archive)
        defer { try? handle.close() }
        return try readCentralDirectory(
            handle: handle,
            archiveName: archive.lastPathComponent,
            maxEntryCount: limits.maxEntryCount
        )
            .map { record in
                Entry(
                    path: record.name,
                    uncompressedSize: Int64(record.uncompressedSize),
                    compressedSize: Int64(record.compressedSize),
                    isDirectory: record.isDirectory,
                    isSupported: record.isSupported
                )
            }
    }

    /// Entpackt die vom Vorfilter gewuenschten Eintraege nach `destination`.
    ///
    /// - Parameter shouldExtract: bekommt eine aus dem Eintragsnamen gebaute
    ///   URL (damit `pathExtension`/`lastPathComponent` funktionieren, z.B. fuer
    ///   `PlaylistScanner.isModFile`). Nur bei `true` wird ueberhaupt
    ///   dekomprimiert — genau darin liegt die Zeit- und Platzersparnis.
    /// - Parameter isCancelled: wird pro Eintrag und pro Datenblock abgefragt.
    ///
    /// Die Verzeichnisstruktur des Archivs bleibt erhalten. Bricht ein Eintrag
    /// mit einem Fehler ab, wird dessen halbfertige Zieldatei entfernt; bereits
    /// vollstaendig geschriebene Dateien bleiben liegen — der Aufrufer verwirft
    /// im Fehlerfall am besten das ganze Zielverzeichnis.
    @discardableResult
    public static func extract(
        archive: URL,
        to destination: URL,
        shouldExtract: (URL) -> Bool,
        limits: Limits = .default,
        isCancelled: () -> Bool = { false }
    ) throws -> ExtractionResult {
        try limits.validated()
        let fileManager = FileManager.default
        let handle = try openForReading(archive)
        defer { try? handle.close() }

        // Das Entry-Limit wird bereits BEIM Parsen des Central Directory
        // erzwungen — nicht erst danach, wenn alle Records samt Namen schon
        // im Speicher stehen.
        let records = try readCentralDirectory(
            handle: handle,
            archiveName: archive.lastPathComponent,
            maxEntryCount: limits.maxEntryCount
        )

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        // Die Wurzel EINMAL aufloesen und danach nur noch diese Fassung
        // verwenden. Auf macOS ist z.B. /tmp ein Symlink auf /private/tmp —
        // ohne Aufloesung wuerde jeder spaetere Vergleich scheitern.
        let root = destination.standardizedFileURL.resolvingSymlinksInPath()

        var extractedFiles: [URL] = []
        var skippedEntries = 0
        var unsupportedEntries = 0
        var totalBytes: Int64 = 0
        // Kanonisch reservierte Zielpfade dieses Archivs. APFS auf iOS/macOS
        // ist case-insensitiv und normalisierungs-insensitiv — "Song.MOD" und
        // "song.mod" (oder NFC-/NFD-Varianten eines Umlauts) traefen dieselbe
        // Datei, und der spaetere Eintrag wuerde den frueheren ueberschreiben.
        var reservedTargets = Set<String>()

        for record in records {
            if isCancelled() { throw ZipArchiveError.cancelled }

            // Pfadpruefung zuerst: ein Name wie "../evil.mod" ist nie harmlos,
            // egal ob der Vorfilter ihn haben wollte. Solche Archive werden
            // komplett abgelehnt statt still zurechtgebogen.
            let components = try safeRelativeComponents(for: record.name)

            // Link und Verschluesselung machen das GESAMTE Archiv ungueltig,
            // auch wenn der Eintrag ein Verzeichnis ist oder der Vorfilter ihn
            // nicht entpacken wollte. Sonst koennte ein Import das Quellarchiv
            // als vollstaendig verarbeitet entfernen, obwohl es verbotene
            // Inhalte nur ausgeblendet hat.
            if record.isSymbolicLink { throw ZipArchiveError.symbolicLinkEntry(record.name) }
            if record.isEncrypted { throw ZipArchiveError.encryptedEntry(record.name) }

            if record.isDirectory {
                // Leere Ordner braucht niemand; die Struktur entsteht ohnehin
                // beim Anlegen der Dateien.
                skippedEntries += 1
                continue
            }

            // Der Vorfilter arbeitet auf einer URL, damit der Aufrufer seine
            // vorhandene Datei-Erkennung unveraendert durchreichen kann.
            guard shouldExtract(URL(fileURLWithPath: record.name)) else {
                skippedEntries += 1
                continue
            }

            guard record.isSupportedMethod else {
                // Andere Verfahren (bzip2, LZMA, …) kommen in Modul-Sammlungen
                // praktisch nicht vor und gelten hier als "uebersprungen" —
                // aber gesondert gezaehlt, damit der Aufrufer das Archiv nicht
                // fuer vollstaendig uebernommen haelt.
                skippedEntries += 1
                unsupportedEntries += 1
                continue
            }

            // Vorabpruefung mit den ANGEGEBENEN Groessen. Das ist nur die
            // billige erste Huerde — die Angabe kann luegen, deshalb wird
            // waehrend des Entpackens erneut geprueft.
            let declaredSize = Int64(record.uncompressedSize)
            guard declaredSize <= limits.maxEntryUncompressedBytes else {
                throw ZipArchiveError.entryTooLarge(record.name)
            }
            guard totalBytes + declaredSize <= limits.maxTotalUncompressedBytes else {
                throw ZipArchiveError.archiveTooLarge
            }

            // Zielpfad exklusiv reservieren: Kollisionen werden abgelehnt,
            // nicht stillschweigend ueberschrieben.
            let canonicalTarget = components
                .map { $0.precomposedStringWithCanonicalMapping.lowercased() }
                .joined(separator: "/")
            guard reservedTargets.insert(canonicalTarget).inserted else {
                throw ZipArchiveError.duplicateEntryPath(record.name)
            }

            let dataOffset = try dataOffsetForEntry(handle: handle, record: record)
            let targetURL = try prepareTargetURL(root: root, components: components, name: record.name)

            let written = try writeEntry(
                record: record,
                dataOffset: dataOffset,
                from: handle,
                to: targetURL,
                limits: limits,
                alreadyWritten: totalBytes,
                isCancelled: isCancelled
            )
            totalBytes += written
            extractedFiles.append(targetURL)
        }

        return ExtractionResult(
            extractedFiles: extractedFiles,
            skippedEntries: skippedEntries,
            unsupportedEntries: unsupportedEntries,
            totalUncompressedBytes: totalBytes,
            entryCount: records.count
        )
    }

    // MARK: - Central Directory

    /// Ein Eintrag aus dem Central Directory — die verlaessliche Inhaltsliste.
    private struct CentralRecord {
        let name: String
        let flags: UInt16
        let method: UInt16
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
        let externalAttributes: UInt32
        let versionMadeBy: UInt16

        /// Bit 0 des General-Purpose-Flags: Eintrag ist verschluesselt.
        /// (Bit 11 = UTF-8-Name wird direkt beim Parsen ausgewertet, Bit 3 =
        /// Data Descriptor ist folgenlos, weil ohnehin die Werte des Central
        /// Directory gelten — siehe Kommentar in `writeEntry`.)
        var isEncrypted: Bool { flags & 0x0001 != 0 }
        var isDirectory: Bool { name.hasSuffix("/") }
        var isSupportedMethod: Bool { method == 0 || method == 8 }

        /// Systeme, die laut ZIP APPNOTE (Abschnitt 4.4.2.2) in den oberen
        /// 16 Bit der externen Attribute einen Unix-Dateimodus ablegen:
        /// 3 = Unix, 19 = OS X (Darwin). Ein von macOS geschriebenes Archiv
        /// traegt haeufig die 19 — wer nur die 3 prueft, uebersieht dessen
        /// Symlinks.
        private static let unixModeHostSystems: Set<UInt16> = [3, 19]

        /// Symbolische Links erkennt man an den oberen 16 Bit der externen
        /// Attribute: dort steht bei diesen Systemen der Dateimodus, und
        /// S_IFLNK ist 0xA000. Die unteren Bits sind DOS-Attribute und hier
        /// uninteressant. Das obere Byte von `versionMadeBy` sagt, welches
        /// System das Archiv geschrieben hat.
        var isSymbolicLink: Bool {
            guard Self.unixModeHostSystems.contains(versionMadeBy >> 8) else { return false }
            let unixMode = (externalAttributes >> 16) & 0xF000
            return unixMode == 0xA000
        }

        var isSupported: Bool { isSupportedMethod && !isEncrypted && !isSymbolicLink }
    }

    /// Oeffnet das Archiv — und stellt zuerst sicher, dass es ueberhaupt eine
    /// gewoehnliche Datei ist.
    ///
    /// Warum der Umweg ueber `open`/`fstat` statt `FileHandle(forReadingFrom:)`:
    /// Eine benannte Pipe (FIFO) mit der Endung `.zip` laesst `open()`
    /// blockieren, solange niemand hineinschreibt — ohne Zeitlimit und ohne
    /// Abbruchmoeglichkeit. Der Bibliotheks-Worker haenge dann fuer immer. Das
    /// fiel auf, als der Leser 1.6.10 auch auf macOS und Linux zustaendig
    /// wurde; auf iOS war so ein Pfad praktisch unerreichbar.
    ///
    /// `O_NONBLOCK` schon beim Oeffnen verhindert genau dieses Warten, und
    /// `fstat` auf den offenen Deskriptor prueft danach am selben Objekt statt
    /// am Pfad — zwischen einer Pfadpruefung und dem Oeffnen liesse sich sonst
    /// tauschen.
    private static func openForReading(_ archive: URL) throws -> FileHandle {
        let descriptor = archive.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_NONBLOCK)
        }
        guard descriptor >= 0 else {
            throw ZipArchiveError.cannotOpenArchive(archive.lastPathComponent)
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            close(descriptor)
            throw ZipArchiveError.cannotOpenArchive(archive.lastPathComponent)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            throw ZipArchiveError.notARegularFile(archive.lastPathComponent)
        }
        // Fuer eine gewoehnliche Datei ist O_NONBLOCK bedeutungslos; zurueck auf
        // die normalen Flags, damit sich der FileHandle wie ueblich verhaelt.
        _ = fcntl(descriptor, F_SETFL, 0)
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Sucht das EOCD, liest das Central Directory am Stueck und zerlegt es.
    /// `maxEntryCount` wird waehrend der Parse-Schleife erzwungen, damit ein
    /// praeparierter 64-MiB-Katalog nicht erst Hunderttausende Records samt
    /// Namens-Strings alloziert, bevor irgendwer das Limit prueft.
    private static func readCentralDirectory(
        handle: FileHandle,
        archiveName: String,
        maxEntryCount: Int
    ) throws -> [CentralRecord] {
        let fileSize = Int64(try handle.seekToEnd())
        guard fileSize >= 22 else { throw ZipArchiveError.notAZipArchive }

        // Rueckwaerts im letzten Fenster nach der EOCD-Signatur suchen. Ein
        // Archivkommentar darf bis zu 64 KB lang sein und steht dahinter.
        let windowSize = Int(min(Int64(eocdSearchWindow), fileSize))
        let windowStart = fileSize - Int64(windowSize)
        let window = try readExactly(handle: handle, at: UInt64(windowStart), count: windowSize)

        var eocdIndex: Int?
        var scan = windowSize - 22
        while scan >= 0 {
            if readUInt32(window, scan) == signatureEOCD {
                // Der Kommentar hinter dem EOCD muss exakt bis zum Dateiende
                // reichen — sonst hat der Bytemustertreffer nichts zu bedeuten.
                let commentLength = Int(readUInt16(window, scan + 20))
                if scan + 22 + commentLength == windowSize {
                    eocdIndex = scan
                    break
                }
            }
            scan -= 1
        }
        guard let eocd = eocdIndex else { throw ZipArchiveError.notAZipArchive }

        let entryCount = readUInt16(window, eocd + 10)
        let directorySize = readUInt32(window, eocd + 12)
        let directoryOffset = readUInt32(window, eocd + 16)

        // ZIP64 erkennen und ablehnen, statt mit den Platzhalterwerten
        // 0xFFFF/0xFFFFFFFF an eine falsche Stelle zu springen.
        if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw ZipArchiveError.unsupportedZip64
        }
        // Direkt vor dem EOCD liegt bei ZIP64 der Locator.
        if eocd >= 20, readUInt32(window, eocd - 20) == signatureZip64Locator {
            throw ZipArchiveError.unsupportedZip64
        }

        guard Int64(directorySize) <= Int64(maxCentralDirectoryBytes) else {
            throw ZipArchiveError.corruptArchive("Inhaltsverzeichnis unplausibel groß")
        }
        guard Int64(directoryOffset) + Int64(directorySize) <= fileSize else {
            throw ZipArchiveError.corruptArchive("Inhaltsverzeichnis liegt außerhalb der Datei")
        }

        let directory = try readExactly(
            handle: handle,
            at: UInt64(directoryOffset),
            count: Int(directorySize)
        )

        var records: [CentralRecord] = []
        // `max(0, …)` ist Absicht: `maxEntryCount` kommt aus dem oeffentlichen
        // `Limits` und wird am API-Einstieg geprueft — eine negative Kapazitaet
        // waere hier aber keine Ausnahme, sondern ein sofortiger Prozessabbruch.
        records.reserveCapacity(max(0, min(Int(entryCount), maxEntryCount)))
        var cursor = 0
        // Vier Byte genuegen, um die naechste Struktur zu erkennen; wie lang sie
        // ist, entscheidet erst ihre Signatur.
        while cursor + 4 <= directory.count {
            let signature = readUInt32(directory, cursor)
            if signature == signatureZip64EOCD { throw ZipArchiveError.unsupportedZip64 }
            if signature == signatureDigitalSignature {
                // Optionaler Digital-Signature-Record (ZIP APPNOTE 6.3.10,
                // Abschnitt 4.3.13): 4 Byte Signatur, 2 Byte Datenlaenge, dann
                // die Daten. Er steht als letzte Struktur hinter den
                // Dateieintraegen und ist selbst kein Eintrag. Streng
                // laengengefuehrt uebersprungen — er muss exakt bis zum Ende des
                // Inhaltsverzeichnisses reichen, sonst gilt das Archiv weiter
                // als beschaedigt.
                guard cursor + 6 <= directory.count else {
                    throw ZipArchiveError.corruptArchive(
                        "Digital-Signature-Record von \(archiveName) ist abgeschnitten")
                }
                let signatureDataLength = Int(readUInt16(directory, cursor + 4))
                guard cursor + 6 + signatureDataLength == directory.count else {
                    throw ZipArchiveError.corruptArchive(
                        "Digital-Signature-Record von \(archiveName) passt nicht ans Ende "
                        + "des Inhaltsverzeichnisses")
                }
                cursor = directory.count
                break
            }
            guard signature == signatureCentralDirectory else {
                throw ZipArchiveError.corruptArchive("unerwartete Signatur im Inhaltsverzeichnis")
            }
            // Limit VOR dem naechsten Record erzwingen (siehe Funktionskommentar).
            guard records.count < maxEntryCount else {
                throw ZipArchiveError.tooManyEntries(max(Int(entryCount), records.count + 1))
            }
            guard cursor + 46 <= directory.count else {
                throw ZipArchiveError.corruptArchive("Eintrag im Inhaltsverzeichnis abgeschnitten")
            }
            let nameLength = Int(readUInt16(directory, cursor + 28))
            let extraLength = Int(readUInt16(directory, cursor + 30))
            let commentLength = Int(readUInt16(directory, cursor + 32))
            let headerEnd = cursor + 46 + nameLength + extraLength + commentLength
            guard headerEnd <= directory.count else {
                throw ZipArchiveError.corruptArchive("Eintrag im Inhaltsverzeichnis abgeschnitten")
            }

            let compressedSize = readUInt32(directory, cursor + 20)
            let uncompressedSize = readUInt32(directory, cursor + 24)
            let localHeaderOffset = readUInt32(directory, cursor + 42)
            // Auch je Eintrag koennen die ZIP64-Platzhalter stehen.
            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF || localHeaderOffset == 0xFFFF_FFFF {
                throw ZipArchiveError.unsupportedZip64
            }

            let flags = readUInt16(directory, cursor + 8)
            let nameStart = directory.startIndex + cursor + 46
            let nameBytes = [UInt8](directory[nameStart ..< nameStart + nameLength])

            records.append(CentralRecord(
                name: decodeEntryName(nameBytes, isUTF8: flags & 0x0800 != 0),
                flags: flags,
                method: readUInt16(directory, cursor + 10),
                crc32: readUInt32(directory, cursor + 16),
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset,
                externalAttributes: readUInt32(directory, cursor + 38),
                versionMadeBy: readUInt16(directory, cursor + 4)
            ))
            cursor = headerEnd
        }

        // Struktur-Abgleich mit dem EOCD: Das Central Directory muss exakt
        // aufgehen (kein Byterest unter 46 Bytes) und genau die deklarierte
        // Eintragszahl enthalten. Abweichungen bedeuten ein kaputtes oder
        // praepariertes Archiv.
        guard cursor == directory.count else {
            throw ZipArchiveError.corruptArchive(
                "Inhaltsverzeichnis von \(archiveName) hat \(directory.count - cursor) Byte Rest")
        }
        guard records.count == Int(entryCount) else {
            throw ZipArchiveError.corruptArchive(
                "Inhaltsverzeichnis von \(archiveName) enthält \(records.count) statt \(entryCount) Einträge")
        }
        return records
    }

    /// Liest den Local File Header und liefert den Byte-Offset, an dem die
    /// Nutzdaten beginnen. Wichtig: Name- und Extra-Laenge werden aus DIESEM
    /// Kopf genommen. Sie duerfen sich von den Angaben im Central Directory
    /// unterscheiden (viele Packer schreiben dort andere Extra-Felder), und wer
    /// die falschen Werte nimmt, landet mitten in den Daten.
    private static func dataOffsetForEntry(handle: FileHandle, record: CentralRecord) throws -> UInt64 {
        let header = try readExactly(handle: handle, at: UInt64(record.localHeaderOffset), count: 30)
        guard readUInt32(header, 0) == signatureLocalFileHeader else {
            throw ZipArchiveError.corruptArchive("kein Local File Header bei „\(record.name)“")
        }
        let nameLength = UInt64(readUInt16(header, 26))
        let extraLength = UInt64(readUInt16(header, 28))
        return UInt64(record.localHeaderOffset) + 30 + nameLength + extraLength
    }

    // MARK: - Pfadsicherheit (Zip-Slip)

    /// Zerlegt den Eintragsnamen in Pfadbestandteile und lehnt alles ab, was
    /// aus dem Zielordner herausfuehren koennte. Bewusst ablehnen statt
    /// bereinigen: ein Archiv mit solchen Namen ist entweder kaputt oder
    /// boesartig, und in beiden Faellen will man es nicht auspacken.
    private static func safeRelativeComponents(for name: String) throws -> [String] {
        guard !name.isEmpty else { throw ZipArchiveError.unsafeEntryPath("(leerer Name)") }
        // Absoluter Pfad, Windows-Trenner, Laufwerksbuchstabe, Null-Byte.
        guard !name.hasPrefix("/") else { throw ZipArchiveError.unsafeEntryPath(name) }
        guard !name.contains("\\") else { throw ZipArchiveError.unsafeEntryPath(name) }
        guard !name.contains("\0") else { throw ZipArchiveError.unsafeEntryPath(name) }
        if hasDriveLetterPrefix(name) { throw ZipArchiveError.unsafeEntryPath(name) }

        let components = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { throw ZipArchiveError.unsafeEntryPath(name) }
        for component in components where component == ".." || component == "." {
            throw ZipArchiveError.unsafeEntryPath(name)
        }
        return components
    }

    /// Erkennt "C:\…" bzw. "C:/…" — ein Windows-Laufwerk hat im Archiv nichts
    /// verloren.
    private static func hasDriveLetterPrefix(_ name: String) -> Bool {
        let characters = Array(name)
        guard characters.count >= 2, characters[1] == ":" else { return false }
        return characters[0].isLetter
    }

    /// Baut die Ziel-URL, legt die Elternordner an und stellt sicher, dass das
    /// Ergebnis wirklich unterhalb der Wurzel liegt.
    private static func prepareTargetURL(root: URL, components: [String], name: String) throws -> URL {
        let target = components.reduce(root) { $0.appendingPathComponent($1) }
        // Rein rechnerische Kontrolle (kann nach der Namenspruefung eigentlich
        // nicht mehr fehlschlagen — als zweites Netz trotzdem da).
        guard isInside(root: root, candidate: target.standardizedFileURL) else {
            throw ZipArchiveError.unsafeEntryPath(name)
        }

        let parent = target.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw ZipArchiveError.writeFailed(parent.lastPathComponent)
        }
        // Und jetzt die eigentlich wichtige Kontrolle: der Elternordner
        // existiert, kann also aufgeloest werden. Lag im Zielverzeichnis schon
        // vorher ein Symlink nach draussen, faellt genau das hier auf.
        let resolvedParent = parent.standardizedFileURL.resolvingSymlinksInPath()
        guard isInside(root: root, candidate: resolvedParent) else {
            throw ZipArchiveError.unsafeEntryPath(name)
        }
        return target
    }

    /// Praefixvergleich auf Pfad-BESTANDTEILEN, nicht auf Zeichen. Sonst gilt
    /// "/a/bc" faelschlich als innerhalb von "/a/b".
    private static func isInside(root: URL, candidate: URL) -> Bool {
        let rootParts = root.pathComponents
        let candidateParts = candidate.pathComponents
        guard candidateParts.count >= rootParts.count else { return false }
        return Array(candidateParts.prefix(rootParts.count)) == rootParts
    }

    // MARK: - Entpacken eines Eintrags

    /// Schreibt einen Eintrag blockweise in seine Zieldatei und liefert die
    /// Anzahl geschriebener Bytes. Bei jedem Fehler wird die halbfertige Datei
    /// wieder entfernt.
    private static func writeEntry(
        record: CentralRecord,
        dataOffset: UInt64,
        from handle: FileHandle,
        to target: URL,
        limits: Limits,
        alreadyWritten: Int64,
        isCancelled: () -> Bool
    ) throws -> Int64 {
        let fileManager = FileManager.default
        // O_EXCL: Die Zieldatei wird exklusiv NEU angelegt statt eine
        // vorhandene zu ueberschreiben. Zusammen mit der Pfad-Reservierung im
        // Aufrufer faengt das auch Kollisionen ab, die erst das Dateisystem
        // sieht (Case-/Normalisierungs-Varianten).
        let descriptor = open(target.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else {
            throw errno == EEXIST
                ? ZipArchiveError.duplicateEntryPath(record.name)
                : ZipArchiveError.writeFailed(target.lastPathComponent)
        }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        var completed = false
        defer {
            try? output.close()
            // Kein halbfertiger Torso auf der Platte: bei Abbruch, Bombe oder
            // CRC-Fehler verschwindet die Datei wieder.
            if !completed { try? fileManager.removeItem(at: target) }
        }

        var checksum = ZipCRC32()
        var produced: Int64 = 0

        // Gemeinsame Kontrolle fuer beide Verfahren: erst pruefen, dann
        // schreiben. `consumed` ist die Menge komprimierter Bytes, die der
        // Dekomprimierer bis hierhin wirklich verbraucht hat.
        func emit(_ bytes: UnsafePointer<UInt8>, _ count: Int, consumed: Int64) throws {
            guard count > 0 else { return }
            let next = produced + Int64(count)
            guard next <= limits.maxEntryUncompressedBytes else {
                throw ZipArchiveError.entryTooLarge(record.name)
            }
            guard alreadyWritten + next <= limits.maxTotalUncompressedBytes else {
                throw ZipArchiveError.archiveTooLarge
            }
            if next > ratioGraceBytes, consumed > 0 {
                let ratio = Double(next) / Double(consumed)
                guard ratio <= limits.maxCompressionRatio else {
                    throw ZipArchiveError.compressionRatioExceeded(record.name)
                }
            }
            checksum.update(bytes, count: count)
            do {
                try output.write(contentsOf: Data(bytes: bytes, count: count))
            } catch {
                throw ZipArchiveError.writeFailed(target.lastPathComponent)
            }
            produced = next
        }

        try handle.seek(toOffset: dataOffset)
        if record.method == 0 {
            try copyStored(
                from: handle,
                byteCount: Int64(record.compressedSize),
                emit: emit,
                isCancelled: isCancelled
            )
        } else {
            try inflate(
                from: handle,
                compressedSize: Int64(record.compressedSize),
                name: record.name,
                emit: emit,
                isCancelled: isCancelled
            )
        }

        // Groesse und Pruefsumme stammen immer aus dem Central Directory —
        // auch bei Eintraegen mit Data Descriptor (Flag-Bit 3), deren Local
        // File Header nur Nullen enthaelt.
        guard produced == Int64(record.uncompressedSize) else {
            throw ZipArchiveError.corruptArchive("Größe von „\(record.name)“ weicht ab")
        }
        guard checksum.value == record.crc32 else {
            throw ZipArchiveError.checksumMismatch(record.name)
        }

        completed = true
        return produced
    }

    /// Methode 0: unkomprimiert, also nur blockweise durchreichen.
    private static func copyStored(
        from handle: FileHandle,
        byteCount: Int64,
        emit: (UnsafePointer<UInt8>, Int, Int64) throws -> Void,
        isCancelled: () -> Bool
    ) throws {
        var remaining = byteCount
        var moved: Int64 = 0
        while remaining > 0 {
            // Ohne diesen Autorelease-Pool waechst der Speicher mit der
            // Dateigroesse: `FileHandle` liefert intern autoreleaste Objekte,
            // und ein Pool wird ausserhalb einer Ereignisschleife nie von
            // selbst geleert. Gemessen an einem 120-MB-Archiv war das der
            // Unterschied zwischen 122 MB und knapp 10 MB Spitzenverbrauch.
            try drainingPool {
                if isCancelled() { throw ZipArchiveError.cancelled }
                let want = Int(min(Int64(blockSize), remaining))
                guard let chunk = try handle.read(upToCount: want), !chunk.isEmpty else {
                    throw ZipArchiveError.corruptArchive("Nutzdaten abgeschnitten")
                }
                moved += Int64(chunk.count)
                try chunk.withUnsafeBytes { raw in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                    try emit(base, chunk.count, moved)
                }
                remaining -= Int64(chunk.count)
            }
        }
    }

    /// Fuehrt einen Schleifendurchlauf in einem Autorelease-Pool aus — dort, wo
    /// es einen gibt.
    ///
    /// Auf Apple-Plattformen liefert jeder `read` ein Objekt, das sonst bis zum
    /// Ende der Schleife liegen bliebe; bei einem grossen Eintrag summierte sich
    /// das zu genau dem Speicherwachstum, das dieser Leser vermeiden soll.
    /// Unter Linux gibt es keine Autorelease-Pools und auch das Problem nicht —
    /// dort laeuft der Block einfach direkt.
    @inline(__always)
    private static func drainingPool<T>(_ body: () throws -> T) rethrows -> T {
        #if canImport(Darwin)
        return try autoreleasepool { try body() }
        #else
        return try body()
        #endif
    }

    /// Methode 8: Deflate, gestreamt.
    ///
    /// Zwei Fassungen, gleicher Vertrag: Es wird je ein Eingabe- und ein
    /// Ausgabeblock von 64 KiB benutzt, der Speicherbedarf haengt also nicht an
    /// der Dateigroesse, und `emit` bekommt jeden fertigen Ausgabeblock samt
    /// der bis dahin verbrauchten Eingabemenge (die geht in die
    /// Verhaeltnispruefung gegen Zip-Bomben).
    ///
    /// Wichtig in beiden Faellen: In einer ZIP-Datei steht "raw DEFLATE" nach
    /// RFC 1951, also OHNE zlib-Rahmen. Apples `COMPRESSION_ZLIB` meint genau
    /// das; bei zlib selbst muss man es mit einem negativen Fenster-Parameter
    /// ausdruecklich verlangen.
#if canImport(Compression)
    private static func inflate(
        from handle: FileHandle,
        compressedSize: Int64,
        name: String,
        emit: (UnsafePointer<UInt8>, Int, Int64) throws -> Void,
        isCancelled: () -> Bool
    ) throws {
        let input = UnsafeMutablePointer<UInt8>.allocate(capacity: blockSize)
        let output = UnsafeMutablePointer<UInt8>.allocate(capacity: blockSize)
        defer {
            input.deallocate()
            output.deallocate()
        }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw ZipArchiveError.decompressionFailed(name)
        }
        defer { compression_stream_destroy(stream) }

        stream.pointee.src_ptr = UnsafePointer(input)
        stream.pointee.src_size = 0
        stream.pointee.dst_ptr = output
        stream.pointee.dst_size = blockSize

        var unreadCompressed = compressedSize   // noch nicht gelesene Archivbytes
        var fed: Int64 = 0                      // in den Dekomprimierer gegebene Bytes
        var flags: Int32 = 0

        while true {
            // Autorelease-Pool je Durchlauf, aus demselben Grund wie in
            // `copyStored`. Der Rueckgabewert sagt, ob der Strom zu Ende ist —
            // aus einem Closure heraus kann die Funktion nicht verlassen werden.
            let finished = try drainingPool { () -> Bool in
                if isCancelled() { throw ZipArchiveError.cancelled }

                // Nachschub holen, sobald der Eingabeblock leer ist.
                if stream.pointee.src_size == 0, flags == 0 {
                    let want = Int(min(Int64(blockSize), unreadCompressed))
                    if want > 0, let chunk = try handle.read(upToCount: want), !chunk.isEmpty {
                        chunk.copyBytes(to: input, count: chunk.count)
                        stream.pointee.src_ptr = UnsafePointer(input)
                        stream.pointee.src_size = chunk.count
                        unreadCompressed -= Int64(chunk.count)
                        fed += Int64(chunk.count)
                    } else {
                        // Keine Eingabe mehr: dem Framework sagen, dass jetzt
                        // der Rest herauskommen soll.
                        flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                    }
                }

                let status = compression_stream_process(stream, flags)
                let producedNow = blockSize - stream.pointee.dst_size
                if producedNow > 0 {
                    // Verbrauchte Eingabe = eingefuettert minus noch offen.
                    // Genau dieser Wert geht in die Verhaeltnispruefung — die
                    // Angabe im Archivkopf waere bei einer Bombe wertlos.
                    let consumed = fed - Int64(stream.pointee.src_size)
                    try emit(output, producedNow, consumed)
                    stream.pointee.dst_ptr = output
                    stream.pointee.dst_size = blockSize
                }

                switch status {
                case COMPRESSION_STATUS_OK:
                    return false
                case COMPRESSION_STATUS_END:
                    return true
                default:
                    throw ZipArchiveError.decompressionFailed(name)
                }
            }
            if finished { return }
        }
    }
#else
    private static func inflate(
        from handle: FileHandle,
        compressedSize: Int64,
        name: String,
        emit: (UnsafePointer<UInt8>, Int, Int64) throws -> Void,
        isCancelled: () -> Bool
    ) throws {
        let input = UnsafeMutablePointer<UInt8>.allocate(capacity: blockSize)
        let output = UnsafeMutablePointer<UInt8>.allocate(capacity: blockSize)
        defer {
            input.deallocate()
            output.deallocate()
        }

        var stream = z_stream()
        // Negatives Fenster = raw DEFLATE ohne zlib-Kopf und ohne Pruefsumme —
        // genau die Form, die in einer ZIP-Datei steht. `inflateInit2` ist ein
        // C-Makro; aus Swift heraus wird die dahinterliegende Funktion mit
        // Version und Strukturgroesse gerufen.
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION,
                            Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ZipArchiveError.decompressionFailed(name)
        }
        defer { inflateEnd(&stream) }

        var unreadCompressed = compressedSize   // noch nicht gelesene Archivbytes
        var fed: Int64 = 0                      // in den Dekomprimierer gegebene Bytes
        var reachedInputEnd = false

        while true {
            if isCancelled() { throw ZipArchiveError.cancelled }

            // Nachschub holen, sobald der Eingabeblock leer ist.
            if stream.avail_in == 0, !reachedInputEnd {
                let want = Int(min(Int64(blockSize), unreadCompressed))
                if want > 0, let chunk = try handle.read(upToCount: want), !chunk.isEmpty {
                    chunk.copyBytes(to: input, count: chunk.count)
                    stream.next_in = input
                    stream.avail_in = uInt(chunk.count)
                    unreadCompressed -= Int64(chunk.count)
                    fed += Int64(chunk.count)
                } else {
                    reachedInputEnd = true
                }
            }

            stream.next_out = output
            stream.avail_out = uInt(blockSize)
            let status = CZlib.inflate(&stream, Z_NO_FLUSH)

            let producedNow = blockSize - Int(stream.avail_out)
            if producedNow > 0 {
                // Verbrauchte Eingabe = eingefuettert minus noch offen.
                let consumed = fed - Int64(stream.avail_in)
                try emit(output, producedNow, consumed)
            }

            switch status {
            case Z_STREAM_END:
                return
            case Z_OK:
                continue
            case Z_BUF_ERROR:
                // Kein Fortschritt moeglich. Solange noch Eingabe nachkommt, ist
                // das nur ein leerer Durchlauf; ist die Eingabe erschoepft und
                // der Strom trotzdem nicht zu Ende, ist das Archiv kaputt.
                if reachedInputEnd && producedNow == 0 {
                    throw ZipArchiveError.decompressionFailed(name)
                }
                continue
            default:
                throw ZipArchiveError.decompressionFailed(name)
            }
        }
    }
#endif

    // MARK: - Dateinamen (UTF-8 oder CP437)

    /// Die obere Haelfte der Codepage 437 (0x80–0xFF), Zeichen fuer Zeichen.
    /// 0x00–0x7F ist mit ASCII identisch und braucht keine Tabelle. Alte
    /// DOS-Packer haben Umlaute so abgelegt; ohne diese Umsetzung heisst eine
    /// Datei "M÷bius" statt "Möbius".
    static let cp437UpperHalf: [Character] = Array(
        "ÇüéâäàåçêëèïîìÄÅ" +          // 0x80–0x8F
        "ÉæÆôöòûùÿÖÜ¢£¥₧ƒ" +          // 0x90–0x9F
        "áíóúñÑªº¿⌐¬½¼¡«»" +          // 0xA0–0xAF
        "░▒▓│┤╡╢╖╕╣║╗╝╜╛┐" +          // 0xB0–0xBF
        "└┴┬├─┼╞╟╚╔╩╦╠═╬╧" +          // 0xC0–0xCF
        "╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀" +          // 0xD0–0xDF
        "αßΓπΣσµτΦΘΩδ∞φε∩" +          // 0xE0–0xEF
        "≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u{00A0}"     // 0xF0–0xFF
    )

    /// Flag-Bit 11 sagt "Name ist UTF-8". Alles andere ist CP437. Ist ein als
    /// UTF-8 markierter Name in Wahrheit kaputt, wird ersatzweise CP437
    /// gelesen — ein unschoener Name ist besser als ein verlorener Eintrag.
    static func decodeEntryName(_ bytes: [UInt8], isUTF8: Bool) -> String {
        if isUTF8, let text = String(bytes: bytes, encoding: .utf8) { return text }
        var result = ""
        result.reserveCapacity(bytes.count)
        for byte in bytes {
            if byte < 0x80 {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result.append(cp437UpperHalf[Int(byte) - 0x80])
            }
        }
        return result
    }

    // MARK: - Kleine Lesehelfer

    /// Liest exakt `count` Bytes ab `offset` — oder wirft. ZIP-Strukturen sind
    /// festlaengig, kurze Lesevorgaenge bedeuten immer ein kaputtes Archiv.
    private static func readExactly(handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw ZipArchiveError.corruptArchive("Datei endet früher als erwartet")
            }
            return data
        } catch let error as ZipArchiveError {
            throw error
        } catch {
            throw ZipArchiveError.corruptArchive("Lesefehler an Position \(offset)")
        }
    }

    // ZIP speichert alle Zahlen little-endian (niederwertiges Byte zuerst).
    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        let index = data.startIndex + offset
        return UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        let index = data.startIndex + offset
        return UInt32(data[index])
            | (UInt32(data[index + 1]) << 8)
            | (UInt32(data[index + 2]) << 16)
            | (UInt32(data[index + 3]) << 24)
    }
}

// MARK: - CRC32

/// Pruefsumme nach IEEE-Polynom (0xEDB88320, das ist das gespiegelte
/// 0x04C11DB7) — genau die Variante, die ZIP je Eintrag ablegt. Die Tabelle
/// nimmt acht Schritte auf einmal vorweg und macht die Berechnung damit
/// byteweise statt bitweise.
struct ZipCRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    // Start- und Endwert sind beide 0xFFFFFFFF-invertiert; das gehoert zur
    // Definition und ist kein Zufallswert.
    private var current: UInt32 = 0xFFFF_FFFF

    var value: UInt32 { current ^ 0xFFFF_FFFF }

    mutating func update(_ bytes: UnsafePointer<UInt8>, count: Int) {
        var running = current
        Self.table.withUnsafeBufferPointer { table in
            for index in 0..<count {
                running = table[Int((running ^ UInt32(bytes[index])) & 0xFF)] ^ (running >> 8)
            }
        }
        current = running
    }
}

#endif

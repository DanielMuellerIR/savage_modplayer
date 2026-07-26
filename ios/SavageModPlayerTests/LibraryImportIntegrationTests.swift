import XCTest
import SavageModPlayerCore
@testable import SavageModPlayer

// Der Nachweis fuer den Import-Weg auf iOS — headless im Simulator.
//
// Warum hier und nicht in der SwiftPM-Suite: auf iOS gibt es weder `Process`
// noch `bsdtar`. Archive werden dort ausschliesslich vom eigenen
// `ZipArchiveReader` ausgepackt. Genau dieser Pfad laeuft nur, wenn der Test auf
// iOS ausgefuehrt wird — auf macOS wuerde stattdessen bsdtar greifen und der
// Test bewiese das Falsche.
//
// Geprueft werden die fuenf Dinge, die beim Import wirklich schiefgehen koennen:
// Struktur, Doppelte, Abbruch, Zuruecksetzen und ein zweiter Import danach.
final class LibraryImportIntegrationTests: XCTestCase {

    private var workDir: URL!
    private var sourceDir: URL!
    private var libraryRoot: URL!
    private var indexURL: URL!

    override func setUpWithError() throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LibraryImport-\(UUID().uuidString)", isDirectory: true)
        sourceDir = workDir.appendingPathComponent("Sammlung", isDirectory: true)
        libraryRoot = workDir.appendingPathComponent("Bibliothek", isDirectory: true)
        indexURL = workDir.appendingPathComponent("index.json")
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try buildSourceTree()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - Testbaum

    // Legt den synthetischen Quellbaum an. Die Moduldateien sind blosse
    // Platzhalter-Bytes: der Import erkennt Module an der Endung und parst sie
    // nicht. Echte Moduldateien duerfen nicht ins Repo, und fuer diesen Nachweis
    // braucht es sie auch nicht.
    private func buildSourceTree() throws {
        try write("root.mod", bytes: 64)
        try write("Chiptunes/tune.mod", bytes: 96)
        try write("Chiptunes/Deep/nested.s3m", bytes: 128)
        try write("Chiptunes/notes.txt", bytes: 32)          // kein Modul — bleibt draussen
        try write("Bilder/cover.png", bytes: 40)             // ebenfalls nicht spielbar

        // Ein im Test erzeugtes ZIP. Es enthaelt eine eigene Unterstruktur und
        // eine nicht spielbare Datei, damit auch der Vorfilter belegt ist.
        let archive = try makeStoredZip(entries: [
            ("Coolpack/alpha.mod", Data(repeating: 0xA1, count: 200)),
            ("Coolpack/sub/beta.xm", Data(repeating: 0xB2, count: 300)),
            ("Coolpack/readme.txt", Data(repeating: 0x21, count: 50))
        ])
        let archiveURL = sourceDir.appendingPathComponent("pack.zip")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try archive.write(to: archiveURL)
    }

    private func write(_ relativePath: String, bytes: Int) throws {
        let url = sourceDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Inhalt vom Pfad ableiten, damit zwei verschiedene Dateien nie zufaellig
        // denselben Hash bekommen (sonst waere der Dedupe-Test wertlos).
        var data = Data(relativePath.utf8)
        data.append(Data(repeating: 0x5A, count: max(0, bytes - data.count)))
        try data.write(to: url)
    }

    // MARK: - Tests

    func testImportKeepsStructureAndUnpacksArchive() throws {
        let library = MusicLibrary(rootURL: libraryRoot, indexURL: indexURL)
        try library.load()
        let importer = LibraryImporter(library: library)

        let report = try importer.importContents(of: [sourceDir])

        XCTAssertFalse(report.wasCancelled)
        XCTAssertTrue(report.failures.isEmpty, "unerwartete Fehler: \(report.failures)")

        let paths = Set(library.index.items.map(\.relativePath))
        XCTAssertTrue(paths.contains("Sammlung/root.mod"), "gefunden: \(paths.sorted())")
        XCTAssertTrue(paths.contains("Sammlung/Chiptunes/tune.mod"))
        XCTAssertTrue(paths.contains("Sammlung/Chiptunes/Deep/nested.s3m"))
        // Das Archiv erscheint als Ordner mit dem Archivnamen ohne Endung.
        XCTAssertTrue(paths.contains("Sammlung/pack/Coolpack/alpha.mod"))
        XCTAssertTrue(paths.contains("Sammlung/pack/Coolpack/sub/beta.xm"))
        // Vorfilter: nichts Unspielbares darf in der Bibliothek landen.
        XCTAssertFalse(paths.contains { $0.hasSuffix(".txt") || $0.hasSuffix(".png") })
        XCTAssertEqual(paths.count, 5)

        // Der Anzeigebaum muss dieselbe Hierarchie zeigen wie die Pfade.
        let tree = library.folderTree()
        let flattened = PlaylistScanner.flattenedFiles(tree)
        XCTAssertEqual(flattened.count, 5)
    }

    func testSecondImportIsFullyDeduplicated() throws {
        let library = MusicLibrary(rootURL: libraryRoot, indexURL: indexURL)
        try library.load()
        let importer = LibraryImporter(library: library)

        let first = try importer.importContents(of: [sourceDir])
        XCTAssertEqual(first.imported.count, 5)

        let second = try importer.importContents(of: [sourceDir])
        XCTAssertEqual(second.imported.count, 0, "zweiter Import darf nichts Neues anlegen")
        XCTAssertEqual(second.duplicates.count, 5)
        XCTAssertEqual(library.index.items.count, 5)
    }

    func testImportCanBeCancelled() throws {
        let library = MusicLibrary(rootURL: libraryRoot, indexURL: indexURL)
        try library.load()
        let importer = LibraryImporter(library: library)

        var seen = 0
        let report = try importer.importContents(
            of: [sourceDir],
            progress: { _ in seen += 1 },
            isCancelled: { seen >= 1 }
        )

        XCTAssertTrue(report.wasCancelled)
        XCTAssertLessThan(report.imported.count, 5)
        // Der Index darf nur enthalten, was wirklich auf der Platte liegt.
        for item in library.index.items {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: library.url(for: item).path),
                "Index verweist auf fehlende Datei: \(item.relativePath)"
            )
        }
    }

    func testResetEmptiesLibraryAndAllowsFreshImport() throws {
        let library = MusicLibrary(rootURL: libraryRoot, indexURL: indexURL)
        try library.load()
        let importer = LibraryImporter(library: library)
        _ = try importer.importContents(of: [sourceDir])
        XCTAssertEqual(library.index.items.count, 5)

        _ = try LibraryReset.reset(library: library)
        XCTAssertTrue(library.index.items.isEmpty)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: libraryRoot.path)
        XCTAssertTrue(remaining.isEmpty, "Bibliothekswurzel nicht leer: \(remaining)")

        // Idempotent: ein zweiter Aufruf darf nicht scheitern.
        XCTAssertNoThrow(try LibraryReset.reset(library: library))

        // Und danach muss ein erneuter Import wieder funktionieren.
        let again = try importer.importContents(of: [sourceDir])
        XCTAssertEqual(again.imported.count, 5)
        XCTAssertEqual(library.index.items.count, 5)
    }

    // MARK: - Minimaler ZIP-Schreiber (nur "stored", ohne Kompression)

    // Baut ein gueltiges ZIP-Archiv im Speicher. Bewusst ohne Kompression: fuer
    // diesen Nachweis zaehlt die Struktur, nicht der Deflate-Pfad — den deckt
    // ZipArchiveReaderTests in der SwiftPM-Suite ab.
    private func makeStoredZip(entries: [(String, Data)]) throws -> Data {
        var output = Data()
        var directory = Data()
        var offsets: [Int] = []

        func appendUInt16(_ value: UInt16, to data: inout Data) {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
        }
        func appendUInt32(_ value: UInt32, to data: inout Data) {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
        }

        for (name, payload) in entries {
            offsets.append(output.count)
            let nameBytes = Data(name.utf8)
            let crc = Self.crc32(payload)

            appendUInt32(0x0403_4B50, to: &output)          // Local File Header
            appendUInt16(20, to: &output)                    // benoetigte Version
            appendUInt16(0x0800, to: &output)                // Flags: Bit 11 = Name ist UTF-8
            appendUInt16(0, to: &output)                     // Methode 0 = stored
            appendUInt16(0, to: &output)                     // Uhrzeit
            appendUInt16(0x21, to: &output)                  // Datum (1980-01-01)
            appendUInt32(crc, to: &output)
            appendUInt32(UInt32(payload.count), to: &output) // komprimiert
            appendUInt32(UInt32(payload.count), to: &output) // unkomprimiert
            appendUInt16(UInt16(nameBytes.count), to: &output)
            appendUInt16(0, to: &output)                     // kein Extra-Feld
            output.append(nameBytes)
            output.append(payload)
        }

        for (index, (name, payload)) in entries.enumerated() {
            let nameBytes = Data(name.utf8)
            let crc = Self.crc32(payload)

            appendUInt32(0x0201_4B50, to: &directory)        // Central Directory Header
            appendUInt16(20, to: &directory)                 // erzeugt von Version
            appendUInt16(20, to: &directory)                 // benoetigte Version
            appendUInt16(0x0800, to: &directory)
            appendUInt16(0, to: &directory)
            appendUInt16(0, to: &directory)
            appendUInt16(0x21, to: &directory)
            appendUInt32(crc, to: &directory)
            appendUInt32(UInt32(payload.count), to: &directory)
            appendUInt32(UInt32(payload.count), to: &directory)
            appendUInt16(UInt16(nameBytes.count), to: &directory)
            appendUInt16(0, to: &directory)                  // Extra
            appendUInt16(0, to: &directory)                  // Kommentar
            appendUInt16(0, to: &directory)                  // Disk
            appendUInt16(0, to: &directory)                  // interne Attribute
            appendUInt32(0, to: &directory)                  // externe Attribute
            appendUInt32(UInt32(offsets[index]), to: &directory)
            directory.append(nameBytes)
        }

        let directoryOffset = output.count
        output.append(directory)

        appendUInt32(0x0605_4B50, to: &output)               // End of Central Directory
        appendUInt16(0, to: &output)                         // Disk-Nummer
        appendUInt16(0, to: &output)                         // Disk mit Central Directory
        appendUInt16(UInt16(entries.count), to: &output)
        appendUInt16(UInt16(entries.count), to: &output)
        appendUInt32(UInt32(directory.count), to: &output)
        appendUInt32(UInt32(directoryOffset), to: &output)
        appendUInt16(0, to: &output)                         // kein Kommentar

        return output
    }

    // CRC32 nach IEEE — dieselbe Pruefsumme, die im ZIP-Format steht.
    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var value = UInt32(i)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            table[i] = value
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

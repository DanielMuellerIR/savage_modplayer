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
        let archive = try ZipTestSupport.makeStoredZip(entries: [
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

    // Ein per Finder/Dateien-App direkt in Documents gelegtes ZIP braucht
    // keinen separaten Knopf: LibraryStore findet es beim Abgleich, packt es
    // automatisch aus und ersetzt das Archiv durch den sichtbaren Ordner.
    @MainActor
    func testStoreAutomaticallyUnpacksArchiveFoundDuringScan() async throws {
        let archive = try ZipTestSupport.makeStoredZip(entries: [
            ("Inside/automatic.it", Data(repeating: 0xC3, count: 256))
        ])
        let archiveURL = libraryRoot.appendingPathComponent("drop.zip")
        try archive.write(to: archiveURL)

        let library = MusicLibrary(rootURL: libraryRoot, indexURL: indexURL)
        try library.load()

        let suiteName = "LibraryStore-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LibraryStore(defaults: defaults, library: library)
        store.start()

        // 60 s statt 5 s: Der Wert ist eine Obergrenze, keine Wartezeit — die
        // Schleife endet, sobald der Import fertig ist (lokal nach ~0,2 s).
        // 5 s waren auf den langsamen GitHub-Runnern zweimal nacheinander zu
        // knapp (CI-Läufe zu v1.6.5 am 2026-08-07), lokal aber nie.
        let deadline = Date().addingTimeInterval(60)
        while store.isBusy, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(store.isBusy, "automatischer ZIP-Import lief in ein Timeout")
        XCTAssertEqual(store.tracks.map(\.relativePath), ["drop/Inside/automatic.it"])
        XCTAssertTrue(store.pendingArchives.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

}

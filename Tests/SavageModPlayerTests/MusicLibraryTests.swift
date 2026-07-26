import XCTest
@testable import SavageModPlayerCore

// Tests fuer die Bibliotheks-Schicht: Index laden/speichern, Abgleich mit dem
// Dateisystem (Fremdablagen und Fremdloeschungen), Anzeigebaum, Loeschen und
// das Zuruecksetzen.
//
// Alle Fixtures entstehen zur Laufzeit in einem Temp-Verzeichnis — im Repo
// liegen keine Moduldateien.
final class MusicLibraryTests: XCTestCase {

    private var workDir: URL!
    private var rootURL: URL!
    private var indexURL: URL!

    override func setUpWithError() throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MusicLibraryTests-\(UUID().uuidString)", isDirectory: true)
        rootURL = workDir.appendingPathComponent("Library", isDirectory: true)
        // Der Index liegt bewusst NEBEN der Bibliothek, nicht darin.
        indexURL = workDir.appendingPathComponent("Support/library-index.json")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - Helfer

    private func makeLibrary() -> MusicLibrary {
        MusicLibrary(rootURL: rootURL, indexURL: indexURL)
    }

    // Legt eine Datei mit unterscheidbarem Inhalt in der Bibliothek ab.
    @discardableResult
    private func writeFile(_ relativePath: String, marker: UInt8 = 0x41) throws -> URL {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: marker, count: 64 + Int(marker)).write(to: url)
        return url
    }

    // Alle Moduldateien, die tatsaechlich auf der Platte liegen.
    private func modulesOnDisk() -> Set<String> {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        var result: Set<String> = []
        let base = rootURL.standardizedFileURL.path
        while let url = enumerator.nextObject() as? URL {
            guard PlaylistScanner.isModFile(url) else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(base + "/") { result.insert(String(path.dropFirst(base.count + 1))) }
        }
        return result
    }

    // MARK: - Index laden und speichern

    func testLoadWithoutIndexFileStartsEmpty() throws {
        let library = makeLibrary()
        XCTAssertNoThrow(try library.load())
        XCTAssertTrue(library.index.items.isEmpty)
        XCTAssertEqual(library.index.formatVersion, LibraryIndex.currentFormatVersion)
    }

    func testLoadWithBrokenIndexStartsEmptyInsteadOfThrowing() throws {
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("kein json".utf8).write(to: indexURL)

        let library = makeLibrary()
        XCTAssertNoThrow(try library.load())
        XCTAssertTrue(library.index.items.isEmpty)
    }

    // Neustart-Ersatz: eine zweite Instanz auf dieselben URLs muss denselben
    // Stand sehen.
    func testIndexSurvivesFreshInstance() throws {
        try writeFile("Chiptunes/4mat/tune.mod", marker: 0x01)
        try writeFile("Chiptunes/andere.s3m", marker: 0x02)

        let first = makeLibrary()
        try first.load()
        let report = try first.rescan()
        XCTAssertEqual(report.added.count, 2)

        let second = makeLibrary()
        try second.load()
        XCTAssertEqual(second.index.items.count, 2)
        let item = try XCTUnwrap(second.item(withRelativePath: "Chiptunes/4mat/tune.mod"))
        XCTAssertEqual(item.displayName, "tune.mod")
        XCTAssertEqual(item.folderPath, ["Chiptunes", "4mat"])
        XCTAssertEqual(second.url(for: item).path, rootURL.appendingPathComponent(item.relativePath).path)
        // Der Fingerabdruck ueberlebt das Speichern unveraendert.
        XCTAssertEqual(item.contentHash, try ContentHasher.fingerprint(of: second.url(for: item)).hash)
    }

    // MARK: - Abgleich mit dem Dateisystem

    func testRescanDetectsManualAddRemoveAndArchives() throws {
        try writeFile("bleibt.mod", marker: 0x10)
        try writeFile("verschwindet.xm", marker: 0x11)

        let library = makeLibrary()
        try library.load()
        _ = try library.rescan()
        XCTAssertEqual(library.index.items.count, 2)

        // Nutzer legt per Dateien-App etwas dazu, loescht etwas und wirft ein
        // Archiv sowie eine belanglose Datei dazwischen.
        try writeFile("Neu/handgelegt.it", marker: 0x12)
        try FileManager.default.removeItem(at: rootURL.appendingPathComponent("verschwindet.xm"))
        try writeFile("Neu/sammlung.zip", marker: 0x13)
        try writeFile("Neu/liesmich.txt", marker: 0x14)

        let report = try library.rescan()

        XCTAssertEqual(report.added, ["Neu/handgelegt.it"])
        XCTAssertEqual(report.removed, ["verschwindet.xm"])
        XCTAssertEqual(report.unchanged, 1)
        XCTAssertEqual(report.archivesFound, ["Neu/sammlung.zip"])
        XCTAssertFalse(report.wasCancelled)
        // Weder Archiv noch Textdatei landen als Titel im Index.
        XCTAssertEqual(
            Set(library.index.items.map(\.relativePath)),
            ["bleibt.mod", "Neu/handgelegt.it"])
    }

    func testRescanSecondRunReportsEverythingUnchanged() throws {
        try writeFile("a.mod", marker: 0x20)
        try writeFile("Sub/b.mod", marker: 0x21)

        let library = makeLibrary()
        try library.load()
        _ = try library.rescan()
        let second = try library.rescan()

        XCTAssertEqual(second.unchanged, 2)
        XCTAssertTrue(second.added.isEmpty)
        XCTAssertTrue(second.removed.isEmpty)
        XCTAssertTrue(second.changed.isEmpty)
    }

    // Wird eine bekannte Datei von aussen ersetzt, faellt das ueber Groesse
    // bzw. Zeitstempel auf und der Eintrag wird neu gehasht.
    func testRescanDetectsChangedContent() throws {
        let url = try writeFile("a.mod", marker: 0x30)

        let library = makeLibrary()
        try library.load()
        _ = try library.rescan()
        let before = try XCTUnwrap(library.item(withRelativePath: "a.mod"))

        try Data(repeating: 0x31, count: 999).write(to: url)
        let report = try library.rescan()

        XCTAssertEqual(report.changed, ["a.mod"])
        let after = try XCTUnwrap(library.item(withRelativePath: "a.mod"))
        XCTAssertNotEqual(after.contentHash, before.contentHash)
        XCTAssertEqual(after.fileSize, 999)
    }

    // Nach einem Abbruch darf der Abgleich nichts loeschen — ueber die nicht
    // besuchten Dateien ist nichts bekannt.
    func testCancelledRescanKeepsKnownItems() throws {
        try writeFile("a.mod", marker: 0x40)
        try writeFile("b.mod", marker: 0x41)

        let library = makeLibrary()
        try library.load()
        _ = try library.rescan()

        let report = try library.rescan(isCancelled: { true })
        XCTAssertTrue(report.wasCancelled)
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertEqual(library.index.items.count, 2)
    }

    // MARK: - Anzeigebaum

    func testFolderTreeMatchesPlaylistOrder() throws {
        try writeFile("zzz.mod", marker: 0x50)
        try writeFile("Beta/b.mod", marker: 0x51)
        try writeFile("Alpha/a2.mod", marker: 0x52)
        try writeFile("Alpha/a10.mod", marker: 0x53)
        try writeFile("Alpha/Inner/deep.mod", marker: 0x54)

        let library = makeLibrary()
        try library.load()
        _ = try library.rescan()

        let tree = library.folderTree()
        XCTAssertEqual(tree.subfolders.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(tree.files.map(\.displayName), ["zzz.mod"])
        XCTAssertEqual(tree.subfolders[0].files.map(\.displayName), ["a2.mod", "a10.mod"])
        XCTAssertEqual(tree.subfolders[0].subfolders[0].path, "Alpha/Inner")

        // Anzeige- und Abspielreihenfolge sind dieselbe Tiefensuche.
        let flat = PlaylistScanner.flattenedFiles(tree).map(\.displayName)
        XCTAssertEqual(flat, ["deep.mod", "a2.mod", "a10.mod", "b.mod", "zzz.mod"])
    }

    // MARK: - Loeschen

    func testRemoveDropsFileIndexEntryAndEmptyFolders() throws {
        try writeFile("Ordner/nur-hier.mod", marker: 0x60)
        try writeFile("bleibt.mod", marker: 0x61)

        let library = makeLibrary()
        try library.load()
        _ = try library.rescan()

        let item = try XCTUnwrap(library.item(withRelativePath: "Ordner/nur-hier.mod"))
        try library.remove(item)

        XCTAssertNil(library.item(withRelativePath: "Ordner/nur-hier.mod"))
        XCTAssertEqual(library.index.items.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("Ordner").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("bleibt.mod").path))
        // Die Wurzel selbst bleibt stehen.
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.path))
    }

    func testRemoveAllEmptiesRootAndIndex() throws {
        try writeFile("Ordner/a.mod", marker: 0x70)
        try writeFile("b.mod", marker: 0x71)

        let library = makeLibrary()
        try library.load()
        _ = try library.rescan()
        try library.removeAll()

        XCTAssertTrue(library.index.items.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rootURL.path), [])
    }

    // MARK: - Zuruecksetzen

    func testResetWipesLibraryIsIdempotentAndAllowsNewImport() throws {
        try writeFile("Ordner/a.mod", marker: 0x80)
        try writeFile("Ordner/tief/b.mod", marker: 0x81)
        try writeFile("c.mod", marker: 0x82)

        let cacheDir = workDir.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data([0x00]).write(to: cacheDir.appendingPathComponent("extrakt.tmp"))

        let library = makeLibrary()
        try library.load()
        _ = try library.rescan()
        XCTAssertEqual(library.index.items.count, 3)

        var favoritesCleared = false
        let report = try LibraryReset.reset(
            library: library,
            temporaryDirectories: [cacheDir],
            options: LibraryReset.Options(removeIndex: true, clearFavorites: true),
            favoritesCleaner: { favoritesCleared = true })

        // 3 Moduldateien + 1 Cache-Datei, dazu die beiden Ordner.
        XCTAssertEqual(report.removedFiles, 4)
        XCTAssertEqual(report.removedDirectories, 2)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertTrue(favoritesCleared)
        XCTAssertTrue(library.index.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rootURL.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cacheDir.path), [])

        // Zweiter Aufruf: nichts mehr da, trotzdem kein Fehler.
        let again = try LibraryReset.reset(
            library: library, temporaryDirectories: [cacheDir])
        XCTAssertEqual(again.removedFiles, 0)
        XCTAssertEqual(again.removedDirectories, 0)
        XCTAssertTrue(again.failures.isEmpty)

        // Und danach laesst sich wieder befuellen.
        let source = workDir.appendingPathComponent("Neu/Sammlung", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(repeating: 0x90, count: 32).write(to: source.appendingPathComponent("frisch.mod"))

        let importer = LibraryImporter(library: library)
        let importReport = try importer.importContents(of: [source])
        XCTAssertEqual(importReport.imported, ["Sammlung/frisch.mod"])
        XCTAssertEqual(modulesOnDisk(), ["Sammlung/frisch.mod"])
    }

    // MARK: - Fingerabdruck

    func testFingerprintIsStableAndContentSensitive() throws {
        let a = workDir.appendingPathComponent("a.bin")
        let b = workDir.appendingPathComponent("b.bin")
        let c = workDir.appendingPathComponent("c.bin")
        // Groesser als ein Leseblock, damit auch der Blockuebergang mitlaeuft.
        let bytes = Data((0..<(300 * 1024)).map { UInt8($0 % 251) })
        try bytes.write(to: a)
        try bytes.write(to: b)
        var changed = bytes
        changed[123_456] = changed[123_456] &+ 1
        try changed.write(to: c)

        let first = try ContentHasher.fingerprint(of: a)
        let second = try ContentHasher.fingerprint(of: b)
        let third = try ContentHasher.fingerprint(of: c)

        XCTAssertEqual(first.hash, second.hash)
        XCTAssertEqual(first.size, Int64(bytes.count))
        XCTAssertNotEqual(first.hash, third.hash)
        XCTAssertEqual(first.hash.count, 32)

        // Leere Datei: kein Sonderfall, nur ein anderer Wert.
        let empty = workDir.appendingPathComponent("leer.bin")
        try Data().write(to: empty)
        let emptyPrint = try ContentHasher.fingerprint(of: empty)
        XCTAssertEqual(emptyPrint.size, 0)
        XCTAssertNotEqual(emptyPrint.hash, first.hash)
    }
}

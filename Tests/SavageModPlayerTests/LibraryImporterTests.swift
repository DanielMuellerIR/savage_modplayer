import XCTest
@testable import SavageModPlayerCore

// Tests fuer den Bibliotheks-Import: Struktur-Erhalt, Dedupe, Namenskollision,
// Abbruch, Filterung nicht spielbarer Dateien und Archive.
//
// Alle Quellordner und Archive entstehen zur Laufzeit im Temp-Verzeichnis —
// im Repo liegt kein einziges Modul und kein Archiv.
final class LibraryImporterTests: XCTestCase {

    private var workDir: URL!
    private var rootURL: URL!
    private var indexURL: URL!
    private var sourceDir: URL!
    private var library: MusicLibrary!

    override func setUpWithError() throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LibraryImporterTests-\(UUID().uuidString)", isDirectory: true)
        rootURL = workDir.appendingPathComponent("Library", isDirectory: true)
        indexURL = workDir.appendingPathComponent("Support/library-index.json")
        sourceDir = workDir.appendingPathComponent("Quelle/Sammlung", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        library = MusicLibrary(rootURL: rootURL, indexURL: indexURL)
        try library.load()
    }

    override func tearDownWithError() throws {
        library = nil
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - Helfer

    // Legt eine Quelldatei mit unterscheidbarem Inhalt an.
    @discardableResult
    private func writeSource(_ relativePath: String, marker: UInt8) throws -> URL {
        try write(sourceDir.appendingPathComponent(relativePath), marker: marker)
    }

    @discardableResult
    private func write(_ url: URL, marker: UInt8) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: marker, count: 100 + Int(marker)).write(to: url)
        return url
    }

    // Alle Moduldateien, die tatsaechlich in der Bibliothek liegen.
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

    private func indexedPaths() -> Set<String> {
        Set(library.index.items.map(\.relativePath))
    }

    func testImportRejectsSymlinkedDestinationDirectory() throws {
        try writeSource("song.mod", marker: 0x31)
        let outside = workDir.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("Sammlung"), withDestinationURL: outside)

        let report = try LibraryImporter(library: library).importContents(of: [sourceDir])

        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(library.index.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("song.mod").path))
    }

    func testImportRejectsSymlinkedDestinationFileInsteadOfDeduplicating() throws {
        let source = try writeSource("song.mod", marker: 0x32)
        let outside = try write(workDir.appendingPathComponent("outside.mod"), marker: 0x32)
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("song.mod"), withDestinationURL: outside)

        let report = try LibraryImporter(library: library).importContents(of: [source])

        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertTrue(report.duplicates.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(library.index.items.isEmpty)
        XCTAssertEqual(try Data(contentsOf: outside), try Data(contentsOf: source))
    }

    // MARK: - Struktur und Filterung

    func testImportKeepsStructureAndSkipsUnplayableFiles() throws {
        try writeSource("a.mod", marker: 0x01)
        try writeSource("Sub/b.s3m", marker: 0x02)
        try writeSource("Sub/Deep/c.xm", marker: 0x03)
        try writeSource("Sub/notizen.txt", marker: 0x04)
        try writeSource("cover.png", marker: 0x05)

        var progressSteps: [ImportProgress] = []
        let importer = LibraryImporter(library: library)
        let report = try importer.importContents(of: [sourceDir], progress: { progressSteps.append($0) })

        // Der Quellordner selbst wird zur obersten Ebene in der Bibliothek.
        XCTAssertEqual(
            Set(report.imported),
            ["Sammlung/a.mod", "Sammlung/Sub/b.s3m", "Sammlung/Sub/Deep/c.xm"])
        XCTAssertTrue(report.duplicates.isEmpty)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertFalse(report.wasCancelled)
        XCTAssertEqual(modulesOnDisk(), Set(report.imported))
        XCTAssertEqual(indexedPaths(), Set(report.imported))

        // Fortschritt: eine Meldung je spielbarer Datei, mit bekanntem Ziel.
        XCTAssertEqual(progressSteps.count, 3)
        XCTAssertEqual(progressSteps.last?.totalFiles, 3)
        XCTAssertEqual(progressSteps.last?.processedFiles, 3)

        // Der Index kennt Groesse und Anzeigename.
        let item = try XCTUnwrap(library.item(withRelativePath: "Sammlung/Sub/Deep/c.xm"))
        XCTAssertEqual(item.displayName, "c.xm")
        XCTAssertEqual(item.folderPath, ["Sammlung", "Sub", "Deep"])
        XCTAssertEqual(item.fileSize, 103)

        // Anzeigebaum und Abspielreihenfolge: Tiefensuche, Ordner vor Dateien.
        let tree = library.folderTree()
        XCTAssertEqual(tree.subfolders.map(\.name), ["Sammlung"])
        XCTAssertEqual(tree.subfolders[0].subfolders.map(\.name), ["Sub"])
        XCTAssertEqual(
            PlaylistScanner.flattenedFiles(tree).map(\.displayName),
            ["c.xm", "b.s3m", "a.mod"])
    }

    // Mehrere Quellen bleiben getrennt, auch bei gleichnamigen Unterordnern.
    func testMultipleSourcesKeepTheirOwnRootFolders() throws {
        let second = workDir.appendingPathComponent("Quelle/Zweite", isDirectory: true)
        try writeSource("Gemeinsam/song.mod", marker: 0x10)
        try write(second.appendingPathComponent("Gemeinsam/song.mod"), marker: 0x11)

        let importer = LibraryImporter(library: library)
        let report = try importer.importContents(of: [sourceDir, second])

        XCTAssertEqual(
            Set(report.imported),
            ["Sammlung/Gemeinsam/song.mod", "Zweite/Gemeinsam/song.mod"])
        XCTAssertTrue(report.duplicates.isEmpty)
    }

    // Eine Verknuepfung ist kein eigener Bibliotheksinhalt. Insbesondere darf
    // eine direkt ausgewaehlte Verknuepfung auf einen Ordner nicht dazu
    // fuehren, dass der Importer den Zielordner ausserhalb der Quelle ablaeuft.
    func testSymbolicLinksInSelectedSourcesAreRejected() throws {
        let outside = workDir.appendingPathComponent("Ausserhalb", isDirectory: true)
        let target = try write(outside.appendingPathComponent("extern.mod"), marker: 0x12)
        let fileLink = sourceDir.appendingPathComponent("verknuepft.mod")
        let directoryLink = workDir.appendingPathComponent("Ordner-Link")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: outside)

        let report = try LibraryImporter(library: library).importContents(
            of: [sourceDir, directoryLink])

        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertEqual(report.failures.count, 2)
        XCTAssertTrue(report.failures.allSatisfy { $0.reason.contains("Verknuepfung") })
        XCTAssertTrue(library.index.items.isEmpty)
        XCTAssertTrue(modulesOnDisk().isEmpty)
    }

    func testNamedPipeNamedLikeAModuleIsRejectedBeforeFingerprinting() throws {
        let fifo = sourceDir.appendingPathComponent("haenger.mod")
        try XCTSkipIf(mkfifo(fifo.path, 0o644) != 0, "FIFO liess sich nicht anlegen")

        let report = try LibraryImporter(library: library).importContents(of: [fifo])

        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(report.failures[0].reason.contains("reguläre Datei"))
        XCTAssertTrue(library.index.items.isEmpty)
    }

    /// `contentsOfDirectory` hat das Kind bereits geliefert; scheitert danach
    /// seine Typabfrage, darf es nicht lautlos aus einem angeblich erfolgreichen
    /// Import verschwinden.
    func testChildResourceClassificationErrorIsReportedWithRelativePath() throws {
        try writeSource("Sub/kaputt.mod", marker: 0x13)
        let importer = LibraryImporter(
            library: library,
            resourceValuesReader: { url, keys in
                if url.lastPathComponent == "kaputt.mod" {
                    throw NSError(
                        domain: "LibraryImporterTests", code: 13,
                        userInfo: [NSLocalizedDescriptionKey: "simulierter Metadatenfehler"])
                }
                return try url.resourceValues(forKeys: keys)
            })

        let report = try importer.importContents(of: [sourceDir])

        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.failures[0].path, "Sammlung/Sub/kaputt.mod")
        XCTAssertTrue(report.failures[0].reason.contains("Metadatenfehler"))
    }

    // MARK: - Dedupe

    func testSecondImportOfSameSourceChangesNothing() throws {
        try writeSource("a.mod", marker: 0x20)
        try writeSource("Sub/b.mod", marker: 0x21)

        let importer = LibraryImporter(library: library)
        _ = try importer.importContents(of: [sourceDir])
        let before = modulesOnDisk()

        let second = try importer.importContents(of: [sourceDir])

        XCTAssertTrue(second.imported.isEmpty)
        XCTAssertEqual(
            Set(second.duplicates),
            ["Sammlung/a.mod", "Sammlung/Sub/b.mod"])
        XCTAssertTrue(second.failures.isEmpty)
        XCTAssertEqual(modulesOnDisk(), before)
        XCTAssertEqual(library.index.items.count, 2)
    }

    // Gleicher Name, anderer Inhalt: die vorhandene Datei bleibt unangetastet,
    // die neue bekommt einen Zaehler.
    func testNameCollisionWithDifferentContentGetsCounterSuffix() throws {
        let sourceFile = try writeSource("a.mod", marker: 0x30)

        let importer = LibraryImporter(library: library)
        _ = try importer.importContents(of: [sourceDir])
        let originalContent = try Data(contentsOf: rootURL.appendingPathComponent("Sammlung/a.mod"))

        // Dieselbe Position, anderer Inhalt.
        try Data(repeating: 0x31, count: 77).write(to: sourceFile)
        let second = try importer.importContents(of: [sourceDir])

        XCTAssertEqual(second.imported, ["Sammlung/a-2.mod"])
        XCTAssertEqual(modulesOnDisk(), ["Sammlung/a.mod", "Sammlung/a-2.mod"])
        XCTAssertEqual(
            try Data(contentsOf: rootURL.appendingPathComponent("Sammlung/a.mod")),
            originalContent)
        XCTAssertEqual(
            try Data(contentsOf: rootURL.appendingPathComponent("Sammlung/a-2.mod")).count, 77)

        // Noch einmal derselbe Inhalt: jetzt ist es ein Duplikat von a-2.
        let third = try importer.importContents(of: [sourceDir])
        XCTAssertEqual(third.duplicates, ["Sammlung/a-2.mod"])
        XCTAssertTrue(third.imported.isEmpty)
    }

    // Die Amiga-Schreibweise "mod.<name>" darf beim Zaehlen nicht kaputtgehen.
    func testNumberedNameKeepsFilePlayable() {
        XCTAssertEqual(LibraryImporter.numberedName(for: "song.mod", counter: 2), "song-2.mod")
        XCTAssertEqual(LibraryImporter.numberedName(for: "song.IT", counter: 3), "song-3.IT")
        XCTAssertEqual(LibraryImporter.numberedName(for: "mod.tune", counter: 2), "mod.tune-2")
        XCTAssertTrue(PlaylistScanner.isModFile(URL(fileURLWithPath: "/x/mod.tune-2")))
    }

    // MARK: - Abbruch

    func testCancelledImportLeavesConsistentState() throws {
        for number in 1...10 {
            try writeSource("track-\(number).mod", marker: UInt8(0x40 + number))
        }

        let importer = LibraryImporter(library: library)
        // Abbrechen, sobald drei Titel in der Bibliothek stehen.
        let watched = library!
        let report = try importer.importContents(
            of: [sourceDir],
            isCancelled: { watched.index.items.count >= 3 })

        XCTAssertTrue(report.wasCancelled)
        XCTAssertEqual(report.imported.count, 3)
        XCTAssertLessThan(report.imported.count, 10)
        // Kein halber Zustand: Index und Platte stimmen ueberein.
        XCTAssertEqual(indexedPaths(), modulesOnDisk())
        XCTAssertEqual(indexedPaths(), Set(report.imported))

        // Der naechste Lauf holt den Rest nach und meldet die drei als Duplikat.
        let rest = try importer.importContents(of: [sourceDir])
        XCTAssertFalse(rest.wasCancelled)
        XCTAssertEqual(rest.imported.count, 7)
        XCTAssertEqual(rest.duplicates.count, 3)
        XCTAssertEqual(modulesOnDisk().count, 10)
    }

    // MARK: - Koordiniertes Lesen

    // Der Haken fuers koordinierte Lesen (auf iOS NSFileCoordinator) wird
    // wirklich fuer jede Quelldatei benutzt.
    func testCoordinatedReadHookIsUsedForEverySource() throws {
        try writeSource("a.mod", marker: 0x50)
        try writeSource("b.mod", marker: 0x51)

        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let importer = LibraryImporter(library: library, coordinatedRead: { url, body in
            counter.value += 1
            try body(url)
        })
        _ = try importer.importContents(of: [sourceDir])

        XCTAssertEqual(counter.value, 2)
    }

    // MARK: - Archive

    // Baut mit bsdtar ein ZIP aus einem Ordner — so liegt kein Archiv im Repo.
    private func makeZip(from directory: URL, named name: String, at destination: URL) throws -> URL {
        let tool = try XCTUnwrap(PlaylistScanner.bsdtarURL)
        let archiveURL = destination.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = tool
        process.arguments = [
            "-a", "-c", "-f", archiveURL.path,
            "-C", directory.deletingLastPathComponent().path,
            directory.lastPathComponent
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "bsdtar konnte das Test-ZIP nicht erzeugen")
        return archiveURL
    }

    func testArchiveIsUnpackedIntoFolderNamedAfterTheArchive() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Import nicht pruefbar (Linux: libarchive-tools)")

        // Inhalt fuers Archiv vorbereiten (ausserhalb der Quelle, damit nur das
        // fertige ZIP importiert wird).
        let packDir = workDir.appendingPathComponent("Rohmaterial/Coolpack", isDirectory: true)
        try write(packDir.appendingPathComponent("alpha.mod"), marker: 0x60)
        try write(packDir.appendingPathComponent("sub/beta.s3m"), marker: 0x61)
        try write(packDir.appendingPathComponent("liesmich.txt"), marker: 0x62)
        _ = try makeZip(from: packDir, named: "pack.zip", at: sourceDir.appendingPathComponent("A", isDirectory: true))
        try writeSource("direkt.mod", marker: 0x63)

        let importer = LibraryImporter(library: library)
        let report = try importer.importContents(of: [sourceDir])

        // A/pack.zip landet unter A/pack/ — der Archivname wird zum Ordner.
        XCTAssertEqual(
            Set(report.imported),
            ["Sammlung/direkt.mod",
             "Sammlung/A/pack/Coolpack/alpha.mod",
             "Sammlung/A/pack/Coolpack/sub/beta.s3m"])
        XCTAssertEqual(modulesOnDisk(), Set(report.imported))
        XCTAssertEqual(indexedPaths(), Set(report.imported))
        // Das Archiv selbst wird nicht in die Bibliothek kopiert.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Sammlung/A/pack.zip").path))
    }

    // Ein Archiv IM Archiv wird mit ausgepackt. Frueher sah `ingestStaged` nur
    // Moduldateien: Der Inhalt des inneren Archivs kam nie an, und weil das
    // direkte Modul trotzdem als uebernommen zaehlte, loeschte
    // `unpackPendingArchives` das aeussere Quellarchiv — die letzte Kopie des
    // inneren Inhalts war damit weg.
    func testNestedArchiveInsideArchiveIsUnpackedToo() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Import nicht pruefbar (Linux: libarchive-tools)")

        // Inneres Archiv bauen und in den Ordner legen, aus dem das aeussere
        // Archiv entsteht — zusaetzlich zu einem direkten Modul.
        let innerDir = workDir.appendingPathComponent("Rohmaterial/Innen", isDirectory: true)
        try write(innerDir.appendingPathComponent("innen.mod"), marker: 0x40)
        let outerDir = workDir.appendingPathComponent("Rohmaterial/Aussen", isDirectory: true)
        try write(outerDir.appendingPathComponent("direkt.mod"), marker: 0x41)
        _ = try makeZip(from: innerDir, named: "innen.zip", at: outerDir)
        _ = try makeZip(from: outerDir, named: "aussen.zip", at: sourceDir)

        let importer = LibraryImporter(library: library)
        let report = try importer.importContents(of: [sourceDir])

        XCTAssertTrue(report.failures.isEmpty, "unerwartete Fehler: \(report.failures)")
        XCTAssertEqual(
            Set(report.imported),
            ["Sammlung/aussen/Aussen/direkt.mod",
             "Sammlung/aussen/Aussen/innen/Innen/innen.mod"])
        XCTAssertEqual(modulesOnDisk(), Set(report.imported))
        // Das innere Archiv landet nicht als "Moduldatei" in der Bibliothek.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Sammlung/aussen/Aussen/innen.zip").path))
    }

    // Dasselbe fuer ein per Finder abgelegtes Archiv: Erst wenn auch das innere
    // Archiv uebernommen ist, darf die Quelle verschwinden.
    func testPendingArchiveWithNestedArchiveKeepsAllContentBeforeDeletingSource() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Import nicht pruefbar (Linux: libarchive-tools)")

        let innerDir = workDir.appendingPathComponent("Rohmaterial/Innen", isDirectory: true)
        try write(innerDir.appendingPathComponent("innen.mod"), marker: 0x42)
        let outerDir = workDir.appendingPathComponent("Rohmaterial/Aussen", isDirectory: true)
        try write(outerDir.appendingPathComponent("direkt.mod"), marker: 0x43)
        _ = try makeZip(from: innerDir, named: "innen.zip", at: outerDir)
        _ = try makeZip(from: outerDir, named: "aussen.zip",
                        at: rootURL.appendingPathComponent("Manuell", isDirectory: true))

        let importer = LibraryImporter(library: library)
        let report = try importer.unpackPendingArchives()

        XCTAssertTrue(report.failures.isEmpty, "unerwartete Fehler: \(report.failures)")
        XCTAssertEqual(
            Set(report.imported),
            ["Manuell/aussen/Aussen/direkt.mod",
             "Manuell/aussen/Aussen/innen/Innen/innen.mod"])
        // Erst jetzt darf die Quelle weg sein.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Manuell/aussen.zip").path))
    }

    // Das Bytebudget gilt ueber die ganze Rekursion. Beide Archive passen fuer
    // sich allein; erst ihre SUMME muss den Import stoppen und die Finder-
    // Quelle erhalten.
    func testNestedArchivesShareOneUncompressedByteBudget() throws {
        try XCTSkipIf(PlaylistScanner.bsdtarURL == nil, "bsdtar nicht installiert")

        let innerDir = workDir.appendingPathComponent("Rohmaterial/Innen", isDirectory: true)
        try Data(repeating: 0x31, count: 4_000).write(
            to: try write(innerDir.appendingPathComponent("innen.mod"), marker: 0x31))
        let outerDir = workDir.appendingPathComponent("Rohmaterial/Aussen", isDirectory: true)
        try Data(repeating: 0x32, count: 4_000).write(
            to: try write(outerDir.appendingPathComponent("direkt.mod"), marker: 0x32))
        let inner = try makeZip(from: innerDir, named: "innen.zip", at: outerDir)
        let outer = try makeZip(
            from: outerDir, named: "aussen.zip",
            at: rootURL.appendingPathComponent("Manuell", isDirectory: true))

        let probeOuter = workDir.appendingPathComponent("Probe/Aussen", isDirectory: true)
        let outerUsage = try PlaylistScanner.unpackArchive(outer, into: probeOuter)
        let stagedInner = probeOuter
            .appendingPathComponent(outerDir.lastPathComponent)
            .appendingPathComponent(inner.lastPathComponent)
        let innerUsage = try PlaylistScanner.unpackArchive(
            stagedInner, into: workDir.appendingPathComponent("Probe/Innen", isDirectory: true))
        let combined = outerUsage.totalUncompressedBytes + innerUsage.totalUncompressedBytes
        XCTAssertGreaterThan(combined, max(
            outerUsage.totalUncompressedBytes, innerUsage.totalUncompressedBytes))

        let importer = LibraryImporter(
            library: library,
            archiveLimits: .init(
                maxTotalUncompressedBytes: combined - 1,
                maxEntries: 100,
                maxArchives: 10))
        let report = try importer.unpackPendingArchives()

        XCTAssertFalse(report.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outer.path),
                      "Budgetfehler darf die letzte Archivkopie nicht loeschen")
    }

    func testNestedArchivesShareOneEntryBudget() throws {
        try XCTSkipIf(PlaylistScanner.bsdtarURL == nil, "bsdtar nicht installiert")

        let innerDir = workDir.appendingPathComponent("Rohmaterial/Innen", isDirectory: true)
        try write(innerDir.appendingPathComponent("innen.mod"), marker: 0x33)
        let outerDir = workDir.appendingPathComponent("Rohmaterial/Aussen", isDirectory: true)
        try write(outerDir.appendingPathComponent("direkt.mod"), marker: 0x34)
        let inner = try makeZip(from: innerDir, named: "innen.zip", at: outerDir)
        let outer = try makeZip(
            from: outerDir, named: "aussen.zip",
            at: rootURL.appendingPathComponent("Manuell", isDirectory: true))

        let probeOuter = workDir.appendingPathComponent("Probe/Aussen", isDirectory: true)
        let outerUsage = try PlaylistScanner.unpackArchive(outer, into: probeOuter)
        let stagedInner = probeOuter
            .appendingPathComponent(outerDir.lastPathComponent)
            .appendingPathComponent(inner.lastPathComponent)
        let innerUsage = try PlaylistScanner.unpackArchive(
            stagedInner, into: workDir.appendingPathComponent("Probe/Innen", isDirectory: true))
        let combined = outerUsage.entryCount + innerUsage.entryCount

        let importer = LibraryImporter(
            library: library,
            archiveLimits: .init(
                maxTotalUncompressedBytes: 1_000_000,
                maxEntries: combined - 1,
                maxArchives: 10))
        let report = try importer.unpackPendingArchives()

        XCTAssertFalse(report.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outer.path))
    }

    func testNestedArchivesShareOneArchiveCountBudget() throws {
        try XCTSkipIf(PlaylistScanner.bsdtarURL == nil, "bsdtar nicht installiert")

        let innerDir = workDir.appendingPathComponent("Rohmaterial/Innen", isDirectory: true)
        try write(innerDir.appendingPathComponent("innen.mod"), marker: 0x35)
        let outerDir = workDir.appendingPathComponent("Rohmaterial/Aussen", isDirectory: true)
        _ = try makeZip(from: innerDir, named: "eins.zip", at: outerDir)
        _ = try makeZip(from: innerDir, named: "zwei.zip", at: outerDir)
        let outer = try makeZip(
            from: outerDir, named: "aussen.zip",
            at: rootURL.appendingPathComponent("Manuell", isDirectory: true))

        let importer = LibraryImporter(
            library: library,
            archiveLimits: .init(
                maxTotalUncompressedBytes: 1_000_000,
                maxEntries: 100,
                maxArchives: 2))
        let report = try importer.unpackPendingArchives()

        XCTAssertTrue(report.failures.contains { $0.reason.contains("verschachtelte Archive") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: outer.path))
    }

    // Ein Link im Archiv koennte auf eine externe Datei zeigen und deren Inhalt
    // in die Bibliothek ziehen. Er muss deshalb VOR Endungspruefung und
    // Rekursion abgelehnt werden.
    //
    // Seit 1.6.10 greift die Ablehnung frueher: Der eigene Leser weist das
    // GANZE Archiv ab, sobald ein Eintrag ein Link ist — vorher schrieb bsdtar
    // den Link erst auf die Platte und der Importer sortierte ihn danach aus.
    // Beide Meldungen sind hier zugelassen, das Ergebnis zaehlt: extern.mod
    // kommt nicht in die Bibliothek, das Quellarchiv bleibt liegen.
    func testSymbolicLinkArchiveEntryIsRejectedWithoutFollowingIt() throws {
        try XCTSkipIf(PlaylistScanner.bsdtarURL == nil, "bsdtar nicht installiert")

        let externalDir = workDir.appendingPathComponent("Extern/Innen", isDirectory: true)
        try write(externalDir.appendingPathComponent("extern.mod"), marker: 0x36)
        let externalArchive = try makeZip(
            from: externalDir, named: "extern.zip",
            at: workDir.appendingPathComponent("Extern", isDirectory: true))

        let outerDir = workDir.appendingPathComponent("Rohmaterial/Aussen", isDirectory: true)
        try write(outerDir.appendingPathComponent("direkt.mod"), marker: 0x37)
        try FileManager.default.createSymbolicLink(
            at: outerDir.appendingPathComponent("inner.zip"),
            withDestinationURL: externalArchive)
        let outer = try makeZip(
            from: outerDir, named: "aussen.zip",
            at: rootURL.appendingPathComponent("Manuell", isDirectory: true))

        let report = try LibraryImporter(library: library).unpackPendingArchives()

        XCTAssertTrue(report.failures.contains {
            $0.reason.contains("Symbolischer Link") || $0.reason.contains("symbolischer Link")
        }, "erwartet wurde eine Link-Ablehnung, bekommen: \(report.failures.map(\.reason))")
        XCTAssertFalse(report.imported.contains { $0.hasSuffix("extern.mod") })
        XCTAssertFalse(report.imported.contains { $0.hasSuffix("direkt.mod") },
                       "das ganze Archiv gilt als abgelehnt, nicht nur der Link")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outer.path))
    }

    func testHiddenSupportedArchiveContentIsImportedCompletely() throws {
        try XCTSkipIf(PlaylistScanner.bsdtarURL == nil, "bsdtar nicht installiert")

        let packDir = workDir.appendingPathComponent("Rohmaterial/Versteckt", isDirectory: true)
        try write(packDir.appendingPathComponent(".direkt.mod"), marker: 0x38)
        let nestedDir = workDir.appendingPathComponent("Rohmaterial/Innen", isDirectory: true)
        try write(nestedDir.appendingPathComponent("innen.xm"), marker: 0x39)
        _ = try makeZip(from: nestedDir, named: ".innen.zip", at: packDir)
        let outer = try makeZip(
            from: packDir, named: "aussen.zip",
            at: rootURL.appendingPathComponent("Manuell", isDirectory: true))

        let report = try LibraryImporter(library: library).unpackPendingArchives()

        XCTAssertTrue(report.failures.isEmpty, "unerwartete Fehler: \(report.failures)")
        XCTAssertTrue(report.imported.contains { $0.hasSuffix("/.direkt.mod") })
        XCTAssertTrue(report.imported.contains { $0.hasSuffix("/innen.xm") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: outer.path))
    }

    // Ein kaputtes Archiv meldet einen lesbaren Grund und stoppt den Import nicht.
    func testBrokenArchiveIsReportedAndImportContinues() throws {
        try write(sourceDir.appendingPathComponent("kaputt.zip"), marker: 0x70)
        try writeSource("gut.mod", marker: 0x71)

        let importer = LibraryImporter(library: library)
        let report = try importer.importContents(of: [sourceDir])

        XCTAssertEqual(report.imported, ["Sammlung/gut.mod"])
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.failures.first?.path, "Sammlung/kaputt.zip")
        XCTAssertFalse(try XCTUnwrap(report.failures.first?.reason).isEmpty)
    }

    // Ein als Abbruch markierter Fehler des koordinierten Lesers (z.B. Warten
    // auf eine Cloud-Datei) ist KEIN Fehlschlag der Datei: er setzt
    // wasCancelled und erzeugt keinen Failure-Eintrag.
    func testCancellationFromCoordinatedReadIsNotAFailure() throws {
        struct ReaderCancelled: ImportCancellationError {}
        try writeSource("cloud.mod", marker: 0x90)

        let importer = LibraryImporter(library: library) { _, _ in
            throw ReaderCancelled()
        }
        let report = try importer.importContents(of: [sourceDir])

        XCTAssertTrue(report.wasCancelled)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertTrue(report.imported.isEmpty)
    }

    // Ein Archiv ohne spielbaren Inhalt bleibt nach unpackPendingArchives
    // liegen (fail-closed): Frueher wurde die Quelle geloescht, obwohl nichts
    // uebernommen worden war.
    func testPendingArchiveWithoutPlayableContentIsKept() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Import nicht pruefbar (Linux: libarchive-tools)")

        let packDir = workDir.appendingPathComponent("Rohmaterial/NurText", isDirectory: true)
        try write(packDir.appendingPathComponent("liesmich.txt"), marker: 0x91)
        _ = try makeZip(from: packDir, named: "leer.zip", at: rootURL.appendingPathComponent("Manuell", isDirectory: true))

        let importer = LibraryImporter(library: library)
        let report = try importer.unpackPendingArchives()

        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Manuell/leer.zip").path),
            "Quellarchiv ohne uebernommene Dateien darf nicht verschwinden")
    }

    // Ein Abbruch, BEVOR das Archiv ueberhaupt geoeffnet wird, laesst das
    // Quellarchiv liegen. (Der Abbruch eines bereits laufenden bsdtar steht im
    // Test darunter — hier kommt es nie so weit.)
    func testCancelBeforeUnpackKeepsSourceArchive() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Import nicht pruefbar (Linux: libarchive-tools)")

        let packDir = workDir.appendingPathComponent("Rohmaterial/Coolpack", isDirectory: true)
        try write(packDir.appendingPathComponent("alpha.mod"), marker: 0x92)
        _ = try makeZip(from: packDir, named: "pack.zip", at: rootURL.appendingPathComponent("Manuell", isDirectory: true))

        let importer = LibraryImporter(library: library)
        // Der erste Haken-Aufruf (Schleifenkopf) laeuft durch, der zweite
        // (Einstieg in unpackArchive) bricht ab — bsdtar startet gar nicht.
        var calls = 0
        let report = try importer.unpackPendingArchives(isCancelled: {
            calls += 1
            return calls > 1
        })

        XCTAssertTrue(report.wasCancelled)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Manuell/pack.zip").path),
            "Nach Abbruch muss das Quellarchiv erhalten bleiben")
    }

    // Abbruch eines BEREITS LAUFENDEN bsdtar: `process.terminate()` und
    // `waitUntilExit()` werden hier wirklich durchlaufen.
    //
    // Der Trick ist die "Archivdatei": eine benannte Pipe (FIFO). bsdtar
    // blockiert beim Oeffnen, solange niemand hineinschreibt — der Prozess
    // laeuft also garantiert noch, wenn der Abbruch kommt. Mit einem echten
    // Mini-Archiv waere bsdtar oft schon fertig, und der Test waere ein
    // Zufallstreffer.
    //
    // Die Endung ist seit 1.6.10 `.7z` und nicht mehr `.zip`: `.zip` uebernimmt
    // ueberall der eigene Leser, bsdtar ist nur noch fuer `.7z` zustaendig.
    //
    // Dass dieser Test ueberhaupt zurueckkehrt, IST der Beleg: Ohne
    // `terminate()` liefe bsdtar endlos weiter.
    func testCancelTerminatesRunningBsdtar() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Import nicht pruefbar (Linux: libarchive-tools)")

        let manuell = rootURL.appendingPathComponent("Manuell", isDirectory: true)
        try FileManager.default.createDirectory(at: manuell, withIntermediateDirectories: true)
        let fifo = manuell.appendingPathComponent("haenger.7z")
        try XCTSkipIf(mkfifo(fifo.path, 0o644) != 0, "FIFO liess sich nicht anlegen")

        let importer = LibraryImporter(library: library)
        // Aufrufe: 1 Schleifenkopf, 2 Einstieg unpackArchive, 3 Vorabpruefung in
        // unpackUsingBsdtar (alle noch "weiterlaufen"), 4 erste Runde der
        // Warteschleife — dort greift der Abbruch, waehrend bsdtar laeuft.
        var calls = 0
        let report = try importer.unpackPendingArchives(isCancelled: {
            calls += 1
            return calls > 3
        })

        XCTAssertTrue(report.wasCancelled)
        XCTAssertTrue(report.failures.isEmpty, "ein Abbruch ist kein Archivfehler")
        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertGreaterThan(calls, 3, "der Abbruch muss erst in der Warteschleife greifen")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fifo.path),
                      "Nach Abbruch muss das Quellarchiv erhalten bleiben")
    }

    // Gegenstueck zum Test darueber: Dieselbe Falle mit `.zip` geht jetzt an den
    // eigenen Leser — und der darf an einer benannten Pipe nicht haengen
    // bleiben. Er oeffnet mit O_NONBLOCK und weist alles ab, was keine
    // gewoehnliche Datei ist.
    //
    // Dass dieser Test zurueckkehrt, IST der Beleg. Ohne die Pruefung blockiert
    // schon das `open()`, ohne Zeitlimit und ohne Abbruchmoeglichkeit.
    func testNamedPipeNamedLikeAZipDoesNotBlockTheReader() throws {
        let manuell = rootURL.appendingPathComponent("Manuell", isDirectory: true)
        try FileManager.default.createDirectory(at: manuell, withIntermediateDirectories: true)
        let fifo = manuell.appendingPathComponent("haenger.zip")
        try XCTSkipIf(mkfifo(fifo.path, 0o644) != 0, "FIFO liess sich nicht anlegen")

        let importer = LibraryImporter(library: library)
        let report = try importer.unpackPendingArchives()

        XCTAssertFalse(report.wasCancelled)
        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertEqual(report.failures.count, 1, "die Pipe gehoert als Fehlschlag gemeldet")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fifo.path),
                      "Was nicht gelesen werden konnte, bleibt liegen")
    }

    // `mod.collection.zip` ist ein Archiv, keine Amiga-Moduldatei: Die
    // Archiv-Klassifikation gewinnt gegen das `mod.`-Namenspraefix.
    func testArchiveNamedWithModPrefixIsUnpackedNotCopied() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Import nicht pruefbar (Linux: libarchive-tools)")

        let packDir = workDir.appendingPathComponent("Rohmaterial/Coolpack", isDirectory: true)
        try write(packDir.appendingPathComponent("alpha.mod"), marker: 0x93)
        _ = try makeZip(from: packDir, named: "mod.collection.zip", at: sourceDir)

        let importer = LibraryImporter(library: library)
        let report = try importer.importContents(of: [sourceDir])

        XCTAssertEqual(report.imported, ["Sammlung/mod.collection/Coolpack/alpha.mod"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Sammlung/mod.collection.zip").path),
            "Das ZIP darf nicht als Moduldatei in die Bibliothek kopiert werden")
    }

    // Ein unlesbarer Quellordner erscheint als Fehler im Bericht statt still
    // ausgelassen zu werden.
    func testUnreadableSourceDirectoryIsReported() throws {
        let locked = sourceDir.appendingPathComponent("Gesperrt", isDirectory: true)
        try write(locked.appendingPathComponent("drin.mod"), marker: 0x94)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        // Als root (z.B. CI-Container) greifen Dateirechte nicht — dann ist
        // dieser Fall hier nicht pruefbar.
        if (try? FileManager.default.contentsOfDirectory(atPath: locked.path)) != nil {
            throw XCTSkip("Dateirechte greifen in dieser Umgebung nicht (root?)")
        }

        let importer = LibraryImporter(library: library)
        let report = try importer.importContents(of: [sourceDir])

        XCTAssertFalse(report.wasCancelled)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(try XCTUnwrap(report.failures.first?.path).contains("Gesperrt"))
    }

    // Per Finder abgelegtes Archiv: rescan meldet es, unpackPendingArchives
    // packt es aus und raeumt es weg.
    func testPendingArchiveFromFinderIsUnpackedAndRemoved() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Import nicht pruefbar (Linux: libarchive-tools)")

        let packDir = workDir.appendingPathComponent("Rohmaterial/Coolpack", isDirectory: true)
        try write(packDir.appendingPathComponent("alpha.mod"), marker: 0x80)
        _ = try makeZip(from: packDir, named: "pack.zip", at: rootURL.appendingPathComponent("Manuell", isDirectory: true))

        let rescan = try library.rescan()
        XCTAssertEqual(rescan.archivesFound, ["Manuell/pack.zip"])
        XCTAssertTrue(rescan.added.isEmpty)

        let importer = LibraryImporter(library: library)
        let report = try importer.unpackPendingArchives()

        XCTAssertEqual(report.imported, ["Manuell/pack/Coolpack/alpha.mod"])
        XCTAssertEqual(indexedPaths(), ["Manuell/pack/Coolpack/alpha.mod"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Manuell/pack.zip").path))
        // Danach ist nichts mehr offen.
        XCTAssertTrue(try library.rescan().archivesFound.isEmpty)
    }
}

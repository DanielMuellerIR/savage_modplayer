import XCTest
@testable import SavageModPlayerCore

// Tests fuer den Playlist-Scanner: Hierarchie-Erfassung beim Einsammeln,
// Baum-Aufbau/Sortierung, flache Abspiel-Reihenfolge und das unsichtbare
// Entpacken von Zip-/7z-Archiven (via System-bsdtar).
final class PlaylistScannerTests: XCTestCase {

    // Frisches Arbeitsverzeichnis pro Test; wird in tearDown geloescht.
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlaylistScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private func makeFile(_ relativePath: String) throws -> URL {
        let url = workDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x78]).write(to: url)
        return url
    }

    private var tempDir: URL {
        workDir.appendingPathComponent("scan-temp", isDirectory: true)
    }

    private func storedZip(_ items: [(String, Data)]) -> Data {
        func word<T: FixedWidthInteger>(_ value: T) -> Data {
            var value = value.littleEndian
            return withUnsafeBytes(of: &value) { Data($0) }
        }
        var body = Data(), directory = Data()
        for (name, payload) in items {
            let name = Data(name.utf8), offset = UInt32(body.count)
            var crc: UInt32 = 0xFFFFFFFF
            for byte in payload {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xEDB88320) }
            }
            crc ^= 0xFFFFFFFF
            body += word(UInt32(0x04034B50)) + word(UInt16(20))
            body += Data(repeating: 0, count: 8)
            body += word(crc) + word(UInt32(payload.count)) + word(UInt32(payload.count))
            body += word(UInt16(name.count)) + word(UInt16(0)) + name + payload
            directory += word(UInt32(0x02014B50)) + word(UInt16(20)) + word(UInt16(20))
            directory += Data(repeating: 0, count: 8)
            directory += word(crc) + word(UInt32(payload.count)) + word(UInt32(payload.count))
            directory += word(UInt16(name.count)) + Data(repeating: 0, count: 12)
            directory += word(offset) + name
        }
        let offset = UInt32(body.count)
        body += directory
        body += word(UInt32(0x06054B50)) + Data(repeating: 0, count: 4)
        body += word(UInt16(items.count)) + word(UInt16(items.count))
        body += word(UInt32(directory.count)) + word(offset) + word(UInt16(0))
        return body
    }

    func testNestedArchivesShareBudgetsAndReleaseExtractionTrees() throws {
        let innerA = storedZip([("a.mod", Data(repeating: 1, count: 32))])
        let innerB = storedZip([("b.mod", Data(repeating: 2, count: 32))])
        let outer = workDir.appendingPathComponent("outer.zip")
        try storedZip([("a.zip", innerA), ("b.zip", innerB)]).write(to: outer)
        let limits = PlaylistScanner.ArchiveUnpackLimits(
            maxUncompressedBytes: Int64(innerA.count + innerB.count + 32), maxEntries: 3)
        let entries = PlaylistScanner.collectEntries(from: [outer], tempDir: tempDir,
            archiveLimits: limits, maxArchives: 3)
        XCTAssertEqual(entries.count, 1)
        let children = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertFalse(children.contains { $0.hasPrefix("extracted-") })
        let none = PlaylistScanner.collectEntries(from: [outer], tempDir: tempDir,
            archiveLimits: .default, maxArchives: 1)
        XCTAssertTrue(none.isEmpty)
    }

    func testHiddenFilesAndNestedArchivesRemainPlayable() throws {
        let inner = storedZip([("inside.it", Data([3]))])
        let archive = workDir.appendingPathComponent("hidden.zip")
        try storedZip([(".direct.mod", Data([1])), (".folder/song.xm", Data([2])),
                       (".inner.zip", inner)]).write(to: archive)
        let entries = PlaylistScanner.collectEntries(from: [archive], tempDir: tempDir)
        XCTAssertEqual(Set(entries.map(\.displayName)), [".direct.mod", "song.xm", "inside.it"])
        for entry in entries { XCTAssertTrue(FileManager.default.fileExists(atPath: entry.url.path)) }
    }

    // MARK: - Einsammeln mit Hierarchie

    func testCollectEntriesKeepsFolderHierarchy() throws {
        _ = try makeFile("root.mod")
        _ = try makeFile("Chiptunes/tune.mod")
        _ = try makeFile("Chiptunes/Deep/nested.s3m")
        _ = try makeFile("Chiptunes/Deep/impulse.it")
        _ = try makeFile("Chiptunes/notes.txt") // kein Mod — muss ignoriert werden

        let entries = PlaylistScanner.collectEntries(from: [workDir], tempDir: tempDir)

        XCTAssertEqual(entries.count, 4)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.displayName, $0.folderPath) })
        XCTAssertEqual(byName["root.mod"], [])
        XCTAssertEqual(byName["tune.mod"], ["Chiptunes"])
        XCTAssertEqual(byName["nested.s3m"], ["Chiptunes", "Deep"])
        XCTAssertEqual(byName["impulse.it"], ["Chiptunes", "Deep"])
        // Kopien liegen im Temp-Ziel, nicht im Quellordner.
        for entry in entries {
            XCTAssertTrue(entry.url.path.hasPrefix(tempDir.path))
        }
    }

    func testCollectEntriesFollowsSymbolicLinksInUserDirectory() throws {
        let targetDirectory = workDir.appendingPathComponent("Ziel", isDirectory: true)
        try FileManager.default.createDirectory(
            at: targetDirectory, withIntermediateDirectories: true)
        let targetFile = targetDirectory.appendingPathComponent("verlinkt.mod")
        try Data([0x78]).write(to: targetFile)

        let sourceDirectory = workDir.appendingPathComponent("Quelle", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: sourceDirectory.appendingPathComponent("datei.mod"),
            withDestinationURL: targetFile)
        try FileManager.default.createSymbolicLink(
            at: sourceDirectory.appendingPathComponent("Ordner"),
            withDestinationURL: targetDirectory)

        XCTAssertTrue(PlaylistScanner.directoryContainsPlayableContent(sourceDirectory))
        let entries = PlaylistScanner.collectEntries(
            from: [sourceDirectory], tempDir: tempDir)

        XCTAssertEqual(Set(entries.map(\.displayName)), ["datei.mod", "verlinkt.mod"])
        XCTAssertEqual(entries.first { $0.displayName == "verlinkt.mod" }?.folderPath,
                       ["Ordner"])
        let linkedEntry = try XCTUnwrap(entries.first { $0.displayName == "datei.mod" })
        XCTAssertEqual(try Data(contentsOf: linkedEntry.url), Data([0x78]))
        XCTAssertNotEqual(
            try linkedEntry.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink,
            true,
            "die Temp-Kopie muss nach Ende des Security-Scopes eigenstaendig bleiben")
    }

    func testUserDirectorySymlinkCycleTerminates() throws {
        let sourceDirectory = workDir.appendingPathComponent("Zyklus", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: sourceDirectory.appendingPathComponent("zurueck"),
            withDestinationURL: sourceDirectory)

        XCTAssertFalse(PlaylistScanner.directoryContainsPlayableContent(sourceDirectory))
        XCTAssertTrue(PlaylistScanner.collectEntries(
            from: [sourceDirectory], tempDir: tempDir).isEmpty)
    }

    // MARK: - Baum & flache Reihenfolge

    func testBuildTreeSortsAndFlattenMatchesDisplayOrder() throws {
        func entry(_ name: String, _ path: [String]) -> PlaylistScanner.Entry {
            PlaylistScanner.Entry(url: URL(fileURLWithPath: "/x/\(path.joined(separator: "_"))_\(name)"),
                                  displayName: name, folderPath: path)
        }
        let entries = [
            entry("zzz.mod", []),
            entry("b.mod", ["Beta"]),
            entry("a2.mod", ["Alpha"]),
            entry("a10.mod", ["Alpha"]),
            entry("deep.mod", ["Alpha", "Inner"]),
        ]
        let tree = PlaylistScanner.buildTree(entries)

        // Ebene 1: Ordner alphabetisch, Dateien danach.
        XCTAssertEqual(tree.subfolders.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(tree.files.map(\.displayName), ["zzz.mod"])
        // Numerisch-natuerliche Sortierung innerhalb eines Ordners (a2 vor a10).
        XCTAssertEqual(tree.subfolders[0].files.map(\.displayName), ["a2.mod", "a10.mod"])
        // Pfad-IDs sind die "/"-verbundenen Komponenten.
        XCTAssertEqual(tree.subfolders[0].subfolders[0].path, "Alpha/Inner")

        // Flache Abspiel-Reihenfolge = Tiefensuche in Anzeige-Reihenfolge:
        // Alpha/Inner/deep, Alpha/a2, Alpha/a10, Beta/b, dann Wurzel-Dateien.
        let flat = PlaylistScanner.flattenedFiles(tree).map(\.displayName)
        XCTAssertEqual(flat, ["deep.mod", "a2.mod", "a10.mod", "b.mod", "zzz.mod"])
    }

    // MARK: - Archive

    // Beide Fixtures enthalten: Coolpack/alpha.mod, Coolpack/sub/beta.mod,
    // Coolpack/readme.txt (Nicht-Mod, muss ignoriert werden).
    private static let zipFixtureBase64 = "UEsDBAoAAAAAABF95VwAAAAAAAAAAAAAAAAJABwAQ29vbHBhY2svVVQJAAPSXkpq0l5KanV4CwABBPUBAAAEAAAAAFBLAwQKAAAAAAARfeVcAAAAAAAAAAAAAAAADQAcAENvb2xwYWNrL3N1Yi9VVAkAA9JeSmrSXkpqdXgLAAEE9QEAAAQAAAAAUEsDBAoAAAAAABF95VyDFtyMAQAAAAEAAAAVABwAQ29vbHBhY2svc3ViL2JldGEubW9kVVQJAAPSXkpq0l5KanV4CwABBPUBAAAEAAAAAHhQSwMECgAAAAAAEX3lXIMW3IwBAAAAAQAAABMAHABDb29scGFjay9yZWFkbWUudHh0VVQJAAPSXkpq0l5KanV4CwABBPUBAAAEAAAAAHhQSwMECgAAAAAAEX3lXIMW3IwBAAAAAQAAABIAHABDb29scGFjay9hbHBoYS5tb2RVVAkAA9JeSmrSXkpqdXgLAAEE9QEAAAQAAAAAeFBLAQIeAwoAAAAAABF95VwAAAAAAAAAAAAAAAAJABgAAAAAAAAAEADtQQAAAABDb29scGFjay9VVAUAA9JeSmp1eAsAAQT1AQAABAAAAABQSwECHgMKAAAAAAARfeVcAAAAAAAAAAAAAAAADQAYAAAAAAAAABAA7UFDAAAAQ29vbHBhY2svc3ViL1VUBQAD0l5KanV4CwABBPUBAAAEAAAAAFBLAQIeAwoAAAAAABF95VyDFtyMAQAAAAEAAAAVABgAAAAAAAEAAACkgYoAAABDb29scGFjay9zdWIvYmV0YS5tb2RVVAUAA9JeSmp1eAsAAQT1AQAABAAAAABQSwECHgMKAAAAAAARfeVcgxbcjAEAAAABAAAAEwAYAAAAAAABAAAApIHaAAAAQ29vbHBhY2svcmVhZG1lLnR4dFVUBQAD0l5KanV4CwABBPUBAAAEAAAAAFBLAQIeAwoAAAAAABF95VyDFtyMAQAAAAEAAAASABgAAAAAAAEAAACkgSgBAABDb29scGFjay9hbHBoYS5tb2RVVAUAA9JeSmp1eAsAAQT1AQAABAAAAABQSwUGAAAAAAUABQCuAQAAdQEAAAAA"
    private static let sevenZipFixtureBase64 = "N3q8ryccAATZ8ns+mQAAAAAAAAAiAAAAAAAAAKxU7hQBAAJ4eHgAAACBMweuD84lflFCynNIGZqoUZTnWFv8ZmYGcG13U53ZggeBDAzB8o5I0anqwxnW/rhjcps9sIvSAoEiOVrO6+r7ZZVEQtnNAcSLzgb6BFxP+wgEOb4uJbOflweo3aMUoAy0Z7Bg1mOI5QcyHrl3sDtLu/afdnufYpe2vkwzcjoasFLGjLA8Fy+v6omM20gAAAAXBgcBCYCSAAcLAQABIwMBAQVdABAAAAyBMgoB+cP6zwAA"

    private func runArchiveTest(base64: String, filename: String) throws {
        // Ohne System-bsdtar kann der Scanner grundsaetzlich nicht entpacken
        // (z.B. schlanker Linux-Container ohne libarchive-tools). Das ist kein
        // Fehler des Scanners — sauber ueberspringen statt rot melden.
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Scan nicht pruefbar (Linux: libarchive-tools)"
        )
        let archiveURL = workDir.appendingPathComponent(filename)
        try XCTUnwrap(Data(base64Encoded: base64)).write(to: archiveURL)

        let entries = PlaylistScanner.collectEntries(from: [archiveURL], tempDir: tempDir)

        // Das Archiv erscheint als Ordner-Komponente OHNE Endung ("fixture"),
        // sein Innenleben als normale Hierarchie; readme.txt bleibt aussen vor.
        XCTAssertEqual(entries.count, 2, "erwartet alpha.mod + beta.mod aus \(filename)")
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.displayName, $0.folderPath) })
        let archiveNode = (filename as NSString).deletingPathExtension
        XCTAssertEqual(byName["alpha.mod"], [archiveNode, "Coolpack"])
        XCTAssertEqual(byName["beta.mod"], [archiveNode, "Coolpack", "sub"])
    }

    func testZipArchiveIsScannedLikeAFolder() throws {
        try runArchiveTest(base64: Self.zipFixtureBase64, filename: "fixture.zip")
    }

    func test7zArchiveIsScannedLikeAFolder() throws {
        try runArchiveTest(base64: Self.sevenZipFixtureBase64, filename: "fixture.7z")
    }

    func testCorruptArchiveIsSkippedWithoutEntries() throws {
        let archiveURL = workDir.appendingPathComponent("broken.zip")
        try Data("kein echtes archiv".utf8).write(to: archiveURL)
        let entries = PlaylistScanner.collectEntries(from: [archiveURL], tempDir: tempDir)
        XCTAssertTrue(entries.isEmpty)
    }

    func testDirectoryContainsPlayableContentSeesModsAndArchives() throws {
        _ = try makeFile("Leer/nur-text.txt")
        XCTAssertFalse(PlaylistScanner.directoryContainsPlayableContent(workDir.appendingPathComponent("Leer")))
        _ = try makeFile("MitMod/deep/song.mod")
        XCTAssertTrue(PlaylistScanner.directoryContainsPlayableContent(workDir.appendingPathComponent("MitMod")))
    }

    func testDirectoryProbeIgnoresNonFilesWithModuleNames() throws {
        let source = workDir.appendingPathComponent("Nur-Dateinamen", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("ordner.xm", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("kaputt.s3m"),
            withDestinationURL: source.appendingPathComponent("fehlt"))

        XCTAssertFalse(
            PlaylistScanner.directoryContainsPlayableContent(source),
            "Ordner und tote Links sind trotz Modulendung nicht spielbar")
        XCTAssertTrue(
            PlaylistScanner.collectEntries(from: [source], tempDir: tempDir).isEmpty)
    }

    // Packt `sources` (relativ zu `directory`) in ein Archiv im Arbeitsordner.
    private func pack(_ names: [String], from directory: URL, as name: String) throws -> URL {
        let tool = try XCTUnwrap(PlaylistScanner.bsdtarURL)
        let archiveURL = directory.appendingPathComponent(name)
        let process = Process()
        process.executableURL = tool
        process.arguments = ["-a", "-c", "-f", archiveURL.path, "-C", directory.path] + names
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "bsdtar konnte \(name) nicht erzeugen")
        for entry in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry))
        }
        return archiveURL
    }

    // Jenseits der Tiefengrenze wird ein Archiv gar nicht mehr geoeffnet — es
    // darf dann aber auch nicht in den Modul-Zweig fallen. Ein Archiv mit
    // Amiga-Namenskonvention (`mod.<name>.zip`) traf genau das: es landete als
    // unspielbare "Moduldatei" in der Playlist, obwohl es ein ZIP ist.
    func testArchiveBeyondTheDepthLimitIsSkippedInsteadOfTreatedAsModule() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Scan nicht pruefbar (Linux: libarchive-tools)")

        let nest = workDir.appendingPathComponent("Nest", isDirectory: true)
        try FileManager.default.createDirectory(at: nest, withIntermediateDirectories: true)
        try Data([0x78]).write(to: nest.appendingPathComponent("platzhalter.txt"))

        // Ebene 4 traegt die Amiga-Namenskonvention und liegt damit genau auf
        // der Grenze: mod.inner.zip ist ein Archiv, matcht aber auch "mod.".
        _ = try pack(["platzhalter.txt"], from: nest, as: "mod.inner.zip")
        _ = try pack(["mod.inner.zip"], from: nest, as: "l3.zip")
        _ = try pack(["l3.zip"], from: nest, as: "l2.zip")
        let outer = try pack(["l2.zip"], from: nest, as: "outer.zip")

        let entries = PlaylistScanner.collectEntries(from: [outer], tempDir: tempDir)
        XCTAssertTrue(
            entries.isEmpty,
            "ein zu tief liegendes Archiv darf nicht als Modul eingesammelt werden, war: "
            + entries.map(\.displayName).joined(separator: ", "))
    }

    // Gegenprobe: innerhalb der Grenze wird weiterhin ausgepackt, damit der
    // Test oben nicht einfach nur die ganze Rekursion abschaltet.
    func testArchiveWithinTheDepthLimitIsStillUnpacked() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — Archiv-Scan nicht pruefbar (Linux: libarchive-tools)")

        let nest = workDir.appendingPathComponent("Nest2", isDirectory: true)
        try FileManager.default.createDirectory(at: nest, withIntermediateDirectories: true)
        try Data([0x78]).write(to: nest.appendingPathComponent("song.mod"))

        _ = try pack(["song.mod"], from: nest, as: "inner.zip")
        let outer = try pack(["inner.zip"], from: nest, as: "outer.zip")

        let entries = PlaylistScanner.collectEntries(from: [outer], tempDir: tempDir)
        XCTAssertEqual(entries.map(\.displayName), ["song.mod"])
        XCTAssertEqual(entries.first?.folderPath, ["outer", "inner"])
    }

    // bsdtar legt Archiv-Links als echte Links im temporaeren Ziel an. Der
    // Playlist-Scanner darf ihnen weder beim Modul-Kopieren noch bei einer
    // vermeintlichen inner.zip folgen, sonst verlaesst er unbemerkt das
    // Entpackverzeichnis des fremden Archivs.
    //
    // Seit 1.6.10 uebernimmt der eigene Leser auch hier, und der ist strenger
    // als das frueher genutzte bsdtar: Ein Link macht das GANZE Archiv
    // ungueltig, statt nur uebersprungen zu werden. Deshalb kommt hier
    // nichts mehr heraus — auch nicht die harmlose direkt.mod.
    func testArchiveWithASymbolicLinkIsRejectedAsAWhole() throws {
        try XCTSkipIf(
            PlaylistScanner.bsdtarURL == nil,
            "bsdtar nicht installiert — das Testarchiv laesst sich nicht packen")

        let external = workDir.appendingPathComponent("Extern", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data([0x65]).write(to: external.appendingPathComponent("extern.mod"))
        let externalArchive = try pack(["extern.mod"], from: external, as: "extern.zip")

        let outerDir = workDir.appendingPathComponent("Aussen", isDirectory: true)
        try FileManager.default.createDirectory(at: outerDir, withIntermediateDirectories: true)
        try Data([0x64]).write(to: outerDir.appendingPathComponent("direkt.mod"))
        try FileManager.default.createSymbolicLink(
            at: outerDir.appendingPathComponent("inner.zip"),
            withDestinationURL: externalArchive)
        let outer = try pack(["direkt.mod", "inner.zip"], from: outerDir, as: "outer.zip")

        let entries = PlaylistScanner.collectEntries(from: [outer], tempDir: tempDir)

        XCTAssertTrue(entries.isEmpty,
                      "ein Archiv mit Link wird ganz abgelehnt, nicht teilweise entpackt")
        XCTAssertFalse(entries.contains { $0.displayName == "extern.mod" },
                       "dem Link darf der Scanner unter keinen Umstaenden folgen")
    }
}

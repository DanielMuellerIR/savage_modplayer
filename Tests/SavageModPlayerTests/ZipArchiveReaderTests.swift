import XCTest
@testable import SavageModPlayerCore

// Der ZIP-Reader existiert nur dort, wo es das Compression-Framework gibt.
// Unter Linux entfaellt damit auch diese Suite.
#if canImport(Compression)
import Compression

// Tests fuer den eigenen ZIP-Reader. Alle Archive entstehen hier im Test aus
// von Hand geschriebenen Bytes — es liegt kein einziges Archiv und keine
// Moduldatei im Repo. Das Arbeitsverzeichnis wird in tearDown geloescht.
//
// Geprueft werden drei Gruppen:
// 1. Funktioniert es ueberhaupt (stored, deflate, Struktur, Vorfilter)?
// 2. Haelt die Sicherheitsschicht (Zip-Slip, Bomben, CRC, Links, Passwort)?
// 3. Werden Sonderfaelle sauber abgelehnt statt falsch gelesen (ZIP64,
//    unbekannte Methode, Abbruch)?
final class ZipArchiveReaderTests: XCTestCase {

    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZipArchiveReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private var destination: URL { workDir.appendingPathComponent("out", isDirectory: true) }

    // MARK: - Bausteine fuer Test-Archive

    // Ein Eintrag, wie er ins Testarchiv geschrieben werden soll.
    private struct ZipItem {
        var name: String
        /// Rohe Namensbytes, falls der Name absichtlich kein UTF-8 ist (CP437).
        var rawNameBytes: [UInt8]?
        var payload: Data
        /// 0 = stored, 8 = deflate, alles andere landet ungepackt im Archiv und
        /// gilt fuer den Reader als nicht unterstuetzt.
        var method: UInt16
        var flags: UInt16
        /// Falsche Pruefsumme erzwingen.
        var crcOverride: UInt32?
        /// Gelogene Groessenangabe im Inhaltsverzeichnis (fuer Bomben-Tests).
        var declaredSizeOverride: UInt32?
        var externalAttributes: UInt32
        var versionMadeBy: UInt16
        /// Groessen/CRC erst hinter den Daten (Flag-Bit 3).
        var useDataDescriptor: Bool

        init(
            name: String,
            payload: Data = Data(),
            method: UInt16 = 0,
            flags: UInt16 = 0,
            rawNameBytes: [UInt8]? = nil,
            crcOverride: UInt32? = nil,
            declaredSizeOverride: UInt32? = nil,
            externalAttributes: UInt32 = 0,
            versionMadeBy: UInt16 = 0x0314,   // 0x03 = Unix, 0x14 = Version 2.0
            useDataDescriptor: Bool = false
        ) {
            self.name = name
            self.payload = payload
            self.method = method
            self.flags = flags
            self.rawNameBytes = rawNameBytes
            self.crcOverride = crcOverride
            self.declaredSizeOverride = declaredSizeOverride
            self.externalAttributes = externalAttributes
            self.versionMadeBy = versionMadeBy
            self.useDataDescriptor = useDataDescriptor
        }
    }

    // Baut ein vollstaendiges ZIP: je Eintrag ein Local File Header samt Daten,
    // danach das Central Directory und zum Schluss das EOCD.
    private func makeArchive(
        _ items: [ZipItem],
        comment: Data = Data(),
        forceZip64Marker: Bool = false
    ) throws -> Data {
        var body = Data()
        var directory = Data()

        for item in items {
            let nameBytes = item.rawNameBytes ?? Array(item.name.utf8)
            let stored: Data = item.method == 8 ? try deflateRaw(item.payload) : item.payload
            let crc = item.crcOverride ?? crc32(item.payload)
            let declaredSize = item.declaredSizeOverride ?? UInt32(item.payload.count)
            let offset = UInt32(body.count)
            var flags = item.flags
            if item.useDataDescriptor { flags |= 0x0008 }

            // Local File Header
            body.appendUInt32(0x0403_4B50)
            body.appendUInt16(20)                      // benoetigte Version
            body.appendUInt16(flags)
            body.appendUInt16(item.method)
            body.appendUInt16(0)                       // Uhrzeit
            body.appendUInt16(0)                       // Datum
            // Bei Data Descriptor stehen hier definitionsgemaess Nullen — der
            // Reader muss trotzdem die Werte aus dem Central Directory nehmen.
            body.appendUInt32(item.useDataDescriptor ? 0 : crc)
            body.appendUInt32(item.useDataDescriptor ? 0 : UInt32(stored.count))
            body.appendUInt32(item.useDataDescriptor ? 0 : declaredSize)
            body.appendUInt16(UInt16(nameBytes.count))
            body.appendUInt16(0)                       // Extra-Feld
            body.append(contentsOf: nameBytes)
            body.append(stored)
            if item.useDataDescriptor {
                body.appendUInt32(0x0807_4B50)         // optionale Signatur
                body.appendUInt32(crc)
                body.appendUInt32(UInt32(stored.count))
                body.appendUInt32(declaredSize)
            }

            // Central Directory Header
            directory.appendUInt32(0x0201_4B50)
            directory.appendUInt16(item.versionMadeBy)
            directory.appendUInt16(20)
            directory.appendUInt16(flags)
            directory.appendUInt16(item.method)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt32(crc)
            directory.appendUInt32(UInt32(stored.count))
            directory.appendUInt32(declaredSize)
            directory.appendUInt16(UInt16(nameBytes.count))
            directory.appendUInt16(0)                  // Extra-Feld
            directory.appendUInt16(0)                  // Kommentar
            directory.appendUInt16(0)                  // Startdiskette
            directory.appendUInt16(0)                  // interne Attribute
            directory.appendUInt32(item.externalAttributes)
            directory.appendUInt32(offset)
            directory.append(contentsOf: nameBytes)
        }

        var archive = body
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.appendUInt32(0x0605_4B50)
        archive.appendUInt16(0)                        // Disketten-Nummer
        archive.appendUInt16(0)                        // Diskette mit CD-Start
        archive.appendUInt16(UInt16(items.count))
        archive.appendUInt16(UInt16(items.count))
        archive.appendUInt32(UInt32(directory.count))
        // Der ZIP64-Platzhalter steht genau an dieser Stelle: 0xFFFFFFFF heisst
        // "der echte Wert steht im ZIP64-Datensatz".
        archive.appendUInt32(forceZip64Marker ? 0xFFFF_FFFF : directoryOffset)
        archive.appendUInt16(UInt16(comment.count))
        archive.append(comment)
        return archive
    }

    private func writeArchive(_ items: [ZipItem], name: String = "test.zip", comment: Data = Data(), forceZip64Marker: Bool = false) throws -> URL {
        let url = workDir.appendingPathComponent(name)
        try makeArchive(items, comment: comment, forceZip64Marker: forceZip64Marker).write(to: url)
        return url
    }

    // Raw-Deflate erzeugen. Apples COMPRESSION_ZLIB ist genau das Format ohne
    // zlib-Rahmen, das auch in einer ZIP-Datei steht.
    private func deflateRaw(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + 64 * 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            data.withUnsafeBytes { source -> Int in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else {
            throw XCTSkip("Deflate-Testdaten ließen sich nicht erzeugen")
        }
        return output.prefix(written)
    }

    // Bewusst eigenstaendige, bitweise CRC32-Berechnung — sie soll die
    // Tabellenvariante im Reader pruefen, nicht spiegeln.
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // Schlecht komprimierbare, aber reproduzierbare Testdaten.
    private func pseudoRandomData(count: Int, seed: UInt64 = 0x5EED_1234) -> Data {
        var state = seed
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for _ in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes.append(UInt8((state >> 33) & 0xFF))
        }
        return Data(bytes)
    }

    private func acceptAll(_ url: URL) -> Bool { true }

    // Fuehrt den Aufruf aus und liefert den erwarteten ZipArchiveError zurueck.
    private func zipError(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) -> ZipArchiveError? {
        do {
            try body()
            XCTFail("Fehler erwartet, aber der Aufruf lief durch", file: file, line: line)
            return nil
        } catch let error as ZipArchiveError {
            return error
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)", file: file, line: line)
            return nil
        }
    }

    private func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: destination.appendingPathComponent(relativePath).path)
    }

    // MARK: - Grundfunktion

    func testStoredEntryIsExtractedByteIdentical() throws {
        let payload = pseudoRandomData(count: 5_000)
        let archive = try writeArchive([ZipItem(name: "song.mod", payload: payload, method: 0)])

        let result = try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)

        XCTAssertEqual(result.extractedFiles.count, 1)
        XCTAssertEqual(result.skippedEntries, 0)
        XCTAssertEqual(result.totalUncompressedBytes, Int64(payload.count))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(result.extractedFiles.first)), payload)
    }

    func testDeflatedEntryLargerThanBlockSizeIsExtractedByteIdentical() throws {
        // 1 MiB laeuft durch 16 Eingabe- und mindestens 16 Ausgabebloecke — der
        // Streaming-Pfad wird also wirklich mehrfach durchlaufen.
        let payload = pseudoRandomData(count: 1024 * 1024)
        let archive = try writeArchive([ZipItem(name: "big.mod", payload: payload, method: 8)])

        let result = try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)

        XCTAssertEqual(result.extractedFiles.count, 1)
        XCTAssertEqual(result.totalUncompressedBytes, Int64(payload.count))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(result.extractedFiles.first)), payload)
    }

    func testNestedDirectoryStructureIsPreserved() throws {
        let alpha = Data("alpha".utf8)
        let beta = pseudoRandomData(count: 2_048)
        let archive = try writeArchive([
            ZipItem(name: "Pack/"),                                        // Verzeichniseintrag
            ZipItem(name: "Pack/alpha.mod", payload: alpha, method: 0),
            ZipItem(name: "Pack/sub/"),
            ZipItem(name: "Pack/sub/beta.mod", payload: beta, method: 8)
        ])

        let result = try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)

        XCTAssertEqual(result.extractedFiles.count, 2)
        // Die beiden Verzeichniseintraege zaehlen als uebersprungen und werden
        // nicht als Datei angelegt.
        XCTAssertEqual(result.skippedEntries, 2)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Pack/alpha.mod")), alpha)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Pack/sub/beta.mod")), beta)
    }

    func testPrefilterExtractsOnlyWantedEntries() throws {
        let archive = try writeArchive([
            ZipItem(name: "song.mod", payload: Data("mod".utf8), method: 8),
            ZipItem(name: "readme.txt", payload: Data("nur text".utf8), method: 8)
        ])

        let result = try ZipArchiveReader.extract(
            archive: archive,
            to: destination,
            shouldExtract: PlaylistScanner.isModFile
        )

        XCTAssertEqual(result.extractedFiles.map(\.lastPathComponent), ["song.mod"])
        XCTAssertEqual(result.skippedEntries, 1)
        XCTAssertTrue(fileExists("song.mod"))
        XCTAssertFalse(fileExists("readme.txt"), "gefilterte Einträge dürfen gar nicht erst entpackt werden")
    }

    func testDataDescriptorEntryUsesCentralDirectorySizes() throws {
        // Flag-Bit 3: der Local File Header enthaelt nur Nullen, die echten
        // Werte stehen im Central Directory (und hinter den Daten).
        let payload = pseudoRandomData(count: 3_000)
        let archive = try writeArchive([
            ZipItem(name: "stream.mod", payload: payload, method: 8, useDataDescriptor: true)
        ])

        let result = try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)

        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(result.extractedFiles.first)), payload)
    }

    func testArchiveCommentDoesNotHideTheEndOfCentralDirectory() throws {
        let payload = Data("mit Kommentar".utf8)
        let archive = try writeArchive(
            [ZipItem(name: "song.mod", payload: payload, method: 0)],
            comment: Data(repeating: 0x41, count: 5_000)
        )

        let result = try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)

        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(result.extractedFiles.first)), payload)
    }

    // MARK: - Inhaltsverzeichnis lesen

    func testInspectReturnsMetadataWithoutExtracting() throws {
        let payload = pseudoRandomData(count: 1_500)
        let archive = try writeArchive([
            ZipItem(name: "Pack/"),
            ZipItem(name: "Pack/song.mod", payload: payload, method: 8),
            ZipItem(name: "Pack/exotic.mod", payload: payload, method: 12)   // bzip2: nicht unterstuetzt
        ])

        let entries = try ZipArchiveReader.inspect(archive: archive)

        XCTAssertEqual(entries.map(\.path), ["Pack/", "Pack/song.mod", "Pack/exotic.mod"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertFalse(entries[1].isDirectory)
        XCTAssertEqual(entries[1].uncompressedSize, Int64(payload.count))
        XCTAssertLessThan(entries[1].compressedSize, Int64(payload.count) + 1_024)
        XCTAssertTrue(entries[1].isSupported)
        XCTAssertFalse(entries[2].isSupported, "Methode 12 ist nicht unterstützt")
        // inspect schreibt nichts.
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testUnsupportedCompressionMethodIsCountedAsSkipped() throws {
        let archive = try writeArchive([
            ZipItem(name: "ok.mod", payload: Data("ok".utf8), method: 0),
            ZipItem(name: "exotic.mod", payload: Data("exotisch".utf8), method: 12)
        ])

        let result = try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)

        XCTAssertEqual(result.extractedFiles.map(\.lastPathComponent), ["ok.mod"])
        XCTAssertEqual(result.skippedEntries, 1)
        XCTAssertFalse(fileExists("exotic.mod"))
    }

    // MARK: - Zip-Slip

    func testRelativeEscapeIsRejected() throws {
        let archive = try writeArchive([ZipItem(name: "../evil.mod", payload: Data("boese".utf8), method: 0)])

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }

        guard case .some(.unsafeEntryPath) = error else {
            return XCTFail("unsafeEntryPath erwartet, war: \(String(describing: error))")
        }
        // Weder neben noch im Zielordner darf etwas gelandet sein.
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appendingPathComponent("evil.mod").path))
        XCTAssertFalse(fileExists("evil.mod"))
    }

    func testAbsolutePathIsRejected() throws {
        // Absoluter Pfad, der bewusst im eigenen Arbeitsverzeichnis liegt: der
        // Test bleibt damit hermetisch, egal wie sich der Reader verhaelt.
        let absoluteName = workDir.appendingPathComponent("evil.mod").path
        let archive = try writeArchive([ZipItem(name: absoluteName, payload: Data("boese".utf8), method: 0)])

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }

        guard case .some(.unsafeEntryPath) = error else {
            return XCTFail("unsafeEntryPath erwartet, war: \(String(describing: error))")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: absoluteName))
    }

    func testBackslashAndDriveLetterAreRejected() throws {
        for name in ["sub\\evil.mod", "C:/evil.mod", "C:\\evil.mod"] {
            let archive = try writeArchive(
                [ZipItem(name: name, payload: Data("boese".utf8), method: 0)],
                name: "slip-\(abs(name.hashValue)).zip"
            )
            let error = zipError {
                try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
            }
            guard case .some(.unsafeEntryPath) = error else {
                return XCTFail("unsafeEntryPath erwartet für „\(name)“, war: \(String(describing: error))")
            }
        }
    }

    func testPreexistingSymlinkInDestinationCannotBeUsedToEscape() throws {
        // Der Eintragsname selbst ist harmlos ("sub/evil.mod"). Im Ziel liegt
        // aber schon ein Ordner-Symlink namens "sub", der nach draussen zeigt.
        // Nur ein Vergleich AUFGELÖSTER Pfade faengt das ab — und das Ziel
        // liegt hier zusaetzlich hinter dem /var-Symlink von macOS.
        let outside = workDir.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("sub"),
            withDestinationURL: outside
        )
        let archive = try writeArchive([ZipItem(name: "sub/evil.mod", payload: Data("boese".utf8), method: 0)])

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }

        guard case .some(.unsafeEntryPath) = error else {
            return XCTFail("unsafeEntryPath erwartet, war: \(String(describing: error))")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("evil.mod").path))
    }

    func testSymbolicLinkEntryIsRejected() throws {
        // Unix-Modus S_IFLNK (0xA000) in den oberen 16 Bit der externen
        // Attribute — so markiert ein Unix-Packer einen symbolischen Link.
        let archive = try writeArchive([
            ZipItem(
                name: "link.mod",
                payload: Data("/etc/passwd".utf8),
                method: 0,
                externalAttributes: 0xA1FF_0000
            )
        ])

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }

        guard case .some(.symbolicLinkEntry) = error else {
            return XCTFail("symbolicLinkEntry erwartet, war: \(String(describing: error))")
        }
        XCTAssertFalse(fileExists("link.mod"))
    }

    // MARK: - Zip-Bomben

    func testEntryLimitAbortsDuringInflateAndRemovesFile() throws {
        // Die Groessenangabe luegt (10 Byte), tatsaechlich kommen 100 KiB
        // heraus. Nur eine Pruefung WAEHREND des Entpackens faengt das ab.
        let payload = pseudoRandomData(count: 100 * 1024)
        let archive = try writeArchive([
            ZipItem(name: "bomb.mod", payload: payload, method: 8, declaredSizeOverride: 10)
        ])
        var limits = ZipArchiveReader.Limits.default
        limits.maxEntryUncompressedBytes = 50 * 1024

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll, limits: limits)
        }

        guard case .some(.entryTooLarge) = error else {
            return XCTFail("entryTooLarge erwartet, war: \(String(describing: error))")
        }
        XCTAssertFalse(fileExists("bomb.mod"), "halbfertige Zieldatei muss entfernt werden")
    }

    func testTotalLimitAborts() throws {
        let payload = pseudoRandomData(count: 64 * 1024)
        let archive = try writeArchive([
            ZipItem(name: "one.mod", payload: payload, method: 0),
            ZipItem(name: "two.mod", payload: payload, method: 0)
        ])
        var limits = ZipArchiveReader.Limits.default
        limits.maxTotalUncompressedBytes = 100 * 1024

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll, limits: limits)
        }

        guard case .some(.archiveTooLarge) = error else {
            return XCTFail("archiveTooLarge erwartet, war: \(String(describing: error))")
        }
        XCTAssertTrue(fileExists("one.mod"), "der erste Eintrag war noch im Rahmen")
        XCTAssertFalse(fileExists("two.mod"))
    }

    func testCompressionRatioIsCheckedDuringInflate() throws {
        // 8 MiB Nullen komprimieren auf wenige Kilobyte — das klassische
        // Bomben-Muster. Die Groessenangabe luegt wieder. Die Menge liegt
        // bewusst ueber der Schonfrist des Readers, ab der er das Verhaeltnis
        // ueberhaupt erst bewertet.
        let payload = Data(count: 8 * 1024 * 1024)
        let archive = try writeArchive([
            ZipItem(name: "bomb.mod", payload: payload, method: 8, crcOverride: 0, declaredSizeOverride: 100)
        ])
        var limits = ZipArchiveReader.Limits.default
        limits.maxCompressionRatio = 20

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll, limits: limits)
        }

        guard case .some(.compressionRatioExceeded) = error else {
            return XCTFail("compressionRatioExceeded erwartet, war: \(String(describing: error))")
        }
        XCTAssertFalse(fileExists("bomb.mod"))
    }

    func testEntryCountLimitAborts() throws {
        let items = (0..<5).map { ZipItem(name: "song\($0).mod", payload: Data("x".utf8), method: 0) }
        let archive = try writeArchive(items)
        var limits = ZipArchiveReader.Limits.default
        limits.maxEntryCount = 4

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll, limits: limits)
        }

        guard case .some(.tooManyEntries) = error else {
            return XCTFail("tooManyEntries erwartet, war: \(String(describing: error))")
        }
    }

    func testInspectEnforcesEntryCountLimit() throws {
        // Auch der reine Inhaltsverzeichnis-Pfad (inspect) respektiert das
        // Limit — frueher wurde es dort gar nicht geprueft.
        let items = (0..<5).map { ZipItem(name: "song\($0).mod", payload: Data("x".utf8), method: 0) }
        let archive = try writeArchive(items)
        var limits = ZipArchiveReader.Limits.default
        limits.maxEntryCount = 4

        let error = zipError {
            _ = try ZipArchiveReader.inspect(archive: archive, limits: limits)
        }
        guard case .some(.tooManyEntries) = error else {
            return XCTFail("tooManyEntries erwartet, war: \(String(describing: error))")
        }
    }

    // MARK: - Kollisionen auf dieselbe Zieldatei

    func testDuplicateEntryNameIsRejected() throws {
        let archive = try writeArchive([
            ZipItem(name: "twice.mod", payload: Data("erste".utf8), method: 0),
            ZipItem(name: "twice.mod", payload: Data("zweite".utf8), method: 0)
        ])
        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }
        guard case .some(.duplicateEntryPath) = error else {
            return XCTFail("duplicateEntryPath erwartet, war: \(String(describing: error))")
        }
    }

    func testCaseVariantCollisionIsRejected() throws {
        // Auf case-insensitivem APFS traefen beide Schreibweisen dieselbe
        // Datei; der spaetere Eintrag wuerde den frueheren ueberschreiben.
        let archive = try writeArchive([
            ZipItem(name: "collection/Song.MOD", payload: Data("gross".utf8), method: 0),
            ZipItem(name: "collection/song.mod", payload: Data("klein".utf8), method: 0)
        ])
        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }
        guard case .some(.duplicateEntryPath) = error else {
            return XCTFail("duplicateEntryPath erwartet, war: \(String(describing: error))")
        }
    }

    func testUnicodeNormalizationCollisionIsRejected() throws {
        // NFC "ö" und NFD "o + Kombinationstrema" sind fuer APFS derselbe
        // Name. Beide Eintraege sind als UTF-8 geflaggt (Bit 11).
        let nfc = Array("m\u{00F6}dul.mod".utf8)
        let nfd = Array("mo\u{0308}dul.mod".utf8)
        let archive = try writeArchive([
            ZipItem(name: "nfc", payload: Data("eins".utf8), method: 0, flags: 0x0800, rawNameBytes: nfc),
            ZipItem(name: "nfd", payload: Data("zwei".utf8), method: 0, flags: 0x0800, rawNameBytes: nfd)
        ])
        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }
        guard case .some(.duplicateEntryPath) = error else {
            return XCTFail("duplicateEntryPath erwartet, war: \(String(describing: error))")
        }
    }

    // MARK: - EOCD-Abgleich

    func testEntryCountMismatchWithEOCDIsRejected() throws {
        // EOCD behauptet einen Eintrag mehr, als das Central Directory
        // enthaelt -> kaputtes/praepariertes Archiv.
        var bytes = try makeArchive([
            ZipItem(name: "one.mod", payload: Data("a".utf8), method: 0)
        ])
        let eocdStart = bytes.count - 22
        bytes[eocdStart + 8] = 2       // Eintraege auf dieser Diskette
        bytes[eocdStart + 10] = 2      // Eintraege gesamt
        let url = workDir.appendingPathComponent("count-mismatch.zip")
        try bytes.write(to: url)

        let error = zipError {
            try ZipArchiveReader.extract(archive: url, to: destination, shouldExtract: acceptAll)
        }
        guard case .some(.corruptArchive) = error else {
            return XCTFail("corruptArchive erwartet, war: \(String(describing: error))")
        }
    }

    func testTrailingBytesInCentralDirectoryAreRejected() throws {
        // 5 Muellbytes zwischen letztem Record und EOCD, directorySize zaehlt
        // sie mit: Das Verzeichnis geht nicht restlos auf -> Ablehnung.
        var bytes = try makeArchive([
            ZipItem(name: "one.mod", payload: Data("a".utf8), method: 0)
        ])
        let eocdStart = bytes.count - 22
        bytes.insert(contentsOf: [0, 0, 0, 0, 0], at: eocdStart)
        let newEocdStart = eocdStart + 5
        // directorySize (Offset +12 im EOCD) um die 5 Byte erhoehen.
        let oldSize = UInt32(bytes[newEocdStart + 12])
            | (UInt32(bytes[newEocdStart + 13]) << 8)
            | (UInt32(bytes[newEocdStart + 14]) << 16)
            | (UInt32(bytes[newEocdStart + 15]) << 24)
        let newSize = oldSize + 5
        bytes[newEocdStart + 12] = UInt8(newSize & 0xFF)
        bytes[newEocdStart + 13] = UInt8((newSize >> 8) & 0xFF)
        bytes[newEocdStart + 14] = UInt8((newSize >> 16) & 0xFF)
        bytes[newEocdStart + 15] = UInt8((newSize >> 24) & 0xFF)
        let url = workDir.appendingPathComponent("trailing-bytes.zip")
        try bytes.write(to: url)

        let error = zipError {
            try ZipArchiveReader.extract(archive: url, to: destination, shouldExtract: acceptAll)
        }
        guard case .some(.corruptArchive) = error else {
            return XCTFail("corruptArchive erwartet, war: \(String(describing: error))")
        }
    }

    // MARK: - Integritaet und Sonderfaelle

    func testChecksumMismatchIsRejectedAndFileRemoved() throws {
        let payload = pseudoRandomData(count: 4_000)
        let archive = try writeArchive([
            ZipItem(name: "broken.mod", payload: payload, method: 8, crcOverride: 0xDEAD_BEEF)
        ])

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }

        guard case .some(.checksumMismatch) = error else {
            return XCTFail("checksumMismatch erwartet, war: \(String(describing: error))")
        }
        XCTAssertFalse(fileExists("broken.mod"), "Datei mit falscher Prüfsumme darf nicht liegen bleiben")
    }

    func testEncryptedEntryIsRejected() throws {
        let archive = try writeArchive([
            ZipItem(name: "secret.mod", payload: Data("geheim".utf8), method: 0, flags: 0x0001)
        ])

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }

        guard case .some(.encryptedEntry) = error else {
            return XCTFail("encryptedEntry erwartet, war: \(String(describing: error))")
        }
        XCTAssertFalse(fileExists("secret.mod"))
    }

    func testZip64MarkerIsRejected() throws {
        let archive = try writeArchive(
            [ZipItem(name: "song.mod", payload: Data("x".utf8), method: 0)],
            forceZip64Marker: true
        )

        let error = zipError {
            try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        }

        guard case .some(.unsupportedZip64) = error else {
            return XCTFail("unsupportedZip64 erwartet, war: \(String(describing: error))")
        }
    }

    func testNonZipFileIsRejected() throws {
        let url = workDir.appendingPathComponent("kaputt.zip")
        try Data("kein echtes archiv".utf8).write(to: url)

        let error = zipError {
            try ZipArchiveReader.extract(archive: url, to: destination, shouldExtract: acceptAll)
        }

        guard case .some(.notAZipArchive) = error else {
            return XCTFail("notAZipArchive erwartet, war: \(String(describing: error))")
        }
    }

    func testCancellationAborts() throws {
        let archive = try writeArchive([
            ZipItem(name: "song.mod", payload: pseudoRandomData(count: 10_000), method: 8)
        ])

        let error = zipError {
            try ZipArchiveReader.extract(
                archive: archive,
                to: self.destination,
                shouldExtract: self.acceptAll,
                isCancelled: { true }
            )
        }

        guard case .some(.cancelled) = error else {
            return XCTFail("cancelled erwartet, war: \(String(describing: error))")
        }
        XCTAssertFalse(fileExists("song.mod"))
    }

    // MARK: - Dateinamen

    func testCP437NameIsDecoded() throws {
        // "M" 0x94 "bius.mod" ohne UTF-8-Flag: 0x94 ist in CP437 ein "ö".
        let rawName: [UInt8] = Array("M".utf8) + [0x94] + Array("bius.mod".utf8)
        let payload = Data("dos".utf8)
        let archive = try writeArchive([
            ZipItem(name: "unbenutzt", payload: payload, method: 0, rawNameBytes: rawName)
        ])

        let entries = try ZipArchiveReader.inspect(archive: archive)
        XCTAssertEqual(entries.map(\.path), ["Möbius.mod"])

        let result = try ZipArchiveReader.extract(archive: archive, to: destination, shouldExtract: acceptAll)
        XCTAssertEqual(result.extractedFiles.map(\.lastPathComponent), ["Möbius.mod"])
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Möbius.mod")), payload)
    }

    func testUTF8FlaggedNameIsDecodedAsUTF8() throws {
        let name = "Grüße.mod"
        let archive = try writeArchive([
            ZipItem(name: name, payload: Data("utf8".utf8), method: 0, flags: 0x0800)
        ])

        let entries = try ZipArchiveReader.inspect(archive: archive)
        XCTAssertEqual(entries.map(\.path), [name])
    }

    func testCP437TableCoversTheCompleteUpperHalf() {
        // Sicherheitsnetz gegen ein verrutschtes Zeichen in der Tabelle.
        XCTAssertEqual(ZipArchiveReader.cp437UpperHalf.count, 128)
        XCTAssertEqual(ZipArchiveReader.decodeEntryName([0x80, 0x9F, 0xE1, 0xFF], isUTF8: false), "Çƒß\u{00A0}")
        XCTAssertEqual(ZipArchiveReader.decodeEntryName(Array("abc.mod".utf8), isUTF8: false), "abc.mod")
    }
}

// Kleine Schreibhelfer: ZIP legt alle Zahlen little-endian ab.
private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

#endif

import XCTest
import SavageModPlayerCore
@testable import SavageModPlayer

/// „Öffnen mit …" — eine von aussen hereingereichte Datei landet in der
/// Bibliothek und wird abgespielt.
///
/// Hintergrund (2026-08-23): Die `Info.plist` meldet MOD/S3M/XM/IT und ZIP als
/// Dokumenttypen an, es gab aber keinen `onOpenURL`-Handler. Eine übergebene
/// Datei startete nur die App und wurde verworfen.
///
/// Die Tests arbeiten auf einer Bibliothek mit eigener Wurzel im
/// Temp-Verzeichnis, nicht im echten `Documents/` des Simulators.
@MainActor
final class OpenWithTests: XCTestCase {

    private var workDir: URL!
    private var libraryRoot: URL!
    private var incoming: URL!
    private var model: AppModel!

    override func setUp() async throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OpenWith-\(UUID().uuidString)", isDirectory: true)
        libraryRoot = workDir.appendingPathComponent("Bibliothek", isDirectory: true)
        incoming = workDir.appendingPathComponent("Eingang", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)

        let library = MusicLibrary(
            rootURL: libraryRoot,
            indexURL: workDir.appendingPathComponent("index.json"))
        model = AppModel(library: LibraryStore(library: library))
    }

    override func tearDown() async throws {
        model = nil
        try? FileManager.default.removeItem(at: workDir)
    }

    /// Minimal gueltiges M.K.-MOD mit Titel im Header; das Sample besteht aus
    /// Nullbytes und bleibt damit stumm.
    private func writeIncomingModule(named name: String, title: String) throws -> URL {
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        let titleBytes = Array(title.utf8.prefix(20))
        data.replaceSubrange(0..<titleBytes.count, with: titleBytes)
        data[20 + 23] = 0x02
        data[20 + 25] = 64
        data[950] = 1
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        let period = 428
        data[1084] = UInt8((period >> 8) & 0x0F)
        data[1085] = UInt8(period & 0xFF)
        data[1086] = 0x10
        let url = incoming.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 15,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Zeitueberschreitung: \(description)")
    }

    // MARK: - Der Normalfall

    /// Eine uebergebene Datei wird in die Bibliothek uebernommen und laeuft.
    ///
    /// Die Uebernahme ist der Kern: Eine bloss weitergereichte URL waere beim
    /// naechsten Start wertlos, weil iOS den Uebergabeordner wieder aufraeumt.
    func testOpenedFileIsImportedAndPlayed() async throws {
        let url = try writeIncomingModule(named: "gast.mod", title: "GAST")

        model.open(url)

        await waitUntil("Titel steht in der Bibliothek") { !self.model.library.tracks.isEmpty }
        XCTAssertEqual(model.library.tracks.map(\.relativePath), ["gast.mod"])

        await waitUntil("Titel wird abgespielt") { self.model.player.currentTrack != nil }
        XCTAssertEqual(model.player.currentTrack?.relativePath, "gast.mod")
        XCTAssertEqual(model.player.coordinator.trackName, "GAST")

        // Die Datei liegt jetzt wirklich in der Bibliothek, nicht nur im Index.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("gast.mod").path),
            "Die Kopie in der Bibliothek fehlt")

        model.player.stop()
    }

    /// Dieselbe Datei ein zweites Mal: Der Import meldet ein Duplikat, und der
    /// vorhandene Titel spielt trotzdem — kein Fehlschlag, keine zweite Kopie.
    func testOpeningTheSameFileTwiceStillPlaysIt() async throws {
        let url = try writeIncomingModule(named: "doppelt.mod", title: "DOPPELT")

        model.open(url)
        await waitUntil("erster Import") { self.model.player.currentTrack != nil }
        model.player.stop()

        model.open(url)
        await waitUntil("zweiter Aufruf spielt wieder") {
            self.model.player.currentTrack?.relativePath == "doppelt.mod"
        }
        XCTAssertEqual(model.library.tracks.count, 1, "Ein Duplikat darf keine zweite Kopie anlegen")

        model.player.stop()
    }

    /// Eine Datei, die kein Parser annimmt, wird nicht abgespielt — und reisst
    /// die App nicht mit.
    func testUnplayableFileIsNotPlayed() async throws {
        let url = incoming.appendingPathComponent("kaputt.mod")
        try Data(repeating: 0, count: 2048).write(to: url)

        model.open(url)
        // Der Import nimmt die Datei an (er erkennt Module an der Endung); erst
        // die Wiedergabe merkt, dass sie nicht spielbar ist.
        await waitUntil("Fehler wird gemeldet") { self.model.player.errorMessage != nil }
        XCTAssertNil(model.player.currentTrack)
    }

    /// Ein Archiv ist ebenfalls ein angemeldeter Dokumenttyp: Es wird beim
    /// Uebernehmen ausgepackt, und der erste enthaltene Titel spielt.
    func testOpenedArchiveIsUnpackedAndPlayed() async throws {
        let module = try Data(contentsOf: writeIncomingModule(named: "vorlage.mod", title: "AUSPACK"))
        try FileManager.default.removeItem(at: incoming.appendingPathComponent("vorlage.mod"))
        let archive = try ZipTestSupport.makeStoredZip(entries: [("Pack/drin.mod", module)])
        let archiveURL = incoming.appendingPathComponent("pack.zip")
        try archive.write(to: archiveURL)

        model.open(archiveURL)

        await waitUntil("Archivinhalt steht in der Bibliothek") {
            !self.model.library.tracks.isEmpty
        }
        // Das Archiv erscheint als Ordner mit dem Archivnamen ohne Endung.
        XCTAssertEqual(model.library.tracks.map(\.relativePath), ["pack/Pack/drin.mod"])

        await waitUntil("Titel aus dem Archiv wird abgespielt") {
            self.model.player.currentTrack != nil
        }
        XCTAssertEqual(model.player.coordinator.trackName, "AUSPACK")

        model.player.stop()
    }

    // MARK: - Kaltstart

    /// Trifft die Datei ein, waehrend die Bibliothek noch beschaeftigt ist,
    /// darf sie nicht verloren gehen. Genau das ist der Kaltstart: Die App
    /// startet, gleicht ab — und bekommt dabei die Datei gereicht.
    func testFileArrivingDuringAScanIsNotLost() async throws {
        let url = try writeIncomingModule(named: "wartend.mod", title: "WARTEND")

        model.library.start()          // belegt die Bibliothek
        model.open(url)                // kommt genau jetzt herein

        await waitUntil("wartende Datei wird nachgeholt") {
            self.model.player.currentTrack?.relativePath == "wartend.mod"
        }
        XCTAssertEqual(model.library.tracks.map(\.relativePath), ["wartend.mod"])

        model.player.stop()
    }
}

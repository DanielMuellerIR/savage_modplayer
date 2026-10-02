import XCTest
import SavageModPlayerCore
@testable import SavageModPlayer

/// Aus der Dateien-App in die Bibliothek gezogene Module.
///
/// Hintergrund (iPad-Feinschliff, 2026-08-23): Auf einem breiten Bildschirm
/// liegen Dateien-App und Bibliothek nebeneinander, und der naheliegende Weg
/// ist Ziehen statt eines Import-Blatts. Der Weg dahinter ist derselbe wie bei
/// „Öffnen mit …" — Übernahme nach `Documents/`, Archive unterwegs ausgepackt.
///
/// Der Unterschied, den diese Tests festhalten: Fallengelassene Dateien starten
/// **keine** Wiedergabe. Wer während eines laufenden Titels zehn Module ablegt,
/// will sie einsortiert wissen und nicht mitten im Stück unterbrochen werden.
@MainActor
final class DroppedFilesTests: XCTestCase {

    private var workDir: URL!
    private var libraryRoot: URL!
    private var incoming: URL!
    private var model: AppModel!

    override func setUp() async throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Dropped-\(UUID().uuidString)", isDirectory: true)
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
        model?.player.stop()
        model = nil
        try? FileManager.default.removeItem(at: workDir)
    }

    /// Minimal gueltiges M.K.-MOD; das Sample besteht aus Nullbytes und bleibt
    /// damit stumm.
    @discardableResult
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

    /// Mehrere Dateien auf einmal landen alle in der Bibliothek.
    func testDroppedFilesAreAllImported() async throws {
        let urls = [
            try writeIncomingModule(named: "eins.mod", title: "EINS"),
            try writeIncomingModule(named: "zwei.mod", title: "ZWEI"),
            try writeIncomingModule(named: "drei.mod", title: "DREI")
        ]

        model.importDropped(urls)

        await waitUntil("alle drei stehen in der Bibliothek") {
            self.model.library.tracks.count == 3
        }
        XCTAssertEqual(
            model.library.tracks.map(\.relativePath).sorted(),
            ["drei.mod", "eins.mod", "zwei.mod"])
        for name in ["eins.mod", "zwei.mod", "drei.mod"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent(name).path),
                "Die Kopie von \(name) fehlt")
        }
    }

    /// Der Punkt des Ganzen: Fallenlassen spielt nichts ab.
    func testDroppingDoesNotStartPlayback() async throws {
        let url = try writeIncomingModule(named: "still.mod", title: "STILL")

        model.importDropped([url])
        await waitUntil("Import fertig") { !self.model.library.tracks.isEmpty }

        // Nach dem Import noch etwas Luft lassen: Ein verspaetetes Abspielen
        // waere sonst genau zwischen den Zeilen durchgerutscht.
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(model.player.currentTrack, "Fallenlassen darf nichts starten")
        XCTAssertFalse(model.player.isPlaying)
    }

    /// Ein leerer Wurf tut nichts — und blockiert vor allem die Warteschlange
    /// nicht.
    func testDroppingNothingIsHarmless() async throws {
        model.importDropped([])
        let url = try writeIncomingModule(named: "danach.mod", title: "DANACH")
        model.importDropped([url])

        await waitUntil("der Import danach laeuft trotzdem") {
            self.model.library.tracks.count == 1
        }
    }

    /// Ein Archiv wird beim Fallenlassen genauso ausgepackt wie beim Öffnen —
    /// nur eben ohne anschliessend zu spielen.
    func testDroppedArchiveIsUnpackedWithoutPlaying() async throws {
        let module = try Data(contentsOf: writeIncomingModule(named: "vorlage.mod", title: "PACK"))
        try FileManager.default.removeItem(at: incoming.appendingPathComponent("vorlage.mod"))
        let archive = try ZipTestSupport.makeStoredZip(entries: [("Pack/drin.mod", module)])
        let archiveURL = incoming.appendingPathComponent("pack.zip")
        try archive.write(to: archiveURL)

        model.importDropped([archiveURL])

        await waitUntil("Archivinhalt steht in der Bibliothek") {
            !self.model.library.tracks.isEmpty
        }
        // Das Archiv erscheint als Ordner mit dem Archivnamen ohne Endung.
        XCTAssertEqual(model.library.tracks.map(\.relativePath), ["pack/Pack/drin.mod"])
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(model.player.currentTrack)
    }

    /// Der harte Fall: Waehrend die Bibliothek noch beschaeftigt ist, kommt ein
    /// Wurf herein und danach eine Datei per „Öffnen mit …". Beide Stapel
    /// muessen durchlaufen, und nur der zweite darf abspielen.
    ///
    /// Vorher lag in `AppModel` eine einzige Warteschlange ohne Unterscheidung;
    /// ein gemeinsamer Stapel haette entweder alles abgespielt oder nichts.
    func testDropAndOpenAreProcessedAsSeparateBatches() async throws {
        let dropped = try writeIncomingModule(named: "gezogen.mod", title: "GEZOGEN")
        let opened = try writeIncomingModule(named: "geoeffnet.mod", title: "GEOEFFNET")

        model.importDropped([dropped])
        // Direkt hinterher, ohne auf den ersten Stapel zu warten.
        model.open(opened)

        await waitUntil("beide Dateien sind uebernommen") {
            self.model.library.tracks.count == 2
        }
        await waitUntil("die geoeffnete Datei spielt") {
            self.model.player.currentTrack?.relativePath == "geoeffnet.mod"
        }
        XCTAssertEqual(
            model.player.currentTrack?.relativePath, "geoeffnet.mod",
            "Nur die per Oeffnen-mit uebergebene Datei darf starten")
    }
}

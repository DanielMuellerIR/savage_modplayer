import Combine
import XCTest
import SavageModPlayerCore
@testable import SavageModPlayer

/// Wann die Bibliothek eine neue Titelliste meldet — vor oder nach dem
/// Übernehmen.
///
/// Hintergrund (2026-08-23, im iPad-Simulator mit einer Sonde belegt): Der
/// zuletzt gespielte Titel wurde nach dem Start nie wiederhergestellt. Die
/// Ursache lag nicht in `restoreSession`, sondern im Zeitpunkt der Meldung:
/// `@Published` meldet in `willSet`. Wer `$tracks` abonnierte, bekam die neue
/// Liste als Parameter, las aus `library.tracks` aber noch die alte — beim
/// ersten Mal also eine leere. Die Oberfläche baute daraus eine leere
/// Wiedergabeliste und suchte den gemerkten Titel darin vergeblich.
///
/// `tracksDidChange` meldet nach dem Übernehmen. Diese Tests halten genau das
/// fest, denn von außen sieht man den Unterschied nur an einem Detail: was die
/// Bibliothek im Moment der Meldung von sich selbst preisgibt.
@MainActor
final class LibraryChangeOrderTests: XCTestCase {

    private var workDir: URL!
    private var libraryRoot: URL!
    private var store: LibraryStore!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ChangeOrder-\(UUID().uuidString)", isDirectory: true)
        libraryRoot = workDir.appendingPathComponent("Bibliothek", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try writeModule(named: "eins.mod", title: "EINS")
        try writeModule(named: "zwei.mod", title: "ZWEI")

        store = LibraryStore(library: MusicLibrary(
            rootURL: libraryRoot,
            indexURL: workDir.appendingPathComponent("index.json")))
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        store = nil
        try? FileManager.default.removeItem(at: workDir)
    }

    private func writeModule(named name: String, title: String) throws {
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        let titleBytes = Array(title.utf8.prefix(20))
        data.replaceSubrange(0..<titleBytes.count, with: titleBytes)
        data[20 + 23] = 0x02
        data[20 + 25] = 64
        data[950] = 1
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        data[1084] = 0x01
        data[1085] = 0xAC
        data[1086] = 0x10
        try data.write(to: libraryRoot.appendingPathComponent(name))
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

    /// Der eigentliche Fehler: Beim Melden muss die Bibliothek den neuen Stand
    /// auch herausgeben.
    func testTheStoreAlreadyHoldsTheNewTracksWhenItReports() async {
        var observed: [(reported: Int, readBack: Int, filtered: Int)] = []
        store.tracksDidChange
            .sink { [weak store] tracks in
                observed.append((
                    tracks.count,
                    store?.tracks.count ?? -1,
                    store?.filteredTracks(search: "", favoritesOnly: false).count ?? -1))
            }
            .store(in: &cancellables)

        store.start()
        await waitUntil("Bibliothek gelesen") { !self.store.tracks.isEmpty }
        await waitUntil("Meldung angekommen") { !observed.isEmpty }

        for entry in observed {
            XCTAssertEqual(
                entry.readBack, entry.reported,
                "Beim Melden von \(entry.reported) Titeln gibt die Bibliothek \(entry.readBack) heraus")
            XCTAssertEqual(
                entry.filtered, entry.reported,
                "Die gefilterte Liste hinkt hinterher: \(entry.filtered) statt \(entry.reported)")
        }
    }

    /// Der Gegenbeweis, damit der Test oben nicht versehentlich trivial wird:
    /// Der alte Weg über `$tracks` zeigt den Fehler weiterhin. Faende diese
    /// Prüfung ihn nicht mehr, waere die Ursache eine andere geworden und der
    /// Test oben nicht laenger aussagekraeftig.
    func testThePublishedStreamStillReportsBeforeTheChange() async {
        var sawStaleRead = false
        store.$tracks
            .sink { [weak store] tracks in
                if !tracks.isEmpty, store?.tracks.isEmpty == true { sawStaleRead = true }
            }
            .store(in: &cancellables)

        store.start()
        await waitUntil("Bibliothek gelesen") { !self.store.tracks.isEmpty }

        XCTAssertTrue(
            sawStaleRead,
            "@Published meldet in willSet — faellt das weg, ist die Begruendung im Code veraltet")
    }

    /// Und der Weg, um den es ging: Nach dem Start steht der zuletzt gespielte
    /// Titel wieder da. Nachgestellt wird, was RootView beim Eintreffen der
    /// Titelliste tut.
    func testLastPlayedTrackIsRestoredOnAColdStart() async {
        let settings = PlayerSettings()
        let previous = settings.lastPlayedRelativePath
        defer { settings.lastPlayedRelativePath = previous }
        settings.lastPlayedRelativePath = "zwei.mod"

        let player = PlaybackEngine(settings: settings, library: store)
        var didRestore = false
        store.tracksDidChange
            .sink { tracks in
                player.refreshQueueFromLibrary()
                guard !didRestore, !tracks.isEmpty else { return }
                didRestore = true
                player.restoreSession()
            }
            .store(in: &cancellables)

        store.start()
        await waitUntil("zuletzt gespielter Titel steht wieder da") {
            player.currentTrack?.relativePath == "zwei.mod"
        }
        XCTAssertFalse(player.isPlaying, "Wiederherstellen waehlt aus, es spielt nicht ab")
        player.stop()
    }
}

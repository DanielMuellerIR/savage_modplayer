import XCTest
import SavageModPlayerCore
@testable import SavageModPlayer

/// Die Abspielliste behält ihre Auswahl, wenn sich die Bibliothek ändert.
///
/// Hintergrund (Code-Review 2026-08-02): `RootView` setzte bei jeder Änderung
/// von `LibraryStore.tracks` den Gesamtbestand als Abspielliste ein. Wer die
/// Wiedergabe aus einer Suche oder aus den Favoriten gestartet hatte, spielte
/// danach durch die ganze Sammlung weiter — ein einzelner neuer Favorit
/// reichte dafür.
@MainActor
final class QueueFilterTests: XCTestCase {

    private var workDir: URL!
    private var store: LibraryStore!
    private var defaultsSuite: String!
    private var engine: PlaybackEngine!

    override func setUp() async throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QueueFilter-\(UUID().uuidString)", isDirectory: true)
        let root = workDir.appendingPathComponent("Bibliothek", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Vier Titel: zwei mit "amiga" im Namen, zwei ohne.
        for name in ["amiga-eins.mod", "amiga-zwei.mod", "pc-eins.s3m", "pc-zwei.xm"] {
            try Data(repeating: 0x5A, count: 64).write(to: root.appendingPathComponent(name))
        }
        let library = MusicLibrary(
            rootURL: root, indexURL: workDir.appendingPathComponent("index.json"))
        try library.load()
        _ = try library.rescan()

        // Eigene Voreinstellungen, damit der Favoritenstand des Simulators
        // unberuehrt bleibt.
        defaultsSuite = "QueueFilterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        store = LibraryStore(defaults: defaults, library: library)
        engine = PlaybackEngine(settings: PlayerSettings(), library: store)
    }

    override func tearDown() async throws {
        engine = nil
        store = nil
        if let suite = defaultsSuite {
            UserDefaults().removePersistentDomain(forName: suite)
        }
        try? FileManager.default.removeItem(at: workDir)
    }

    private func waitForTracks() async {
        store.start()
        for _ in 0..<100 {
            if !store.tracks.isEmpty && !store.isBusy { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Bibliothek lieferte keine Titel")
    }

    // MARK: - Suche

    func testSearchFilteredQueueStaysFilteredWhenTheLibraryChanges() async throws {
        await waitForTracks()
        XCTAssertEqual(store.tracks.count, 4)

        let filtered = store.filteredTracks(search: "amiga", favoritesOnly: false)
        XCTAssertEqual(filtered.count, 2, "Testaufbau: genau zwei Treffer erwartet")
        engine.setQueue(filtered, filter: QueueFilter(search: "amiga", favoritesOnly: false))

        // Die Bibliothek meldet einen neuen Stand — genau der Moment, in dem
        // vorher der Gesamtbestand die Liste ersetzte.
        engine.refreshQueueFromLibrary()

        XCTAssertEqual(engine.queue.count, 2, "Die Suche muss die Liste weiter begrenzen")
        XCTAssertTrue(engine.queue.allSatisfy { $0.relativePath.contains("amiga") })
    }

    /// Ein neuer Titel, der zur Suche passt, kommt dazu — einer, der nicht
    /// passt, bleibt draussen.
    func testMatchingNewTrackJoinsTheFilteredQueue() async throws {
        await waitForTracks()
        engine.setQueue(
            store.filteredTracks(search: "amiga", favoritesOnly: false),
            filter: QueueFilter(search: "amiga", favoritesOnly: false))
        XCTAssertEqual(engine.queue.count, 2)

        let root = workDir.appendingPathComponent("Bibliothek", isDirectory: true)
        try Data(repeating: 0x11, count: 64).write(to: root.appendingPathComponent("amiga-drei.it"))
        try Data(repeating: 0x22, count: 64).write(to: root.appendingPathComponent("atari.mod"))

        store.refresh()
        for _ in 0..<100 {
            if store.tracks.count == 6 && !store.isBusy { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(store.tracks.count, 6, "Testaufbau: beide neuen Dateien im Index")

        engine.refreshQueueFromLibrary()
        XCTAssertEqual(
            Set(engine.queue.map(\.relativePath)),
            ["amiga-eins.mod", "amiga-zwei.mod", "amiga-drei.it"])
    }

    // MARK: - Favoriten

    func testFavouritesQueueStaysWithinTheFavourites() async throws {
        await waitForTracks()
        store.toggleFavorite("amiga-eins.mod")

        engine.setQueue(
            store.filteredTracks(search: "", favoritesOnly: true),
            filter: QueueFilter(search: "", favoritesOnly: true))
        XCTAssertEqual(engine.queue.map(\.relativePath), ["amiga-eins.mod"])

        // Ein zweiter Favorit kommt dazu: Die Liste waechst um genau diesen
        // Titel — und nicht auf die ganze Bibliothek.
        store.toggleFavorite("pc-eins.s3m")
        XCTAssertEqual(
            Set(engine.queue.map(\.relativePath)), ["amiga-eins.mod", "pc-eins.s3m"])
    }

    func testRemovingAFavoriteImmediatelyRemovesItFromTheQueue() async {
        await waitForTracks()
        store.toggleFavorite("amiga-eins.mod")
        store.toggleFavorite("pc-eins.s3m")
        engine.setQueue(store.filteredTracks(search: "", favoritesOnly: true),
                        filter: QueueFilter(search: "", favoritesOnly: true))
        store.toggleFavorite("pc-eins.s3m")
        XCTAssertEqual(engine.queue.map(\.relativePath), ["amiga-eins.mod"])
    }

    // MARK: - Ohne Filter

    /// Ohne Suche und ohne Favoritenfilter bleibt alles wie bisher.
    func testUnfilteredQueueFollowsTheWholeLibrary() async throws {
        await waitForTracks()
        engine.setQueue(store.tracks)
        XCTAssertTrue(engine.queueFilter.isWholeLibrary)

        engine.refreshQueueFromLibrary()
        XCTAssertEqual(engine.queue.count, store.tracks.count)
    }
}

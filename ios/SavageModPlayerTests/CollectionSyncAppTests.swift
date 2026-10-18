import XCTest
import SwiftUI
@testable import SavageModPlayerCore
@testable import SavageModPlayer

actor CollectionSyncTestBackend: CollectionSyncAssetBackend {
    var asset: CollectionSyncCloudAsset?
    var failure: CollectionSyncTransportError?
    var writes = 0
    func currentAccountScope() -> String { String(repeating: "a", count: 64) }
    func fetch() throws -> CollectionSyncCloudAsset? {
        if let failure { throw failure }
        return asset
    }
    func save(_ data: Data, replacing tag: String?) throws -> CollectionSyncCloudAsset {
        guard tag == asset?.changeTag else { throw CollectionSyncTransportError.conflict }
        writes += 1
        let saved = CollectionSyncCloudAsset(data: data, changeTag: "saved-\(writes)")
        asset = saved; return saved
    }
    func put(_ snapshot: CollectionSyncSnapshot) throws {
        asset = .init(data: try CollectionSyncCodec.encode(snapshot), changeTag: "remote-\(UUID())")
    }
    func setFailure(_ error: CollectionSyncTransportError?) { failure = error }
    func snapshot() throws -> CollectionSyncSnapshot { try CollectionSyncCodec.decode(XCTUnwrap(asset).data) }
    func writeCount() -> Int { writes }
}

@MainActor
final class CollectionSyncAppFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CollectionSync-\(UUID())")
    let domain = "CollectionSync.\(UUID())"
    let backend = CollectionSyncTestBackend()
    let longName = "A very long shared module title with a distinct ending — synthetic-sync-collection-song.mod"
    let defaults: UserDefaults
    let appDomain: String
    let productionDefaults: [String: Any]?
    var model: AppModel!
    let playlistID = UUID()
    var files: [URL] { ["playlists.json", "markers.json", "settings.json", "sync.json"].map { root.appendingPathComponent($0) } }

    init(configured: Bool = true, service: CollectionSyncService? = nil, emptyCollection: Bool = false) async throws {
        defaults = UserDefaults(suiteName: domain)!
        appDomain = Bundle.main.bundleIdentifier!
        productionDefaults = UserDefaults.standard.persistentDomain(forName: appDomain)
        let documents = root.appendingPathComponent("Documents")
        for folder in ["A", "B"] {
            let url = documents.appendingPathComponent(folder + "/" + longName)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = Data(repeating: 0, count: 2112)
            data[43] = 2; data[45] = 64; data[49] = 2; data[950] = 1
            data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
            data[1084] = 1; data[1085] = 0xAC; data[1086] = 0x10
            data.replaceSubrange(2108..<2112, with: [64, 192, 64, 192])
            try data.write(to: url)
        }
        let core = MusicLibrary(rootURL: documents, indexURL: root.appendingPathComponent("index.json"))
        try core.load(); _ = try core.rescan()
        let settings = PlayerSettings(defaults: defaults); settings.volume = 0
        for (key, value) in CollectionExchangeSoundPreferences.values(settings.playbackOptions, prefix: "savage.ios.") {
            defaults.set(value, forKey: key)
        }
        defaults.set(0.37, forKey: "savage.ios.volume"); defaults.synchronize()
        let library = LibraryStore(defaults: defaults, library: core); library.start()
        try await Self.wait { !library.isBusy && library.tracks.count == 2 }
        var playlists = SavedPlaylistDocument()
        if !emptyCollection {
            playlists.playlists = [.init(id: playlistID, name: "Local collection with a long descriptive title", tracks: library.tracks.compactMap(\.playlistReference))]
        }
        try SavedPlaylistStore.encodedData(playlists).write(to: files[0])
        try SongMarkerStore.encodedData(.init()).write(to: files[1])
        try TrackPlaybackSettingsStore.encodedData(.init()).write(to: files[2])
        let preferences = CollectionExchangePreferences(defaults: defaults, domain: domain,
            keys: CollectionExchangeSoundPreferences.keys(prefix: "savage.ios.").union([LibraryStore.favoritesDefaultsKey]))
        model = AppModel(settings: settings, library: library,
            playlists: PlaylistCollectionStore(fileURL: files[0]),
            catalog: LibraryCatalogModel(metadataURL: root.appendingPathComponent("metadata.json"),
                preferencesURL: root.appendingPathComponent("library-preferences.json")),
            markers: SongMarkersModel(fileURL: files[1]),
            playbackSettings: TrackPlaybackSettingsModel(fileURL: files[2], defaults: settings.playbackOptions),
            collectionPersistence: try persistence(sync: false), collectionPreferences: preferences,
            syncPersistence: try persistence(), syncService: configured ? (service ?? .init(backend: backend)) : nil)
        model.prepareCollectionSync()
        model.collectionSync?.cancelReview()
        await model.collectionSync?.synchronize()
    }
    func persistence(sync: Bool = true) throws -> CollectionExchangePersistence {
        try .init(playlistsURL: files[0], markersURL: files[1], trackSettingsURL: files[2],
            journalURL: root.appendingPathComponent("journal"), syncStateURL: sync ? files[3] : nil)
    }
    var sync: CollectionSyncModel { model.collectionSync! }
    func connect() async throws {
        await sync.beginSetup(); XCTAssertTrue(sync.canConfirm, "\(String(describing: sync.error))")
        await sync.confirm(); XCTAssertEqual(sync.status, .current, "\(String(describing: sync.error))")
    }
    func state() throws -> CollectionSyncApplicationState { try CollectionSyncApplicationCodec.decode(Data(contentsOf: files[3])) }
    func close() async throws {
        model.scenePhaseChanged(to: .background)
        model.collectionContext?.model.cancel(); model.collectionContext = nil; model.collectionSyncContext = nil
        sync.deactivate(); model.player.stop()
        try await Self.wait { !self.model.library.isBusy }
        model = nil
        await Task.yield()
        let current = UserDefaults.standard.persistentDomain(forName: appDomain)
        XCTAssertEqual(current == nil, productionDefaults == nil)
        XCTAssertTrue(NSDictionary(dictionary: current ?? [:]).isEqual(to: productionDefaults ?? [:]), "Die isolierte Fixture hat Produktionseinstellungen verändert.")
        defaults.removePersistentDomain(forName: domain); defaults.synchronize()
        try FileManager.default.removeItem(at: root)
    }
    static func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(10)
        while !condition(), Date() < end { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}

@MainActor
final class CollectionSyncAppTests: XCTestCase {
    func testMalformedPreferencesCannotPublishFavoriteDeletionsOrDefaultSoundSettings() async throws {
        let f = try await CollectionSyncAppFixture()
        do {
            try await f.connect()
            f.model.library.toggleFavorite("A/" + f.longName)
            try await CollectionSyncAppFixture.wait { !f.sync.isBusy && (try? f.state().observed.exchangeDocument().favoriteTrackIDs.count) == 1 }
            let before = await f.backend.writeCount(), stored = try Data(contentsOf: f.files[3])
            for (key, value) in [(LibraryStore.favoritesDefaultsKey, "corrupt"), ("savage.ios.palClock", "false")] {
                let old = f.defaults.object(forKey: key)
                f.defaults.set(value, forKey: key); f.defaults.synchronize()
                await f.sync.synchronize()
                try await CollectionSyncAppFixture.wait { !f.sync.isBusy && f.sync.status == .failed && f.sync.error != nil }
                XCTAssertEqual(f.sync.status, .failed)
                XCTAssertNotNil(f.sync.error)
                let writes = await f.backend.writeCount(); XCTAssertEqual(writes, before)
                XCTAssertEqual(try Data(contentsOf: f.files[3]), stored)
                XCTAssertEqual(f.defaults.string(forKey: key), value)
                f.defaults.set(old, forKey: key); f.defaults.synchronize()
            }
        } catch { try await f.close(); throw error }
        try await f.close()
    }
    func testActualAppSubscriptionsPublishPlaylistFavoritesAndOverridesAndPreserveDeviceSettings() async throws {
        let f = try await CollectionSyncAppFixture()
        do {
            try await f.connect()
            let before = await f.backend.writeCount()
            f.model.playlists.rename(id: f.playlistID, name: "Edited in the app")
            f.model.library.toggleFavorite("A/" + f.longName)
            XCTAssertTrue(f.model.player.playbackSettings.updateTitle("A/" + f.longName) { $0.ledFilterActive = true })
            let track = try XCTUnwrap(f.model.library.tracks.first)
            let module = try ModuleLoader.parse(data: Data(contentsOf: track.url))
            f.model.markers.setContext(sourceID: track.relativePath, module: module, moduleID: UUID())
            let saved = await f.model.markers.save(name: "Saved in the app", address: .init(position: 0, row: 8))
            XCTAssertTrue(saved)
            try await CollectionSyncAppFixture.wait { f.sync.status == .current && !f.sync.isBusy && (try? f.state().observed.exchangeDocument().playlists[0].name) == "Edited in the app" }
            if let error = f.sync.error { throw error }
            let cloud = try await f.backend.snapshot()
            XCTAssertEqual(try cloud.exchangeDocument().playlists[0].name, "Edited in the app")
            XCTAssertEqual(try cloud.exchangeDocument().favoriteTrackIDs.count, 1)
            XCTAssertEqual(try cloud.exchangeDocument().trackSettings.first?.overrides.ledFilterActive, true)
            XCTAssertEqual(try cloud.exchangeDocument().markers.first?.name, "Saved in the app")
            let after = await f.backend.writeCount(); XCTAssertGreaterThan(after, before)
            XCTAssertEqual(f.defaults.double(forKey: "savage.ios.volume"), 0.37)
            XCTAssertFalse(f.model.player.coordinator.isPlaying)
        } catch { try await f.close(); throw error }
        try await f.close()
    }

    func testManualTransferPausesAutomaticSyncAndClosingItCapturesTheSavedChange() async throws {
        let f = try await CollectionSyncAppFixture()
        do {
            try await f.connect()
            f.model.showCollectionExchange()
            XCTAssertNotNil(f.model.collectionContext)
            let before = await f.backend.writeCount()
            f.model.playlists.rename(id: f.playlistID, name: "Edited while transfer is open")
            try await Task.sleep(for: .milliseconds(500))
            let paused = await f.backend.writeCount(); XCTAssertEqual(paused, before)
            let manual = try XCTUnwrap(f.model.collectionContext?.model)
            await manual.load(); XCTAssertNil(manual.error)
            let data = try await manual.exportData()
            XCTAssertEqual(try CollectionExchangeCodec.decode(data).playlists[0].name, "Edited while transfer is open")
            manual.cancel(); f.model.collectionContext = nil
            try await CollectionSyncAppFixture.wait { !f.sync.isBusy && f.sync.status == .current && (try? f.state().observed.exchangeDocument().playlists[0].name) == "Edited while transfer is open" }
            let cloud = try await f.backend.snapshot()
            XCTAssertEqual(try cloud.exchangeDocument().playlists[0].name, "Edited while transfer is open")
        } catch { try await f.close(); throw error }
        try await f.close()
    }
}

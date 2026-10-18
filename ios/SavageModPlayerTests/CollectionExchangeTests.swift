import XCTest
import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class CollectionExchangeTests: XCTestCase {
    private var root: URL!
    private var domain: String!
    private var defaults: UserDefaults!
    private var appDomain: String!
    private var originalDefaults: [String: Any]?
    private var model: AppModel!
    private var persistence: CollectionExchangePersistence!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CollectionExchange-\(UUID())")
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        for path in ["A/song.mod", "B/song.mod", "C/other.mod"] { try writeModule(to: documents.appendingPathComponent(path)) }
        let core = MusicLibrary(rootURL: documents, indexURL: root.appendingPathComponent("index.json"))
        try core.load(); _ = try core.rescan()
        domain = "CollectionExchange-\(UUID())"; defaults = UserDefaults(suiteName: domain)!
        appDomain = Bundle.main.bundleIdentifier!; originalDefaults = UserDefaults.standard.persistentDomain(forName: appDomain)
        let settings = PlayerSettings(); settings.volume = 0; settings.shuffleEnabled = false
        for (key, value) in CollectionExchangeSoundPreferences.values(settings.playbackOptions, prefix: "savage.ios.") { defaults.set(value, forKey: key) }
        defaults.set(0.37, forKey: "savage.ios.volume")
        let library = LibraryStore(defaults: defaults, library: core); library.start()
        try await wait { !library.isBusy && library.tracks.count == 3 }
        persistence = try .init(playlistsURL: root.appendingPathComponent("playlists.json"), markersURL: root.appendingPathComponent("markers.json"),
                                trackSettingsURL: root.appendingPathComponent("settings.json"), journalURL: root.appendingPathComponent("journal"))
        let preferences = CollectionExchangePreferences(defaults: defaults, domain: domain,
            keys: CollectionExchangeSoundPreferences.keys(prefix: "savage.ios.").union([LibraryStore.favoritesDefaultsKey]))
        model = AppModel(settings: settings, library: library,
            playlists: PlaylistCollectionStore(fileURL: root.appendingPathComponent("playlists.json")),
            markers: SongMarkersModel(fileURL: root.appendingPathComponent("markers.json")),
            playbackSettings: TrackPlaybackSettingsModel(fileURL: root.appendingPathComponent("settings.json"), defaults: settings.playbackOptions),
            collectionPersistence: persistence, collectionPreferences: preferences)
    }
    override func tearDown() async throws {
        model.collectionContext?.model.cancel(); model.collectionContext = nil; model.player.stop()
        try await wait { !self.model.library.isBusy }
        model = nil
        if let originalDefaults { UserDefaults.standard.setPersistentDomain(originalDefaults, forName: appDomain) }
        else { UserDefaults.standard.removePersistentDomain(forName: appDomain) }
        UserDefaults.standard.synchronize(); defaults.removePersistentDomain(forName: domain); defaults.synchronize()
        try FileManager.default.removeItem(at: root)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(10)
        while !condition(), Date() < end { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
    private func writeModule(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        let title = url.deletingLastPathComponent().lastPathComponent == "A" ? "ALPHA" : url.deletingLastPathComponent().lastPathComponent == "B" ? "BETA" : "OTHER"
        data.replaceSubrange(0..<title.utf8.count, with: title.utf8)
        data[43] = 2; data[45] = 64; data[49] = 2; data[950] = 2
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        data[1084] = 1; data[1085] = 0xAC; data[1086] = 0x10
        data.replaceSubrange(2108..<2112, with: [64, 192, 64, 192])
        try data.write(to: url)
    }
    private func wireFile() throws -> URL {
        let paths = ["A/song.mod", "B/song.mod"]
        let references = paths.map { PlaylistTrackReference(source: .init(location: URL(fileURLWithPath: "/synthetic/mac/" + $0)), displayName: "song.mod") }
        var snapshot = CollectionExchangeSnapshot(playbackDefaults: .init(palClock: false, stereoSeparation: 0.25, useInterpolation: false, ledFilterActive: true))
        snapshot.playlists.playlists = [.init(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, name: "Shared collection", tracks: references.reversed())]
        snapshot.playlists.favoriteIDs = [references[0].id]
        snapshot.markers.markers = [.init(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, sourceID: references[1].id,
            name: "Second order", address: .init(position: 1, row: 16), createdAt: Date(timeIntervalSince1970: 1_700_000_000))]
        snapshot.trackSettings.tracks[references[0].id] = .init(palClock: false, stereoSeparation: 0.2, useInterpolation: false)
        let sources = zip(references, paths).map { CollectionExchangeLocalTrack(reference: $0.0, descriptor: .init(fileName: "song.mod", relativePath: $0.1, byteCount: 2112)) }
        let file = root.appendingPathComponent("incoming.savagecollection")
        try CollectionExchangeCodec.encode(CollectionExchangeExporter.makeDocument(from: snapshot, sources: sources)).write(to: file)
        return file
    }
    private func prepare(_ url: URL) async throws -> CollectionExchangeModel {
        model.open(url)
        try await wait { self.model.collectionContext != nil }
        let transfer = try XCTUnwrap(model.collectionContext?.model)
        await transfer.load(); await transfer.loadFile(url)
        try await wait { !transfer.isBusy && !transfer.isFiltering }
        if let error = transfer.error { throw error }
        for conflict in transfer.preview?.conflicts ?? [] {
            transfer.resolve(conflict.id, with: conflict.allowedResolutions.contains(.useIncoming) ? .useIncoming : .keepBoth)
            try await wait { !transfer.isBusy && !transfer.isFiltering }
        }
        XCTAssertTrue(transfer.isReady); return transfer
    }
    private func assertStored() async throws {
        let documents = try persistence.snapshot().documents
        XCTAssertEqual(documents.playlists.playlists[0].tracks.map { $0.source.libraryRelativePath! }, ["B/song.mod", "A/song.mod"])
        XCTAssertEqual(documents.markers.markers[0].sourceID, "B/song.mod")
        XCTAssertEqual(documents.markers.markers[0].address, .init(position: 1, row: 16))
        XCTAssertEqual(documents.trackSettings.tracks["A/song.mod"]?.palClock, false)
        XCTAssertEqual(model.library.favorites, ["A/song.mod"])
        XCTAssertEqual(defaults.stringArray(forKey: LibraryStore.favoritesDefaultsKey), ["A/song.mod"])
        XCTAssertEqual(defaults.double(forKey: "savage.ios.volume"), 0.37)
        XCTAssertEqual(PlaylistCollectionStore(fileURL: root.appendingPathComponent("playlists.json")).document, documents.playlists)
        let markerDocument = try await SongMarkerStore(fileURL: root.appendingPathComponent("markers.json")).snapshot().document
        XCTAssertEqual(markerDocument, documents.markers)
        XCTAssertEqual(try TrackPlaybackSettingsStore(fileURL: root.appendingPathComponent("settings.json")).load(), documents.trackSettings)
    }
    func testNativeBindingsImportAndRestartKeepActualRelativeStorageIDs() async throws {
        let transfer = try await prepare(wireFile())
        await transfer.applyImport(); XCTAssertEqual(transfer.completion, .imported)
        try await assertStored(); XCTAssertEqual(model.library.tracks.count, 3)
        XCTAssertNil(model.player.currentTrack)
    }
    func testRepeatedImportPreservesPauseTrackTimerAndOriginalVolume() async throws {
        let track = model.library.tracks[0]
        model.player.play(track); try await wait { self.model.player.currentTrack == track && self.model.player.isPlaying }
        model.player.pause()
        let moduleID = model.player.loadedModuleID
        XCTAssertTrue(model.player.coordinator.sleepTimer.start(minutes: 1))
        try await Task.sleep(for: .milliseconds(1100))
        let remaining = model.player.coordinator.sleepTimer.snapshot.remainingSeconds
        let file = try wireFile(), transfer = try await prepare(file)
        await transfer.applyImport()
        XCTAssertTrue(model.player.isPaused); XCTAssertEqual(model.player.loadedModuleID, moduleID)
        XCTAssertEqual(model.player.currentTrack, track)
        XCTAssertTrue(model.player.coordinator.sleepTimer.snapshot.isActive)
        XCTAssertLessThanOrEqual(model.player.coordinator.sleepTimer.snapshot.remainingSeconds, remaining)
        XCTAssertEqual(model.settings.volume, 0)
        let before = try ["playlists.json", "markers.json", "settings.json"].map { try Data(contentsOf: root.appendingPathComponent($0)) }
        model.collectionContext = nil
        let again = try await prepare(file); await again.applyImport()
        let after = try ["playlists.json", "markers.json", "settings.json"].map { try Data(contentsOf: root.appendingPathComponent($0)) }
        XCTAssertEqual(before, after); try await assertStored()
    }
    func testIncomingDataWaitsForOtherPanelAndNeverBecomesAnAudioImport() async throws {
        let file = try wireFile()
        model.isLibraryPanelOpen = true; model.open(file)
        XCTAssertNil(model.collectionContext); XCTAssertNil(model.library.lastReport)
        model.isLibraryPanelOpen = false
        try await wait { self.model.collectionContext != nil }
        XCTAssertNil(model.library.lastReport); XCTAssertEqual(model.library.tracks.count, 3)
        XCTAssertFalse(model.player.isPlaying)
    }
    func testMusicOpenedDuringDataDialogIsCopiedButStopPreventsLatePlayback() async throws {
        model.showCollectionExchange(); XCTAssertNotNil(model.collectionContext)
        let file = root.appendingPathComponent("Incoming/extra.mod"); try writeModule(to: file)
        model.open(file); model.player.stop(); model.collectionContext = nil
        try await wait { !self.model.library.isBusy && self.model.library.tracks.count == 4 }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(model.library.tracks.contains { $0.displayName == "extra.mod" })
        XCTAssertFalse(model.player.isPlaying); XCTAssertNil(model.player.currentTrack)
    }
    func testNativeMacFileRoundTripWhenProvided() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = documents.appendingPathComponent("Interop/from-mac.savagecollection")
        let handoffDeadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: input.path), Date() < handoffDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard FileManager.default.fileExists(atPath: input.path) else { throw XCTSkip("Native Mac-Datei wird nach der Mac-Abnahme bereitgestellt.") }
        let transfer = try await prepare(input); await transfer.applyImport()
        XCTAssertEqual(transfer.completion, .imported)
        try await assertStored()
        model.collectionContext = nil; model.showCollectionExchange()
        let exported = try XCTUnwrap(model.collectionContext?.model); await exported.load()
        let data = try await exported.exportData()
        let before = try CollectionExchangeCodec.load(from: input)
        let after = try CollectionExchangeCodec.decode(data)
        let originalPaths = Dictionary(uniqueKeysWithValues: before.tracks.map { ($0.id, $0.descriptor.relativePath) })
        let exportedPaths = Dictionary(uniqueKeysWithValues: after.tracks.map { ($0.id, $0.descriptor.relativePath) })
        XCTAssertEqual(before.playbackDefaults, after.playbackDefaults)
        XCTAssertEqual(before.playlists.map(\.id), after.playlists.map(\.id))
        for (original, result) in zip(before.playlists, after.playlists) {
            XCTAssertEqual(original.name, result.name)
            XCTAssertEqual(original.trackIDs.map { originalPaths[$0] ?? nil }, result.trackIDs.map { exportedPaths[$0] ?? nil })
        }
        XCTAssertEqual(Set(before.favoriteTrackIDs.compactMap { originalPaths[$0] ?? nil }),
                       Set(after.favoriteTrackIDs.compactMap { exportedPaths[$0] ?? nil }))
        XCTAssertEqual(before.markers.map(\.id), after.markers.map(\.id))
        for (original, result) in zip(before.markers, after.markers) {
            XCTAssertEqual(original.name, result.name); XCTAssertEqual(original.address, result.address)
            XCTAssertEqual(original.createdAt, result.createdAt)
            XCTAssertEqual(originalPaths[original.trackID] ?? nil, exportedPaths[result.trackID] ?? nil)
        }
        let originalSettings = Dictionary(uniqueKeysWithValues: before.trackSettings.map { (originalPaths[$0.trackID] ?? nil, $0.overrides) })
        let exportedSettings = Dictionary(uniqueKeysWithValues: after.trackSettings.map { (exportedPaths[$0.trackID] ?? nil, $0.overrides) })
        XCTAssertEqual(originalSettings, exportedSettings)
        let output = documents.appendingPathComponent("Interop/to-mac-after-native.savagecollection")
        try data.write(to: output, options: .atomic)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(root.path))
        print("Collection native roundtrip complete: \(output.lastPathComponent)")
    }
}

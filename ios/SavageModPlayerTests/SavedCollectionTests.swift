import XCTest
import SwiftUI
import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class SavedCollectionTests: XCTestCase {
    private var work: URL!
    private var store: PlaylistCollectionStore!
    private var library: LibraryStore!
    private var player: PlaybackEngine!
    private var suite: String!

    override func setUp() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("SavedCollection-\(UUID())")
        let root = work.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["alpha.mod", "beta.mod", "gamma.mod"] {
            var data = Data(repeating: 0, count: 1084 + 1024 + 4)
            data[43] = 2; data[45] = 64; data[950] = 1
            data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
            data[1085] = 0xAC; data[1086] = 0x10
            try data.write(to: root.appendingPathComponent(name))
        }
        let core = MusicLibrary(rootURL: root, indexURL: work.appendingPathComponent("index.json"))
        try core.load()
        _ = try core.rescan()
        suite = "SavedCollectionTests-\(UUID())"
        library = LibraryStore(defaults: UserDefaults(suiteName: suite)!, library: core)
        library.start()
        try await waitUntil { !self.library.isBusy && self.library.tracks.count == 3 }
        store = PlaylistCollectionStore(fileURL: work.appendingPathComponent("playlists.json"))
        let settings = PlayerSettings()
        settings.shuffleEnabled = false
        settings.volume = 0
        player = PlaybackEngine(settings: settings, library: library)
    }

    override func tearDown() async throws {
        player.stop()
        player = nil; library = nil; store = nil
        UserDefaults().removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: work)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Erwarteter Endzustand blieb aus")
    }

    func testCollectionEditingAndRestartKeepRelativeSources() throws {
        let id = try XCTUnwrap(store.create(name: " Original "))
        for track in library.tracks { store.add(track, to: id) }
        store.add(library.tracks[0], to: id)
        XCTAssertEqual(store.document.playlists[0].tracks.count, 3)
        store.moveTracks(in: id, from: IndexSet(integer: 0), to: 3)
        store.removeTracks(from: id, at: IndexSet(integer: 1))
        store.rename(id: id, name: "Renamed")
        let reopened = PlaylistCollectionStore(fileURL: work.appendingPathComponent("playlists.json"))
        XCTAssertEqual(reopened.document, store.document)
        XCTAssertEqual(reopened.document.playlists[0].tracks.map { $0.source.libraryRelativePath }, ["beta.mod", "alpha.mod"])
        let data = try Data(contentsOf: work.appendingPathComponent("playlists.json"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(work.path))
        reopened.rename(id: id, name: " ")
        XCTAssertEqual(reopened.document, store.document, "Ein fehlgeschlagenes Speichern darf den Stand nicht ersetzen")
        XCTAssertNotNil(reopened.errorMessageKey)
        reopened.delete(id: id)
        XCTAssertTrue(PlaylistCollectionStore(fileURL: work.appendingPathComponent("playlists.json")).document.playlists.isEmpty)
    }

    func testCorruptStoreIsReadOnlyAndRemainsByteIdentical() throws {
        let file = work.appendingPathComponent("broken.json")
        let bytes = Data("broken".utf8)
        try bytes.write(to: file)
        let broken = PlaylistCollectionStore(fileURL: file)
        XCTAssertFalse(broken.canWrite)
        XCTAssertNil(broken.create(name: "Must not overwrite"))
        XCTAssertNotNil(broken.errorMessageKey)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testMissingSourcesRemainSavedAndReturnAfterRescan() async throws {
        let id = try XCTUnwrap(store.create(name: "Collection"))
        for track in library.tracks { store.add(track, to: id) }
        let file = library.tracks[1].url
        let bytes = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        library.refresh()
        try await waitUntil { !self.library.isBusy && self.library.tracks.count == 2 }
        XCTAssertEqual(PlaylistCollectionStore.resolve(store.document.playlists[0], in: library).count, 2)
        XCTAssertEqual(store.document.playlists[0].tracks.count, 3)
        try bytes.write(to: file)
        library.refresh()
        try await waitUntil { !self.library.isBusy && self.library.tracks.count == 3 }
        XCTAssertEqual(PlaylistCollectionStore.resolve(store.document.playlists[0], in: library).count, 3)
    }

    func testReferencesResolveAfterTheAppContainerChanges() async throws {
        let id = try XCTUnwrap(store.create(name: "Portable IDs"))
        for track in library.tracks { store.add(track, to: id) }
        let root = work.appendingPathComponent("OtherContainer/Documents")
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: work.appendingPathComponent("Documents"), to: root)
        let core = MusicLibrary(rootURL: root, indexURL: work.appendingPathComponent("other-index.json"))
        try core.load(); _ = try core.rescan()
        let relocated = LibraryStore(defaults: UserDefaults(suiteName: suite)!, library: core)
        relocated.start()
        try await waitUntil { !relocated.isBusy && relocated.tracks.count == 3 }
        let tracks = PlaylistCollectionStore.resolve(store.document.playlists[0], in: relocated)
        XCTAssertEqual(tracks.map(\.relativePath), library.tracks.map(\.relativePath))
        XCTAssertTrue(tracks.allSatisfy { $0.url.path.hasPrefix(root.path + "/") })
    }

    func testPendingDuplicatesResumeOriginalListAndStayStopped() async throws {
        let tracks = library.tracks
        player.setExplicitQueue(Array(tracks.prefix(2)))
        player.select(tracks[0])
        try await waitUntil { self.player.currentTrack == tracks[0] }
        player.enqueue(tracks[2]); player.enqueue(tracks[2])
        player.next()
        try await waitUntil { self.player.currentTrack == tracks[2] && self.player.pendingQueue.items.count == 1 }
        XCTAssertEqual(player.currentIndex, 0)
        player.refreshQueueFromLibrary()
        XCTAssertEqual(player.queue, Array(tracks.prefix(2)))
        XCTAssertEqual(player.currentIndex, 0)
        player.next()
        try await waitUntil { self.player.pendingQueue.items.isEmpty }
        player.next()
        try await waitUntil { self.player.currentTrack == tracks[1] }
        XCTAssertFalse(player.coordinator.isPlaying)
    }

    func testMissingQueuedTitleIsSkippedAndReported() async throws {
        let tracks = library.tracks
        player.setQueue(tracks)
        player.select(tracks[0])
        try await waitUntil { self.player.currentTrack == tracks[0] }
        player.enqueue(tracks[2])
        try FileManager.default.removeItem(at: tracks[2].url)
        player.next()
        try await waitUntil { self.player.currentTrack == tracks[1] }
        XCTAssertTrue(player.pendingQueue.items.isEmpty)
        XCTAssertNotNil(player.errorMessage)
        XCTAssertFalse(player.coordinator.isPlaying)
    }

    func testAutomaticAdvanceStopsWhenEveryQueuedSourceIsMissingAndNoListRemains() async throws {
        let tracks = library.tracks
        player.setExplicitQueue([])
        player.play(tracks[0])
        try await waitUntil { self.player.currentTrack == tracks[0] && self.player.coordinator.isPlaying }
        player.enqueue(tracks[1])
        try FileManager.default.removeItem(at: tracks[1].url)
        player.coordinator.songEndPulse += 1
        try await waitUntil { self.player.pendingQueue.items.isEmpty && !self.player.coordinator.isPlaying }
        XCTAssertNotNil(player.errorMessage)
    }

    func testCancelledQueuedLoadKeepsPendingItem() async throws {
        let tracks = library.tracks
        let started = CancellationFlag(), blocked = CancellationFlag()
        let release = DispatchSemaphore(value: 0)
        let settings = PlayerSettings(); settings.shuffleEnabled = false; settings.volume = 0
        player = PlaybackEngine(settings: settings, library: library, readModule: { url in
            if url.lastPathComponent == "gamma.mod", !blocked.isSet {
                blocked.set(); started.set()
                guard release.wait(timeout: .now() + 10) == .success else { throw CocoaError(.fileReadUnknown) }
            }
            return try Data(contentsOf: url)
        })
        defer { release.signal() }
        player.setExplicitQueue(Array(tracks.prefix(2))); player.select(tracks[0])
        try await waitUntil { self.player.currentTrack == tracks[0] }
        player.enqueue(tracks[2]); player.next()
        try await waitUntil { started.isSet }
        player.pause(); release.signal()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(player.pendingQueue.items.count, 1)
        XCTAssertEqual(player.currentTrack, tracks[0])
        player.next()
        try await waitUntil { self.player.currentTrack == tracks[2] }
        XCTAssertTrue(player.pendingQueue.items.isEmpty)
        XCTAssertFalse(player.coordinator.isPlaying)
    }

    func testCancelledResumeKeepsAnchorAcrossLibraryRefresh() async throws {
        let tracks = library.tracks
        let started = CancellationFlag(), blocked = CancellationFlag()
        let release = DispatchSemaphore(value: 0)
        let settings = PlayerSettings(); settings.shuffleEnabled = false; settings.volume = 0
        player = PlaybackEngine(settings: settings, library: library, readModule: { url in
            if url.lastPathComponent == "beta.mod", !blocked.isSet {
                blocked.set(); started.set()
                guard release.wait(timeout: .now() + 10) == .success else { throw CocoaError(.fileReadUnknown) }
            }
            return try Data(contentsOf: url)
        })
        defer { release.signal() }
        player.setExplicitQueue(Array(tracks.prefix(2))); player.select(tracks[0])
        try await waitUntil { self.player.currentTrack == tracks[0] }
        player.enqueue(tracks[2]); player.next()
        try await waitUntil { self.player.currentTrack == tracks[2] }
        player.next(); try await waitUntil { started.isSet }
        player.stop(); release.signal()
        try await Task.sleep(for: .milliseconds(200))
        player.refreshQueueFromLibrary()
        XCTAssertEqual(player.currentIndex, 0)
        player.next(); try await waitUntil { self.player.currentTrack == tracks[1] }
        XCTAssertFalse(player.coordinator.isPlaying)
    }

    func testEnqueueDuringFailedLoadRetainsPriority() async throws {
        let tracks = library.tracks
        let started = CancellationFlag()
        let release = DispatchSemaphore(value: 0)
        let settings = PlayerSettings(); settings.shuffleEnabled = false; settings.volume = 0
        player = PlaybackEngine(settings: settings, library: library, readModule: { url in
            if url.lastPathComponent == "beta.mod" {
                started.set()
                guard release.wait(timeout: .now() + 10) == .success else { throw CocoaError(.fileReadUnknown) }
                throw CocoaError(.fileReadCorruptFile)
            }
            return try Data(contentsOf: url)
        })
        defer { release.signal() }
        player.setExplicitQueue([tracks[0]]); player.select(tracks[0])
        try await waitUntil { self.player.currentTrack == tracks[0] }
        player.enqueue(tracks[1]); player.next(); try await waitUntil { started.isSet }
        player.enqueue(tracks[2]); release.signal()
        try await waitUntil { self.player.currentTrack == tracks[2] }
        XCTAssertTrue(player.pendingQueue.items.isEmpty)
        XCTAssertEqual(player.queue, [tracks[0]])
        XCTAssertNotNil(player.errorMessage)
    }

    func testPlaylistAndQueueViewsRenderInPhoneAndPadLayouts() async throws {
        let id = try XCTUnwrap(store.create(name: "Evening modules"))
        for track in library.tracks { store.add(track, to: id); player.enqueue(track) }
        let model = AppModel(library: library, playlists: store)
        for (width, height, locale, scheme) in [(393, 852, "de", ColorScheme.light), (1024, 768, "en", ColorScheme.dark)] {
            try await snapshot(LibraryView().environmentObject(model), name: "library-\(width)-\(locale)",
                               width: width, height: height, locale: locale, scheme: scheme)
            try await snapshot(PlaylistsView(store: store, library: library, player: player),
                               name: "playlists-\(width)-\(locale)", width: width, height: height, locale: locale, scheme: scheme)
            try await snapshot(PendingQueueView(player: player), name: "queue-\(width)-\(locale)",
                               width: width, height: height, locale: locale, scheme: scheme)
            try await snapshot(NavigationStack { PlaylistDetailView(id: id, store: store, library: library, player: player) },
                               name: "playlist-detail-\(width)-\(locale)", width: width, height: height, locale: locale, scheme: scheme)
        }
        try FileManager.default.removeItem(at: library.tracks[2].url)
        library.refresh()
        try await waitUntil { !self.library.isBusy && self.library.tracks.count == 2 }
        try await snapshot(NavigationStack { PlaylistDetailView(id: id, store: store, library: library, player: player) },
                           name: "playlist-missing", width: 393, height: 852, locale: "de", scheme: .light)
        try await snapshot(NavigationStack { PlaylistDetailView(id: id, store: store, library: library, player: player, editMode: .active) },
                           name: "playlist-edit", width: 393, height: 852, locale: "de", scheme: .light)
        let brokenFile = work.appendingPathComponent("broken-ui.json")
        try Data("broken".utf8).write(to: brokenFile)
        let broken = PlaylistCollectionStore(fileURL: brokenFile)
        try await snapshot(PlaylistsView(store: broken, library: library, player: player),
                           name: "playlist-readonly", width: 393, height: 852, locale: "en", scheme: .dark)
    }

    private func snapshot<V: View>(_ view: V, name: String, width: Int, height: Int, locale: String, scheme: ColorScheme) async throws {
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: locale)).preferredColorScheme(scheme))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        var rendered = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered, "Die Ansicht muss im Render-Server angekommen sein")
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

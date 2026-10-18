#if canImport(Combine)
import XCTest
import Combine
@testable import SavageModPlayerCore

private func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual, expected, message, file: file, line: line)
}
private func unwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
private func checkTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value, file: file, line: line)
}

@MainActor
final class CollectionSyncModelTests: XCTestCase {
    private actor Backend: CollectionSyncAssetBackend {
        var scope = String(repeating: "a", count: 64)
        var assets: [String: CollectionSyncCloudAsset] = [:]
        var asset: CollectionSyncCloudAsset? {
            get { assets[scope] }
            set { assets[scope] = newValue }
        }
        var failure: CollectionSyncTransportError?
        var reads = 0, writes = 0, accounts = 0, zones = 0
        var holdWrite = false
        var continuation: CheckedContinuation<Void, Never>?
        func currentAccountScope() -> String { accounts += 1; return scope }
        func fetch() throws -> CollectionSyncCloudAsset? {
            reads += 1
            if let failure { throw failure }
            return asset
        }
        func save(_ data: Data, replacing tag: String?) async throws -> CollectionSyncCloudAsset {
            writes += 1
            if holdWrite { await withCheckedContinuation { continuation = $0 } }
            guard asset?.changeTag == tag else { throw CollectionSyncTransportError.conflict }
            let saved = CollectionSyncCloudAsset(data: data, changeTag: "revision-\(writes)")
            asset = saved; return saved
        }
        func createZone() { zones += 1 }
        func configure(failure: CollectionSyncTransportError? = nil, hold: Bool = false) {
            self.failure = failure; holdWrite = hold
        }
        func setScope(_ scope: String) { self.scope = scope }
        func release() { holdWrite = false; continuation?.resume(); continuation = nil }
        func isHeld() -> Bool { continuation != nil }
        func put(_ snapshot: CollectionSyncSnapshot) throws {
            asset = .init(data: try CollectionSyncCodec.encode(snapshot), changeTag: "remote-\(UUID())")
        }
        func snapshot() throws -> CollectionSyncSnapshot? { try asset.map { try CollectionSyncCodec.decode($0.data) } }
        func counts() -> [Int] { [accounts, reads, writes, zones] }
    }
    @MainActor
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncModel-\(UUID())")
        let domain = "SyncModel.\(UUID())"
        let defaults: UserDefaults
        let reference = PlaylistTrackReference(source: PlaylistTrackSource(libraryRelativePath: "Music/song.mod")!, displayName: "song.mod")
        let playlistID = UUID()
        let backend = Backend()
        var adopted: CollectionExchangeSnapshot?
        var files: [URL] { ["playlists.json", "markers.json", "settings.json", "sync.json"].map { root.appendingPathComponent($0) } }
        init() throws {
            defaults = UserDefaults(suiteName: domain)!
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var playlists = SavedPlaylistDocument()
            playlists.playlists = [.init(id: playlistID, name: "Original", tracks: [reference])]
            playlists.favoriteIDs = [reference.id]
            try SavedPlaylistStore.encodedData(playlists).write(to: files[0])
            try SongMarkerStore.encodedData(.init()).write(to: files[1])
            try TrackPlaybackSettingsStore.encodedData(.init()).write(to: files[2])
            defaults.set(0.4, forKey: "test.stereoSeparation")
            defaults.set(0.23, forKey: "volume")
            defaults.synchronize()
        }
        deinit { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        func persistence(sync: Bool = true) throws -> CollectionExchangePersistence {
            try .init(playlistsURL: files[0], markersURL: files[1], trackSettingsURL: files[2],
                      journalURL: root.appendingPathComponent("journal"), syncStateURL: sync ? files[3] : nil)
        }
        func binding(sync: Bool = true) throws -> CollectionExchangeStoreBinding {
            let preferences = CollectionExchangePreferences(defaults: defaults, domain: domain,
                keys: CollectionExchangeSoundPreferences.keys(prefix: "test."))
            return .init(persistence: try persistence(sync: sync), preferences: preferences,
                normalize: { documents, raw in
                    .init(playlists: documents.playlists, markers: documents.markers, trackSettings: documents.trackSettings,
                        playbackDefaults: try CollectionExchangeSoundPreferences.validatedOptions(in: preferences.values(in: raw), prefix: "test."))
                }, encode: { candidate, _, raw in
                    let old = try CollectionExchangeSoundPreferences.validatedOptions(in: preferences.values(in: raw), prefix: "test.")
                    let values = candidate.playbackDefaults.flatMap { $0 == old ? nil : CollectionExchangeSoundPreferences.values($0, prefix: "test.") } ?? [:]
                    return .init(documents: .init(playlists: candidate.playlists, markers: candidate.markers, trackSettings: candidate.trackSettings), preferences: values)
                }, available: { [self] _ in [.init(reference: reference, url: root.appendingPathComponent("song.mod"))] },
                canCapture: { true }, adopt: { [weak self] _, snapshot in self?.adopted = snapshot })
        }
        func model(configured: Bool = true) throws -> CollectionSyncModel {
            .init(binding: try binding(), service: configured ? .init(backend: backend,
                prepareNewCollection: { [backend] _ in await backend.createZone() }) : nil)
        }
        func state() throws -> CollectionSyncApplicationState { try CollectionSyncApplicationCodec.decode(Data(contentsOf: files[3])) }
        func rename(_ name: String) throws {
            var document = try persistence().snapshot().documents.playlists
            document.playlists[0].name = name
            try SavedPlaylistStore.encodedData(document).write(to: files[0], options: .atomic)
        }
        func connect() async throws -> CollectionSyncModel {
            let model = try model()
            await model.beginSetup()
            XCTAssertTrue(model.canConfirm, "\(String(describing: model.error))")
            await model.confirm()
            checkEqual(model.status, .current, "\(String(describing: model.error))")
            return model
        }
        func remoteRename(_ name: String) async throws {
            var snapshot = try unwrap(try await backend.snapshot())
            snapshot.cells.removeAll { $0.id == .playlist(playlistID) }
            let trackIDs = try state().observed.exchangeDocument().playlists[0].trackIDs
            snapshot.cells.append(.init(.playlist(playlistID), .playlist(.init(id: playlistID, name: name, trackIDs: trackIDs))))
            try await backend.put(snapshot)
        }
    }

    func testNoCloudAccessBeforeOptInAndNoGuessedConfiguration() async throws {
        let f = try Fixture(), model = try f.model()
        await model.synchronize()
        checkEqual(model.status, .off)
        checkEqual(await f.backend.counts(), [0, 0, 0, 0])
        let unconfigured = try f.model(configured: false)
        await unconfigured.beginSetup()
        checkEqual(unconfigured.status, .notConfigured)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.files[3].path))
        checkEqual(await f.backend.counts(), [0, 0, 0, 0])
    }

    func testNewCollectionRequiresConfirmationThenPersistsIdentityAndExcludesVolume() async throws {
        let f = try Fixture(), model = try f.model()
        await model.beginSetup()
        checkEqual(model.status, .review)
        XCTAssertTrue(model.canConfirm)
        checkEqual((await f.backend.counts())[2...3], [0, 0])
        await model.confirm()
        checkEqual(model.status, .current, "\(String(describing: model.error))")
        let state = try f.state(), cloud = try unwrap(try await f.backend.snapshot())
        checkEqual(state.localState.checkpoint.base.indexed(), cloud.indexed())
        XCTAssertFalse(try state.hasPendingChanges())
        checkEqual(state.localState.registry.bindings.first?.reference.id, f.reference.id)
        checkEqual(f.defaults.double(forKey: "volume"), 0.23)
        let bytes = try CollectionSyncCodec.encode(cloud)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(f.root.path))
        let before = await f.backend.counts()
        f.defaults.set(0.91, forKey: "volume")
        await model.synchronize(force: false)
        checkEqual(await f.backend.counts(), before)
    }

    func testLocalDeletionAndRemoteChangeConvergeAndSurviveRestart() async throws {
        let f = try Fixture(), model = try await f.connect()
        var documents = try f.persistence().snapshot().documents
        documents.playlists.favoriteIDs = []
        try SavedPlaylistStore.encodedData(documents.playlists).write(to: f.files[0])
        try await f.remoteRename("Other device")
        await model.synchronize()
        checkEqual(model.status, .current, "\(String(describing: model.error))")
        checkEqual(f.adopted?.playlists.playlists.first?.name, "Other device")
        checkEqual(f.adopted?.playlists.favoriteIDs, [])
        let restarted = try f.model()
        await restarted.synchronize()
        checkEqual(restarted.status, .current)
        XCTAssertFalse(try f.state().hasPendingChanges())
    }

    func testConflictsRequireExplicitChoiceAndKeepBothDoesNotDuplicateOnRestart() async throws {
        let f = try Fixture(), model = try await f.connect()
        try f.rename("Local"); try await f.remoteRename("Remote")
        await model.synchronize()
        checkEqual(model.status, .review)
        XCTAssertFalse(model.canConfirm)
        let conflict = try unwrap(model.conflicts.first), copy = UUID()
        XCTAssertTrue(conflict.allowsKeepingBoth)
        model.resolve(conflict.id, with: .keepBoth(copyID: copy))
        await model.confirm()
        checkEqual(model.status, .current, "\(String(describing: model.error))")
        checkEqual(Set(f.adopted?.playlists.playlists.map(\.name) ?? []), ["Local", "Remote"])
        let restarted = try f.model()
        await restarted.synchronize()
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists.count, 2)
        XCTAssertTrue(try f.state().localState.checkpoint.base.exchangeDocument().playlists.contains { $0.id == copy })
    }

    func testOfflinePendingEditsAndDisableNeverLoseMetadataOrTouchCloud() async throws {
        let f = try Fixture(), model = try await f.connect()
        try f.rename("Offline")
        await f.backend.configure(failure: .temporarilyUnavailable(retryAfter: nil))
        await model.synchronize()
        checkEqual(model.status, .waiting)
        XCTAssertTrue(try f.state().hasPendingChanges())
        let before = await f.backend.counts()
        await model.disable()
        XCTAssertFalse(try f.state().isEnabled)
        let restarted = try f.model()
        await restarted.synchronize()
        checkEqual(restarted.status, .off)
        checkEqual(await f.backend.counts(), before)
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists[0].name, "Offline")
    }

    func testPublishedButUnappliedLocalEditCannotBeOverwrittenByLateReceipt() async throws {
        let f = try Fixture(), model = try await f.connect()
        try f.rename("Uploaded")
        await f.backend.configure(hold: true)
        let sync = Task { await model.synchronize() }
        for _ in 0..<1000 { if await f.backend.isHeld() { break }; try await Task.sleep(for: .milliseconds(2)) }
        checkTrue(await f.backend.isHeld())
        try f.rename("Newer local edit")
        await f.backend.release(); await sync.value
        checkEqual(model.error as? CollectionSyncError, .stalePreview)
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists[0].name, "Newer local edit")
        let restarted = try f.model()
        await restarted.synchronize()
        checkEqual(restarted.status, .review)
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists[0].name, "Newer local edit")
        for conflict in restarted.conflicts { restarted.resolve(conflict.id, with: .keepLocal) }
        await restarted.confirm()
        checkEqual(restarted.status, .current, "\(String(describing: restarted.error))")
        checkEqual(try await f.backend.snapshot()?.exchangeDocument().playlists[0].name, "Newer local edit")
        XCTAssertFalse(try f.state().hasPendingChanges())
    }

    func testMissingStoreAccountSwitchAndCorruptSyncFileCannotPublishEmptyMetadata() async throws {
        let f = try Fixture(), model = try await f.connect()
        let original = try Data(contentsOf: f.files[0]), before = await f.backend.counts()
        try FileManager.default.removeItem(at: f.files[0])
        await model.synchronize()
        checkEqual(model.error as? CollectionExchangeError, .invalidLocalState)
        checkEqual(await f.backend.counts(), before)
        try original.write(to: f.files[0])
        await f.backend.setScope(String(repeating: "b", count: 64))
        await model.synchronize()
        checkEqual(model.error as? CollectionSyncError, .staleAccount)
        checkEqual((await f.backend.counts())[2], before[2])
        try Data("broken".utf8).write(to: f.files[3])
        await model.synchronize()
        checkEqual(model.error as? CollectionSyncError, .invalidCheckpoint)
        let manual = try f.binding(sync: false)
        let captured = try await manual.captureStorage()
        var candidate = captured.snapshot; candidate.playlists.playlists[0].name = "Manual still works"
        try manual.commit(candidate, replacing: captured)
        checkEqual(try Data(contentsOf: f.files[3]), Data("broken".utf8))
        checkEqual(try f.persistence(sync: false).snapshot().documents.playlists.playlists[0].name, "Manual still works")
    }

    func testJoiningExistingCollectionRequiresMappingAndReusesConfirmedGlobalTrackIdentity() async throws {
        let f = try Fixture(), trackID = UUID(), remoteList = UUID()
        let remote = CollectionSyncSnapshot(collectionID: UUID(), generation: UUID(), cells: [
            .init(.track(trackID), .track(.init(fileName: "song.mod", relativePath: "Other-device/song.mod"))),
            .init(.favorite(trackID), .flag(true)),
            .init(.playlist(remoteList), .playlist(.init(id: remoteList, name: "Remote list", trackIDs: [trackID]))),
        ])
        try await f.backend.put(remote)
        let model = try f.model()
        await model.beginSetup()
        checkEqual(model.status, .review)
        checkEqual(model.tracks.map(\.id), [trackID])
        XCTAssertFalse(model.canConfirm)
        checkEqual((await f.backend.counts())[2...3], [0, 0])
        let source = try unwrap(model.tracks.first?.suggestions.first)
        await model.assign(source, to: trackID)
        for conflict in model.conflicts { model.resolve(conflict.id, with: .useRemote) }
        XCTAssertTrue(model.canConfirm)
        await model.confirm()
        checkEqual(model.status, .current, "\(String(describing: model.error))")
        let state = try f.state()
        checkEqual(state.localState.registry.bindings.map(\.id), [trackID])
        checkEqual(state.localState.checkpoint.base.collectionID, remote.collectionID)
        checkEqual(try state.localState.checkpoint.base.exchangeDocument().tracks.map(\.id), [trackID])
        checkEqual(Set(f.adopted?.playlists.playlists.map(\.name) ?? []), ["Original", "Remote list"])
        let restarted = try f.model(); await restarted.synchronize()
        checkEqual(restarted.status, .current, "\(String(describing: restarted.error))")
        checkEqual(try f.state().localState.registry.bindings.map(\.id), [trackID])
    }

    func testCancellationAfterPublicationBeforeProjectionResumesWithoutLosingRemoteChoice() async throws {
        let f = try Fixture(), model = try await f.connect()
        try f.rename("Local"); try await f.remoteRename("Remote")
        await model.synchronize()
        for conflict in model.conflicts { model.resolve(conflict.id, with: .keepBoth(copyID: UUID())) }
        await f.backend.configure(hold: true)
        let operation = Task { await model.confirm() }
        for _ in 0..<1000 { if await f.backend.isHeld() { break }; try await Task.sleep(for: .milliseconds(2)) }
        checkTrue(await f.backend.isHeld())
        model.deactivate()
        await f.backend.release(); await operation.value
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists.count, 1)
        XCTAssertTrue(try f.state().needsProjection)
        let restarted = try f.model()
        await restarted.synchronize()
        checkEqual(restarted.status, .current, "\(String(describing: restarted.error))")
        checkEqual(Set(f.adopted?.playlists.playlists.map(\.name) ?? []), ["Local", "Remote"])
        XCTAssertFalse(try f.state().hasPendingChanges())
    }

    func testRemoteDeletionOfCollectionNeverRecreatesRecordOrZone() async throws {
        let f = try Fixture(), model = try await f.connect()
        let before = await f.backend.counts()
        await f.backend.configure(failure: .missingRecord)
        await model.synchronize()
        checkEqual(model.error as? CollectionSyncTransportError, .missingRecord)
        checkEqual((await f.backend.counts())[2...3], before[2...3])
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists[0].name, "Original")
    }

    func testNewAccountNeedsFreshPreviewAndConfirmationBeforeReplacingLocalConnection() async throws {
        let f = try Fixture(), model = try await f.connect()
        let before = try f.state()
        try f.rename("Saved for the new account")
        await f.backend.setScope(String(repeating: "b", count: 64))
        await model.synchronize()
        checkEqual(model.error as? CollectionSyncError, .staleAccount)
        let savedOldAccount = try f.state()
        checkEqual(savedOldAccount.localState.checkpoint.account, before.localState.checkpoint.account)
        let writes = (await f.backend.counts())[2]
        await model.beginSetup()
        XCTAssertTrue(model.isRelinking)
        checkEqual(model.status, .review)
        checkEqual(try f.state(), savedOldAccount)
        checkEqual((await f.backend.counts())[2], writes)
        await model.assignUniqueSuggestions()
        for conflict in model.conflicts { model.resolve(conflict.id, with: .keepLocal) }
        await model.confirm()
        checkEqual(model.status, .current, "\(String(describing: model.error))")
        let linked = try f.state()
        checkEqual(linked.localState.checkpoint.account.scope, String(repeating: "b", count: 64))
        XCTAssertNotEqual(linked.localState.checkpoint.account.epoch, before.localState.checkpoint.account.epoch)
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists[0].name, "Saved for the new account")
        checkEqual(f.defaults.double(forKey: "volume"), 0.23)
    }

    func testTwentyThousandTrackCollectionCanPublishRestartAndCaptureOneEdit() async throws {
        let f = try Fixture()
        let references = [f.reference] + (1..<CollectionExchangeCodec.maximumTracks).map { index in
            PlaylistTrackReference(source: PlaylistTrackSource(libraryRelativePath: "Music/song-\(index).mod")!,
                                   displayName: "song-\(index).mod")
        }
        var playlists = try f.persistence().snapshot().documents.playlists
        playlists.playlists[0].tracks = references
        playlists.favoriteIDs = Set(references.map(\.id))
        try SavedPlaylistStore.encodedData(playlists).write(to: f.files[0])
        let started = Date()
        let heartbeat = Task { @MainActor in
            var last = Date(), longest = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
                let now = Date(); longest = max(longest, now.timeIntervalSince(last)); last = now
            }
            return longest
        }
        defer { heartbeat.cancel() }
        let model = try await f.connect()
        heartbeat.cancel()
        let longest = await heartbeat.value
        let setupSeconds = Date().timeIntervalSince(started)
        print("Collection sync 20000 tracks: setup \(setupSeconds) s, longest main-thread pause \(longest) s")
        XCTAssertLessThan(longest, 2, "Die Sammlungsaufbereitung darf den Hauptthread nicht dauerhaft blockieren.")
        XCTAssertLessThan(setupSeconds, 60)
        let first = try f.state()
        checkEqual(first.localState.registry.bindings.count, CollectionExchangeCodec.maximumTracks)
        try f.rename("Large collection after restart")
        let restarted = try f.model()
        await restarted.synchronize()
        checkEqual(restarted.status, .current, "\(String(describing: restarted.error))")
        checkEqual(try await f.backend.snapshot()?.exchangeDocument().playlists[0].name, "Large collection after restart")
        checkEqual(try f.state().localState.registry.bindings, first.localState.registry.bindings)
        XCTAssertFalse(try f.state().hasPendingChanges())
        model.deactivate(); restarted.deactivate()
    }

    func testUnexpectedLossOfOneStoredPreferenceCannotBecomeAGlobalCloudEdit() async throws {
        let f = try Fixture()
        f.defaults.set(false, forKey: "test.palClock"); f.defaults.synchronize()
        let model = try await f.connect(), before = await f.backend.counts()
        let saved = try f.state()
        checkEqual(saved.storedPreferenceKeys, ["test.palClock", "test.stereoSeparation"])
        f.defaults.removeObject(forKey: "test.palClock"); f.defaults.synchronize()
        await model.synchronize()
        checkEqual(model.error as? CollectionExchangeError, .invalidLocalState)
        checkEqual(await f.backend.counts(), before)
        checkEqual(try f.state(), saved)
        checkEqual(f.defaults.double(forKey: "test.stereoSeparation"), 0.4)
    }

    func testAcceptingRemoteConflictRefetchesRevisionEvenWhenNoUploadIsNeeded() async throws {
        let f = try Fixture(), model = try await f.connect()
        try f.rename("Local choice"); try await f.remoteRename("Remote preview")
        await model.synchronize()
        checkEqual(model.status, .review)
        for conflict in model.conflicts { model.resolve(conflict.id, with: .useRemote) }
        XCTAssertTrue(model.canConfirm)
        try await f.remoteRename("Newer remote revision")
        let writes = (await f.backend.counts())[2]
        await model.confirm()
        checkEqual(model.error as? CollectionSyncTransportError, .conflict)
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists[0].name, "Local choice")
        checkEqual((await f.backend.counts())[2], writes)
        checkEqual(try await f.backend.snapshot()?.exchangeDocument().playlists[0].name, "Newer remote revision")
        XCTAssertTrue(try f.state().hasPendingChanges())
    }

    func testAccountRelinkingCannotDiscardAnAcceptedButUnappliedKeepBothCopy() async throws {
        let f = try Fixture(), model = try await f.connect(), copy = UUID()
        try f.rename("Local"); try await f.remoteRename("Remote")
        await model.synchronize()
        for conflict in model.conflicts { model.resolve(conflict.id, with: .keepBoth(copyID: copy)) }
        await f.backend.configure(hold: true)
        let confirmation = Task { await model.confirm() }
        for _ in 0..<1000 { if await f.backend.isHeld() { break }; try await Task.sleep(for: .milliseconds(2)) }
        checkTrue(await f.backend.isHeld())
        model.deactivate(); await f.backend.release(); await confirmation.value
        let original = try f.state()
        XCTAssertTrue(original.needsProjection)
        await f.backend.setScope(String(repeating: "b", count: 64))
        let restarted = try f.model()
        await restarted.beginSetup()
        checkEqual(restarted.error as? CollectionSyncError, .unappliedDecisions)
        checkEqual(try f.state(), original)
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists.count, 1)
        XCTAssertTrue(try f.state().localState.checkpoint.local.exchangeDocument().playlists.contains { $0.id == copy })
        checkEqual(try await f.backend.snapshot(), nil)
        await f.backend.setScope(String(repeating: "a", count: 64))
        await restarted.synchronize()
        checkEqual(restarted.status, .current, "\(String(describing: restarted.error))")
        checkEqual(try f.persistence().snapshot().documents.playlists.playlists.count, 2)
        await f.backend.setScope(String(repeating: "b", count: 64))
        await restarted.beginSetup()
        XCTAssertTrue(restarted.canConfirm)
        checkEqual(try f.state().localState.checkpoint.account.scope, String(repeating: "a", count: 64))
    }

    func testBulkMappingPublishesCompleteAssignmentsWithoutIntermediatePartialStates() async throws {
        let f = try Fixture(), count = 1000
        let references = [f.reference] + (1..<count).map { index in
            PlaylistTrackReference(source: PlaylistTrackSource(libraryRelativePath: "Music/song-\(index).mod")!, displayName: "song-\(index).mod")
        }
        var lists = try f.persistence().snapshot().documents.playlists
        lists.playlists[0].tracks = references
        try SavedPlaylistStore.encodedData(lists).write(to: f.files[0])
        let ids = references.map { _ in UUID() }
        var cells = zip(ids, references).map { id, reference in
            CollectionSyncCell(.track(id), .track(.init(fileName: reference.displayName, relativePath: reference.source.libraryRelativePath)))
        }
        cells.append(.init(.playlist(f.playlistID), .playlist(.init(id: f.playlistID, name: "Original", trackIDs: ids))))
        cells.append(.init(.favorite(ids[0]), .flag(true)))
        try await f.backend.put(.init(collectionID: UUID(), generation: UUID(), cells: cells))
        let model = try f.model()
        await model.beginSetup()
        checkEqual(model.tracks.count, count)
        XCTAssertTrue(model.tracks.allSatisfy { $0.suggestions.count == 1 })
        var observations: [Int] = []
        let subscription = model.$mapping.receive(on: DispatchQueue.main).sink { observations.append($0.count) }
        await model.assignUniqueSuggestions()
        for _ in 0..<100 { if observations.last == count { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(observations.allSatisfy { $0 == 0 || $0 == count })
        checkEqual(observations.last, count)
        XCTAssertTrue(model.canConfirm, "\(String(describing: model.error))")
        withExtendedLifetime(subscription) {}
    }
}
#endif

import XCTest

@testable import SavageModPlayerCore

final class CollectionSyncLocalStateTests: XCTestCase {
    private func fixture() throws -> (CollectionSyncLocalState, UUID, UUID) {
        let account = CollectionSyncAccountToken(
            scope: String(repeating: "a", count: 64), epoch: UUID())
        let reference = PlaylistTrackReference(
            source: .init(location: URL(fileURLWithPath: "/synthetic/song.mod")),
            displayName: "song.mod")
        let track = UUID()
        let marker = UUID()
        let collection = UUID()
        let generation = UUID()
        var document = CollectionExchangeDocument(id: collection)
        document.tracks = [.init(id: track, descriptor: .init(fileName: "song.mod"))]
        document.favoriteTrackIDs = [track]
        document.markers = [
            .init(
                id: marker, trackID: track, name: "Original", address: .init(position: 0, row: 0),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000.123456))
        ]
        document.trackSettings = [.init(trackID: track, overrides: .init(palClock: false))]
        let base = try CollectionSyncSnapshot(
            document: document, collectionID: collection, generation: generation)
        let checkpoint = CollectionSyncCheckpoint(
            account: account, base: base, local: base, serverChangeTag: "known-tag")
        let registry = CollectionSyncTrackRegistry(
            account: account, collectionID: collection, generation: generation,
            bindings: [.init(id: track, reference: reference)])
        return (.init(checkpoint: checkpoint, registry: registry), track, marker)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SyncLocalState-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testExplicitOfflineChangesKeepMappingsTombstonesInheritanceAndBaseAcrossRestart() throws {
        let (state, track, _) = try fixture()
        let edited = try state.applying(
            [.init(.favorite(track), .deleted), .init(.trackSetting(track, .palClock), .inherit)],
            ifUnchanged: state.checkpoint.local, account: state.checkpoint.account)
        let file = try directory().appendingPathComponent("state.json")
        try CollectionSyncLocalStateCodec.encode(edited).write(to: file, options: .atomic)
        let restarted = try CollectionSyncLocalStateCodec.load(from: file)
        XCTAssertEqual(restarted, edited)
        XCTAssertEqual(restarted.registry, state.registry)
        XCTAssertEqual(restarted.checkpoint.base, state.checkpoint.base)
        XCTAssertEqual(restarted.checkpoint.serverChangeTag, "known-tag")
        XCTAssertTrue(try restarted.checkpoint.pendingChanges())
        XCTAssertEqual(restarted.checkpoint.local.indexed()[.favorite(track)], .deleted)
        XCTAssertEqual(
            restarted.checkpoint.local.indexed()[.trackSetting(track, .palClock)], .inherit)
        XCTAssertTrue(try restarted.checkpoint.local.exchangeDocument().favoriteTrackIDs.isEmpty)
    }

    func testEmptyChangesNeverInferDeletionsFromMissingInput() throws {
        let (state, _, _) = try fixture()
        let result = try state.applying(
            [], ifUnchanged: state.checkpoint.local, account: state.checkpoint.account)
        XCTAssertEqual(result.checkpoint.local.indexed(), state.checkpoint.local.indexed())
        XCTAssertFalse(try result.checkpoint.pendingChanges())
    }

    func testLateAccountPreviewDuplicateAndInvalidChangesLeaveOriginalUntouched() throws {
        let (state, track, _) = try fixture()
        let account = state.checkpoint.account
        let other = CollectionSyncAccountToken(scope: account.scope, epoch: UUID())
        XCTAssertThrowsError(
            try state.applying(
                [.init(.favorite(track), .deleted)], ifUnchanged: state.checkpoint.local,
                account: other)
        ) { XCTAssertEqual($0 as? CollectionSyncError, .staleAccount) }
        let newer = try state.applying(
            [.init(.favorite(track), .deleted)], ifUnchanged: state.checkpoint.local,
            account: account)
        XCTAssertThrowsError(
            try newer.applying([], ifUnchanged: state.checkpoint.local, account: account)
        ) { XCTAssertEqual($0 as? CollectionSyncError, .stalePreview) }
        XCTAssertThrowsError(
            try state.applying(
                [.init(.favorite(track), .deleted), .init(.favorite(track), .flag(true))],
                ifUnchanged: state.checkpoint.local, account: account)
        ) { XCTAssertEqual($0 as? CollectionSyncError, .invalidDecision) }
        XCTAssertThrowsError(
            try state.applying(
                [.init(.trackSetting(track, .stereoSeparation), .number(.nan))],
                ifUnchanged: state.checkpoint.local, account: account))
        XCTAssertFalse(try state.checkpoint.pendingChanges())
    }

    func testRemovingUserMetadataRetainsTrackDescriptorAndConfirmedMapping() throws {
        let (state, track, marker) = try fixture()
        XCTAssertThrowsError(
            try state.applying(
                [.init(.track(track), .deleted)], ifUnchanged: state.checkpoint.local,
                account: state.checkpoint.account))
        let changes: [CollectionSyncCell] =
            [
            .init(.favorite(track), .deleted),
                .init(.marker(marker), .deleted),
            ] + CollectionSyncField.allCases.map { .init(.trackSetting(track, $0), .inherit) }
        let removed = try state.applying(
            changes, ifUnchanged: state.checkpoint.local, account: state.checkpoint.account)
        let document = try removed.checkpoint.local.exchangeDocument()
        XCTAssertEqual(document.tracks.count, 1)
        XCTAssertTrue(document.favoriteTrackIDs.isEmpty)
        XCTAssertTrue(document.markers.isEmpty)
        XCTAssertTrue(document.trackSettings.isEmpty)
        XCTAssertEqual(removed.registry.bindings.count, 1)
    }

    func testNewTrackAndItsIdentityAreProposedTogetherAndOldAliasesCannotDisappear() throws {
        let (state, _, _) = try fixture()
        let account = state.checkpoint.account
        let id = UUID()
        let reference = PlaylistTrackReference(
            source: .init(location: URL(fileURLWithPath: "/synthetic/second.mod")),
            displayName: "second.mod")
        let changes: [CollectionSyncCell] = [
            .init(.track(id), .track(.init(fileName: "second.mod"))),
            .init(.favorite(id), .flag(true)),
        ]
        XCTAssertThrowsError(
            try state.applying(changes, ifUnchanged: state.checkpoint.local, account: account)
        ) { XCTAssertEqual($0 as? CollectionExchangeError, .unmappedSources) }
        let registry = try state.registry.assigning(id, to: reference, account: account)
        let added = try state.applying(
            changes, registry: registry, ifUnchanged: state.checkpoint.local, account: account)
        XCTAssertEqual(added.registry.bindings.count, 2)
        let lost = CollectionSyncTrackRegistry(
            account: account, collectionID: registry.collectionID, generation: registry.generation)
        XCTAssertThrowsError(
            try added.applying(
                [], registry: lost, ifUnchanged: added.checkpoint.local, account: account)
        ) { XCTAssertEqual($0 as? CollectionExchangeError, .invalidMapping) }
        let retargeted = CollectionSyncTrackRegistry(
            account: account, collectionID: registry.collectionID, generation: registry.generation,
            bindings: state.registry.bindings.map { .init(id: $0.id, reference: reference) })
        XCTAssertThrowsError(
            try state.applying(
                [], registry: retargeted, ifUnchanged: state.checkpoint.local, account: account)
        ) { XCTAssertEqual($0 as? CollectionExchangeError, .invalidMapping) }
    }

    func testOfflineMarkerConflictAfterRestartRequiresDecisionAndKeepsFractionalDate() throws {
        let (state, _, marker) = try fixture()
        let account = state.checkpoint.account
        guard case .marker(var localMarker) = state.checkpoint.local.indexed()[.marker(marker)]
        else { return XCTFail("Missing marker") }
        let date = localMarker.createdAt
        localMarker.name = "Local edit"
        let edited = try state.applying(
            [.init(.marker(marker), .marker(localMarker))], ifUnchanged: state.checkpoint.local,
            account: account)
        let restarted = try CollectionSyncLocalStateCodec.decode(
            CollectionSyncLocalStateCodec.encode(edited))
        localMarker.name = "Remote edit"
        var remote = state.checkpoint.base
        remote.cells.removeAll { $0.id == .marker(marker) }
        remote.cells.append(.init(.marker(marker), .marker(localMarker)))
        let plan = try CollectionSyncMergePlan(
            base: restarted.checkpoint.base, local: restarted.checkpoint.local, remote: remote)
        XCTAssertEqual(plan.conflicts.count, 1)
        XCTAssertThrowsError(try plan.result(ifUnchanged: restarted.checkpoint.local))
        let copy = UUID()
        let merged = try plan.result(
            ifUnchanged: restarted.checkpoint.local,
            resolutions: [.marker(marker): .keepBoth(copyID: copy)])
        let markers = try merged.exchangeDocument().markers
        XCTAssertEqual(Set(markers.map(\.name)), ["Local edit", "Remote edit"])
        XCTAssertEqual(Set(markers.map(\.createdAt)), [date])
    }

    func testBundleRejectsMismatchedAccountCollectionGenerationAndCloudCodec() throws {
        let (state, _, _) = try fixture()
        let registry = state.registry
        func stateWith(_ value: CollectionSyncTrackRegistry) -> CollectionSyncLocalState {
            .init(checkpoint: state.checkpoint, registry: value)
        }
        let other = CollectionSyncAccountToken(scope: registry.account.scope, epoch: UUID())
        XCTAssertThrowsError(
            try stateWith(
                .init(
                    account: other, collectionID: registry.collectionID,
                    generation: registry.generation)
            ).validate()
        ) { XCTAssertEqual($0 as? CollectionSyncError, .staleAccount) }
        XCTAssertThrowsError(
            try stateWith(
                .init(
                    account: registry.account, collectionID: UUID(), generation: registry.generation
                )
            ).validate()
        ) { XCTAssertEqual($0 as? CollectionSyncError, .mismatchedCollection) }
        XCTAssertThrowsError(
            try stateWith(
                .init(
                    account: registry.account, collectionID: registry.collectionID,
                    generation: UUID())
            ).validate()
        ) { XCTAssertEqual($0 as? CollectionSyncError, .staleGeneration) }
        let localData = try CollectionSyncLocalStateCodec.encode(state)
        XCTAssertThrowsError(try CollectionSyncCodec.decode(localData))
        XCTAssertThrowsError(
            try CollectionSyncLocalStateCodec.decode(
                CollectionSyncCodec.encode(state.checkpoint.local)))
    }

    func testMissingCorruptFutureNonRegularOversizedAndCancelledFilesDoNotBecomeEmpty() throws {
        let (state, _, _) = try fixture()
        let root = try directory()
        let file = root.appendingPathComponent("state.json")
        XCTAssertThrowsError(try CollectionSyncLocalStateCodec.load(from: file))
        try Data("{broken".utf8).write(to: file)
        XCTAssertThrowsError(try CollectionSyncLocalStateCodec.load(from: file))
        var future = state
        future.schemaVersion = 2
        XCTAssertThrowsError(try CollectionSyncLocalStateCodec.decode(JSONEncoder().encode(future)))
        { XCTAssertEqual($0 as? CollectionSyncError, .unsupportedVersion(2)) }
        XCTAssertThrowsError(try CollectionSyncLocalStateCodec.load(from: root))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(CollectionSyncLocalStateCodec.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try CollectionSyncLocalStateCodec.load(from: file)) {
            XCTAssertEqual($0 as? CollectionSyncError, .oversized)
        }
        XCTAssertThrowsError(
            try CollectionSyncLocalStateCodec.load(from: file, isCancelled: { true })
        ) { XCTAssertTrue($0 is CancellationError) }
    }
}

import XCTest
@testable import SavageModPlayerCore

final class CollectionSyncTests: XCTestCase {
    private let collection = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let generation = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private let track = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let otherTrack = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let playlist = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private let marker = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!

    private func fixture(full: Bool = true) throws -> CollectionSyncSnapshot {
        var document = CollectionExchangeDocument(id: collection)
        document.tracks = [.init(id: track, descriptor: .init(fileName: "song.mod", relativePath: "A/song.mod", byteCount: 2112)),
                           .init(id: otherTrack, descriptor: .init(fileName: "song.mod", relativePath: "B/song.mod", byteCount: 2112))]
        if full {
            document.playlists = [.init(id: playlist, name: "Synthetic", trackIDs: [track, otherTrack])]
            document.favoriteTrackIDs = [track]
            document.markers = [.init(id: marker, trackID: otherTrack, name: "Position", address: .init(position: 1, row: 16),
                                     createdAt: Date(timeIntervalSinceReferenceDate: 812_345_678.1234567))]
            document.trackSettings = [.init(trackID: track, overrides: .init(palClock: false, stereoSeparation: 0.2))]
            document.playbackDefaults = .init(.init(palClock: true, stereoSeparation: 0.8, useInterpolation: true, ledFilterActive: false))
        }
        return try .init(document: document, collectionID: collection, generation: generation)
    }
    private func replacing(_ snapshot: CollectionSyncSnapshot, _ key: CollectionSyncKey, _ value: CollectionSyncValue?) -> CollectionSyncSnapshot {
        var snapshot = snapshot
        snapshot.cells.removeAll { $0.id == key }
        if let value { snapshot.cells.append(.init(key, value)) }
        return snapshot
    }
    private func token(epoch: UUID = UUID()) -> CollectionSyncAccountToken { .init(scope: String(repeating: "a", count: 64), epoch: epoch) }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("collection-sync-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }

    func testPortableProjectionPreservesStableReferencesOrderAndSound() throws {
        let snapshot = try fixture(), document = try snapshot.exchangeDocument()
        XCTAssertEqual(document.tracks.count, 2); XCTAssertEqual(document.playlists.first?.trackIDs, [track, otherTrack])
        XCTAssertEqual(document.favoriteTrackIDs, [track]); XCTAssertEqual(document.markers.first?.trackID, otherTrack)
        XCTAssertEqual(document.trackSettings.first?.overrides, .init(palClock: false, stereoSeparation: 0.2))
        XCTAssertEqual(document.playbackDefaults?.stereoSeparation, 0.8)
        XCTAssertTrue(snapshot.cells.contains(.init(.trackSetting(track, .ledFilterActive), .inherit)))
    }

    func testCheckpointSurvivesDiskRestartWithExactFractionalDatesAndPendingChanges() throws {
        let root = try directory(), base = try fixture()
        let local = replacing(base, .trackSetting(track, .palClock), .inherit)
        let checkpoint = CollectionSyncCheckpoint(account: token(), base: base, local: local, serverChangeTag: "synthetic-change-tag")
        XCTAssertTrue(try checkpoint.pendingChanges())
        let file = root.appendingPathComponent("checkpoint.json")
        try CollectionSyncCodec.encode(checkpoint).write(to: file, options: .atomic)
        let restored = try CollectionSyncCodec.loadCheckpoint(from: file)
        XCTAssertTrue(try restored.pendingChanges()); XCTAssertEqual(restored.serverChangeTag, checkpoint.serverChangeTag)
        XCTAssertEqual(try restored.local.exchangeDocument().markers.first?.createdAt,
                       try local.exchangeDocument().markers.first?.createdAt)
        XCTAssertEqual(try CollectionSyncCodec.encode(restored), try CollectionSyncCodec.encode(checkpoint))
        try restored.validate(completing: checkpoint.account)
    }

    func testAll64AtomicCellCombinationsFailClosedOrMergeSymmetrically() throws {
        let base = try fixture(full: false)
        let values: [CollectionSyncValue?] = [nil, .deleted,
            .playlist(.init(id: playlist, name: "A", trackIDs: [track])),
            .playlist(.init(id: playlist, name: "B", trackIDs: [otherTrack]))]
        var combinations = 0
        for b in values { for l in values { for r in values {
            let baseline = replacing(base, .playlist(playlist), b), local = replacing(base, .playlist(playlist), l), remote = replacing(base, .playlist(playlist), r)
            combinations += 1
            if b != nil && (l == nil || r == nil) {
                XCTAssertThrowsError(try CollectionSyncMergePlan(base: baseline, local: local, remote: remote)) {
                    XCTAssertEqual($0 as? CollectionSyncError, .incompleteSnapshot)
                }; continue
            }
            let plan = try CollectionSyncMergePlan(base: baseline, local: local, remote: remote)
            let isConflict = l != r && l != b && r != b
            XCTAssertEqual(!plan.conflicts.isEmpty, isConflict)
            if isConflict { XCTAssertThrowsError(try plan.result(ifUnchanged: local)) }
            else {
                let mirrored = try CollectionSyncMergePlan(base: baseline, local: remote, remote: local).result(ifUnchanged: remote)
                XCTAssertEqual(try CollectionSyncCodec.encode(plan.result(ifUnchanged: local)), try CollectionSyncCodec.encode(mirrored))
            }
        } } }
        XCTAssertEqual(combinations, 64)
    }

    func testIndependentChangesConvergeAndPublishedButUnacknowledgedStateIsIdempotent() throws {
        let base = try fixture()
        let a = replacing(base, .defaultSetting(.ledFilterActive), .flag(true))
        let b = replacing(base, .trackSetting(track, .stereoSeparation), .number(0.31))
        let merged = try CollectionSyncMergePlan(base: base, local: a, remote: b).result(ifUnchanged: a)
        XCTAssertEqual(try merged.exchangeDocument().playbackDefaults?.ledFilterActive, true)
        XCTAssertEqual(try merged.exchangeDocument().trackSettings.first?.overrides.stereoSeparation, 0.31)
        let replayed = try CollectionSyncMergePlan(base: base, local: a, remote: merged).result(ifUnchanged: a)
        XCTAssertEqual(try CollectionSyncCodec.encode(replayed), try CollectionSyncCodec.encode(merged))
    }

    func testPlaylistReorderAndRenameConflictAsOneUnitAndKeepBothIsStable() throws {
        let base = try fixture()
        let a = replacing(base, .playlist(playlist), .playlist(.init(id: playlist, name: "Renamed", trackIDs: [track, otherTrack])))
        let b = replacing(base, .playlist(playlist), .playlist(.init(id: playlist, name: "Synthetic", trackIDs: [otherTrack, track])))
        let plan = try CollectionSyncMergePlan(base: base, local: a, remote: b)
        XCTAssertEqual(plan.conflicts.count, 1); XCTAssertTrue(plan.conflicts[0].allowsKeepingBoth)
        let copy = UUID()
        let choices: [CollectionSyncKey: CollectionSyncResolution] = [.playlist(playlist): .keepBoth(copyID: copy)]
        let result = try plan.result(ifUnchanged: a, resolutions: choices)
        let lists = try result.exchangeDocument().playlists
        XCTAssertEqual(lists.first { $0.id == playlist }?.name, "Renamed")
        XCTAssertEqual(lists.first { $0.id == copy }?.trackIDs, [otherTrack, track])
        XCTAssertEqual(try CollectionSyncCodec.encode(result), try CollectionSyncCodec.encode(plan.result(ifUnchanged: a, resolutions: choices)))
        let replay = try CollectionSyncMergePlan(base: base, local: a, remote: result).result(ifUnchanged: a)
        XCTAssertEqual(try CollectionSyncCodec.encode(replay), try CollectionSyncCodec.encode(result))
        XCTAssertThrowsError(try plan.result(ifUnchanged: a, resolutions: [.playlist(playlist): .keepBoth(copyID: playlist)]))
    }

    func testDeleteVersusEditRequiresExplicitRestoreOrDeletion() throws {
        let base = try fixture(), deleted = replacing(base, .playlist(playlist), .deleted)
        let edited = replacing(base, .playlist(playlist), .playlist(.init(id: playlist, name: "Offline edit", trackIDs: [track])))
        let plan = try CollectionSyncMergePlan(base: base, local: deleted, remote: edited)
        XCTAssertFalse(plan.conflicts[0].allowsKeepingBoth)
        XCTAssertTrue(try plan.result(ifUnchanged: deleted, resolutions: [.playlist(playlist): .keepLocal]).exchangeDocument().playlists.isEmpty)
        XCTAssertEqual(try plan.result(ifUnchanged: deleted, resolutions: [.playlist(playlist): .useRemote]).exchangeDocument().playlists.first?.name, "Offline edit")
        XCTAssertThrowsError(try plan.result(ifUnchanged: deleted, resolutions: [.playlist(playlist): .keepBoth(copyID: UUID())]))
    }

    func testUnchangedOfflineDeviceDoesNotResurrectDeletedFavorite() throws {
        let base = try fixture(), deleted = replacing(base, .favorite(track), .deleted)
        let result = try CollectionSyncMergePlan(base: base, local: base, remote: deleted).result(ifUnchanged: base)
        XCTAssertTrue(try result.exchangeDocument().favoriteTrackIDs.isEmpty)
        XCTAssertTrue(result.cells.contains(.init(.favorite(track), .deleted)))
    }

    func testMissingKnownMetadataCannotMasqueradeAsAnIntentionalDeletion() throws {
        let base = try fixture(), missing = replacing(base, .marker(marker), nil)
        XCTAssertThrowsError(try CollectionSyncMergePlan(base: base, local: missing, remote: base)) {
            XCTAssertEqual($0 as? CollectionSyncError, .incompleteSnapshot)
        }
        XCTAssertThrowsError(try CollectionSyncCheckpoint(account: token(), base: base, local: missing).validate())
    }

    func testStalePreviewAndUnrelatedDecisionsAreRejected() throws {
        let base = try fixture(), local = replacing(base, .favorite(track), .deleted)
        let plan = try CollectionSyncMergePlan(base: base, local: local, remote: base)
        XCTAssertThrowsError(try plan.result(ifUnchanged: base)) { XCTAssertEqual($0 as? CollectionSyncError, .stalePreview) }
        XCTAssertThrowsError(try plan.result(ifUnchanged: local, resolutions: [.marker(marker): .keepLocal])) {
            XCTAssertEqual($0 as? CollectionSyncError, .invalidDecision)
        }
    }

    func testConcurrentParentRemovalAndNewReferenceCannotPublishBrokenCollection() throws {
        let base = try fixture(full: false), local = replacing(base, .track(track), .deleted)
        let remote = replacing(base, .playlist(playlist), .playlist(.init(id: playlist, name: "New", trackIDs: [track])))
        let plan = try CollectionSyncMergePlan(base: base, local: local, remote: remote)
        XCTAssertTrue(plan.conflicts.isEmpty)
        XCTAssertThrowsError(try plan.result(ifUnchanged: local)) { XCTAssertEqual($0 as? CollectionSyncError, .invalidSnapshot) }
    }

    func testMarkerCopiesPreservePositionAndFractionalCreationDate() throws {
        let base = try fixture(), original = try XCTUnwrap(base.exchangeDocument().markers.first)
        var a = original, b = original; a.name = "Local"; b.address.row = 32
        let local = replacing(base, .marker(marker), .marker(a)), remote = replacing(base, .marker(marker), .marker(b))
        let plan = try CollectionSyncMergePlan(base: base, local: local, remote: remote), copy = UUID()
        let result = try plan.result(ifUnchanged: local, resolutions: [.marker(marker): .keepBoth(copyID: copy)])
        let markers = try CollectionSyncCodec.decode(CollectionSyncCodec.encode(result)).exchangeDocument().markers
        XCTAssertEqual(markers.first { $0.id == copy }?.address.row, 32)
        XCTAssertEqual(markers.first { $0.id == copy }?.createdAt, original.createdAt)
        XCTAssertEqual(markers.first { $0.id == marker }?.name, "Local")
    }

    func testInheritanceIsExplicitAndInvalidScalarKindsAreRejected() throws {
        let base = try fixture(), inherited = replacing(base, .trackSetting(track, .palClock), .inherit)
        let result = try CollectionSyncMergePlan(base: base, local: inherited, remote: base).result(ifUnchanged: inherited)
        XCTAssertNil(try result.exchangeDocument().trackSettings.first?.overrides.palClock)
        for value: CollectionSyncValue in [.deleted, .number(0.5), .track(.init(fileName: "song.mod"))] {
            XCTAssertThrowsError(try replacing(base, .trackSetting(track, .palClock), value).validate())
        }
        for number in [-0.1, 1.1, Double.nan, .infinity] {
            XCTAssertThrowsError(try replacing(base, .defaultSetting(.stereoSeparation), .number(number)).validate())
        }
    }

    func testAccountEpochAndOpaqueScopeRejectOldCompletionsWithoutDroppingLocalData() throws {
        let base = try fixture(), account = token()
        let checkpoint = CollectionSyncCheckpoint(account: account, base: base, local: base)
        XCTAssertThrowsError(try checkpoint.validate(completing: token())) { XCTAssertEqual($0 as? CollectionSyncError, .staleAccount) }
        let other = CollectionSyncAccountToken(scope: String(repeating: "b", count: 64), epoch: account.epoch)
        XCTAssertThrowsError(try checkpoint.validate(completing: other))
        XCTAssertEqual(checkpoint.local, base)
        XCTAssertThrowsError(try CollectionSyncCheckpoint(account: .init(scope: "account@example.invalid", epoch: UUID()), base: base, local: base).validate())
    }

    func testCanonicalEncodingAndCorruptFutureDuplicateOrPartialDataFailClosed() throws {
        let base = try fixture(); var reordered = base; reordered.cells.reverse()
        XCTAssertEqual(try CollectionSyncCodec.encode(base), try CollectionSyncCodec.encode(reordered))
        XCTAssertThrowsError(try CollectionSyncCodec.decode(Data("{broken".utf8)))
        var future = base; future.schemaVersion = 2
        XCTAssertThrowsError(try CollectionSyncCodec.decode(JSONEncoder().encode(future))) { XCTAssertEqual($0 as? CollectionSyncError, .unsupportedVersion(2)) }
        var duplicate = base; duplicate.cells.append(base.cells[0]); XCTAssertThrowsError(try duplicate.validate())
        XCTAssertThrowsError(try replacing(base, .defaultSetting(.palClock), nil).validate())
        XCTAssertThrowsError(try replacing(base, .playlist(playlist), .playlist(.init(id: UUID(), name: "Wrong ID", trackIDs: []))).validate())
        XCTAssertThrowsError(try replacing(base, .playlist(playlist), .playlist(.init(id: playlist, name: "Duplicate entry", trackIDs: [track, track]))).validate())
        XCTAssertThrowsError(try CollectionSyncCodec.decode(Data(count: CollectionSyncCodec.maximumBytes + 1))) { XCTAssertEqual($0 as? CollectionSyncError, .oversized) }
        var foreign = base; foreign.format = "other-format"
        XCTAssertThrowsError(try CollectionSyncCodec.decode(JSONEncoder().encode(foreign)))
    }

    func testLocalSavedListDisplayOrderIsRetainedWhileTrackOrderRemainsShared() throws {
        var snapshot = try fixture(), copy = UUID()
        snapshot.cells.append(.init(.playlist(copy), .playlist(.init(id: copy, name: "Second", trackIDs: [otherTrack, track]))))
        let document = try snapshot.exchangeDocument(preservingLocalPlaylistOrder: [copy, playlist])
        XCTAssertEqual(document.playlists.map(\.id), [copy, playlist])
        XCTAssertEqual(document.playlists.first?.trackIDs, [otherTrack, track])
        XCTAssertThrowsError(try snapshot.exchangeDocument(preservingLocalPlaylistOrder: [copy, copy]))
    }

    func testMissingDamagedCanceledAndOversizedCheckpointsNeverReturnAnEmptyState() throws {
        let root = try directory(), file = root.appendingPathComponent("checkpoint.json")
        XCTAssertThrowsError(try CollectionSyncCodec.loadCheckpoint(from: file))
        try Data("{broken".utf8).write(to: file); XCTAssertThrowsError(try CollectionSyncCodec.loadCheckpoint(from: file))
        XCTAssertThrowsError(try CollectionSyncCodec.loadCheckpoint(from: file, isCancelled: { true })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try CollectionSyncCodec.decodeCheckpoint(Data(count: CollectionSyncCodec.maximumCheckpointBytes + 1))) {
            XCTAssertEqual($0 as? CollectionSyncError, .oversized)
        }
    }

    func testForeignCollectionsAndGenerationsNeverMerge() throws {
        let base = try fixture()
        for remote in [CollectionSyncSnapshot(collectionID: UUID(), generation: generation),
                       CollectionSyncSnapshot(collectionID: collection, generation: UUID())] {
            XCTAssertThrowsError(try CollectionSyncMergePlan(base: base, local: base, remote: remote))
        }
    }

    func testTwentyThousandTracksRoundTripAndTombstonesCountTowardLimits() throws {
        let cells = (0..<20_000).map { index -> CollectionSyncCell in
            let id = UUID(uuidString: String(format: "50000000-0000-0000-0000-%012d", index))!
            return .init(.track(id), .track(.init(fileName: "track-\(index).mod", byteCount: 2112)))
        }
        let snapshot = CollectionSyncSnapshot(collectionID: collection, generation: generation, cells: cells)
        let data = try CollectionSyncCodec.encode(snapshot)
        XCTAssertEqual(try CollectionSyncCodec.decode(data).cells.count, 20_000)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("file://"))
        var oversized = snapshot; oversized.cells.append(.init(.track(UUID()), .deleted))
        XCTAssertThrowsError(try oversized.validate()) { XCTAssertEqual($0 as? CollectionSyncError, .oversized) }
    }
}

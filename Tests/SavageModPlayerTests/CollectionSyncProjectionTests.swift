import XCTest
@testable import SavageModPlayerCore

final class CollectionSyncProjectionTests: XCTestCase {
    private let collection = UUID(), generation = UUID(), track = UUID(), playlist = UUID(), marker = UUID()
    private func reference(_ name: String) -> PlaylistTrackReference {
        .init(source: .init(location: URL(fileURLWithPath: "/synthetic/\(name).mod")), displayName: "\(name).mod")
    }
    private func local() -> CollectionExchangeSnapshot {
        var local = CollectionExchangeSnapshot(playbackDefaults: .init())
        let track = reference("known"), unknown = reference("device-only")
        local.playlists.playlists = [.init(id: playlist, name: "Before", tracks: [track]), .init(name: "Device only", tracks: [unknown])]
        local.playlists.favoriteIDs = [track.id, unknown.id]
        local.markers.markers = [.init(id: marker, sourceID: track.id, name: "Before", address: .init(position: 0, row: 0))]
        local.trackSettings.tracks[track.id] = .init(palClock: false, stereoSeparation: 0.2)
        local.trackSettings.tracks[unknown.id] = .init(useInterpolation: false)
        return local
    }
    private func snapshot(_ cells: [CollectionSyncCell]) -> CollectionSyncSnapshot {
        .init(collectionID: collection, generation: generation, cells: [.init(.track(track), .track(.init(fileName: "known.mod")))] + cells)
    }
    private func projection(_ snapshot: CollectionSyncSnapshot, _ local: CollectionExchangeSnapshot,
                            mapping: [UUID: PlaylistTrackReference]? = nil) throws -> CollectionSyncProjection {
        try .init(snapshot: snapshot, into: local, mapping: mapping ?? [track: reference("known")],
                  collectionID: collection, generation: generation)
    }

    func testExplicitDeletionsRemoveOnlyLinkedMetadataWhileManualImportStaysAdditive() throws {
        let local = local(), mapping = [track: reference("known")]
        let snapshot = snapshot([.init(.favorite(track), .deleted), .init(.playlist(playlist), .deleted), .init(.marker(marker), .deleted)])
        let manual = try CollectionExchangeImporter.preview(snapshot.exchangeDocument(), into: local, mapping: mapping).result(ifUnchanged: local)
        XCTAssertTrue(manual.playlists.favoriteIDs.contains(reference("known").id))
        let plan = try projection(snapshot, local)
        let result = try plan.result(ifUnchanged: local, mapping: mapping)
        XCTAssertFalse(result.playlists.favoriteIDs.contains(reference("known").id))
        XCTAssertTrue(result.playlists.favoriteIDs.contains(reference("device-only").id))
        XCTAssertFalse(result.playlists.playlists.contains { $0.id == playlist }); XCTAssertTrue(result.markers.markers.isEmpty)
        XCTAssertEqual(result.playlists.playlists.first?.name, "Device only")
        XCTAssertEqual(result.trackSettings, local.trackSettings)
    }

    func testMissingAndAmbiguousMappingsCannotPartiallyApply() throws {
        let local = local(), snapshot = snapshot([.init(.favorite(track), .deleted)])
        let missing = try projection(snapshot, local, mapping: [:])
        XCTAssertFalse(missing.isReady); XCTAssertEqual(missing.unresolvedTrackIDs, [track])
        XCTAssertThrowsError(try missing.result(ifUnchanged: local, mapping: [:])) {
            XCTAssertEqual($0 as? CollectionExchangeError, .unmappedSources)
        }
        let other = UUID()
        var duplicate = snapshot; duplicate.cells.append(.init(.track(other), .track(.init(fileName: "known.mod"))))
        XCTAssertThrowsError(try projection(duplicate, local, mapping: [track: reference("known"), other: reference("known")]))
        XCTAssertEqual(local.playlists.favoriteIDs.count, 2)
    }

    func testInheritanceClearsOnlySpecifiedOverrideAndUsesIncomingGlobalDefault() throws {
        let local = local(), mapping = [track: reference("known")]
        let snapshot = snapshot([.init(.trackSetting(track, .palClock), .inherit),
            .init(.defaultSetting(.palClock), .flag(true)), .init(.defaultSetting(.stereoSeparation), .number(0.31)),
            .init(.defaultSetting(.useInterpolation), .flag(false)), .init(.defaultSetting(.ledFilterActive), .flag(true))])
        let result = try projection(snapshot, local).result(ifUnchanged: local, mapping: mapping)
        XCTAssertNil(result.trackSettings.tracks[reference("known").id]?.palClock)
        XCTAssertEqual(result.trackSettings.tracks[reference("known").id]?.stereoSeparation, 0.2)
        XCTAssertEqual(result.playbackDefaults, .init(palClock: true, stereoSeparation: 0.31, useInterpolation: false, ledFilterActive: true))
        XCTAssertEqual(result.trackSettings.tracks[reference("device-only").id], .init(useInterpolation: false))
    }

    func testTrackTombstoneDoesNotDeleteLocalMusicReferencesOrUnlistedMetadata() throws {
        let local = local()
        let snapshot = CollectionSyncSnapshot(collectionID: collection, generation: generation, cells: [.init(.track(track), .deleted)])
        let result = try projection(snapshot, local).result(ifUnchanged: local, mapping: [track: reference("known")])
        XCTAssertEqual(result, local)
    }

    func testLiveEntitiesUpdateByIDAndKeepExistingSavedListDisplayOrder() throws {
        let local = local(), date = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
        let snapshot = snapshot([.init(.playlist(playlist), .playlist(.init(id: playlist, name: "After", trackIDs: [track]))),
            .init(.marker(marker), .marker(.init(id: marker, trackID: track, name: "After", address: .init(position: 1, row: 16), createdAt: date)))])
        let result = try projection(snapshot, local).result(ifUnchanged: local, mapping: [track: reference("known")])
        XCTAssertEqual(result.playlists.playlists.map(\.id), local.playlists.playlists.map(\.id))
        XCTAssertEqual(result.playlists.playlists.first?.name, "After")
        XCTAssertEqual(result.markers.markers.first?.createdAt, date); XCTAssertEqual(result.markers.markers.first?.address.row, 16)
    }

    func testChangedLocalStateMappingOrCollectionInvalidatesPreview() throws {
        let local = local(), snapshot = snapshot([.init(.favorite(track), .deleted)])
        let plan = try projection(snapshot, local)
        var changed = local; changed.playlists.favoriteIDs.removeAll()
        XCTAssertThrowsError(try plan.result(ifUnchanged: changed, mapping: [track: reference("known")]))
        XCTAssertThrowsError(try plan.result(ifUnchanged: local, mapping: [track: reference("different")]))
        XCTAssertThrowsError(try CollectionSyncProjection(snapshot: snapshot, into: local, mapping: [:], collectionID: UUID(), generation: generation))
        XCTAssertThrowsError(try CollectionSyncProjection(snapshot: snapshot, into: local, mapping: [:], collectionID: collection, generation: UUID()))
    }
}

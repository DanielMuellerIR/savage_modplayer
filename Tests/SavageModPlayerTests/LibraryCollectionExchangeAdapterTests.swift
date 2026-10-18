import XCTest
@testable import SavageModPlayerCore

final class LibraryCollectionExchangeAdapterTests: XCTestCase {
    func testRealLibraryStorageFormsRoundTripWithoutChangingUnrelatedFavorites() throws {
        let paths = ["A/same.mod", "B/same.mod"]
        let mac = paths.map { PlaylistTrackReference(source: .init(location: URL(fileURLWithPath: "/synthetic/" + $0)), displayName: "same.mod") }
        let phone = paths.map { PlaylistTrackReference(source: PlaylistTrackSource(libraryRelativePath: $0)!, displayName: "same.mod") }
        var original = CollectionExchangeSnapshot(playbackDefaults: .init(stereoSeparation: 0.4))
        original.playlists.playlists = [.init(name: "Ordered", tracks: mac.reversed())]
        original.playlists.favoriteIDs = [mac[0].id]
        original.markers.markers = [.init(sourceID: mac[1].id, name: "Second order", address: .init(position: 2, row: 7), createdAt: Date(timeIntervalSince1970: 1_700_000_000))]
        original.trackSettings.tracks[mac[0].id] = .init(palClock: false, useInterpolation: false)
        let sources = zip(mac, paths).map { CollectionExchangeLocalTrack(reference: $0.0, descriptor: .init(fileName: "same.mod", relativePath: $0.1)) }
        let wire = try CollectionExchangeCodec.decode(CollectionExchangeCodec.encode(CollectionExchangeExporter.makeDocument(from: original, sources: sources)))
        var emptyLists = SavedPlaylistDocument(); emptyLists.favoriteIDs = ["unused-private-store-value"]
        let empty = CollectionExchangeStoredDocuments(playlists: emptyLists, markers: .init(), trackSettings: .init())
        let adapter = try LibraryCollectionExchangeAdapter(documents: empty, favoritePaths: ["missing/old.mod"], availablePaths: paths, defaults: .init())
        let mapping = Dictionary(uniqueKeysWithValues: wire.tracks.map { track in
            (track.id, phone[paths.firstIndex(of: track.descriptor.relativePath!)!])
        })
        let result = try CollectionExchangeImporter.preview(wire, into: adapter.snapshot, mapping: mapping,
            resolutions: [.playbackDefaults: .useIncoming]).result(ifUnchanged: adapter.snapshot)
        let stored = try adapter.storedResult(from: result)
        XCTAssertEqual(stored.favoritePaths, [paths[0], "missing/old.mod"])
        XCTAssertEqual(stored.documents.playlists.favoriteIDs, emptyLists.favoriteIDs)
        XCTAssertEqual(stored.documents.markers.markers[0].sourceID, paths[1])
        XCTAssertEqual(stored.documents.trackSettings.tracks[paths[0]]?.palClock, false)
        XCTAssertNil(stored.documents.trackSettings.tracks[phone[0].id])
        XCTAssertEqual(stored.documents.playlists.playlists[0].tracks.map { $0.source.libraryRelativePath! }, paths.reversed())
        let after = try LibraryCollectionExchangeAdapter(documents: stored.documents, favoritePaths: stored.favoritePaths, availablePaths: paths, defaults: result.playbackDefaults!)
        let phoneSources = try CollectionExchangeSources.make(snapshot: after.snapshot, available: [])
        let back = try CollectionExchangeCodec.decode(CollectionExchangeCodec.encode(CollectionExchangeExporter.makeDocument(from: after.snapshot, sources: phoneSources)))
        let known = back.tracks.filter { paths.contains($0.descriptor.relativePath ?? "") }
        let reverseMapping = Dictionary(uniqueKeysWithValues: known.map { ($0.id, mac[paths.firstIndex(of: $0.descriptor.relativePath!)!]) })
        let skipped = Set(back.tracks.filter { reverseMapping[$0.id] == nil }.map(\.id))
        let restored = try CollectionExchangeImporter.preview(back, into: original, mapping: reverseMapping, skippedTrackIDs: skipped).result(ifUnchanged: original)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(try adapter.storedResult(from: adapter.snapshot).documents, empty)
    }

    func testMissingLibrarySourcesRemainPortableAndInvalidPathsFailVisibly() throws {
        var markers = SongMarkerDocument()
        markers.markers = [.init(sourceID: "missing/ü.mod", name: "Marker", address: .init(position: 4, row: 9))]
        let documents = CollectionExchangeStoredDocuments(playlists: .init(), markers: markers, trackSettings: .init())
        let adapter = try LibraryCollectionExchangeAdapter(documents: documents, favoritePaths: [], availablePaths: [], defaults: .init())
        let sources = try CollectionExchangeSources.make(snapshot: adapter.snapshot, available: [])
        XCTAssertEqual(sources[0].descriptor.relativePath, "missing/ü.mod")
        XCTAssertNil(sources[0].descriptor.byteCount)
        XCTAssertThrowsError(try LibraryCollectionExchangeAdapter(documents: documents, favoritePaths: ["/absolute/song.mod"], availablePaths: [], defaults: .init()))
        var bad = adapter.snapshot; bad.playlists.favoriteIDs.insert("unknown")
        XCTAssertThrowsError(try adapter.storedResult(from: bad))
    }
}

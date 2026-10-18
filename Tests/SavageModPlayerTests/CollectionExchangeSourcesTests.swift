import XCTest
@testable import SavageModPlayerCore

final class CollectionExchangeSourcesTests: XCTestCase {
    func testArchiveHintsUseOuterRelativePathMemberChainAndResolvedModuleSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resolved = root.appendingPathComponent("extracted.mod")
        try Data(repeating: 0, count: 2112).write(to: resolved)
        let reference = PlaylistTrackReference(source: .init(location: root.appendingPathComponent("Music/outer.zip"),
            archiveMembers: ["folder/inner.zip", "A/song.mod"]), displayName: "song.mod")
        var snapshot = CollectionExchangeSnapshot()
        snapshot.playlists.favoriteIDs = [reference.id]
        let sources = try CollectionExchangeSources.make(snapshot: snapshot, available: [.init(reference: reference, url: resolved)], libraryRoot: root)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].descriptor, .init(fileName: "song.mod", relativePath: "Music/outer.zip",
            archiveMembers: ["folder/inner.zip", "A/song.mod"], byteCount: 2112))
        let exported = try CollectionExchangeExporter.makeDocument(from: snapshot, sources: sources, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(try CollectionExchangeCodec.decode(CollectionExchangeCodec.encode(exported)), exported)
    }

    func testMissingMetadataSourcesRemainExportableAndCancellationStopsCatalogWork() throws {
        let reference = PlaylistTrackReference(source: .init(location: URL(fileURLWithPath: "/synthetic/unavailable/song.mod")), displayName: "song.mod")
        var snapshot = CollectionExchangeSnapshot()
        snapshot.markers.markers = [.init(sourceID: reference.id, name: "Retained marker", address: .init(position: 1, row: 16))]
        let sources = try CollectionExchangeSources.make(snapshot: snapshot, available: [])
        XCTAssertEqual(sources.count, 1); XCTAssertEqual(sources[0].reference.id, reference.id)
        XCTAssertEqual(sources[0].descriptor.fileName, "song.mod")
        XCTAssertNil(sources[0].descriptor.relativePath); XCTAssertNil(sources[0].descriptor.byteCount)
        let document = try CollectionExchangeExporter.makeDocument(from: snapshot, sources: sources)
        XCTAssertEqual(document.markers.count, 1)
        XCTAssertThrowsError(try CollectionExchangeSources.make(snapshot: snapshot, available: [], isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
    }
}

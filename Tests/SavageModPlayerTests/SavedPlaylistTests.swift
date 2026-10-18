import XCTest
@testable import SavageModPlayerCore

final class SavedPlaylistTests: XCTestCase {
    func testLibraryReferencesHaveRelativeIdentityAndRejectTraversal() throws {
        let path = "Archive #1/ä %20/same.mod"
        let source = try XCTUnwrap(PlaylistTrackSource(libraryRelativePath: path))
        XCTAssertEqual(source.libraryRelativePath, path)
        XCTAssertFalse(source.location.isFileURL)
        let data = try JSONEncoder().encode(source)
        XCTAssertEqual(try JSONDecoder().decode(PlaylistTrackSource.self, from: data), source)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("file:"))
        for invalid in ["", "/a.mod", "../a.mod", "a/../b.mod", "a//b.mod", "a\\b.mod", "a/./b.mod", "a\0.mod"] {
            XCTAssertNil(PlaylistTrackSource(libraryRelativePath: invalid), invalid)
        }
    }
    private var directory: URL!
    private var store: SavedPlaylistStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedPlaylistTests-\(UUID().uuidString)")
        store = SavedPlaylistStore(fileURL: directory.appendingPathComponent("state/playlists.json"))
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func track(_ path: String) -> PlaylistTrackReference {
        PlaylistTrackReference(source: PlaylistTrackSource(location: directory.appendingPathComponent(path)),
                               displayName: URL(fileURLWithPath: path).lastPathComponent)
    }

    func testSameFilenameInDifferentFoldersHasDistinctIdentity() {
        XCTAssertNotEqual(track("a/song.mod").id, track("b/song.mod").id)
        XCTAssertEqual(track("a/../b/song.mod").id, track("b/song.mod").id)
        let archive = PlaylistTrackSource(location: directory.appendingPathComponent("collection.zip"))
        XCTAssertNotEqual(archive.appendingArchiveMember("a/song.mod").id,
                          archive.appendingArchiveMember("b/song.mod").id)
        XCTAssertNotEqual(archive.appendingArchiveMember("a/b.mod").id,
                          archive.appendingArchiveMember("a").appendingArchiveMember("b.mod").id)
    }

    func testStoreSurvivesRestartAndEditing() throws {
        XCTAssertEqual(try store.load(), SavedPlaylistDocument())
        var document = SavedPlaylistDocument()
        let first = track("a/first.mod"), second = track("b/second.xm")
        document.playlists = [SavedPlaylist(name: "  Test  ", tracks: [second, first])]
        document.favoriteIDs = [first.id]
        try store.save(document)
        let reopened = SavedPlaylistStore(fileURL: store.fileURL)
        XCTAssertEqual(try reopened.load(), document)
        document.playlists[0].name = "Renamed"
        document.playlists[0].tracks.removeFirst()
        try reopened.save(document)
        XCTAssertEqual(try store.load(), document)
        document.playlists.removeAll()
        try store.save(document)
        XCTAssertTrue(try store.load().playlists.isEmpty)
        XCTAssertEqual(try store.load().favoriteIDs, [first.id])
    }

    func testInvalidSaveDoesNotReplaceGoodData() throws {
        var document = SavedPlaylistDocument()
        document.playlists = [SavedPlaylist(name: "Kept", tracks: [track("song.mod")])]
        try store.save(document)
        let original = try Data(contentsOf: store.fileURL)
        document.playlists[0].name = " \n "
        XCTAssertThrowsError(try store.save(document))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    func testFutureAndCorruptDocumentsAreRejectedWithoutReplacement() throws {
        try store.save(SavedPlaylistDocument())
        var future = SavedPlaylistDocument(); future.formatVersion = 2
        let data = try JSONEncoder().encode(future)
        try data.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.fileURL), data)
        try Data("broken".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: store.fileURL, encoding: .utf8), "broken")
    }

    func testDuplicateAndUnsafeReferencesAreRejected() throws {
        var document = SavedPlaylistDocument()
        let item = track("song.mod")
        document.playlists = [SavedPlaylist(name: "Bad", tracks: [item, item])]
        XCTAssertThrowsError(try store.save(document))
        for member in ["../song.mod", "/song.mod", "a//song.mod", "a\\song.mod"] {
            let unsafe = PlaylistTrackReference(
                source: PlaylistTrackSource(location: directory.appendingPathComponent("a.zip"),
                                            archiveMembers: [member]), displayName: "song.mod")
            document.playlists[0].tracks = [unsafe]
            XCTAssertThrowsError(try store.save(document))
        }
    }

    func testFavoriteMigrationOnlySelectsUnambiguousNamesAndRunsOnce() {
        var document = SavedPlaylistDocument()
        let a = track("a/song.mod"), b = track("b/song.mod"), unique = track("unique.xm")
        XCTAssertEqual(document.migrateFavorites(names: ["song.mod", "unique.xm"], among: [a, b, unique]),
                       ["song.mod"])
        XCTAssertEqual(document.favoriteIDs, [unique.id])
        document.migrateFavorites(names: ["song.mod"], among: [a])
        XCTAssertEqual(document.favoriteIDs, [unique.id])
    }

    func testFavoriteMigrationKeepsUnseenNamesAndDoesNotRestoreRemovedStars() {
        var document = SavedPlaylistDocument()
        let first = track("first.mod"), later = track("later.it")
        document.migrateFavorites(names: ["first.mod", "later.it"], among: [first])
        XCTAssertEqual(document.favoriteIDs, [first.id])
        XCTAssertFalse(document.favoritesMigrationCompleted)
        document.favoriteIDs.remove(first.id)
        document.migrateFavorites(names: ["first.mod", "later.it"], among: [first, later])
        XCTAssertEqual(document.favoriteIDs, [later.id])
        XCTAssertTrue(document.favoritesMigrationCompleted)
    }

    func testSourceIdentityCanonicalizesSymbolicLinkAliases() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("song.mod")
        try Data([1]).write(to: original)
        let alias = directory.appendingPathComponent("alias.mod")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        XCTAssertEqual(PlaylistTrackSource(location: alias).id, PlaylistTrackSource(location: original).id)
    }

    func testResolverPreservesOrderAndReportsMissingWithoutRemovingReferences() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = track("first.mod"), second = track("second.xm"), missing = track("missing.it")
        try Data([1]).write(to: first.source.location)
        try Data([2]).write(to: second.source.location)
        let tracks = [second, missing, first]
        let result = SavedPlaylistResolver.resolve(tracks, tempDir: directory.appendingPathComponent("scan"))
        XCTAssertEqual(result.entries.map(\.reference), [second, first])
        XCTAssertEqual(result.missing, [missing])
        XCTAssertEqual(tracks.count, 3)
    }
}

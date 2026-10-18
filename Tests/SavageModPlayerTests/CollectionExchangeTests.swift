import XCTest
@testable import SavageModPlayerCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class CollectionExchangeTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_792_272_000)
    private func track(_ path: String, library: Bool = false, hash: String? = nil, bytes: Int64? = nil) -> CollectionExchangeLocalTrack {
        let source = library ? PlaylistTrackSource(libraryRelativePath: path)!
            : PlaylistTrackSource(location: URL(fileURLWithPath: "/private/synthetic/Music/" + path))
        let name = path.split(separator: "/").last.map(String.init)!
        return .init(reference: .init(source: source, displayName: name),
                     descriptor: .init(fileName: name, relativePath: path, byteCount: bytes, sha256: hash))
    }
    private func fixture() throws -> (CollectionExchangeSnapshot, [CollectionExchangeLocalTrack], CollectionExchangeDocument) {
        let sources = [track("Ä/first.mod"), track("B/second.it")]
        var local = CollectionExchangeSnapshot(playbackDefaults: .init(palClock: false, stereoSeparation: 0.4,
                                                                       useInterpolation: false, ledFilterActive: true))
        local.playlists.playlists = [SavedPlaylist(name: "Reihenfolge", tracks: sources.reversed().map(\.reference))]
        local.playlists.favoriteIDs = [sources[0].reference.id]
        local.markers.markers = [SongMarker(sourceID: sources[1].reference.id, name: "Refrain",
                                          address: .init(position: 3, row: 17), createdAt: date)]
        local.trackSettings.tracks[sources[0].reference.id] = .init(palClock: false, useInterpolation: false)
        local.trackSettings.tracks[sources[1].reference.id] = .init(stereoSeparation: 0.2, ledFilterActive: true)
        return (local, sources, try CollectionExchangeExporter.makeDocument(from: local, sources: sources, createdAt: date))
    }
    private func mapping(_ document: CollectionExchangeDocument, to sources: [CollectionExchangeLocalTrack]) -> [UUID: PlaylistTrackReference] {
        Dictionary(uniqueKeysWithValues: document.tracks.map { incoming in
            (incoming.id, sources.first { $0.descriptor.fileName == incoming.descriptor.fileName }!.reference)
        })
    }

    func testMacToPhoneToMacPreservesMetadataAndOrderWithoutLocalPaths() throws {
        let (mac, _, exported) = try fixture()
        let data = try CollectionExchangeCodec.encode(exported)
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["/private/synthetic", "file://", "source-v1:", "library-v1:", "canonicalLocation"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        let document = try CollectionExchangeCodec.decode(data)
        let phoneTracks = [track("Ä/first.mod", library: true), track("B/second.it", library: true)]
        let empty = CollectionExchangeSnapshot()
        let phone = try CollectionExchangeImporter.preview(document, into: empty, mapping: mapping(document, to: phoneTracks)).result(ifUnchanged: empty)
        XCTAssertEqual(phone.playlists.playlists[0].tracks.map(\.displayName), ["second.it", "first.mod"])
        XCTAssertEqual(phone.markers.markers[0].sourceID, phoneTracks[1].reference.id)
        XCTAssertEqual(phone.playlists.favoriteIDs, [phoneTracks[0].reference.id])
        XCTAssertEqual(phone.trackSettings.tracks[phoneTracks[0].reference.id]?.palClock, false)
        XCTAssertNil(phone.trackSettings.tracks[phoneTracks[0].reference.id]?.stereoSeparation)
        let back = try CollectionExchangeCodec.decode(CollectionExchangeCodec.encode(CollectionExchangeExporter.makeDocument(from: phone, sources: phoneTracks)))
        let macTracks = [track("Ä/first.mod"), track("B/second.it")]
        let restored = try CollectionExchangeImporter.preview(back, into: empty, mapping: mapping(back, to: macTracks)).result(ifUnchanged: empty)
        XCTAssertEqual(restored, mac)
        XCTAssertEqual(try CollectionExchangeImporter.preview(document, into: phone, mapping: mapping(document, to: phoneTracks)).result(ifUnchanged: phone), phone)
    }

    func testRoundTripAcceptsDataSliceAndCanonicalizesUnorderedFields() throws {
        let (_, _, document) = try fixture()
        let first = try CollectionExchangeCodec.encode(document)
        var reversed = document
        reversed.tracks.reverse(); reversed.favoriteTrackIDs.reverse(); reversed.trackSettings.reverse()
        XCTAssertEqual(try CollectionExchangeCodec.encode(reversed), first)
        let prefixed = Data([0, 1, 2]) + first
        XCTAssertEqual(try CollectionExchangeCodec.encode(CollectionExchangeCodec.decode(prefixed.dropFirst(3))), first)
    }

    func testExportRequiresExplicitPortableMappingForEveryReferencedSource() throws {
        let (snapshot, sources, _) = try fixture()
        XCTAssertThrowsError(try CollectionExchangeExporter.makeDocument(from: snapshot, sources: [sources[0]])) {
            XCTAssertEqual($0 as? CollectionExchangeError, .unmappedSources)
        }
        XCTAssertThrowsError(try CollectionExchangeExporter.makeDocument(from: snapshot, sources: sources + [sources[0]]))
        var unsafe = sources; unsafe[0].descriptor.relativePath = "/private/Music/first.mod"
        XCTAssertThrowsError(try CollectionExchangeExporter.makeDocument(from: snapshot, sources: unsafe))
    }

    func testUnsafePathsAndInvalidFingerprintsAreRejectedInBothDirections() throws {
        let (_, _, document) = try fixture()
        for path in ["/absolute.mod", "../first.mod", "a/../first.mod", "a//first.mod", "./first.mod",
                     "C:/first.mod", "file:///first.mod", "a\\first.mod", "~/first.mod", "a/\0first.mod"] {
            var bad = document; bad.tracks[0].descriptor.relativePath = path
            XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad), path)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            XCTAssertThrowsError(try CollectionExchangeCodec.decode(encoder.encode(bad)), path)
        }
        for name in ["../first.mod", "/first.mod", "a\\b.mod", "", "a\n.mod", "C:first.mod"] {
            var bad = document; bad.tracks[0].descriptor.fileName = name
            XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad), name)
        }
        var bad = document; bad.tracks[0].descriptor.sha256 = String(repeating: "g", count: 64)
        XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad))
        bad = document; bad.tracks[0].descriptor.byteCount = -1
        XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad))
        bad = document; bad.tracks[0].descriptor.archiveMembers = ["../../first.mod"]
        XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad))
        bad = document; bad.tracks[0].descriptor.fileName = "other.mod"
        XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad))
    }

    func testNestedArchiveReferenceDoesNotExposeOuterLocation() throws {
        let outer = PlaylistTrackSource(location: URL(fileURLWithPath: "/private/synthetic/outer.zip"))
        let source = outer.appendingArchiveMember("packs/inner.zip").appendingArchiveMember("songs/ü.mod")
        let local = CollectionExchangeLocalTrack(reference: .init(source: source, displayName: "ü.mod"),
            descriptor: .init(fileName: "ü.mod", relativePath: "packs/outer.zip", archiveMembers: ["packs/inner.zip", "songs/ü.mod"]))
        var snapshot = CollectionExchangeSnapshot(); snapshot.playlists.favoriteIDs.insert(source.id)
        let document = try CollectionExchangeExporter.makeDocument(from: snapshot, sources: [local])
        XCTAssertEqual(try CollectionExchangeCodec.decode(CollectionExchangeCodec.encode(document)).tracks[0].descriptor, local.descriptor)
        XCTAssertEqual(try CollectionExchangeMatcher.match(document, against: [local])[document.tracks[0].id], .matched(source.id))
    }

    func testDuplicateIDsDanglingReferencesAndFutureVersionsFail() throws {
        let (_, _, document) = try fixture()
        var invalids: [CollectionExchangeDocument] = []
        var bad = document; bad.tracks.append(bad.tracks[0]); invalids.append(bad)
        bad = document; bad.playlists.append(bad.playlists[0]); invalids.append(bad)
        bad = document; bad.markers.append(bad.markers[0]); invalids.append(bad)
        bad = document; bad.trackSettings.append(bad.trackSettings[0]); invalids.append(bad)
        bad = document; bad.favoriteTrackIDs.append(bad.favoriteTrackIDs[0]); invalids.append(bad)
        bad = document; bad.playlists[0].trackIDs.append(UUID()); invalids.append(bad)
        bad = document; bad.playlists[0].trackIDs.append(bad.playlists[0].trackIDs[0]); invalids.append(bad)
        bad = document; bad.favoriteTrackIDs = [UUID()]; invalids.append(bad)
        bad = document; bad.markers[0].trackID = UUID(); invalids.append(bad)
        bad = document; bad.markers[0].address.row = -1; invalids.append(bad)
        bad = document; bad.trackSettings[0].trackID = UUID(); invalids.append(bad)
        bad = document; bad.trackSettings[0].overrides = .init(); invalids.append(bad)
        bad = document; bad.trackSettings[0].overrides.stereoSeparation = 1.01; invalids.append(bad)
        bad = document; bad.playbackDefaults?.stereoSeparation = -.infinity; invalids.append(bad)
        bad = document; bad.format = "other"; invalids.append(bad)
        for invalid in invalids { XCTAssertThrowsError(try CollectionExchangeCodec.encode(invalid)) }
        bad = document; bad.formatVersion = 2
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try CollectionExchangeCodec.decode(encoder.encode(bad))) {
            XCTAssertEqual($0 as? CollectionExchangeError, .unsupportedVersion(2))
        }
        for text in ["{}", "{", "[]", "null", "not json"] { XCTAssertThrowsError(try CollectionExchangeCodec.decode(Data(text.utf8))) }
    }

    func testLimitsCoverBytesStringsTracksMarkersAndTotalPlaylistReferences() throws {
        XCTAssertThrowsError(try CollectionExchangeCodec.decode(Data(repeating: 32, count: CollectionExchangeCodec.maximumBytes + 1))) {
            XCTAssertEqual($0 as? CollectionExchangeError, .oversized)
        }
        let (_, _, document) = try fixture()
        var bad = document; bad.tracks[0].descriptor.fileName = String(repeating: "x", count: 1_025)
        XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad))
        bad = document; bad.playlists[0].name = String(repeating: "x", count: 201)
        XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad))
        bad = document; bad.tracks = (0...CollectionExchangeCodec.maximumTracks).map { _ in ExchangeTrack(descriptor: .init(fileName: "a.mod")) }
        XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad))
        var large = CollectionExchangeDocument(createdAt: date)
        large.tracks = (0..<20_000).map { _ in ExchangeTrack(descriptor: .init(fileName: "a.mod")) }
        large.playlists = (0..<5).map { ExchangePlaylist(id: UUID(), name: "\($0)", trackIDs: large.tracks.map(\.id)) }
        XCTAssertNoThrow(try CollectionExchangeCodec.encode(large))
        large.playlists.append(ExchangePlaylist(id: UUID(), name: "Overflow", trackIDs: [large.tracks[0].id]))
        XCTAssertThrowsError(try CollectionExchangeCodec.encode(large))
        bad = document; bad.markers = (0...CollectionExchangeCodec.maximumMarkers).map { _ in
            ExchangeSongMarker(id: UUID(), trackID: document.tracks[0].id, name: "m", address: .init(position: 0, row: 0), createdAt: date)
        }
        XCTAssertThrowsError(try CollectionExchangeCodec.encode(bad))
    }

    func testFileReaderRejectsNonFilesAndOversizedSparseFileWithoutTouchingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CollectionExchange-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try CollectionExchangeCodec.load(from: root))
        XCTAssertThrowsError(try CollectionExchangeCodec.load(from: URL(string: "https://example.invalid/collection")!))
        let fifo = root.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            do { _ = try CollectionExchangeCodec.load(from: fifo); XCTFail("Named pipe was accepted") }
            catch { }
            done.signal()
        }
        XCTAssertEqual(done.wait(timeout: .now() + 3), .success)
        let file = root.appendingPathComponent("large")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file); try handle.truncate(atOffset: UInt64(CollectionExchangeCodec.maximumBytes + 1)); try handle.close()
        XCTAssertThrowsError(try CollectionExchangeCodec.load(from: file)) { XCTAssertEqual($0 as? CollectionExchangeError, .oversized) }
        XCTAssertEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, CollectionExchangeCodec.maximumBytes + 1)
    }

    func testMatchingNeverGuessesBetweenNamesOrContradictoryHashes() throws {
        let a = track("A/same.mod", bytes: 10), b = track("B/same.mod", bytes: 10)
        var document = CollectionExchangeDocument(createdAt: date)
        let incoming = ExchangeTrack(descriptor: .init(fileName: "same.mod"))
        document.tracks = [incoming]
        XCTAssertEqual(try CollectionExchangeMatcher.match(document, against: [a, b])[incoming.id], .ambiguous([a.reference.id, b.reference.id].sorted(), totalCount: 2))
        document.tracks[0].descriptor.relativePath = "B/same.mod"
        XCTAssertEqual(try CollectionExchangeMatcher.match(document, against: [a, b])[incoming.id], .matched(b.reference.id))
        document.tracks[0].descriptor.sha256 = String(repeating: "a", count: 64)
        XCTAssertEqual(try CollectionExchangeMatcher.match(document, against: [a, b])[incoming.id], .missing)
        var hashed = b; hashed.descriptor.sha256 = document.tracks[0].descriptor.sha256
        XCTAssertEqual(try CollectionExchangeMatcher.match(document, against: [a, hashed])[incoming.id], .matched(b.reference.id))
        var duplicate = a; duplicate.descriptor.sha256 = hashed.descriptor.sha256
        if case .ambiguous(let ids, let count) = try CollectionExchangeMatcher.match(document, against: [duplicate, hashed])[incoming.id] {
            XCTAssertEqual(ids.count, 2)
            XCTAssertEqual(count, 2)
        } else { XCTFail("Identical copies need an explicit location choice") }
        document.tracks[0].descriptor.byteCount = 11
        XCTAssertEqual(try CollectionExchangeMatcher.match(document, against: [hashed])[incoming.id], .missing)
    }

    func testLargeNameCollisionGroupsKeepSuggestionsBounded() throws {
        let sources = (0..<20_000).map { track("Folder-\($0)/same.mod", library: true) }
        var document = CollectionExchangeDocument(createdAt: date)
        document.tracks = (0..<20_000).map { _ in ExchangeTrack(descriptor: .init(fileName: "same.mod")) }
        let started = Date()
        let matches = try CollectionExchangeMatcher.match(document, against: sources)
        XCTAssertEqual(matches.count, 20_000)
        for value in matches.values {
            guard case .ambiguous(let suggestions, let count) = value else { return XCTFail("Ambiguity was lost") }
            XCTAssertEqual(count, 20_000)
            XCTAssertEqual(suggestions.count, CollectionExchangeMatcher.maximumSuggestions)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testUnresolvedAndSkippedTracksRequireExplicitNonConflictingChoices() throws {
        let (_, sources, document) = try fixture()
        let local = CollectionExchangeSnapshot()
        let preview = try CollectionExchangeImporter.preview(document, into: local, mapping: [:])
        XCTAssertEqual(preview.unresolvedTrackIDs.count, 2); XCTAssertFalse(preview.isReady)
        XCTAssertThrowsError(try preview.result(ifUnchanged: local))
        let first = document.tracks.first { $0.descriptor.fileName == sources[0].descriptor.fileName }!
        let other = document.tracks.first { $0.id != first.id }!
        let explicit = [first.id: sources[0].reference]
        let skipped = try CollectionExchangeImporter.preview(document, into: local, mapping: explicit, skippedTrackIDs: [other.id])
        XCTAssertTrue(skipped.isReady)
        let result = try skipped.result(ifUnchanged: local)
        XCTAssertEqual(result.playlists.playlists[0].tracks.count, 1)
        XCTAssertTrue(result.markers.markers.isEmpty)
        XCTAssertEqual(result.trackSettings.tracks.count, 1)
        XCTAssertThrowsError(try CollectionExchangeImporter.preview(document, into: local, mapping: explicit, skippedTrackIDs: [first.id]))
        XCTAssertThrowsError(try CollectionExchangeImporter.preview(document, into: local, mapping: [UUID(): sources[0].reference]))
        XCTAssertThrowsError(try CollectionExchangeImporter.preview(document, into: local,
            mapping: Dictionary(uniqueKeysWithValues: document.tracks.map { ($0.id, sources[0].reference) })))
    }

    func testConflictsKeepReplaceOrCopyOnlyAfterDecisionsAndWithoutChangingBase() throws {
        let (base, sources, document) = try fixture()
        var incoming = document
        incoming.playlists[0].trackIDs.reverse()
        incoming.markers[0].address.row += 1
        incoming.trackSettings[0].overrides.ledFilterActive = false
        incoming.playbackDefaults?.stereoSeparation = 0.9
        let map = mapping(incoming, to: sources)
        let undecided = try CollectionExchangeImporter.preview(incoming, into: base, mapping: map)
        XCTAssertEqual(undecided.conflicts.count, 4); XCTAssertFalse(undecided.isReady)
        XCTAssertThrowsError(try undecided.result(ifUnchanged: base))
        let keep = Dictionary(uniqueKeysWithValues: undecided.conflicts.map { ($0.id, CollectionExchangeResolution.keepLocal) })
        XCTAssertEqual(try CollectionExchangeImporter.preview(incoming, into: base, mapping: map, resolutions: keep).result(ifUnchanged: base), base)
        let replace = Dictionary(uniqueKeysWithValues: undecided.conflicts.map { ($0.id, CollectionExchangeResolution.useIncoming) })
        let replaced = try CollectionExchangeImporter.preview(incoming, into: base, mapping: map, resolutions: replace).result(ifUnchanged: base)
        XCTAssertEqual(replaced.playlists.playlists[0].tracks.map(\.id), base.playlists.playlists[0].tracks.reversed().map(\.id))
        XCTAssertEqual(replaced.markers.markers[0].address.row, 18)
        XCTAssertEqual(replaced.playbackDefaults?.stereoSeparation, 0.9)
        var copies = keep
        copies[.playlist(incoming.playlists[0].id)] = .keepBoth
        copies[.marker(incoming.markers[0].id)] = .keepBoth
        let copied = try CollectionExchangeImporter.preview(incoming, into: base, mapping: map, resolutions: copies).result(ifUnchanged: base)
        XCTAssertEqual(copied.playlists.playlists.count, 2); XCTAssertEqual(copied.markers.markers.count, 2)
        XCTAssertEqual(copied.playlists.playlists[0], base.playlists.playlists[0])
        XCTAssertEqual(copied.playlists.playlists[1].name, "Reihenfolge (2)")
        XCTAssertNotEqual(copied.markers.markers[0].id, copied.markers.markers[1].id)
    }

    func testNameCollisionCannotReplaceAnUnrelatedPlaylist() throws {
        let (base, sources, document) = try fixture()
        var incoming = document
        incoming.playlists[0].id = UUID()
        let map = mapping(incoming, to: sources)
        let key = CollectionExchangeConflictID.playlistName(incoming.playlists[0].id)
        let preview = try CollectionExchangeImporter.preview(incoming, into: base, mapping: map)
        XCTAssertEqual(preview.conflicts.map(\.id), [key])
        XCTAssertThrowsError(try CollectionExchangeImporter.preview(incoming, into: base, mapping: map, resolutions: [key: .useIncoming]))
        let copied = try CollectionExchangeImporter.preview(incoming, into: base, mapping: map, resolutions: [key: .keepBoth]).result(ifUnchanged: base)
        XCTAssertEqual(copied.playlists.playlists[0], base.playlists.playlists[0])
        XCTAssertEqual(copied.playlists.playlists[1].id, incoming.playlists[0].id)
        XCTAssertEqual(copied.playlists.playlists[1].name, "Reihenfolge (2)")
    }

    func testPreviewRejectsAnyInterveningLocalChangeAndStaleDecisions() throws {
        let (_, sources, document) = try fixture()
        let base = CollectionExchangeSnapshot()
        let preview = try CollectionExchangeImporter.preview(document, into: base, mapping: mapping(document, to: sources))
        var changed = base; changed.playlists.favoritesMigrationCompleted = true
        XCTAssertThrowsError(try preview.result(ifUnchanged: changed)) { XCTAssertEqual($0 as? CollectionExchangeError, .stalePreview) }
        XCTAssertThrowsError(try CollectionExchangeImporter.preview(document, into: base, mapping: mapping(document, to: sources), resolutions: [.marker(UUID()): .keepLocal]))
    }

    func testMergeAddsFavoritesWithoutRemovingLocalDataOrMigrationState() throws {
        let (_, sources, document) = try fixture()
        var base = CollectionExchangeSnapshot()
        base.playlists.favoriteIDs = ["unavailable-local-id"]
        base.playlists.favoritesMigrationCompleted = true
        base.playlists.pendingLegacyFavoriteNames = ["legacy"]
        let result = try CollectionExchangeImporter.preview(document, into: base, mapping: mapping(document, to: sources)).result(ifUnchanged: base)
        XCTAssertTrue(result.playlists.favoriteIDs.contains("unavailable-local-id"))
        XCTAssertEqual(result.playlists.favoriteIDs.count, 2)
        XCTAssertTrue(result.playlists.favoritesMigrationCompleted)
        XCTAssertEqual(result.playlists.pendingLegacyFavoriteNames, ["legacy"])
    }

    func testInvalidLocalStateAndInvalidConflictActionsCannotProduceResult() throws {
        let (base, sources, document) = try fixture()
        var invalid = base; invalid.markers.formatVersion = 3
        XCTAssertThrowsError(try CollectionExchangeImporter.preview(document, into: invalid, mapping: mapping(document, to: sources)))
        var incoming = document; incoming.playbackDefaults?.stereoSeparation = 0.9
        XCTAssertThrowsError(try CollectionExchangeImporter.preview(incoming, into: base, mapping: mapping(document, to: sources), resolutions: [.playbackDefaults: .keepBoth]))
        var full = CollectionExchangeSnapshot()
        full.playlists.playlists = (0..<1_000).map { SavedPlaylist(name: "Local \($0)", tracks: []) }
        XCTAssertThrowsError(try CollectionExchangeImporter.preview(document, into: full, mapping: mapping(document, to: sources)))
    }

    func testSettingsOnlyAndEmptyDocumentsAreValid() throws {
        var snapshot = CollectionExchangeSnapshot(playbackDefaults: .init(useInterpolation: false))
        let document = try CollectionExchangeExporter.makeDocument(from: snapshot, sources: [])
        XCTAssertTrue(document.tracks.isEmpty)
        let empty = CollectionExchangeSnapshot()
        XCTAssertEqual(try CollectionExchangeImporter.preview(document, into: empty, mapping: [:]).result(ifUnchanged: empty), snapshot)
        snapshot.playbackDefaults = nil
        XCTAssertNoThrow(try CollectionExchangeExporter.makeDocument(from: snapshot, sources: []))
    }
}

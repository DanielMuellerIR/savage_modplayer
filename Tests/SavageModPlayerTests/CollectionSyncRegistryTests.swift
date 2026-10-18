import XCTest

@testable import SavageModPlayerCore

final class CollectionSyncRegistryTests: XCTestCase {
    func testBatchAssignmentHandlesTwentyThousandTracksAndRejectsDuplicateOwnersAtomically() throws {
        let entries = (0..<CollectionExchangeCodec.maximumTracks).map { index in
            (UUID(), PlaylistTrackReference(source: PlaylistTrackSource(libraryRelativePath: "Music/song-\(index).mod")!, displayName: "song-\(index).mod"))
        }
        let mapping = Dictionary(uniqueKeysWithValues: entries)
        let initial = registry()
        let start = Date()
        let assigned = try initial.assigning(mapping, account: account)
        XCTAssertEqual(assigned.bindings.count, CollectionExchangeCodec.maximumTracks)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        XCTAssertEqual(try assigned.assigning(mapping, account: account), assigned)
        let duplicate = entries[0].1
        XCTAssertThrowsError(try assigned.assigning([UUID(): duplicate], account: account)) {
            XCTAssertEqual($0 as? CollectionExchangeError, .invalidMapping)
        }
        XCTAssertTrue(initial.bindings.isEmpty)
        XCTAssertEqual(assigned.bindings.count, CollectionExchangeCodec.maximumTracks)
    }
    private let account = CollectionSyncAccountToken(
        scope: String(repeating: "a", count: 64), epoch: UUID())
    private let collection = UUID(), generation = UUID()
    private func reference(_ folder: String, name: String = "song.mod") -> PlaylistTrackReference {
        .init(
            source: .init(location: URL(fileURLWithPath: "/synthetic/\(folder)/song.mod")),
            displayName: name)
    }
    private func fixture() -> (CollectionExchangeSnapshot, [CollectionExchangeLocalTrack]) {
        let a = reference("A")
        let b = reference("B")
        var local = CollectionExchangeSnapshot()
        local.playlists.favoriteIDs = [a.id, b.id]
        local.playlists.playlists = [.init(name: "Order", tracks: [b, a])]
        return (
            local,
            [
                .init(
                    reference: a,
                    descriptor: .init(fileName: "song.mod", relativePath: "A/song.mod")),
                .init(
                    reference: b,
                    descriptor: .init(fileName: "song.mod", relativePath: "B/song.mod")),
            ]
        )
    }
    private func registry(_ bindings: [CollectionSyncTrackBinding] = [])
        -> CollectionSyncTrackRegistry
    {
        .init(
            account: account, collectionID: collection, generation: generation, bindings: bindings)
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SyncRegistry-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testGlobalIDsSurviveRepeatedExportDiskRestartAndSameNamedTracks() throws {
        let (local, sources) = fixture()
        let root = try directory()
        let first = try registry().export(from: local, sources: sources, account: account)
        let file = root.appendingPathComponent("local-tracks.json")
        try CollectionSyncRegistryCodec.encode(first.registry).write(to: file, options: .atomic)
        let restored = try CollectionSyncRegistryCodec.load(from: file)
        let second = try restored.export(from: local, sources: sources, account: account)
        XCTAssertEqual(first.document.tracks, second.document.tracks)
        XCTAssertEqual(first.document.playlists, second.document.playlists)
        XCTAssertEqual(Set(second.document.tracks.map(\.id)).count, 2)
        let data = try CollectionExchangeCodec.encode(second.document)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("source-v1:"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("file://"))
    }

    func testManualExportsStillReceiveFreshIDsAndDuplicateInjectedIDsAreRejected() throws {
        let (local, sources) = fixture()
        let a = try CollectionExchangeExporter.makeDocument(from: local, sources: sources)
        let b = try CollectionExchangeExporter.makeDocument(from: local, sources: sources)
        XCTAssertNotEqual(Set(a.tracks.map(\.id)), Set(b.tracks.map(\.id)))
        let same = UUID()
        XCTAssertThrowsError(
            try CollectionExchangeExporter.makeDocument(
                from: local, sources: sources, trackID: { _ in same }))
    }

    func testExplicitAssignmentsAreOneToOneAndDoNotSilentlyRetargetOldMetadata() throws {
        let id = UUID()
        let a = reference("A")
        let b = reference("B")
        let assigned = try registry().assigning(id, to: a, account: account)
        XCTAssertThrowsError(try assigned.assigning(UUID(), to: a, account: account))
        XCTAssertThrowsError(try assigned.assigning(id, to: b, account: account))
        let renamed = try assigned.assigning(
            id, to: reference("A", name: "Updated label"), account: account)
        XCTAssertEqual(renamed.bindings[0].id, id)
        XCTAssertEqual(renamed.bindings[0].reference.displayName, "Updated label")
        XCTAssertEqual(assigned.bindings[0].reference.displayName, "song.mod")
    }

    func testMissingMusicKeepsConfirmedMappingAndUnusedBindingsAreFiltered() throws {
        let id = UUID()
        let unused = UUID()
        let a = reference("A")
        let registry = registry([
            .init(id: id, reference: a), .init(id: unused, reference: reference("unused")),
        ])
        let snapshot = CollectionSyncSnapshot(
            collectionID: collection, generation: generation,
            cells: [
                .init(.track(id), .track(.init(fileName: "song.mod"))),
                .init(.favorite(id), .flag(true)),
            ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.source.location.path))
        let mapping = try registry.mapping(for: snapshot, available: [], account: account)
        XCTAssertEqual(Set(mapping.keys), [id])
        XCTAssertEqual(mapping[id], a)
        let local = CollectionExchangeSnapshot()
        let projection = try CollectionSyncProjection(
            snapshot: snapshot, into: local, mapping: mapping, collectionID: collection,
            generation: generation)
        XCTAssertEqual(
            try projection.result(ifUnchanged: local, mapping: mapping).playlists.favoriteIDs,
            [a.id])
    }

    func testFreshCatalogLabelsAreUsedWithoutChangingIdentity() throws {
        let id = UUID()
        let original = reference("A")
        let updated = reference("A", name: "Catalog label")
        let registry = registry([.init(id: id, reference: original)])
        let snapshot = CollectionSyncSnapshot(
            collectionID: collection, generation: generation,
            cells: [.init(.track(id), .track(.init(fileName: "song.mod")))])
        let mapping = try registry.mapping(for: snapshot, available: [updated], account: account)
        XCTAssertEqual(mapping[id]?.displayName, "Catalog label")
        XCTAssertEqual(registry.bindings[0].reference, original)
        XCTAssertThrowsError(
            try registry.mapping(for: snapshot, available: [original, updated], account: account))
    }

    func testAccountCollectionAndGenerationCannotReuseAnotherRegistry() throws {
        let (local, sources) = fixture()
        let registry = registry()
        let other = CollectionSyncAccountToken(scope: account.scope, epoch: UUID())
        XCTAssertThrowsError(try registry.export(from: local, sources: sources, account: other)) {
            XCTAssertEqual($0 as? CollectionSyncError, .staleAccount)
        }
        let foreign = CollectionSyncSnapshot(collectionID: UUID(), generation: generation)
        XCTAssertThrowsError(try registry.mapping(for: foreign, available: [], account: account)) {
            XCTAssertEqual($0 as? CollectionSyncError, .mismatchedCollection)
        }
        let next = CollectionSyncSnapshot(collectionID: collection, generation: UUID())
        XCTAssertThrowsError(try registry.mapping(for: next, available: [], account: account)) {
            XCTAssertEqual($0 as? CollectionSyncError, .staleGeneration)
        }
    }

    func testFailedExportCorruptDuplicateFutureOrOversizedRegistryCannotReplaceOriginal() throws {
        let (local, sources) = fixture()
        let original = registry()
        var bad = sources
        bad[1] = .init(reference: bad[1].reference, descriptor: .init(fileName: "../invalid.mod"))
        XCTAssertThrowsError(try original.export(from: local, sources: bad, account: account))
        XCTAssertTrue(original.bindings.isEmpty)
        let duplicate = registry([
            .init(id: UUID(), reference: reference("A")),
            .init(id: UUID(), reference: reference("A")),
        ])
        XCTAssertThrowsError(try CollectionSyncRegistryCodec.encode(duplicate))
        XCTAssertThrowsError(try CollectionSyncRegistryCodec.decode(Data("{broken".utf8)))
        var future = original
        future.schemaVersion = 2
        XCTAssertThrowsError(try CollectionSyncRegistryCodec.decode(JSONEncoder().encode(future))) {
            XCTAssertEqual($0 as? CollectionSyncError, .unsupportedVersion(2))
        }
        XCTAssertThrowsError(
            try CollectionSyncRegistryCodec.decode(
                Data(count: CollectionSyncRegistryCodec.maximumBytes + 1))
        ) { XCTAssertEqual($0 as? CollectionSyncError, .oversized) }
    }

    func testTwentyThousandStableMappingsDoNotGrowOnRepeatedExport() throws {
        let sources = (0..<20_000).map { index -> CollectionExchangeLocalTrack in
            let reference = PlaylistTrackReference(
                source: .init(location: URL(fileURLWithPath: "/synthetic/\(index).mod")),
                displayName: "\(index).mod")
            return .init(reference: reference, descriptor: .init(fileName: "\(index).mod"))
        }
        var local = CollectionExchangeSnapshot()
        local.playlists.favoriteIDs = Set(sources.map { $0.reference.id })
        let first = try registry().export(from: local, sources: sources, account: account)
        let restored = try CollectionSyncRegistryCodec.decode(
            CollectionSyncRegistryCodec.encode(first.registry))
        let second = try restored.export(from: local, sources: sources, account: account)
        XCTAssertEqual(first.registry.bindings.count, 20_000)
        XCTAssertEqual(second.registry.bindings.count, 20_000)
        XCTAssertEqual(first.document.tracks, second.document.tracks)
    }
}

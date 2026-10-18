import XCTest
@testable import SavageModPlayerCore

@MainActor
final class CollectionSyncFoundationTests: XCTestCase {
    func testPortableTransportPublishesAndReadsSnapshotBytesOnIOS() async throws {
        let account = CollectionSyncAccountToken(scope: String(repeating: "a", count: 64), epoch: UUID())
        let track = UUID()
        let snapshot = CollectionSyncSnapshot(collectionID: UUID(), generation: UUID(), cells: [
            .init(.track(track), .track(.init(fileName: "song.mod"))), .init(.favorite(track), .flag(true))])
        let backend = SyncFixtureAssetBackend(scope: account.scope)
        let client = try CollectionSyncTransportClient(backend: backend, account: account,
                                                       collectionID: snapshot.collectionID, generation: snapshot.generation)
        let saved = try await client.save(snapshot, replacing: nil, account: account)
        let fetched = try await client.fetch(account: account)
        XCTAssertEqual(fetched, saved)
        XCTAssertEqual(try fetched.snapshot.exchangeDocument().favoriteTrackIDs, [track])
    }

    func testLocalStateKeepsRelativeIdentityAndOfflineDeletionAcrossRestart() throws {
        let source = try XCTUnwrap(PlaylistTrackSource(libraryRelativePath: "B/song.mod"))
        let reference = PlaylistTrackReference(source: source, displayName: "song.mod")
        let account = CollectionSyncAccountToken(scope: String(repeating: "a", count: 64), epoch: UUID())
        let collection = UUID(), generation = UUID(), track = UUID()
        var document = CollectionExchangeDocument(id: collection)
        document.tracks = [.init(id: track, descriptor: .init(fileName: "song.mod"))]
        document.favoriteTrackIDs = [track]
        let base = try CollectionSyncSnapshot(document: document, collectionID: collection, generation: generation)
        let registry = CollectionSyncTrackRegistry(account: account, collectionID: collection, generation: generation,
                                                   bindings: [.init(id: track, reference: reference)])
        let state = CollectionSyncLocalState(checkpoint: .init(account: account, base: base, local: base), registry: registry)
        let edited = try state.applying([.init(.favorite(track), .deleted)], ifUnchanged: base, account: account)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SyncLocalState-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try CollectionSyncLocalStateCodec.encode(edited).write(to: file, options: .atomic)
        let restarted = try CollectionSyncLocalStateCodec.load(from: file)
        XCTAssertEqual(restarted, edited)
        XCTAssertTrue(try restarted.checkpoint.pendingChanges())
        XCTAssertTrue(try restarted.checkpoint.local.exchangeDocument().favoriteTrackIDs.isEmpty)
        XCTAssertEqual(restarted.registry.bindings.first?.reference.source.libraryRelativePath, "B/song.mod")
    }

    func testRelativeLibraryRegistryKeepsGlobalIDAfterFileReload() throws {
        let source = try XCTUnwrap(PlaylistTrackSource(libraryRelativePath: "A/song.mod"))
        let reference = PlaylistTrackReference(source: source, displayName: "song.mod")
        var local = CollectionExchangeSnapshot()
        local.playlists.favoriteIDs = [reference.id]
        let sources = [
            CollectionExchangeLocalTrack(
                reference: reference,
                descriptor: .init(fileName: "song.mod", relativePath: "A/song.mod"))
        ]
        let account = CollectionSyncAccountToken(
            scope: String(repeating: "a", count: 64), epoch: UUID())
        let registry = CollectionSyncTrackRegistry(
            account: account, collectionID: UUID(), generation: UUID())
        let first = try registry.export(from: local, sources: sources, account: account)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SyncRegistry-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try CollectionSyncRegistryCodec.encode(first.registry).write(to: file, options: .atomic)
        let second = try CollectionSyncRegistryCodec.load(from: file).export(
            from: local, sources: sources, account: account)
        XCTAssertEqual(first.document.tracks.first?.id, second.document.tracks.first?.id)
        XCTAssertEqual(
            second.registry.bindings.first?.reference.source.libraryRelativePath, "A/song.mod")
        XCTAssertFalse(
            String(decoding: try CollectionExchangeCodec.encode(second.document), as: UTF8.self)
                .contains(
                    "savage-library"))
    }
    func testExplicitDeletionProjectionRetainsDeviceOnlyFavorites() throws {
        let (base, track, _) = try fixture()
        let known = PlaylistTrackReference(source: .init(location: URL(fileURLWithPath: "/synthetic/known.mod")), displayName: "known.mod")
        let deviceOnly = PlaylistTrackReference(source: .init(location: URL(fileURLWithPath: "/synthetic/device-only.mod")), displayName: "device-only.mod")
        var remote = base
        remote.cells.removeAll { $0.id == .favorite(track) }; remote.cells.append(.init(.favorite(track), .deleted))
        var local = CollectionExchangeSnapshot(); local.playlists.favoriteIDs = [known.id, deviceOnly.id]
        let mapping = [track: known]
        let plan = try CollectionSyncProjection(snapshot: remote, into: local, mapping: mapping,
                                               collectionID: base.collectionID, generation: base.generation)
        let result = try plan.result(ifUnchanged: local, mapping: mapping)
        XCTAssertEqual(result.playlists.favoriteIDs, [deviceOnly.id])
        XCTAssertEqual(result.markers.markers.first?.sourceID, known.id)
    }
    func testActualMacCheckpointReturnsThroughIOSWithoutDateOrReferenceLoss() async throws {
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let folder = documents.appendingPathComponent("SyncFoundationInterop", isDirectory: true)
        let input = folder.appendingPathComponent("from-mac.json")
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: input.path), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard FileManager.default.fileExists(atPath: input.path) else { throw XCTSkip("Optionaler echter Mac-Core-Checkpoint wurde nicht bereitgestellt.") }
        let checkpoint = try CollectionSyncCodec.loadCheckpoint(from: input)
        XCTAssertTrue(try checkpoint.pendingChanges())
        let document = try checkpoint.local.exchangeDocument()
        let bindings = try document.tracks.map { track -> CollectionSyncTrackBinding in
            let source = try XCTUnwrap(PlaylistTrackSource(libraryRelativePath: "Interop/\(track.id)/\(track.descriptor.fileName)"))
            return .init(id: track.id, reference: .init(source: source, displayName: track.descriptor.fileName))
        }
        let registry = CollectionSyncTrackRegistry(account: checkpoint.account, collectionID: checkpoint.local.collectionID,
                                                   generation: checkpoint.local.generation, bindings: bindings)
        let initial = CollectionSyncLocalState(checkpoint: checkpoint, registry: registry)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncJournalInterop-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let localFile = root.appendingPathComponent("local-state.json")
        try CollectionSyncLocalStateCodec.encode(initial).write(to: localFile, options: .atomic)
        let restarted = try CollectionSyncLocalStateCodec.load(from: localFile)
        var marker = try XCTUnwrap(document.markers.first)
        XCTAssertEqual(marker.createdAt.timeIntervalSinceReferenceDate, 812_345_678.1234567)
        marker.name = "iOS returned"
        let edited = try restarted.applying([.init(.marker(marker.id), .marker(marker))],
                                           ifUnchanged: restarted.checkpoint.local, account: checkpoint.account)
        let asset = CollectionSyncCloudAsset(data: try CollectionSyncCodec.encode(checkpoint.base), changeTag: "ios-fixture-base")
        let backend = SyncFixtureAssetBackend(scope: checkpoint.account.scope, asset: asset)
        let client = try CollectionSyncTransportClient(backend: backend, account: checkpoint.account,
                                                       collectionID: checkpoint.local.collectionID, generation: checkpoint.local.generation)
        let fetched = try await client.fetch(account: checkpoint.account)
        try fetched.validate(completing: checkpoint.account)
        let merged = try CollectionSyncMergePlan(base: checkpoint.base, local: edited.checkpoint.local, remote: fetched.snapshot)
            .result(ifUnchanged: edited.checkpoint.local)
        let local = CollectionExchangeSnapshot()
        let mapping = try registry.mapping(for: merged, available: bindings.map(\.reference), account: checkpoint.account)
        let projection = try CollectionSyncProjection(snapshot: merged, into: local, mapping: mapping,
                                                       collectionID: checkpoint.local.collectionID, generation: checkpoint.local.generation)
        let projected = try projection.result(ifUnchanged: local, mapping: mapping)
        let persistence = try CollectionExchangePersistence(playlistsURL: root.appendingPathComponent("playlists.json"),
                                                            markersURL: root.appendingPathComponent("markers.json"),
                                                            trackSettingsURL: root.appendingPathComponent("settings.json"),
                                                            journalURL: root.appendingPathComponent("journal", isDirectory: true))
        _ = try persistence.commit(.init(playlists: projected.playlists, markers: projected.markers, trackSettings: projected.trackSettings),
                                   replacing: persistence.snapshot(), auxiliaryBefore: Data(), auxiliaryAfter: Data()) {
            XCTAssertTrue($0.isEmpty && $1.isEmpty)
        }
        let saved = try persistence.snapshot().documents
        XCTAssertTrue(saved.playlists.favoriteIDs.isEmpty)
        XCTAssertEqual(saved.markers.markers.first?.name, "iOS returned")
        XCTAssertEqual(saved.markers.markers.first?.createdAt, marker.createdAt)
        XCTAssertEqual(saved.markers.markers.first?.sourceID, mapping[marker.trackID]?.id)
        try CollectionSyncLocalStateCodec.encode(edited).write(to: localFile, options: .atomic)
        let published = try await client.save(merged, replacing: fetched.changeTag, account: checkpoint.account)
        try published.validate(completing: checkpoint.account)
        // Unterbrechung nach Versand, vor Checkpoint-Bestätigung: Die lokale
        // Änderung bleibt beim Neustart sichtbar und wird nicht blind verworfen.
        let pending = try CollectionSyncLocalStateCodec.load(from: localFile)
        XCTAssertTrue(try pending.checkpoint.pendingChanges())
        let portable = try CollectionSyncCodec.encode(published.snapshot)
        XCTAssertFalse(String(decoding: portable, as: UTF8.self).contains("library-v1:"))
        try portable.write(to: folder.appendingPathComponent("to-mac-snapshot.json"), options: .atomic)
        try CollectionSyncCodec.encode(pending.checkpoint).write(to: folder.appendingPathComponent("to-mac.json"), options: .atomic)
    }
    private func fixture() throws -> (CollectionSyncSnapshot, UUID, UUID) {
        let track = UUID(), marker = UUID(), collection = UUID()
        var document = CollectionExchangeDocument(id: collection)
        document.tracks = [.init(id: track, descriptor: .init(fileName: "synthetic.mod", byteCount: 2112))]
        document.favoriteTrackIDs = [track]
        document.markers = [.init(id: marker, trackID: track, name: "Position", address: .init(position: 1, row: 16),
                                 createdAt: Date(timeIntervalSinceReferenceDate: 812_345_678.1234567))]
        return (try .init(document: document, collectionID: collection, generation: UUID()), track, marker)
    }

    func testSharedCheckpointRestartsWithExactDateAndRetainsIndependentRemoteEdit() throws {
        let (base, track, marker) = try fixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncFoundation-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        var local = base, remote = base
        local.cells.removeAll { $0.id == .favorite(track) }; local.cells.append(.init(.favorite(track), .deleted))
        var changed = try XCTUnwrap(base.exchangeDocument().markers.first); changed.address.row = 32
        remote.cells.removeAll { $0.id == .marker(marker) }; remote.cells.append(.init(.marker(marker), .marker(changed)))
        let account = CollectionSyncAccountToken(scope: String(repeating: "a", count: 64), epoch: UUID())
        let checkpoint = CollectionSyncCheckpoint(account: account, base: base, local: local, serverChangeTag: "synthetic-tag")
        let file = root.appendingPathComponent("state.json")
        try CollectionSyncCodec.encode(checkpoint).write(to: file, options: .atomic)
        let restarted = try CollectionSyncCodec.loadCheckpoint(from: file)
        XCTAssertTrue(try restarted.pendingChanges())
        let result = try CollectionSyncMergePlan(base: restarted.base, local: restarted.local, remote: remote).result(ifUnchanged: restarted.local)
        let document = try CollectionSyncCodec.decode(CollectionSyncCodec.encode(result)).exchangeDocument()
        XCTAssertTrue(document.favoriteTrackIDs.isEmpty); XCTAssertEqual(document.markers.first?.address.row, 32)
        XCTAssertEqual(document.markers.first?.createdAt, changed.createdAt)
    }

    func testOldAccountCompletionAndMissingMetadataFailWithoutClearingCollection() throws {
        let (base, track, _) = try fixture()
        let token = CollectionSyncAccountToken(scope: String(repeating: "a", count: 64), epoch: UUID())
        let checkpoint = CollectionSyncCheckpoint(account: token, base: base, local: base)
        let obsolete = CollectionSyncAccountToken(scope: token.scope, epoch: UUID())
        XCTAssertThrowsError(try checkpoint.validate(completing: obsolete)) { XCTAssertEqual($0 as? CollectionSyncError, .staleAccount) }
        var incomplete = base; incomplete.cells.removeAll { $0.id == .favorite(track) }
        XCTAssertThrowsError(try CollectionSyncMergePlan(base: base, local: incomplete, remote: base)) {
            XCTAssertEqual($0 as? CollectionSyncError, .incompleteSnapshot)
        }
        XCTAssertEqual(checkpoint.local, base)
    }
}

private actor SyncFixtureAssetBackend: CollectionSyncAssetBackend {
    let scope: String
    var asset: CollectionSyncCloudAsset?
    init(scope: String, asset: CollectionSyncCloudAsset? = nil) { self.scope = scope; self.asset = asset }
    func currentAccountScope() -> String { scope }
    func fetch() -> CollectionSyncCloudAsset? { asset }
    func save(_ data: Data, replacing tag: String?) throws -> CollectionSyncCloudAsset {
        guard asset?.changeTag == tag else { throw CollectionSyncTransportError.conflict }
        let saved = CollectionSyncCloudAsset(data: data, changeTag: UUID().uuidString)
        asset = saved
        return saved
    }
}

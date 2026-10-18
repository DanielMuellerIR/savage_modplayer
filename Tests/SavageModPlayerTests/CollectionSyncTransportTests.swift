import XCTest

@testable import SavageModPlayerCore

@MainActor
final class CollectionSyncTransportTests: XCTestCase {
    private actor Backend: CollectionSyncAssetBackend {
        enum Mode: Sendable {
            case normal, race, accountAfterRead, accountAfterWrite, deletedZone
            case badAcknowledgment(Data)
        }
        var scope: String
        var asset: CollectionSyncCloudAsset?
        var mode = Mode.normal
        var saves = 0, scopes = 0
        var tags: [String?] = []
        init(scope: String, asset: CollectionSyncCloudAsset?) {
            self.scope = scope
            self.asset = asset
        }
        func configure(_ mode: Mode) { self.mode = mode }
        func setAsset(_ asset: CollectionSyncCloudAsset?) { self.asset = asset }
        func currentAccountScope() -> String {
            scopes += 1
            return scope
        }
        func fetch() throws -> CollectionSyncCloudAsset? {
            if case .deletedZone = mode { throw CollectionSyncTransportError.configurationRequired }
            if case .accountAfterRead = mode { scope = String(repeating: "b", count: 64) }
            return asset
        }
        func save(_ data: Data, replacing tag: String?) throws -> CollectionSyncCloudAsset {
            saves += 1
            tags.append(tag)
            if case .race = mode {
                self.asset = .init(data: asset?.data ?? data, changeTag: "other-device")
            }
            guard asset?.changeTag == tag else { throw CollectionSyncTransportError.conflict }
            let result = CollectionSyncCloudAsset(data: data, changeTag: "saved-\(saves)")
            asset = result
            if case .accountAfterWrite = mode { scope = String(repeating: "b", count: 64) }
            if case .badAcknowledgment(let bytes) = mode {
                return .init(data: bytes, changeTag: result.changeTag)
            }
            return result
        }
        func status() -> (
            saves: Int, scopes: Int, tags: [String?], asset: CollectionSyncCloudAsset?
        ) { (saves, scopes, tags, asset) }
    }

    private func fixture(existing: Bool = true) throws -> (
        CollectionSyncAccountToken, CollectionSyncSnapshot, Backend, CollectionSyncTransportClient,
        UUID
    ) {
        let account = CollectionSyncAccountToken(
            scope: String(repeating: "a", count: 64), epoch: UUID())
        let track = UUID()
        let snapshot = CollectionSyncSnapshot(
            collectionID: UUID(), generation: UUID(),
            cells: [
                .init(.track(track), .track(.init(fileName: "song.mod"))),
                .init(.favorite(track), .flag(true)),
            ])
        let backend = Backend(
            scope: account.scope,
            asset: existing
                ? .init(data: try CollectionSyncCodec.encode(snapshot), changeTag: "initial") : nil)
        let client = try CollectionSyncTransportClient(
            backend: backend, account: account, collectionID: snapshot.collectionID,
            generation: snapshot.generation)
        return (account, snapshot, backend, client, track)
    }
    private func failure<T: Sendable>(_ body: @MainActor () async throws -> T) async -> Error? {
        do {
            _ = try await body()
            XCTFail("Expected operation to fail")
            return nil
        } catch { return error }
    }

    func testFirstPublishThenConditionalDeletionKeepsHistoryAndReturnsServerRevision() async throws
    {
        let (account, snapshot, backend, client, track) = try fixture(existing: false)
        let first = try await client.save(snapshot, replacing: nil, account: account)
        var edited = snapshot
        edited.cells.removeAll { $0.id == .favorite(track) }
        edited.cells.append(.init(.favorite(track), .deleted))
        let second = try await client.save(edited, replacing: first.changeTag, account: account)
        let fetched = try await client.fetch(account: account)
        XCTAssertEqual(fetched, second)
        XCTAssertEqual(fetched.snapshot.indexed()[.favorite(track)], .deleted)
        let status = await backend.status()
        XCTAssertEqual(status.tags, [nil, first.changeTag])
        XCTAssertEqual(status.saves, 2)
    }

    func testLateRemoteRevisionCannotBeBlindlyOverwritten() async throws {
        let (account, snapshot, backend, client, track) = try fixture()
        var edited = snapshot
        edited.cells.removeAll { $0.id == .favorite(track) }
        edited.cells.append(.init(.favorite(track), .deleted))
        await backend.configure(.race)
        let error = await failure {
            try await client.save(edited, replacing: "initial", account: account)
        }
        XCTAssertEqual(error as? CollectionSyncTransportError, .conflict)
        let status = await backend.status()
        XCTAssertEqual(status.tags, ["initial"])
        XCTAssertEqual(
            try CollectionSyncCodec.decode(XCTUnwrap(status.asset).data).indexed(),
            snapshot.indexed())
        XCTAssertEqual(status.asset?.changeTag, "other-device")
    }

    func testFirstPublishRaceCannotReplaceAnotherDevicesNewRecord() async throws {
        let (account, snapshot, backend, client, _) = try fixture(existing: false)
        await backend.configure(.race)
        let error = await failure { try await client.save(snapshot, replacing: nil, account: account) }
        XCTAssertEqual(error as? CollectionSyncTransportError, .conflict)
        let status = await backend.status()
        XCTAssertEqual(status.tags, [nil])
        XCTAssertEqual(status.asset?.changeTag, "other-device")
    }

    func testOldAcknowledgmentCannotBeAdoptedAfterAnAccountEpochReset() async throws {
        let (account, _, _, client, _) = try fixture()
        let version = try await client.fetch(account: account)
        XCTAssertNoThrow(try version.validate(completing: account))
        let current = CollectionSyncAccountToken(scope: account.scope, epoch: UUID())
        XCTAssertThrowsError(try version.validate(completing: current)) { XCTAssertEqual($0 as? CollectionSyncError, .staleAccount) }
    }

    func testMissingRecordAndDeletedZoneNeverReturnAnEmptyCollection() async throws {
        let (account, _, backend, client, _) = try fixture(existing: false)
        var error = await failure { try await client.fetch(account: account) }
        XCTAssertEqual(error as? CollectionSyncTransportError, .missingRecord)
        await backend.configure(.deletedZone)
        error = await failure { try await client.fetch(account: account) }
        XCTAssertEqual(error as? CollectionSyncTransportError, .configurationRequired)
        let status = await backend.status()
        XCTAssertEqual(status.saves, 0)
    }

    func testEpochAndAccountChangesDuringReadOrWriteCannotBeAcknowledged() async throws {
        let (account, snapshot, backend, client, _) = try fixture()
        let obsolete = CollectionSyncAccountToken(scope: account.scope, epoch: UUID())
        var error = await failure { try await client.fetch(account: obsolete) }
        XCTAssertEqual(error as? CollectionSyncError, .staleAccount)
        let untouched = await backend.status()
        XCTAssertEqual(untouched.scopes, 0)
        await backend.configure(.accountAfterRead)
        error = await failure { try await client.fetch(account: account) }
        XCTAssertEqual(error as? CollectionSyncError, .staleAccount)
        let next = try fixture()
        await next.2.configure(.accountAfterWrite)
        error = await failure {
            try await next.3.save(next.1, replacing: "initial", account: next.0)
        }
        XCTAssertEqual(error as? CollectionSyncError, .staleAccount)
        let status = await next.2.status()
        XCTAssertEqual(status.saves, 1)
        XCTAssertEqual(status.asset?.changeTag, "saved-1")
        XCTAssertEqual(snapshot.cells.count, 2)
    }

    func testForeignGenerationIncompleteHistoryAndStaleTagsNeverReachSave() async throws {
        let (account, snapshot, backend, client, track) = try fixture()
        let foreign = CollectionSyncSnapshot(collectionID: UUID(), generation: snapshot.generation)
        var error = await failure {
            try await client.save(foreign, replacing: "initial", account: account)
        }
        XCTAssertEqual(error as? CollectionSyncError, .mismatchedCollection)
        let next = CollectionSyncSnapshot(collectionID: snapshot.collectionID, generation: UUID())
        error = await failure {
            try await client.save(next, replacing: "initial", account: account)
        }
        XCTAssertEqual(error as? CollectionSyncError, .staleGeneration)
        var incomplete = snapshot
        incomplete.cells.removeAll { $0.id == .favorite(track) }
        error = await failure {
            try await client.save(incomplete, replacing: "initial", account: account)
        }
        XCTAssertEqual(error as? CollectionSyncError, .incompleteSnapshot)
        error = await failure {
            try await client.save(snapshot, replacing: "outdated", account: account)
        }
        XCTAssertEqual(error as? CollectionSyncTransportError, .conflict)
        error = await failure { try await client.save(snapshot, replacing: nil, account: account) }
        XCTAssertEqual(error as? CollectionSyncTransportError, .conflict)
        let status = await backend.status()
        XCTAssertEqual(status.saves, 0)
    }

    func testCorruptOversizedLocalBundleAndInvalidTagsAreRejected() async throws {
        let (account, snapshot, backend, client, track) = try fixture()
        for data in [Data("{broken".utf8), Data(count: CollectionSyncCodec.maximumBytes + 1)] {
            await backend.setAsset(.init(data: data, changeTag: "initial"))
            let error = await failure { try await client.fetch(account: account) }
            XCTAssertNotNil(error)
        }
        for tag in ["", "bad\nrevision", String(repeating: "x", count: 1025)] {
            let error = await failure {
                try await client.save(snapshot, replacing: tag, account: account)
            }
            XCTAssertEqual(error as? CollectionSyncTransportError, .invalidResponse)
        }
        let reference = PlaylistTrackReference(
            source: .init(location: URL(fileURLWithPath: "/synthetic/song.mod")),
            displayName: "song.mod")
        let local = CollectionSyncLocalState(
            checkpoint: .init(account: account, base: snapshot, local: snapshot),
            registry: .init(
                account: account, collectionID: snapshot.collectionID,
                generation: snapshot.generation, bindings: [.init(id: track, reference: reference)])
        )
        await backend.setAsset(
            .init(data: try CollectionSyncLocalStateCodec.encode(local), changeTag: "initial"))
        let error = await failure { try await client.fetch(account: account) }
        XCTAssertNotNil(error)
        let status = await backend.status()
        XCTAssertEqual(status.saves, 0)
    }

    func testInvalidAcknowledgmentDoesNotAdvanceCallerCheckpointOrRetry() async throws {
        let (account, snapshot, backend, client, track) = try fixture()
        var edited = snapshot
        edited.cells.removeAll { $0.id == .favorite(track) }
        edited.cells.append(.init(.favorite(track), .deleted))
        let checkpoint = CollectionSyncCheckpoint(
            account: account, base: snapshot, local: edited, serverChangeTag: "initial")
        await backend.configure(.badAcknowledgment(try CollectionSyncCodec.encode(snapshot)))
        let error = await failure {
            try await client.save(edited, replacing: "initial", account: account)
        }
        XCTAssertEqual(error as? CollectionSyncTransportError, .invalidResponse)
        XCTAssertEqual(checkpoint.serverChangeTag, "initial")
        XCTAssertTrue(try checkpoint.pendingChanges())
        let status = await backend.status()
        XCTAssertEqual(status.saves, 1)
    }

    func testCancellationBeforeCallDoesNotTouchBackend() async throws {
        let (account, snapshot, backend, client, _) = try fixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.save(snapshot, replacing: "initial", account: account)
        }
        let error = await failure { try await task.value }
        XCTAssertTrue(error is CancellationError)
        let status = await backend.status()
        XCTAssertEqual(status.saves, 0)
        XCTAssertEqual(status.scopes, 0)
    }
}

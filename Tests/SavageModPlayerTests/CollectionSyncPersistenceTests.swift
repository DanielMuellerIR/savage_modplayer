import XCTest
@testable import SavageModPlayerCore

final class CollectionSyncPersistenceTests: XCTestCase {
    private enum Failure: Error { case injected }
    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = true
        func take() -> Bool {
            lock.lock(); defer { lock.unlock() }
            let result = pending; pending = false; return result
        }
    }
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncPersistence-\(UUID())")
        var files: [URL] { ["playlists.json", "markers.json", "settings.json", "sync.json"].map { root.appendingPathComponent($0) } }
        var journal: URL { root.appendingPathComponent("journal") }
        var auxiliary: URL { root.appendingPathComponent("preferences") }
        var pending: URL { journal.appendingPathComponent("pending") }
        let before: CollectionExchangeStoredDocuments
        let after: CollectionExchangeStoredDocuments
        var original: [Data?] = []

        init(withState: Bool = true) throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var lists = SavedPlaylistDocument()
            lists.playlists = [.init(name: "Before", tracks: [])]
            var markers = SongMarkerDocument()
            markers.markers = [.init(sourceID: "source", name: "Before", address: .init(position: 1, row: 2))]
            var settings = TrackPlaybackSettingsDocument()
            settings.tracks["source"] = .init(stereoSeparation: 0.3)
            before = .init(playlists: lists, markers: markers, trackSettings: settings,
                           syncState: withState ? Data("old checkpoint".utf8) : nil)
            lists.playlists[0].name = "After"
            markers.markers[0].name = "After"
            settings.tracks["source"] = .init(useInterpolation: false)
            after = .init(playlists: lists, markers: markers, trackSettings: settings,
                          syncState: Data("new checkpoint".utf8))
            let data = try [SavedPlaylistStore.encodedData(before.playlists), SongMarkerStore.encodedData(before.markers),
                            TrackPlaybackSettingsStore.encodedData(before.trackSettings)]
            for (url, bytes) in zip(files, data) { try (Data(" \n".utf8) + bytes).write(to: url) }
            if let state = before.syncState { try state.write(to: files[3]) }
            try Data("before".utf8).write(to: auxiliary)
            original = files.map { try? Data(contentsOf: $0) }
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func persistence(sync: Bool = true) throws -> CollectionExchangePersistence {
            try .init(playlistsURL: files[0], markersURL: files[1], trackSettingsURL: files[2],
                      journalURL: journal, syncStateURL: sync ? files[3] : nil)
        }
        func replace(_ expected: Data, _ replacement: Data) throws {
            let current = try Data(contentsOf: auxiliary)
            if current == replacement { return }
            guard current == expected else { throw CollectionExchangePersistenceError.staleState }
            try replacement.write(to: auxiliary, options: .atomic)
        }
        func assertOriginal(file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertEqual(files.map { try? Data(contentsOf: $0) }, original, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: auxiliary), Data("before".utf8), file: file, line: line)
            XCTAssertEqual(try persistence().snapshot().documents, before, file: file, line: line)
            XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path), file: file, line: line)
        }
    }
    private let beforePreferences = Data("before".utf8)
    private let afterPreferences = Data("after".utf8)

    func testMetadataCheckpointAndPreferencesCommitAsOneRecoverableGroup() throws {
        let f = try Fixture(), p = try f.persistence()
        XCTAssertEqual(try p.commit(f.after, replacing: p.snapshot(), auxiliaryBefore: beforePreferences,
                                    auxiliaryAfter: afterPreferences, replaceAuxiliary: f.replace), .complete)
        let restarted = try f.persistence()
        XCTAssertEqual(try restarted.snapshot().documents, f.after)
        XCTAssertTrue(try restarted.snapshot().metadataFilesExist)
        XCTAssertEqual(try Data(contentsOf: f.auxiliary), afterPreferences)
        XCTAssertEqual(try restarted.recover(replaceAuxiliary: f.replace), .none)
    }

    func testFailureAfterWritingFourthFileRestoresExactAllOriginalBytes() throws {
        let f = try Fixture(), once = OneShot(), target = f.files[3]
        let p = try CollectionExchangePersistence(copying: f.persistence()) { data, url in
            try data.write(to: url, options: .atomic)
            if url == target, once.take() { throw Failure.injected }
        }
        XCTAssertThrowsError(try p.commit(f.after, replacing: p.snapshot(), auxiliaryBefore: beforePreferences,
                                          auxiliaryAfter: afterPreferences, replaceAuxiliary: f.replace))
        try f.assertOriginal()
    }

    func testPreferencesFailureAfterAllFourWritesRollsBackTheCheckpointToo() throws {
        let f = try Fixture(), p = try f.persistence(), once = OneShot()
        XCTAssertThrowsError(try p.commit(f.after, replacing: p.snapshot(), auxiliaryBefore: beforePreferences,
                                          auxiliaryAfter: afterPreferences) { expected, replacement in
            try f.replace(expected, replacement)
            if once.take() { throw Failure.injected }
        })
        try f.assertOriginal()
    }

    func testEveryIncompleteFourFileBoundaryRecoversInANewPersistenceInstance() throws {
        for boundary in 0...5 {
            let f = try Fixture(), p = try f.persistence(), snapshot = try p.snapshot()
            try p.withLock {
                let prepared = try p.prepare(f.after, replacing: snapshot,
                                             auxiliaryBefore: beforePreferences, auxiliaryAfter: afterPreferences)
                for index in 0..<min(4, boundary) { try p.writePreparedFile(prepared, index: index) }
                if boundary == 5 { try f.replace(beforePreferences, afterPreferences) }
            }
            XCTAssertEqual(try f.persistence().recover(replaceAuxiliary: f.replace), .rolledBack, "Phase \(boundary)")
            try f.assertOriginal()
        }
    }

    func testCompletedFourFileReceiptPreservesLaterLocalCheckpointChanges() throws {
        let f = try Fixture(), p = try f.persistence(), snapshot = try p.snapshot()
        try p.withLock {
            let prepared = try p.prepare(f.after, replacing: snapshot,
                                         auxiliaryBefore: beforePreferences, auxiliaryAfter: afterPreferences)
            for index in 0..<4 { try p.writePreparedFile(prepared, index: index) }
            try f.replace(beforePreferences, afterPreferences)
            try p.markCompleted(prepared)
        }
        let later = Data("later local changes".utf8)
        try later.write(to: f.files[3])
        XCTAssertEqual(try f.persistence().recover(replaceAuxiliary: f.replace), .completed)
        XCTAssertEqual(try f.persistence().snapshot().documents.syncState, later)
    }

    func testLegacyThreeFileJournalWithoutNewFieldsRecoversWithoutChangingSyncState() throws {
        let f = try Fixture(), legacy = try f.persistence(sync: false), snapshot = try legacy.snapshot()
        var replacement = f.after; replacement.syncState = nil
        try legacy.withLock {
            let prepared = try legacy.prepare(replacement, replacing: snapshot,
                                               auxiliaryBefore: beforePreferences, auxiliaryAfter: afterPreferences)
            for index in 0..<2 { try legacy.writePreparedFile(prepared, index: index) }
        }
        let manifest = f.pending.appendingPathComponent("manifest.json")
        var fields = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
        fields.removeValue(forKey: "afterExists")
        try JSONSerialization.data(withJSONObject: fields).write(to: manifest)
        XCTAssertEqual(try f.persistence().recover(replaceAuxiliary: f.replace), .rolledBack)
        try f.assertOriginal()
    }

    func testManualImportPreservesCheckpointAndDoesNotCreateAnAbsentStateFile() throws {
        for withState in [true, false] {
            let f = try Fixture(withState: withState), p = try f.persistence()
            var manual = f.after; manual.syncState = nil
            try p.commit(manual, replacing: p.snapshot(), auxiliaryBefore: beforePreferences,
                         auxiliaryAfter: afterPreferences, replaceAuxiliary: f.replace)
            XCTAssertEqual(try p.snapshot().documents.syncState, f.before.syncState)
            XCTAssertEqual(FileManager.default.fileExists(atPath: f.files[3].path), withState)
        }
    }

    func testConcurrentCheckpointWriteMakesPreparedMetadataStaleBeforeAnyCommit() throws {
        let f = try Fixture(), p = try f.persistence(), snapshot = try p.snapshot()
        let concurrent = Data("new pending local mutation".utf8)
        try concurrent.write(to: f.files[3])
        XCTAssertThrowsError(try p.commit(f.after, replacing: snapshot, auxiliaryBefore: beforePreferences,
                                          auxiliaryAfter: afterPreferences, replaceAuxiliary: f.replace))
        XCTAssertEqual(Array(f.files.prefix(3)).map { try? Data(contentsOf: $0) }, Array(f.original.prefix(3)))
        XCTAssertEqual(try Data(contentsOf: f.files[3]), concurrent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.pending.path))
    }

    func testSyncStateCannotBeSilentlyWrittenByAThreeFileConfiguration() throws {
        let f = try Fixture(), p = try f.persistence(sync: false)
        XCTAssertThrowsError(try p.commit(f.after, replacing: p.snapshot(), auxiliaryBefore: beforePreferences,
                                          auxiliaryAfter: afterPreferences, replaceAuxiliary: f.replace))
        try f.assertOriginal()
    }
}

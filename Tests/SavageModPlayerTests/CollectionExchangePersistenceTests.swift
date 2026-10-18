import XCTest
@testable import SavageModPlayerCore

final class CollectionExchangePersistenceTests: XCTestCase {
    private enum Failure: Error { case injected }
    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = true
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; let value = pending; pending = false; return value }
    }
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CollectionPersistence-\(UUID())")
        var urls: [URL] { ["playlists.json", "markers.json", "settings.json"].map { root.appendingPathComponent($0) } }
        var journal: URL { root.appendingPathComponent("journal") }
        var pending: URL { journal.appendingPathComponent("pending") }
        var persistence: CollectionExchangePersistence {
            get throws { try .init(playlistsURL: urls[0], markersURL: urls[1], trackSettingsURL: urls[2], journalURL: journal) }
        }
        var auxiliary = Data("before".utf8)
        let afterAuxiliary = Data("after".utf8)
        var originalBytes: [Data?] = []
        let before: CollectionExchangeStoredDocuments
        let after: CollectionExchangeStoredDocuments
        init(existing: Bool = true) throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var playlists = SavedPlaylistDocument()
            playlists.playlists = [.init(name: "Before", tracks: [])]; playlists.favoriteIDs = ["source"]
            var markers = SongMarkerDocument()
            markers.markers = [.init(sourceID: "source", name: "Before", address: .init(position: 2, row: 3), createdAt: Date(timeIntervalSince1970: 1_700_000_000))]
            var settings = TrackPlaybackSettingsDocument(); settings.tracks["source"] = .init(palClock: false)
            let populated = CollectionExchangeStoredDocuments(playlists: playlists, markers: markers, trackSettings: settings)
            before = existing ? populated : .init(playlists: .init(), markers: .init(), trackSettings: .init())
            playlists.playlists[0].name = "After"; playlists.favoriteIDs.insert("new")
            markers.markers[0].name = "After"; markers.markers[0].address = .init(position: 4, row: 5)
            settings.tracks["source"] = .init(stereoSeparation: 0.2, useInterpolation: false)
            after = .init(playlists: playlists, markers: markers, trackSettings: settings)
            if existing {
                let bytes = try [SavedPlaylistStore.encodedData(before.playlists), SongMarkerStore.encodedData(before.markers),
                                 TrackPlaybackSettingsStore.encodedData(before.trackSettings)]
                for (url, data) in zip(urls, bytes) { try (Data(" \n".utf8) + data + Data("\n".utf8)).write(to: url) }
            }
            originalBytes = urls.map { try? Data(contentsOf: $0) }
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func replaceAuxiliary(_ expected: Data, _ replacement: Data) throws {
            if auxiliary == replacement { return }
            guard auxiliary == expected else { throw CollectionExchangePersistenceError.staleState }
            auxiliary = replacement
        }
        func assertOriginal(file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertEqual(urls.map { try? Data(contentsOf: $0) }, originalBytes, file: file, line: line)
            XCTAssertEqual(auxiliary, Data("before".utf8), file: file, line: line)
            XCTAssertEqual(try persistence.snapshot().documents, before, file: file, line: line)
            XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path), file: file, line: line)
        }
    }

    func testCommitReplacesAllDocumentsAndAuxiliaryThenRemovesOnlyOwnJournal() throws {
        let f = try Fixture(); let p = try f.persistence
        let keep = f.root.appendingPathComponent("keep.txt"); try Data("untouched".utf8).write(to: keep)
        XCTAssertEqual(try p.commit(f.after, replacing: p.snapshot(), auxiliaryBefore: f.auxiliary,
                                    auxiliaryAfter: f.afterAuxiliary, replaceAuxiliary: f.replaceAuxiliary), .complete)
        XCTAssertEqual(try p.snapshot().documents, f.after)
        XCTAssertEqual(f.auxiliary, f.afterAuxiliary)
        XCTAssertEqual(try String(contentsOf: keep, encoding: .utf8), "untouched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.pending.path))
        XCTAssertEqual(try p.recover(replaceAuxiliary: f.replaceAuxiliary), .none)
    }

    func testFailedSecondFileRestoresExactOriginalBytesAndAuxiliary() throws {
        let f = try Fixture(); let once = OneShot(); let target = f.urls[1]
        let p = try CollectionExchangePersistence(copying: f.persistence) { data, url in
            if url == target, once.take() { throw Failure.injected }
            try data.write(to: url, options: .atomic)
        }
        XCTAssertThrowsError(try p.commit(f.after, replacing: p.snapshot(), auxiliaryBefore: f.auxiliary,
                                          auxiliaryAfter: f.afterAuxiliary, replaceAuxiliary: f.replaceAuxiliary))
        try f.assertOriginal()
    }

    func testAuxiliaryFailureAfterChangingValuesRollsBackFilesAndValues() throws {
        let f = try Fixture(); let p = try f.persistence
        var fail = true
        XCTAssertThrowsError(try p.commit(f.after, replacing: p.snapshot(), auxiliaryBefore: f.auxiliary, auxiliaryAfter: f.afterAuxiliary) { expected, replacement in
            try f.replaceAuxiliary(expected, replacement)
            if fail { fail = false; throw Failure.injected }
        })
        try f.assertOriginal()
    }

    func testEveryIncompleteDurablePhaseRecoversAfterRestart() throws {
        for boundary in 0...4 {
            let f = try Fixture(); let p = try f.persistence; let snapshot = try p.snapshot()
            try p.withLock {
                let prepared = try p.prepare(f.after, replacing: snapshot, auxiliaryBefore: f.auxiliary, auxiliaryAfter: f.afterAuxiliary)
                for index in 0..<min(3, boundary) { try p.writePreparedFile(prepared, index: index) }
                if boundary == 4 { try f.replaceAuxiliary(f.auxiliary, f.afterAuxiliary) }
            }
            let restarted = try f.persistence
            XCTAssertEqual(try restarted.recover(replaceAuxiliary: f.replaceAuxiliary), .rolledBack, "Phase \(boundary)")
            try f.assertOriginal()
        }
    }

    func testRecoveryRemovesNewFilesOnlyWhenTheyStillMatchOwnImportedBytes() throws {
        let f = try Fixture(existing: false); let p = try f.persistence; let snapshot = try p.snapshot()
        let keep = f.root.appendingPathComponent("personal.txt"); try Data("keep".utf8).write(to: keep)
        try p.withLock {
            let prepared = try p.prepare(f.after, replacing: snapshot, auxiliaryBefore: f.auxiliary, auxiliaryAfter: f.afterAuxiliary)
            for index in 0..<3 { try p.writePreparedFile(prepared, index: index) }
            try f.replaceAuxiliary(f.auxiliary, f.afterAuxiliary)
        }
        XCTAssertEqual(try f.persistence.recover(replaceAuxiliary: f.replaceAuxiliary), .rolledBack)
        try f.assertOriginal()
        XCTAssertEqual(try String(contentsOf: keep, encoding: .utf8), "keep")
    }

    func testCompletedReceiptKeepsNewAndSubsequentlyEditedData() throws {
        let f = try Fixture(); let p = try f.persistence; let snapshot = try p.snapshot()
        try p.withLock {
            let prepared = try p.prepare(f.after, replacing: snapshot, auxiliaryBefore: f.auxiliary, auxiliaryAfter: f.afterAuxiliary)
            for index in 0..<3 { try p.writePreparedFile(prepared, index: index) }
            try f.replaceAuxiliary(f.auxiliary, f.afterAuxiliary)
            try p.markCompleted(prepared)
        }
        var later = f.after.playlists; later.playlists[0].name = "Later edit"
        try SavedPlaylistStore.encodedData(later).write(to: f.urls[0])
        XCTAssertEqual(try f.persistence.recover(replaceAuxiliary: f.replaceAuxiliary), .completed)
        XCTAssertEqual(try f.persistence.snapshot().documents.playlists, later)
        XCTAssertEqual(f.auxiliary, f.afterAuxiliary)
    }

    func testStaleSnapshotAndWrongStorageIdentityFailBeforeChangingAnything() throws {
        let f = try Fixture(); let p = try f.persistence; let snapshot = try p.snapshot()
        var changed = f.before.playlists; changed.playlists[0].name = "Foreign edit"
        let foreign = try SavedPlaylistStore.encodedData(changed); try foreign.write(to: f.urls[0])
        XCTAssertThrowsError(try p.commit(f.after, replacing: snapshot, auxiliaryBefore: f.auxiliary,
                                          auxiliaryAfter: f.afterAuxiliary, replaceAuxiliary: f.replaceAuxiliary))
        XCTAssertEqual(try Data(contentsOf: f.urls[0]), foreign)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.pending.path))
        let other = try Fixture()
        XCTAssertThrowsError(try other.persistence.commit(f.after, replacing: snapshot, auxiliaryBefore: f.auxiliary,
                                                        auxiliaryAfter: f.afterAuxiliary, replaceAuxiliary: f.replaceAuxiliary))
        try other.assertOriginal()
    }

    func testForeignEditDuringIncompleteImportIsPreservedAlongWithAllBackups() throws {
        let f = try Fixture(); let p = try f.persistence; let snapshot = try p.snapshot()
        try p.withLock {
            let prepared = try p.prepare(f.after, replacing: snapshot, auxiliaryBefore: f.auxiliary, auxiliaryAfter: f.afterAuxiliary)
            try p.writePreparedFile(prepared, index: 0)
        }
        var changed = f.before.markers; changed.markers[0].name = "Foreign edit"
        let foreign = try SongMarkerStore.encodedData(changed); try foreign.write(to: f.urls[1])
        let first = try Data(contentsOf: f.urls[0])
        XCTAssertThrowsError(try f.persistence.recover(replaceAuxiliary: f.replaceAuxiliary))
        XCTAssertEqual(try Data(contentsOf: f.urls[0]), first)
        XCTAssertEqual(try Data(contentsOf: f.urls[1]), foreign)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.pending.path))
        XCTAssertEqual(try Data(contentsOf: f.pending.appendingPathComponent("before-markers.json")), f.originalBytes[1])
        try f.originalBytes[1]!.write(to: f.urls[1])
        XCTAssertEqual(try f.persistence.recover(replaceAuxiliary: f.replaceAuxiliary), .rolledBack)
        try f.assertOriginal()
    }

    func testCorruptBackupOrUnknownJournalFileBlocksRecoveryWithoutDeletingEvidence() throws {
        for corruptBackup in [true, false] {
            let f = try Fixture(); let p = try f.persistence; let snapshot = try p.snapshot()
            try p.withLock { _ = try p.prepare(f.after, replacing: snapshot, auxiliaryBefore: f.auxiliary, auxiliaryAfter: f.afterAuxiliary) }
            let file = f.pending.appendingPathComponent(corruptBackup ? "before-markers.json" : "unrelated.txt")
            try Data("foreign".utf8).write(to: file)
            XCTAssertThrowsError(try f.persistence.recover(replaceAuxiliary: f.replaceAuxiliary))
            XCTAssertEqual(f.urls.map { try? Data(contentsOf: $0) }, f.originalBytes)
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "foreign")
            XCTAssertThrowsError(try f.persistence.snapshot())
        }
    }

    func testUnfinishedPreparationCannotHaveChangedOriginalsAndIsDiscarded() throws {
        let f = try Fixture(); let p = try f.persistence
        try FileManager.default.createDirectory(at: f.pending, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: f.pending.appendingPathComponent("after-playlists.json"))
        try Data("partial".utf8).write(to: f.pending.appendingPathComponent("manifest.next"))
        XCTAssertEqual(try p.recover(replaceAuxiliary: f.replaceAuxiliary), .preparationDiscarded)
        try f.assertOriginal()
    }

    func testCleanupFailureAfterCommitPointKeepsSuccessfulImportAndForeignFile() throws {
        let f = try Fixture(); let p = try f.persistence
        let foreign = f.pending.appendingPathComponent("unrelated.txt")
        let result = try p.commit(f.after, replacing: p.snapshot(), auxiliaryBefore: f.auxiliary, auxiliaryAfter: f.afterAuxiliary) { expected, replacement in
            try f.replaceAuxiliary(expected, replacement)
            try Data("preserve".utf8).write(to: foreign)
        }
        XCTAssertEqual(result, .cleanupPending)
        XCTAssertEqual(try SavedPlaylistStore(fileURL: f.urls[0]).load(), f.after.playlists)
        XCTAssertEqual(f.auxiliary, f.afterAuxiliary)
        XCTAssertThrowsError(try p.recover(replaceAuxiliary: f.replaceAuxiliary))
        XCTAssertEqual(try String(contentsOf: foreign, encoding: .utf8), "preserve")
        try FileManager.default.removeItem(at: foreign)
        XCTAssertEqual(try p.recover(replaceAuxiliary: f.replaceAuxiliary), .completed)
        XCTAssertEqual(try p.snapshot().documents, f.after)
    }

    func testProcessLockRejectsASecondWriterAndSymlinkStoresRemainUntouched() throws {
        let f = try Fixture(); let p = try f.persistence
        try p.withLock { XCTAssertThrowsError(try f.persistence.snapshot()) }
        let keep = f.root.appendingPathComponent("keep.json"); try Data("preserve".utf8).write(to: keep)
        try FileManager.default.removeItem(at: f.urls[1]); try FileManager.default.createSymbolicLink(at: f.urls[1], withDestinationURL: keep)
        XCTAssertThrowsError(try p.snapshot())
        XCTAssertEqual(try String(contentsOf: keep, encoding: .utf8), "preserve")
        XCTAssertTrue(try f.urls[1].resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    func testInvalidCandidateAndOversizedAuxiliaryNeverCreatePendingImport() throws {
        let f = try Fixture(); let p = try f.persistence
        var bad = f.after; bad.trackSettings.formatVersion = 99
        XCTAssertThrowsError(try p.commit(bad, replacing: p.snapshot(), auxiliaryBefore: f.auxiliary,
                                          auxiliaryAfter: f.afterAuxiliary, replaceAuxiliary: f.replaceAuxiliary))
        XCTAssertThrowsError(try p.commit(f.after, replacing: p.snapshot(), auxiliaryBefore: Data(repeating: 0, count: CollectionExchangePersistence.maximumAuxiliaryBytes + 1),
                                          auxiliaryAfter: f.afterAuxiliary, replaceAuxiliary: f.replaceAuxiliary))
        try f.assertOriginal()
        XCTAssertThrowsError(try CollectionExchangePersistence(playlistsURL: f.urls[0], markersURL: f.urls[0], trackSettingsURL: f.urls[2], journalURL: f.journal))
    }
}

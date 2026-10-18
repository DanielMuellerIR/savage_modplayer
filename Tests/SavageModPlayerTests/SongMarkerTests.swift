import XCTest
@testable import SavageModPlayerCore

final class SongMarkerTests: XCTestCase {
    private func module() -> Mod {
        Mod(name: "Repeated", length: 3, patternTable: [0, 0, 1], instruments: [nil],
            patterns: [Pattern(rows: Array(repeating: Row(notes: []), count: 4)),
                       Pattern(rows: Array(repeating: Row(notes: []), count: 12))])
    }
    func testOrderAddressesDistinguishRepeatedPatternsAndRangeRows() throws {
        let layout = SongPositionLayout(module: module())
        let section = try XCTUnwrap(SongSection(start: .init(position: 1, row: 1), end: .init(position: 2, row: 8)))
        XCTAssertEqual(layout.index(of: .init(position: 0, row: 1)), 1)
        XCTAssertEqual(layout.index(of: .init(position: 1, row: 1)), 5)
        XCTAssertNil(layout.rows(in: section, at: 0))
        XCTAssertEqual(layout.rows(in: section, at: 1), 1...3)
        XCTAssertEqual(layout.rows(in: section, at: 2), 0...8)
        XCTAssertEqual(layout.totalRows, 20)
    }
    func testInvalidAddressesAndReversedSelectionAreRejected() {
        let layout = SongPositionLayout(module: module())
        for value in [SongAddress(position: -1,row: 0), .init(position: 0,row: -1), .init(position: 1,row: 4), .init(position: 3,row: 0)] {
            XCTAssertFalse(layout.contains(value)); XCTAssertNil(layout.index(of: value))
        }
        XCTAssertNil(SongSection(start: .init(position: 2,row: 0), end: .init(position: 1,row: 3)))
    }
    func testStoreRoundTripKeepsSourceIDsNamesDatesAndInvalidModuleTargets() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("SongMarkers-\(UUID())")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appendingPathComponent("markers.json"), store = SongMarkerStore(fileURL: work.appendingPathComponent("markers.json"))
        let a = SongMarker(sourceID: "a/shared.mod", name: "Repeat", address: .init(position: 1,row: 3), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let b = SongMarker(sourceID: "b/shared.mod", name: "Repeat", address: .init(position: 999,row: 0), createdAt: a.createdAt)
        _ = try await store.update { $0.markers = [a,b] }
        let reopened = try await SongMarkerStore(fileURL: file).snapshot()
        XCTAssertEqual(reopened.document.markers, [a,b])
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("2023-11-14T22:13:20Z"))
    }
    func testCorruptAndNewerStoresRemainReadOnlyAndUnchanged() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("SongMarkers-\(UUID())")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        for bytes in [Data("broken".utf8), Data("{\"formatVersion\":2,\"markers\":[]}".utf8)] {
            let file = work.appendingPathComponent(UUID().uuidString)
            try bytes.write(to: file)
            let store = SongMarkerStore(fileURL: file)
            do { _ = try await store.snapshot(); XCTFail("Invalid store accepted") } catch { }
            do { _ = try await store.update { $0.markers = [] }; XCTFail("Invalid store overwritten") } catch { }
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }
    func testFailedWritesAndInvalidMarkersPreservePreviousDocument() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("SongMarkers-\(UUID())")
        let file = work.appendingPathComponent("markers.json"), store = SongMarkerStore(fileURL: work.appendingPathComponent("markers.json"))
        defer { try? FileManager.default.removeItem(at: work) }
        _ = try await store.snapshot()
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let marker = SongMarker(sourceID: "a", name: "Valid", address: .init(position: 0,row: 0))
        do { _ = try await store.update { $0.markers = [marker] }; XCTFail("Directory overwritten") } catch { }
        let afterFailure = try await store.snapshot(); XCTAssertTrue(afterFailure.document.markers.isEmpty)
        try FileManager.default.removeItem(at: file)
        let invalid = SongMarker(sourceID: "a", name: "Invalid", address: .init(position: -1,row: 0))
        do { _ = try await store.update { $0.markers = [invalid] }; XCTFail("Negative address accepted") } catch { }
        do { _ = try await store.update { $0.markers = [marker,marker] }; XCTFail("Duplicate IDs accepted") } catch { }
        let result = try await store.update { $0.markers = [marker] }
        XCTAssertEqual(result.revision, 1)
    }
    func testOversizedStoreRemainsUnchanged() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MarkerLimit-\(UUID()).json")
        let size = SongMarkerStore.maximumBytes + 1
        try Data(repeating: 0x20,count: size).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = SongMarkerStore(fileURL: file)
        do { _ = try await store.snapshot(); XCTFail("Oversized store accepted") }
        catch SongMarkerStoreError.oversized { }
        catch { XCTFail("Unexpected error: \(error)") }
        do { _ = try await store.update { $0.markers = [] }; XCTFail("Oversized store overwritten") } catch { }
        XCTAssertEqual(try Data(contentsOf: file).count,size)
    }
    func testConcurrentActorUpdatesDoNotLoseMarkers() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("SongMarkers-\(UUID())")
        defer { try? FileManager.default.removeItem(at: work) }
        let store = SongMarkerStore(fileURL: work.appendingPathComponent("markers.json"))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask { _ = try await store.update { $0.markers.append(SongMarker(sourceID: "source", name: "\(index)", address: .init(position: 0,row: index))) } }
            }
            try await group.waitForAll()
        }
        let result = try await store.snapshot(); XCTAssertEqual(result.document.markers.count, 30)
    }
}

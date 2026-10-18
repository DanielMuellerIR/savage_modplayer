#if canImport(Combine)
import XCTest
@testable import SavageModPlayerCore

@MainActor
final class SongMarkersModelTests: XCTestCase {
    private func module() -> Mod {
        Mod(name: "Markers", length: 3, patternTable: [0,0,1], instruments: [nil],
            patterns: [Pattern(rows: Array(repeating: Row(notes: []), count: 4)),
                       Pattern(rows: Array(repeating: Row(notes: []), count: 12))])
    }
    private func wait(_ model: SongMarkersModel) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !model.isLoaded && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.isLoaded)
    }
    func testSourceSwitchRenameAndRestartPreserveIndependentMarkers() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MarkerModel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appendingPathComponent("markers.json"), model = SongMarkersModel(fileURL: work.appendingPathComponent("markers.json"))
        model.setContext(sourceID: "one/shared.mod", module: module(), moduleID: UUID())
        try await wait(model)
        let saved = await model.save(name: "Repeat", address: .init(position: 1,row: 3)); XCTAssertTrue(saved)
        let id = try XCTUnwrap(model.markers.first?.id)
        XCTAssertEqual(model.markerRowsByPosition[1], [3]); XCTAssertNil(model.markerRowsByPosition[0])
        let renamed = await model.save(name: "Chorus", address: .init(position: 1,row: 2), editingID: id); XCTAssertTrue(renamed)
        model.setBoundary(.init(position: 1,row: 1), isStart: true); model.setBoundary(.init(position: 2,row: 8), isStart: false)
        XCTAssertNotNil(model.section)
        model.setContext(sourceID: "two/shared.mod", module: module(), moduleID: UUID())
        XCTAssertTrue(model.markers.isEmpty); XCTAssertNil(model.section)
        let savedOther = await model.save(name: "Repeat", address: .init(position: 0,row: 1)); XCTAssertTrue(savedOther)
        let reopened = SongMarkersModel(fileURL: file)
        reopened.setContext(sourceID: "one/shared.mod", module: module(), moduleID: UUID())
        try await wait(reopened)
        XCTAssertEqual(reopened.markers.first?.id, id); XCTAssertEqual(reopened.markers.first?.name, "Chorus")
    }
    func testReadOnlyStoreStillAllowsRangeSelectionAndRejectsReverseBounds() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MarkerModel-\(UUID()).json")
        let bytes = Data("broken".utf8); try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let model = SongMarkersModel(fileURL: file)
        model.setContext(sourceID: "one", module: module(), moduleID: UUID()); try await wait(model)
        XCTAssertFalse(model.canSave)
        model.setBoundary(.init(position: 2,row: 1), isStart: true); model.setBoundary(.init(position: 1,row: 1), isStart: false)
        XCTAssertTrue(model.isSelectionInvalid); XCTAssertNil(model.section)
        model.setBoundary(.init(position: 2,row: 8), isStart: false); XCTAssertNotNil(model.section)
        let result = await model.save(name: "Blocked", address: .init(position: 0,row: 0)); XCTAssertFalse(result)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testSavedAddressSeeksToSecondOccurrenceAndKeepsStoppedState() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MarkerSeek-\(UUID())")
        defer { try? FileManager.default.removeItem(at: work) }
        let model = SongMarkersModel(fileURL: work.appendingPathComponent("markers.json")), song = module()
        model.setContext(sourceID: "one", module: song, moduleID: UUID()); try await wait(model)
        let saved = await model.save(name: "Second", address: .init(position: 1,row: 3)); XCTAssertTrue(saved)
        let target = try XCTUnwrap(model.markers.first?.address)
        let coordinator = ModPlayerCoordinator(); coordinator.setMod(song)
        coordinator.seek(toPosition: target.position, row: target.row)
        XCTAssertEqual(coordinator.currentPosition, 1); XCTAssertEqual(coordinator.currentRow, 3)
        XCTAssertFalse(coordinator.isPlaying)
    }
}
#endif

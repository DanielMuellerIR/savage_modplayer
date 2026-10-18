#if canImport(Combine)
import XCTest
@testable import SavageModPlayerCore

@MainActor
final class LibraryCatalogModelTests: XCTestCase {
    private var work: URL!
    private var model: LibraryCatalogModel!
    override func setUp() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryCatalog-\(UUID())")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        model = makeModel()
    }
    override func tearDown() async throws {
        model.cancelIndexing(); model = nil
        try FileManager.default.removeItem(at: work)
    }
    private func makeModel() -> LibraryCatalogModel {
        LibraryCatalogModel(metadataURL: work.appendingPathComponent("metadata.json"),
                            preferencesURL: work.appendingPathComponent("preferences.json"))
    }
    private func source(_ id: String, title: String) throws -> LibraryCatalogSource {
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        let bytes = Data(title.utf8.prefix(20)); data.replaceSubrange(0..<bytes.count, with: bytes)
        data[43] = 2; data[45] = 64; data[950] = 1
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        let file = work.appendingPathComponent(id + ".mod"); try data.write(to: file)
        return LibraryCatalogSource(id: id, url: file, displayName: id + ".mod", folderPath: "")
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Katalog lieferte den erwarteten Endzustand nicht")
    }

    func testLatestSourceAndQueryWinAndProgressCannotReappearAfterCompletion() async throws {
        let a = try source("a", title: "Zebra"), b = try source("b", title: "Alpha")
        model.setSources([a])
        model.setSources([b, a])
        var query = LibraryQuery(); query.search = "zebra"; model.query = query
        query.search = "alpha"; model.query = query
        try await waitUntil { self.model.progress == nil && !self.model.isFiltering && self.model.filteredIDs == ["b"] }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(model.progress)
        XCTAssertEqual(model.summary.indexed, 2)
    }

    func testIndexingDoesNotMarkHeardAndExplicitPlaybackMarkSurvivesRestart() async throws {
        let a = try source("a", title: "Alpha")
        model.setSources([a])
        try await waitUntil { self.model.progress == nil && self.model.preferencesLoaded }
        var query = LibraryQuery(); query.unheardOnly = true; model.query = query
        try await waitUntil { !self.model.isFiltering && self.model.filteredIDs == ["a"] }
        XCTAssertFalse(model.preferences.heardIDs.contains("a"))
        model.markHeard("a")
        try await waitUntil { !self.model.isFiltering && self.model.preferences.heardIDs.contains("a") && self.model.filteredIDs.isEmpty }
        let saved = await model.saveFilter(name: "Unheard", query: query)
        XCTAssertTrue(saved)
        let reopened = makeModel()
        try await waitUntil { reopened.preferencesLoaded }
        XCTAssertTrue(reopened.preferences.heardIDs.contains("a"))
        XCTAssertEqual(reopened.preferences.savedFilters.first?.query, query)
        reopened.cancelIndexing()
    }
}
#endif

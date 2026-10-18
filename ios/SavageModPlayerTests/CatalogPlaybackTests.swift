import XCTest
import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class CatalogPlaybackTests: XCTestCase {
    private var work: URL!
    private var catalog: LibraryCatalogModel!
    private var engine: PlaybackEngine!
    override func setUp() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("CatalogPlayback-\(UUID())")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        catalog = LibraryCatalogModel(metadataURL: work.appendingPathComponent("metadata.json"),
                                      preferencesURL: work.appendingPathComponent("preferences.json"))
        let settings = PlayerSettings(); settings.volume = 0
        engine = PlaybackEngine(settings: settings, library: LibraryStore(), catalog: catalog)
    }
    override func tearDown() async throws {
        engine.stop(); engine = nil; catalog.cancelIndexing(); catalog = nil
        try FileManager.default.removeItem(at: work)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Erwarteter Zustand blieb aus")
    }
    func testSelectionStaysUnheardAndPlaybackMarksTheRelativeLibraryID() async throws {
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        data[43] = 2; data[45] = 64; data[950] = 1
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        let file = work.appendingPathComponent("silent.mod"); try data.write(to: file)
        let track = TrackRef(relativePath: "Folder/silent.mod", displayName: "silent.mod", folderPath: ["Folder"], url: file)
        catalog.setSources([LibraryCatalogSource(id: track.relativePath, url: file, displayName: track.displayName, folderPath: "Folder")])
        engine.setExplicitQueue([track]); engine.select(track)
        try await waitUntil { self.engine.currentTrack == track && self.catalog.preferencesLoaded }
        XCTAssertFalse(catalog.preferences.heardIDs.contains(track.relativePath))
        engine.play()
        try await waitUntil { self.catalog.preferences.heardIDs.contains(track.relativePath) }
        XCTAssertFalse(catalog.preferences.heardIDs.contains(file.path))
    }
}

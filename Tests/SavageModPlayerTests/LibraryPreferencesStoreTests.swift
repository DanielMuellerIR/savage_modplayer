import XCTest
@testable import SavageModPlayerCore

@MainActor
final class LibraryPreferencesStoreTests: XCTestCase {
    private var work: URL!
    private var file: URL { work.appendingPathComponent("preferences.json") }
    override func setUp() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryPreferences-\(UUID())")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: work) }

    func testFiltersHeardAndFirstSeenSurviveRestartAndFirstSeenIsNotReplaced() async throws {
        let store = LibraryPreferencesStore(fileURL: file)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.registerSources(["library-v1:one": date])
        _ = try await store.registerSources(["library-v1:one": date.addingTimeInterval(100)])
        _ = try await store.markHeard("library-v1:one")
        var query = LibraryQuery(); query.format = .xm; query.unheardOnly = true
        let filter = SavedLibraryFilter(name: " My XM ", query: query)
        _ = try await store.update { $0.savedFilters.append(filter) }
        let reopened = try await LibraryPreferencesStore(fileURL: file).snapshot()
        XCTAssertEqual(reopened.document.firstSeenAt["library-v1:one"], date)
        XCTAssertTrue(reopened.document.heardIDs.contains("library-v1:one"))
        XCTAssertEqual(reopened.document.savedFilters, [filter])
        _ = try await store.markHeard("library-v1:one", heard: false)
        let reset = try await store.snapshot()
        XCTAssertTrue(reset.document.heardIDs.isEmpty)
        XCTAssertEqual(reset.document.firstSeenAt["library-v1:one"], date)
    }

    func testCorruptAndNewerDocumentsRemainReadOnlyAndByteIdentical() async throws {
        let store = LibraryPreferencesStore(fileURL: file)
        let bytes = Data("broken".utf8)
        try bytes.write(to: file)
        do { _ = try await store.markHeard("one"); XCTFail("Defekte Datei darf nicht ersetzt werden") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        var document = LibraryPreferencesDocument(); document.formatVersion = 99
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let newer = try encoder.encode(document)
        try newer.write(to: file)
        let newerStore = LibraryPreferencesStore(fileURL: file)
        do { _ = try await newerStore.markHeard("one"); XCTFail("Neuere Datei darf nicht ersetzt werden") }
        catch LibraryPreferencesError.unsupportedVersion(99) { }
        XCTAssertEqual(try Data(contentsOf: file), newer)
    }

    func testFailedValidationOrWriteDoesNotChangeTheDocumentOrSource() async throws {
        let store = LibraryPreferencesStore(fileURL: file)
        let before = try await store.markHeard("kept")
        let bytes = try Data(contentsOf: file)
        do {
            _ = try await store.update { $0.savedFilters.append(SavedLibraryFilter(name: " ", query: LibraryQuery())) }
            XCTFail("Leerer Name muss abgelehnt werden")
        } catch { }
        let after = try await store.snapshot()
        XCTAssertEqual(before.document, after.document)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let blocker = work.appendingPathComponent("blocker")
        try Data("keep".utf8).write(to: blocker)
        let blocked = LibraryPreferencesStore(fileURL: blocker.appendingPathComponent("preferences.json"))
        do { _ = try await blocked.markHeard("one"); XCTFail("Schreiben muss scheitern") } catch { }
        XCTAssertEqual(try Data(contentsOf: blocker), Data("keep".utf8))
        let unchanged = try await blocked.snapshot()
        XCTAssertTrue(unchanged.document.heardIDs.isEmpty)
    }

    func testConcurrentUpdatesAreSerializedAndNoOpKeepsRevision() async throws {
        let store = LibraryPreferencesStore(fileURL: file)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask { _ = try await store.markHeard("track-\(index)") }
            }
            try await group.waitForAll()
        }
        let before = try await store.snapshot()
        XCTAssertEqual(before.document.heardIDs.count, 50)
        let after = try await store.markHeard("track-0")
        XCTAssertEqual(after.revision, before.revision)
    }
}

import XCTest
@testable import SavageModPlayerCore

final class LibraryQueryTests: XCTestCase {
    private func metadata(_ title: String, format: ModuleFormat = .protracker,
                          channels: Int = 4, duration: Double = 60) -> ModuleMetadata {
        ModuleMetadata(title: title, format: format, channelCount: channels,
                       instrumentCount: 1, sampleCount: 1, patternCount: 1,
                       instrumentNames: ["Synth Lead"], durationSeconds: duration,
                       durationIsLimited: duration >= 600)
    }

    func testSearchMatchesMultipleFieldsAndKeepsSameNamedSourcesDistinct() throws {
        let items = [LibraryQueryItem(id: "a", displayName: "same.mod", folderPath: "Amiga/One",
                                     metadata: metadata("Höhenflug")),
                     LibraryQueryItem(id: "b", displayName: "same.mod", folderPath: "PC/Two",
                                      metadata: metadata("Another", format: .it))]
        var query = LibraryQuery()
        query.search = "hohenflug lead"
        XCTAssertEqual(try query.selectIDs(from: items), ["a"])
        query.search = "pc it"
        XCTAssertEqual(try query.selectIDs(from: items), ["b"])
        query.search = "same"
        XCTAssertEqual(try query.selectIDs(from: items), ["a", "b"])
    }

    func testFavoritesUnheardRecentFormatAndChannelsCombineWithoutInventingUnknownState() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let items = [LibraryQueryItem(id: "match", displayName: "one.it", metadata: metadata("One", format: .it, channels: 16),
                                     addedAt: now, isFavorite: true),
                     LibraryQueryItem(id: "old", displayName: "old.it", metadata: metadata("Old", format: .it, channels: 16),
                                      addedAt: now.addingTimeInterval(-8 * 86_400), isFavorite: true),
                     LibraryQueryItem(id: "heard", displayName: "heard.it", metadata: metadata("Heard", format: .it, channels: 16),
                                      addedAt: now, isFavorite: true, wasPlayed: true),
                     LibraryQueryItem(id: "unknown", displayName: "unknown.it", metadata: metadata("Unknown", format: .it, channels: 16),
                                      addedAt: now, isFavorite: true, wasPlayed: nil)]
        var query = LibraryQuery()
        query.format = .it; query.minimumChannels = 8; query.favoritesOnly = true
        query.unheardOnly = true; query.addedWithinDays = 7
        XCTAssertEqual(try query.selectIDs(from: items, now: now), ["match"])
    }

    func testSortingKeepsUnknownMetadataLastInBothDirectionsAndSourceOrderAsDefault() throws {
        let items = [LibraryQueryItem(id: "unknown", displayName: "Tune1.mod"),
                     LibraryQueryItem(id: "long", displayName: "Tune10.mod", metadata: metadata("Beta", duration: 90)),
                     LibraryQueryItem(id: "short", displayName: "Tune2.mod", metadata: metadata("Alpha", duration: 30))]
        var query = LibraryQuery()
        XCTAssertEqual(try query.selectIDs(from: items), ["unknown", "long", "short"])
        query.sort = .filename
        XCTAssertEqual(try query.selectIDs(from: items), ["unknown", "short", "long"])
        query.sort = .duration
        XCTAssertEqual(try query.selectIDs(from: items), ["short", "long", "unknown"])
        query.reversed = true
        XCTAssertEqual(try query.selectIDs(from: items), ["long", "short", "unknown"])
        query.sort = .title; query.reversed = false
        XCTAssertEqual(try query.selectIDs(from: items), ["short", "long", "unknown"])
    }

    func testLargeCollectionAndCancellationKeepAConcreteOrderedSelection() throws {
        let value = metadata("Indexed", format: .xm, channels: 8)
        let items = (0..<10_000).reversed().map {
            LibraryQueryItem(id: String($0), displayName: "Track\($0).xm", metadata: value)
        }
        var query = LibraryQuery(); query.search = "indexed"; query.sort = .filename
        let ids = try query.selectIDs(from: items)
        XCTAssertEqual(ids.count, 10_000)
        XCTAssertEqual(Array(ids.prefix(3)), ["0", "1", "2"])
        XCTAssertEqual(ids.last, "9999")
        XCTAssertThrowsError(try query.selectIDs(from: items, isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(PlaylistNavigation.adjacentIndex(current: 2, eligible: [2, 0, 1], backwards: false, wrap: true, shuffle: false), 0)
        XCTAssertEqual(PlaylistNavigation.adjacentIndex(current: 0, eligible: [2, 0, 1], backwards: true, wrap: true, shuffle: false), 2)
    }
}

import XCTest
@testable import SavageModPlayerCore

final class TrackQueueTests: XCTestCase {
    private func track(_ name: String) -> PlaylistTrackReference {
        PlaylistTrackReference(source: PlaylistTrackSource(
            location: FileManager.default.temporaryDirectory.appendingPathComponent(name)), displayName: name)
    }

    func testQueuePreservesDuplicatesAndExplicitNextOrder() throws {
        var queue = TrackQueue()
        queue.enqueue(track("a.mod")); queue.enqueue(track("a.mod"))
        queue.enqueue(track("b.xm"), next: true)
        XCTAssertEqual(queue.items.map(\.track.displayName), ["b.xm", "a.mod", "a.mod"])
        XCTAssertEqual(Set(queue.items.map(\.id)).count, 3)
        let firstA = queue.items[1].id
        queue.move(id: firstA, by: -1)
        XCTAssertEqual(queue.items.first?.id, firstA)
        queue.remove(id: firstA)
        XCTAssertEqual(queue.popFirst()?.track.displayName, "b.xm")
        XCTAssertEqual(queue.popFirst()?.track.displayName, "a.mod")
        XCTAssertNil(queue.popFirst())
    }

    func testNavigationStaysInsideExplicitSelectionAndHonorsEdges() {
        let selected = [1, 3, 7]
        XCTAssertEqual(PlaylistNavigation.adjacentIndex(current: 1, eligible: selected,
            backwards: false, wrap: false, shuffle: false), 3)
        XCTAssertNil(PlaylistNavigation.adjacentIndex(current: 7, eligible: selected,
            backwards: false, wrap: false, shuffle: false))
        XCTAssertEqual(PlaylistNavigation.adjacentIndex(current: 7, eligible: selected,
            backwards: false, wrap: true, shuffle: false), 1)
        XCTAssertEqual(PlaylistNavigation.adjacentIndex(current: -1, eligible: selected,
            backwards: true, wrap: false, shuffle: false), 7)
        XCTAssertNil(PlaylistNavigation.adjacentIndex(current: 1, eligible: [],
            backwards: false, wrap: true, shuffle: true))
        for _ in 0..<100 {
            let index = PlaylistNavigation.adjacentIndex(current: 3, eligible: selected,
                backwards: false, wrap: true, shuffle: true)
            XCTAssertTrue(index == 1 || index == 7)
        }
    }

    func testQueuedTrackUsesCurrentPlaylistCopyAfterReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("old.mod")
        let second = directory.appendingPathComponent("new.mod")
        try Data([1]).write(to: first); try Data([1]).write(to: second)
        let reference = track("original.mod")
        let known = [first: reference, second: reference]
        let cachedFirst = try XCTUnwrap(known.first?.key)
        let current = cachedFirst == first ? second : first
        XCTAssertEqual(TrackQueue.playbackURL(for: reference, playlist: [current], references: known), current)
        try FileManager.default.removeItem(at: current)
        XCTAssertEqual(TrackQueue.playbackURL(for: reference, playlist: [current], references: known), cachedFirst)
        try FileManager.default.removeItem(at: cachedFirst)
        XCTAssertNil(TrackQueue.playbackURL(for: reference, playlist: [current], references: known))
    }
}

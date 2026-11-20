import Foundation
import SavageModPlayerCore
import XCTest
@testable import SavageModPlayerApp

final class MacPlaylistNavigationTests: XCTestCase {
    func testExternalQueueTrackReturnsToOriginalSelection() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var navigation = fixture.navigation()
        let playlist = fixture.playlist
        var loaded: [URL] = []
        func load(_ url: URL) -> Bool {
            loaded.append(url)
            return true
        }

        XCTAssertTrue(fixture.next(&navigation, load: load))
        XCTAssertEqual(navigation.currentIndex, -1)
        XCTAssertEqual(navigation.resumeURL, fixture.first)
        XCTAssertTrue(navigation.queue.items.isEmpty)

        XCTAssertTrue(fixture.next(&navigation, load: load))
        XCTAssertEqual(loaded, [fixture.queued, fixture.second])
        XCTAssertNil(navigation.resumeURL)
        XCTAssertTrue(navigation.previous(in: playlist, load: load))
        XCTAssertEqual(loaded.last, fixture.first)
    }

    func testFailedQueueAndPlaylistLoadsCanBeRetried() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var navigation = fixture.navigation()
        let queuedID = navigation.queue.items.first?.id

        XCTAssertFalse(fixture.next(&navigation) { _ in false })
        XCTAssertEqual(navigation.queue.items.first?.id, queuedID)
        XCTAssertEqual(navigation.currentIndex, 0)
        XCTAssertNil(navigation.resumeURL)

        XCTAssertTrue(fixture.next(&navigation) { $0 == fixture.queued })
        XCTAssertFalse(fixture.next(&navigation) { _ in false })
        XCTAssertEqual(navigation.resumeURL, fixture.first)
        XCTAssertFalse(navigation.previous(in: fixture.playlist) { _ in false })
        XCTAssertEqual(navigation.resumeURL, fixture.first)
        XCTAssertTrue(navigation.previous(in: fixture.playlist) { $0 == fixture.first })
        XCTAssertEqual(navigation.currentIndex, 0)
        XCTAssertNil(navigation.resumeURL)
    }

    func testQueueEntryIsKeptIfAudioCannotStart() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var navigation = fixture.navigation()
        let queuedID = navigation.queue.items.first?.id
        XCTAssertFalse(fixture.next(&navigation, startQueuedPlayback: { false }) { $0 == fixture.queued })
        XCTAssertEqual(navigation.queue.items.first?.id, queuedID)
        XCTAssertNil(navigation.resumeURL)
    }

    private struct Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var first: URL { directory.appendingPathComponent("first.mod") }
        var second: URL { directory.appendingPathComponent("second.mod") }
        var queued: URL { directory.appendingPathComponent("queued.mod") }
        var playlist: PlaylistPlaybackNavigation.Playlist {
            .init(urls: [first, second], selection: [first, second], wrap: true, shuffle: false)
        }

        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            do { try Data().write(to: queued) }
            catch { cleanUp(); throw error }
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }

        var reference: PlaylistTrackReference {
            .init(source: .init(location: queued), displayName: "Queued")
        }

        func navigation() -> PlaylistPlaybackNavigation {
            var navigation = PlaylistPlaybackNavigation(currentIndex: 0)
            navigation.queue.enqueue(reference)
            return navigation
        }

        func next(_ navigation: inout PlaylistPlaybackNavigation,
                  startQueuedPlayback: () -> Bool = { true }, load: (URL) -> Bool) -> Bool {
            navigation.next(in: playlist, references: [queued: reference], loadSelection: load,
                            loadQueued: load, startQueuedPlayback: startQueuedPlayback) { track in
                XCTFail("Queue-Quelle fehlt: \(track.displayName)")
            }
        }
    }
}

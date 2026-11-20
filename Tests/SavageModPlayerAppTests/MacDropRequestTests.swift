import Foundation
import SavageModPlayerCore
import XCTest
@testable import SavageModPlayerApp

@MainActor
final class MacDropRequestTests: XCTestCase {
    private let module = URL(fileURLWithPath: "/tmp/delayed.mod")
    private let collection = URL(fileURLWithPath: "/tmp/delayed.savagecollection")

    func testProviderReturningAfterStopCannotStartPlayback() async {
        let actions = PlaybackActions()
        let coordinator = ModPlayerCoordinator()
        let urls = await resolve(module, using: actions) {
            actions.stopPlayback(coordinator: coordinator)
        }
        XCTAssertNil(urls)
    }

    func testProviderReturningAfterNewSelectionIsDiscarded() async {
        let actions = PlaybackActions()
        let urls = await resolve(module, using: actions) {
            actions.beginModuleLoad(origin: .selection)
        }
        XCTAssertNil(urls)
    }

    func testOlderScanCompletionDoesNotDiscardNewDrop() async {
        let actions = PlaybackActions()
        actions.beginFileRequest()
        let urls = await resolve(module, using: actions) {
            actions.beginModuleLoad(origin: .playlistScan)
        }
        XCTAssertEqual(urls, [module])
    }

    func testCollectionDropSurvivesStopAndOrdinaryDropIsAccepted() async {
        let actions = PlaybackActions()
        let coordinator = ModPlayerCoordinator()
        let urls = await resolve(collection, using: actions) {
            actions.stopPlayback(coordinator: coordinator)
        }
        XCTAssertEqual(urls, [collection])
        let next = await resolve(module, using: actions) {}
        XCTAssertEqual(next, [module])
    }

    func testTimerExpiryInvalidatesAnAudioDrop() async {
        let actions = PlaybackActions()
        let coordinator = ModPlayerCoordinator()
        actions.observeSleepTimer(coordinator: coordinator)
        let urls = await resolve(module, using: actions) {
            coordinator.onSleepTimerExpired?()
        }
        XCTAssertNil(urls)
    }

    func testNewDropSupersedesOlderProvider() async {
        let actions = PlaybackActions()
        let second = URL(fileURLWithPath: "/tmp/newer.mod")
        var finishOlder: (@Sendable (URL?) -> Void)?
        let old = expectation(description: "Älterer Drop wurde ausgewertet")
        actions.collectDrop([{ finishOlder = $0 }]) { urls in
            XCTAssertNil(urls)
            old.fulfill()
        }
        let accepted = await resolve(second, using: actions) {}
        XCTAssertEqual(accepted, [second])
        finishOlder?(module)
        await fulfillment(of: [old], timeout: 2)
    }

    private func resolve(_ url: URL, using actions: PlaybackActions, beforeResponse: () -> Void) async -> [URL]? {
        await withCheckedContinuation { result in
            var finish: (@Sendable (URL?) -> Void)?
            actions.collectDrop([{ finish = $0 }]) { result.resume(returning: $0) }
            beforeResponse()
            finish?(url)
        }
    }
}

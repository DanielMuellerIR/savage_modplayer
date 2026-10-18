#if canImport(AVFoundation) && canImport(Combine)
import XCTest
@testable import SavageModPlayerCore

@MainActor
final class SectionLoopCoordinatorTests: XCTestCase {
    private func module() -> Mod {
        Mod(name: "Silent lifecycle", length: 2, patternTable: [0, 0], instruments: [nil],
            patterns: [Pattern(rows: Array(repeating: Row(notes: []), count: 12))],
            channelCount: 1, initialSpeed: 6)
    }

    func testPausedActivationCanBeDisabledBeforeTheFirstCallbackWithoutLosingA() async throws {
        let coordinator = ModPlayerCoordinator()
        coordinator.setVolume(0)
        coordinator.setMod(module())
        defer { coordinator.stop() }
        coordinator.play()
        XCTAssertTrue(coordinator.isPlaying)
        coordinator.pause()
        let section = try XCTUnwrap(SongSection(start: .init(position: 1,row: 3), end: .init(position: 1,row: 4)))
        coordinator.startSectionLoop(section)
        try await wait { coordinator.sectionLoopIsActive || coordinator.sectionLoopError != nil }
        XCTAssertNil(coordinator.sectionLoopError)
        XCTAssertTrue(coordinator.sectionLoopIsActive)
        XCTAssertTrue(coordinator.isPaused)
        XCTAssertEqual(coordinator.currentPosition, 1)
        XCTAssertEqual(coordinator.currentRow, 3)
        coordinator.cancelSectionLoop()
        coordinator.resume()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(coordinator.currentPosition, 1)
        XCTAssertGreaterThanOrEqual(coordinator.currentRow, 3)
        XCTAssertFalse(coordinator.sectionLoopIsActive)
    }

    func testStopAndOptionsRejectLatePreparationAndFailurePreservesPlayback() async throws {
        let coordinator = ModPlayerCoordinator()
        coordinator.setVolume(0)
        coordinator.setMod(module())
        defer { coordinator.stop() }
        let section = try XCTUnwrap(SongSection(start: .init(position: 1,row: 3), end: .init(position: 1,row: 4)))
        coordinator.startSectionLoop(section)
        coordinator.stop()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(coordinator.isPlaying)
        XCTAssertFalse(coordinator.sectionLoopIsPreparing)
        coordinator.startSectionLoop(section)
        coordinator.palClock.toggle()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(coordinator.isPlaying)
        XCTAssertFalse(coordinator.sectionLoopIsPreparing)
        coordinator.play()
        coordinator.startSectionLoop(try XCTUnwrap(SongSection(start: .init(position: 99,row: 0), end: .init(position: 99,row: 1))))
        try await wait { coordinator.sectionLoopError != nil }
        XCTAssertEqual(coordinator.sectionLoopError, .invalidSection)
        XCTAssertTrue(coordinator.isPlaying)
        XCTAssertFalse(coordinator.sectionLoopIsActive)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate())
    }

    func testSleepTimerExpiryRejectsLateSectionPreparation() async throws {
        let coordinator = ModPlayerCoordinator()
        coordinator.setVolume(0)
        coordinator.setMod(module())
        coordinator.sleepTimer.start(minutes: 1)
        let section = try XCTUnwrap(SongSection(start: .init(position: 1, row: 3), end: .init(position: 1, row: 4)))
        coordinator.startSectionLoop(section)
        coordinator.sleepTimer.signal.start(seconds: 0.001, now: SleepTimerClock.now())
        blockMainActorPastDeadline()
        coordinator.sleepTimer.refresh()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(coordinator.sleepTimer.snapshot.phase, .expired)
        XCTAssertFalse(coordinator.sectionLoopIsPreparing)
        XCTAssertFalse(coordinator.sectionLoopIsActive)
        XCTAssertFalse(coordinator.isPlaying)
        coordinator.sleepTimer.cancel()
    }

    private func blockMainActorPastDeadline() { Thread.sleep(forTimeInterval: 0.01) }
}
#endif

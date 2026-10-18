import XCTest
@testable import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class TrackPlaybackSettingsTests: XCTestCase {
    private var root: URL!
    private var settings: PlayerSettings!
    private var original: PlaybackOptions!
    private var preferences: TrackPlaybackSettingsModel!
    private var engine: PlaybackEngine!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TrackSettings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        settings = PlayerSettings(); original = settings.playbackOptions
        settings.setPlaybackOptions(.init())
        preferences = TrackPlaybackSettingsModel(fileURL: root.appendingPathComponent("settings.json"),
            defaults: settings.playbackOptions, saveDefaults: { [weak settings = settings] in settings?.setPlaybackOptions($0) })
        engine = PlaybackEngine(settings: settings, library: LibraryStore(), playbackSettings: preferences)
    }

    override func tearDown() async throws {
        engine.stop(); preferences.flush(); engine = nil; preferences = nil
        settings.setPlaybackOptions(original); settings = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func track(_ name: String) throws -> TrackRef {
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        data[950] = 1; data[43] = 2; data[45] = 64
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        data[1084] = 1; data[1085] = 172; data[1086] = 16
        let url = root.appendingPathComponent(name); try data.write(to: url)
        return TrackRef(relativePath: name, displayName: "same.mod", folderPath: [], url: url)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let end = Date().addingTimeInterval(10)
        while Date()<end {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Titel-Einstellungen wurden nicht rechtzeitig angewandt.")
    }

    func testOverridesApplyBeforePlaybackAndNeverLeakToNextTitle() async throws {
        let a = try track("a.mod"), b = try track("b.mod")
        XCTAssertTrue(preferences.updateTitle(a.relativePath) {
            $0.palClock = false; $0.stereoSeparation = 0.2; $0.useInterpolation = false; $0.ledFilterActive = true
        })
        engine.setQueue([a,b]); engine.play(a)
        try await waitUntil { self.engine.currentTrack==a && self.engine.coordinator.isPlaying }
        XCTAssertFalse(engine.coordinator.palClock); XCTAssertFalse(engine.coordinator.useInterpolation)
        XCTAssertTrue(engine.coordinator.ledFilterActive); XCTAssertEqual(engine.coordinator.stereoSeparation, 0.2, accuracy: 0.0001)
        engine.next()
        try await waitUntil { self.engine.currentTrack==b }
        XCTAssertTrue(engine.coordinator.palClock); XCTAssertTrue(engine.coordinator.useInterpolation)
        XCTAssertFalse(engine.coordinator.ledFilterActive); XCTAssertEqual(engine.coordinator.stereoSeparation, 0.8, accuracy: 0.0001)
        XCTAssertEqual(preferences.sourceID,b.relativePath)
        XCTAssertEqual(settings.playbackOptions,PlaybackOptions())
        engine.select(a);try await waitUntil { self.engine.currentTrack==a }
        let section = try XCTUnwrap(SongSection(start:.init(position:0,row:0),end:.init(position:0,row:1)))
        engine.coordinator.startSectionLoop(section)
        try await waitUntil { self.engine.coordinator.sectionLoopIsActive }
        XCTAssertTrue(preferences.updateTitle(a.relativePath) { $0.useInterpolation = true })
        XCTAssertFalse(engine.coordinator.sectionLoopIsActive)
        XCTAssertTrue(engine.coordinator.useInterpolation)
    }

    func testPausedSwitchDoesNotResumeAndRestoresIndependentValues() async throws {
        let a = try track("a.mod"), b = try track("b.mod")
        XCTAssertTrue(preferences.updateTitle(a.relativePath) { $0.useInterpolation = false })
        engine.setQueue([a,b]); engine.play(a)
        try await waitUntil { self.engine.currentTrack==a && self.engine.coordinator.isPlaying }
        engine.pause(); engine.next()
        try await waitUntil { self.engine.currentTrack==b }
        XCTAssertFalse(engine.coordinator.isPlaying); XCTAssertTrue(engine.coordinator.useInterpolation)
        engine.select(a)
        try await waitUntil { self.engine.currentTrack==a }
        XCTAssertFalse(engine.coordinator.isPlaying); XCTAssertFalse(engine.coordinator.useInterpolation)
    }

    func testGlobalChangesResetAndSleepTimerKeepTheirOwnState() async throws {
        let a = try track("a.mod")
        XCTAssertTrue(preferences.updateTitle(a.relativePath) { $0.useInterpolation = false; $0.stereoSeparation = 0.2 })
        engine.select(a); try await waitUntil { self.engine.currentTrack==a }
        settings.ledFilterActive = true; settings.stereoSeparation = 0.6
        engine.applySettings()
        XCTAssertTrue(engine.coordinator.ledFilterActive)
        XCTAssertFalse(engine.coordinator.useInterpolation); XCTAssertEqual(engine.coordinator.stereoSeparation,0.2,accuracy:0.0001)
        engine.coordinator.sleepTimer.start(minutes:1)
        let deadline = engine.coordinator.sleepTimer.signal.deadline
        preferences.resetTitle(a.relativePath)
        XCTAssertTrue(engine.coordinator.useInterpolation); XCTAssertEqual(engine.coordinator.stereoSeparation,0.6,accuracy:0.0001)
        XCTAssertEqual(engine.coordinator.sleepTimer.signal.deadline,deadline)
        XCTAssertFalse(engine.coordinator.isPlaying)
    }

    func testLateCancelledLoadCannotApplyOldTitleOverrides() async throws {
        let a = try track("a.mod"), b = try track("b.mod")
        XCTAssertTrue(preferences.updateTitle(a.relativePath) { $0.stereoSeparation = 0.1; $0.useInterpolation = false })
        XCTAssertTrue(preferences.updateTitle(b.relativePath) { $0.stereoSeparation = 0.7 })
        let started = expectation(description:"A wartet auf der Ladeschlange")
        let gate = DispatchSemaphore(value:0)
        engine = PlaybackEngine(settings:settings,library:LibraryStore(),playbackSettings:preferences,readModule:{ url in
            if url==a.url { started.fulfill(); gate.wait() }
            return try Data(contentsOf:url)
        })
        engine.select(a)
        await fulfillment(of:[started],timeout:5)
        engine.select(b); gate.signal()
        try await waitUntil { self.engine.currentTrack==b }
        XCTAssertEqual(preferences.sourceID,b.relativePath)
        XCTAssertTrue(engine.coordinator.useInterpolation); XCTAssertEqual(engine.coordinator.stereoSeparation,0.7,accuracy:0.0001)
    }
}

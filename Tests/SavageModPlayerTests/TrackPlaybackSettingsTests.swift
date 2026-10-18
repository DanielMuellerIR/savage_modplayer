import XCTest
@testable import SavageModPlayerCore

final class TrackPlaybackSettingsTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TrackPlaybackSettings-\(UUID().uuidString)")
    }

    func testPartialOverridesPreserveExplicitFalseAndFollowOtherDefaults() {
        let value = TrackPlaybackOverrides(palClock: false, useInterpolation: false)
        let first = value.resolved(defaults: .init(stereoSeparation: 0.2), format: .protracker)
        XCTAssertFalse(first.palClock); XCTAssertFalse(first.useInterpolation)
        XCTAssertEqual(first.stereoSeparation, 0.2); XCTAssertFalse(first.ledFilterActive)
        let second = value.resolved(defaults: .init(stereoSeparation: 0.9, ledFilterActive: true), format: .protracker)
        XCTAssertFalse(second.palClock); XCTAssertFalse(second.useInterpolation)
        XCTAssertEqual(second.stereoSeparation, 0.9); XCTAssertTrue(second.ledFilterActive)
    }

    func testClockOnlyAppliesToMODFamilies() {
        for format in [ModuleFormat.protracker, .soundtracker, .multichannel] {
            XCTAssertTrue(PlaybackOptions.supportsAmigaClock(format))
            XCTAssertFalse(TrackPlaybackOverrides(palClock: false).resolved(defaults: .init(), format: format).palClock)
        }
        for format in [ModuleFormat.s3m, .xm, .it] {
            XCTAssertFalse(PlaybackOptions.supportsAmigaClock(format))
            let effective = TrackPlaybackOverrides(palClock: false, stereoSeparation: 0.3,
                                                  useInterpolation: false, ledFilterActive: true)
                .resolved(defaults: .init(palClock: false), format: format)
            XCTAssertTrue(effective.palClock)
            XCTAssertEqual(effective.stereoSeparation, 0.3)
            XCTAssertFalse(effective.useInterpolation); XCTAssertTrue(effective.ledFilterActive)
        }
    }

    func testUnsafeGlobalSeparationHasFiniteDefaults() {
        for value in [Double.nan, .infinity, -.infinity] { XCTAssertEqual(PlaybackOptions(stereoSeparation: value).stereoSeparation, 0.8) }
        XCTAssertEqual(PlaybackOptions(stereoSeparation: -1).stereoSeparation, 0)
        XCTAssertEqual(PlaybackOptions(stereoSeparation: 2).stereoSeparation, 1)
    }

    func testRestartPreservesAllFourFieldsAndDistinctSourceIdentities() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TrackPlaybackSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        XCTAssertEqual(try store.load(), TrackPlaybackSettingsDocument())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let archive = PlaylistTrackSource(location: root.appendingPathComponent("collection.zip"))
        let ids = [PlaylistTrackSource(location: root.appendingPathComponent("a/song.mod")).id,
                   PlaylistTrackSource(location: root.appendingPathComponent("b/song.mod")).id,
                   archive.appendingArchiveMember("a/song.mod").id,
                   archive.appendingArchiveMember("b/song.mod").id,
                   archive.appendingArchiveMember("nested.zip").appendingArchiveMember("a/song.mod").id,
                   "relative/ä/song.mod"]
        XCTAssertEqual(Set(ids).count, ids.count)
        var document = TrackPlaybackSettingsDocument()
        for (index, id) in ids.enumerated() {
            document.tracks[id] = .init(palClock: false, stereoSeparation: Double(index)/10,
                                        useInterpolation: false, ledFilterActive: true)
        }
        try store.save(document)
        XCTAssertEqual(try TrackPlaybackSettingsStore(fileURL: store.fileURL).load(), document)
        document.tracks.removeValue(forKey: ids[0]); try store.save(document)
        XCTAssertEqual(try store.load(), document)
        XCTAssertEqual(document.tracks[ids[1]]?.stereoSeparation, 0.1)
    }

    func testInvalidSaveDoesNotReplaceExistingSettings() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TrackPlaybackSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        var good = TrackPlaybackSettingsDocument(); good.tracks["a"] = .init(useInterpolation: false)
        try store.save(good); let original = try Data(contentsOf: store.fileURL)
        for separation in [Double.nan, .infinity, -0.1, 1.1] {
            var bad = good; bad.tracks["a"]?.stereoSeparation = separation
            XCTAssertThrowsError(try store.save(bad)); XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        }
        for id in ["", "a\0b", String(repeating: "x", count: 16_385)] {
            var bad = good; bad.tracks[id] = .init(palClock: false)
            XCTAssertThrowsError(try store.save(bad)); XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        }
        var empty = good; empty.tracks["empty"] = TrackPlaybackOverrides()
        XCTAssertThrowsError(try store.save(empty))
        var future = good; future.formatVersion = 2
        XCTAssertThrowsError(try store.save(future)); XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    func testMalformedFutureAndOutOfRangeDocumentsArePreserved() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TrackPlaybackSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for text in ["broken", #"{"formatVersion":2,"tracks":{}}"#,
                     #"{"formatVersion":1,"tracks":{"a":{"stereoSeparation":1.1}}}"#,
                     #"{"formatVersion":1,"tracks":{"a":{"useInterpolation":"false"}}}"#,
                     #"{"formatVersion":1,"tracks":{"a":{}}}"#] {
            let data = Data(text.utf8); try data.write(to: store.fileURL)
            XCTAssertThrowsError(try store.load()); XCTAssertEqual(try Data(contentsOf: store.fileURL), data)
        }
    }

    func testDocumentCountAndByteLimits() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TrackPlaybackSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        var document = TrackPlaybackSettingsDocument()
        document.tracks = Dictionary(uniqueKeysWithValues: (0...TrackPlaybackSettingsStore.maximumTracks).map { (String($0), TrackPlaybackOverrides(palClock: false)) })
        XCTAssertThrowsError(try store.save(document))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: store.fileURL.path, contents: nil))
        let file = try FileHandle(forWritingTo: store.fileURL)
        try file.seek(toOffset: UInt64(TrackPlaybackSettingsStore.maximumBytes))
        try file.write(contentsOf: Data([0])); try file.close()
        XCTAssertThrowsError(try store.load())
    }
}

#if canImport(Combine)
@MainActor
final class TrackPlaybackSettingsModelTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TrackPlaybackSettingsModel-\(UUID().uuidString)")
    }

    func testTitleSwitchGlobalChangesAndResetDoNotLeak() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let model = TrackPlaybackSettingsModel(fileURL: root.appendingPathComponent("settings.json"))
        var published: [PlaybackOptions] = []; model.onResolvedChange = { published.append($0) }
        model.setContext(sourceID: "A", format: .protracker)
        XCTAssertTrue(model.updateTitle("A") { $0.useInterpolation = false; $0.stereoSeparation = 0.2 })
        XCTAssertFalse(model.effective.useInterpolation); XCTAssertEqual(model.effective.stereoSeparation, 0.2)
        model.updateDefaults(.init(palClock: false, stereoSeparation: 0.9, ledFilterActive: true))
        XCTAssertFalse(model.effective.palClock); XCTAssertEqual(model.effective.stereoSeparation, 0.2)
        model.setContext(sourceID: "B", format: .protracker)
        XCTAssertEqual(model.effective, model.defaults)
        model.setContext(sourceID: "A", format: .protracker); model.resetTitle("A")
        XCTAssertEqual(model.effective, model.defaults); XCTAssertNil(model.document.tracks["A"])
        XCTAssertEqual(published.last, model.effective)
    }

    func testQuickControlsEditOnlyExplicitOverridesOrDefaults() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        var savedDefaults: [PlaybackOptions] = []
        let model = TrackPlaybackSettingsModel(fileURL: root.appendingPathComponent("settings.json"), saveDefaults: { savedDefaults.append($0) })
        model.setContext(sourceID: "A", format: .protracker)
        model.setInterpolation(false)
        XCTAssertFalse(model.defaults.useInterpolation); XCTAssertTrue(model.overrides(for: "A").isEmpty)
        XCTAssertEqual(savedDefaults.count, 1)
        XCTAssertTrue(model.updateTitle("A") { $0.useInterpolation = true; $0.palClock = true; $0.ledFilterActive = false })
        model.setInterpolation(false); model.setPALClock(false); model.setFilter(true)
        XCTAssertFalse(model.overrides(for: "A").useInterpolation!)
        XCTAssertFalse(model.overrides(for: "A").palClock!); XCTAssertTrue(model.overrides(for: "A").ledFilterActive!)
        XCTAssertTrue(model.defaults.palClock); XCTAssertFalse(model.defaults.ledFilterActive)
        XCTAssertEqual(savedDefaults.count, 1)
    }

    func testSeparationPreviewFlushesOnTrackSwitchAndSurvivesRestart() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("settings.json")
        let model = TrackPlaybackSettingsModel(fileURL: url)
        model.setContext(sourceID: "A", format: .protracker)
        XCTAssertTrue(model.updateTitle("A") { $0.stereoSeparation = 0.1 })
        for value in [0.2,0.3,0.4] { model.setSeparation(value) }
        XCTAssertEqual(model.effective.stereoSeparation, 0.4)
        XCTAssertEqual(try TrackPlaybackSettingsStore(fileURL: url).load().tracks["A"]?.stereoSeparation, 0.1)
        model.setContext(sourceID: "B", format: .xm)
        XCTAssertEqual(model.effective.stereoSeparation, 0.8)
        let reopened = TrackPlaybackSettingsModel(fileURL: url)
        XCTAssertEqual(reopened.overrides(for: "A").stereoSeparation, 0.4)
        model.resetTitle("A"); XCTAssertTrue(model.overrides(for: "A").isEmpty)
    }

    func testFixedDialogEditsOriginalTitleAndResetPreservesOtherDraft() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let model = TrackPlaybackSettingsModel(fileURL: root.appendingPathComponent("settings.json"))
        model.setContext(sourceID: "A", format: .protracker)
        let context = TrackPlaybackSettingsContext(sourceID: "A", title: "A", format: .protracker, sourceDescription: "folderA/same.mod")
        model.setContext(sourceID: "B", format: .protracker)
        XCTAssertTrue(model.updateTitle(context.sourceID!) { $0.useInterpolation = false })
        XCTAssertTrue(model.effective.useInterpolation)
        XCTAssertTrue(model.updateTitle("B") { $0.stereoSeparation = 0.2 })
        model.previewSeparation(0.6, for: "B"); model.resetTitle("A")
        XCTAssertEqual(model.effective.stereoSeparation, 0.6)
        XCTAssertEqual(model.document.tracks["B"]?.stereoSeparation, 0.6)
        XCTAssertTrue(model.overrides(for: "A").isEmpty)
    }

    func testLoadFailureUsesGlobalsAndNeverOverwritesOriginal() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("settings.json"), original = Data("broken".utf8)
        try original.write(to: url)
        let model = TrackPlaybackSettingsModel(fileURL: url, defaults: .init(stereoSeparation: 0.3))
        XCTAssertEqual(model.issue, .load); XCTAssertFalse(model.canWriteTitles)
        model.setContext(sourceID: "A", format: .protracker)
        XCTAssertFalse(model.updateTitle("A") { $0.useInterpolation = false })
        model.resetTitle("A"); model.previewSeparation(0.5, for: "A")
        XCTAssertEqual(model.effective.stereoSeparation, 0.3)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testFailedSaveRevertsPreviewAndPreservesSavedValue() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("state"), url = folder.appendingPathComponent("settings.json")
        let model = TrackPlaybackSettingsModel(fileURL: url)
        model.setContext(sourceID: "A", format: .protracker)
        XCTAssertTrue(model.updateTitle("A") { $0.stereoSeparation = 0.2 })
        try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent("preserved"))
        try Data([1]).write(to: folder)
        model.previewSeparation(0.6, for: "A")
        XCTAssertEqual(model.effective.stereoSeparation, 0.6)
        XCTAssertFalse(model.flush()); XCTAssertEqual(model.issue, .save)
        XCTAssertEqual(model.effective.stereoSeparation, 0.2)
        XCTAssertEqual(try TrackPlaybackSettingsStore(fileURL: root.appendingPathComponent("preserved/settings.json")).load().tracks["A"]?.stereoSeparation, 0.2)
    }

    func testPreviewIsDebouncedAndCanBeResetBeforeSave() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("settings.json")
        let model = TrackPlaybackSettingsModel(fileURL: url)
        model.setContext(sourceID: "A", format: .protracker)
        XCTAssertTrue(model.updateTitle("A") { $0.stereoSeparation = 0.1 })
        model.previewSeparation(0.7, for: "A")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(try TrackPlaybackSettingsStore(fileURL: url).load().tracks["A"]?.stereoSeparation, 0.7)
        model.previewSeparation(0.5, for: "A"); model.resetTitle("A")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(try TrackPlaybackSettingsStore(fileURL: url).load().tracks["A"])
    }
}
#endif

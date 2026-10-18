import Foundation
import XCTest
@testable import SavageModPlayerCore

final class BatchWAVExporterTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("savage-batch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func source(in root: URL, name: String = "Track.mod") throws -> BatchWAVExportItem {
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        data.replaceSubrange(0..<9, with: Data("Batch MOD".utf8))
        data[43] = 2; data[45] = 64; data[950] = 1
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        data[1084] = 1; data[1085] = 0xAC; data[1086] = 0x10
        data[2108] = 64; data[2109] = 192; data[2110] = 64; data[2111] = 192
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return .init(source: url)
    }

    private var settings: BatchWAVExportSettings {
        .init(audio: .init(sampleRate: 8_000, maximumSeconds: 0.137))
    }

    func testSameNamesGetSeparateOutputsAndRepeatableSettingsAndReport() throws {
        let a = try source(in: directory()), b = try source(in: directory())
        let target = try directory()
        let report = try BatchWAVExporter.export(items: [a, b], to: target, settings: settings)
        XCTAssertEqual(report.results.map(\.status), [.exported, .exported])
        XCTAssertEqual(report.results.map(\.folderName), ["Track.mod", "Track.mod (2)"])
        XCTAssertEqual(report.results[0].audio?.frameCount, 1096)
        XCTAssertEqual(report.results[0].audio?.options, settings.audioWithHeaderDefaults)
        let decoded = try JSONDecoder().decode(BatchWAVExportReport.self,
            from: Data(contentsOf: target.appendingPathComponent(report.reportFileName)))
        XCTAssertEqual(decoded, report)
        let stored = try JSONEncoder().encode(settings)
        let repeatSettings = try JSONDecoder().decode(BatchWAVExportSettings.self, from: stored)
        let second = try BatchWAVExporter.export(items: [a, b], to: directory(), settings: repeatSettings)
        for index in 0..<2 {
            let firstWAV = target.appendingPathComponent(report.results[index].folderName!).appendingPathComponent("Mix.wav")
            XCTAssertTrue(FileManager.default.fileExists(atPath: firstWAV.path))
            XCTAssertEqual(second.results[index].audio, report.results[index].audio)
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: target.path)),
                       ["Track.mod", "Track.mod (2)", report.reportFileName])
    }

    func testSkipAndKeepBothPreserveExistingFilesAndDoNotLoadSkippedSource() throws {
        let target = try directory()
        let existing = target.appendingPathComponent("Track.mod")
        try Data("sentinel".utf8).write(to: existing)
        let absent = BatchWAVExportItem(source: target.appendingPathComponent("missing/Track.mod"))
        let skipped = try BatchWAVExporter.export(items: [absent], to: target, settings: settings)
        XCTAssertEqual(skipped.results[0].status, .skipped)
        var keep = settings; keep.conflictPolicy = .keepBoth
        let source = try source(in: directory())
        let kept = try BatchWAVExporter.export(items: [source], to: target, settings: keep)
        XCTAssertEqual(kept.results[0].status, .exported)
        XCTAssertEqual(kept.results[0].folderName, "Track.mod (2)")
        XCTAssertEqual(try Data(contentsOf: existing), Data("sentinel".utf8))
    }

    func testWorkingCopiesUseStableOriginalNamesInOutputReportsAndProgress() throws {
        let first = try source(in: directory(), name: "\(UUID().uuidString)_Track.mod")
        let second = try source(in: directory(), name: "\(UUID().uuidString)_Track.mod")
        let target = try directory(), values = ProgressValues()
        let a = BatchWAVExportItem(source: first.source, displayName: "Track.mod", sourceDescription: "Collection")
        let b = BatchWAVExportItem(source: second.source, displayName: "Track.mod", sourceDescription: "Collection")
        let report = try BatchWAVExporter.export(items: [a], to: target, settings: settings) { progress in
            XCTAssertEqual(progress.sourceName, "Track.mod")
            values.values.append(progress.fraction)
        }
        XCTAssertEqual(report.results[0].sourceName, "Track.mod")
        XCTAssertEqual(report.results[0].folderName, "Track.mod")
        XCTAssertEqual(report.results[0].status, .exported)
        let repeated = try BatchWAVExporter.export(items: [b], to: target, settings: settings)
        XCTAssertEqual(repeated.results[0].status, .skipped)
        XCTAssertEqual(repeated.results[0].folderName, "Track.mod")
        let encoded = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        XCTAssertFalse(encoded.contains(first.source.lastPathComponent))
        XCTAssertEqual(values.values.last, 1)
    }

    func testLateConflictPreservesTargetAndRemovesOwnStaging() throws {
        let source = try source(in: directory()), target = try directory()
        let sentinel = target.appendingPathComponent("Track.mod")
        let report = try BatchWAVExporter.export(items: [source], to: target, settings: settings) { progress in
            if progress.itemProgress > 0 && progress.itemProgress < 1 && !FileManager.default.fileExists(atPath: sentinel.path) {
                try! Data("late".utf8).write(to: sentinel, options: .withoutOverwriting)
            }
        }
        XCTAssertEqual(report.results[0].status, .skipped)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("late".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: target.path).contains { $0.hasPrefix(".savage-") })
    }

    func testBadSourceDoesNotPreventFollowingTitleAndSourceFilesStayUnchanged() throws {
        let root = try directory(), target = try directory()
        let good = try source(in: root)
        let original = try Data(contentsOf: good.source)
        let bad = root.appendingPathComponent("bad.mod"); try Data([1, 2, 3]).write(to: bad)
        let report = try BatchWAVExporter.export(items: [.init(source: bad), good], to: target, settings: settings)
        XCTAssertEqual(report.results.map(\.status), [.failed, .exported])
        XCTAssertNotNil(report.results[0].detail)
        XCTAssertEqual(try Data(contentsOf: good.source), original)
        XCTAssertEqual(try Data(contentsOf: bad), Data([1, 2, 3]))
    }

    func testOversizedAndNonRegularSourcesFailWithoutPublishing() throws {
        let root = try directory(), target = try directory()
        let large = root.appendingPathComponent("large.mod")
        XCTAssertTrue(FileManager.default.createFile(atPath: large.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(BatchWAVExporter.maximumSourceBytes + 1)); try handle.close()
        let report = try BatchWAVExporter.export(items: [.init(source: large), .init(source: root)], to: target, settings: settings)
        XCTAssertEqual(report.results.map(\.status), [.failed, .failed])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [report.reportFileName])
    }

    func testCancellationKeepsCompletedTitleAndReportsUnstartedTitles() async throws {
        let a = try source(in: directory(), name: "A.mod"), b = try source(in: directory(), name: "B.mod")
        let target = try directory(), settings = settings
        let task = Task.detached {
            try BatchWAVExporter.export(items: [a, b], to: target, settings: settings) { progress in
                if progress.itemIndex == 0 && progress.itemProgress == 1 {
                    // Erst das veröffentlichte Ergebnis abbrechen, nicht die
                    // letzte noch unveröffentlichte Audioblockmeldung.
                    if FileManager.default.fileExists(atPath: target.appendingPathComponent("A.mod/manifest.json").path) {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            }
        }
        let report = try await task.value
        XCTAssertTrue(report.wasCancelled)
        XCTAssertEqual(report.results.map(\.status), [.exported, .notStarted])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("A.mod/Mix.wav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("B.mod").path))
    }

    func testCancellationWithinTitleLeavesNoPartialFilesAndWritesReport() async throws {
        let source = try source(in: directory()), target = try directory(), settings = settings
        let task = Task.detached {
            try BatchWAVExporter.export(items: [source, source], to: target, settings: settings) { progress in
                if progress.itemProgress > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        let report = try await task.value
        XCTAssertTrue(report.wasCancelled)
        XCTAssertEqual(report.results.map(\.status), [.cancelled, .notStarted])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [report.reportFileName])
    }

    func testStemBatchAndMonotonicProgress() throws {
        let source = try source(in: directory()), target = try directory()
        var settings = settings; settings.output = .channelStems
        let values = ProgressValues()
        let report = try BatchWAVExporter.export(items: [source, source], to: target, settings: settings) { values.values.append($0.fraction) }
        XCTAssertEqual(report.results.map(\.status), [.exported, .exported])
        XCTAssertEqual(report.results[0].audio?.channelFiles.count, 4)
        XCTAssertEqual(values.values, values.values.sorted())
        XCTAssertEqual(values.values.first, 0)
        XCTAssertEqual(values.values.last, 1)
        XCTAssertTrue(values.values.allSatisfy { (0...1).contains($0) })
    }

    func testInvalidSelectionSettingsAndDestinationHaveNoEffects() throws {
        let source = try source(in: directory()), target = try directory()
        XCTAssertThrowsError(try BatchWAVExporter.export(items: [], to: target, settings: settings))
        XCTAssertThrowsError(try BatchWAVExporter.export(items: Array(repeating: source, count: 10_001), to: target, settings: settings))
        var invalid = settings; invalid.audio.mutedChannels = [0]
        XCTAssertThrowsError(try BatchWAVExporter.export(items: [source], to: target, settings: invalid))
        invalid = settings; invalid.audio.stereoSeparation = .nan
        XCTAssertThrowsError(try BatchWAVExporter.export(items: [source], to: target, settings: invalid))
        XCTAssertThrowsError(try BatchWAVExporter.export(items: [source], to: source.source, settings: settings))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }
}

private final class ProgressValues: @unchecked Sendable { var values: [Double] = [] }

private extension BatchWAVExportSettings {
    var audioWithHeaderDefaults: ChannelStemExportOptions {
        var options = audio; options.mutedChannels = []; return options
    }
}

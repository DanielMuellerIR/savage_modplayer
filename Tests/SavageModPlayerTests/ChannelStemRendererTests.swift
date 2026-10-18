import Foundation
import XCTest
@testable import SavageModPlayerCore

final class ChannelStemRendererTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("savage-stems-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func module(format: ModuleFormat = .protracker, stereo: Bool = false) -> Mod {
        let sample = Sample(pcm: [0.5, 0.5], loopStart: 0, loopLength: 2, loopType: .forward,
            volume: 64, finetune: 0, rightPCM: stereo ? [-0.5, -0.5] : nil,
            itProperties: .init(c5Speed: 8_000, globalVolume: 64, defaultPanning: nil))
        let instrument = Instrument(index: 1, name: "Synthetic", samples: [sample])
        let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
        var rows = (0..<8).map { _ in Row(notes: [empty, empty]) }
        rows[0] = Row(notes: (0..<2).map { _ in Note(instrument: 1, period: 428, effectId: 0, effectData: 0, key: 60) })
        return Mod(name: "Stem reference", length: 1, patternTable: [0], instruments: [nil, instrument],
            samplePool: [nil, sample], patterns: [Pattern(rows: rows)], channelCount: 2,
            format: format, initialSpeed: 1, initialGlobalVolume: format == .it ? 128 : 64,
            channelPannings: [0, 1])
    }

    private func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }

    private func readWAV(_ url: URL) throws -> (left: [Float], right: [Float]) {
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(Int(uint32(data, 4)) + 8, data.count)
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        var offset = 12
        var result: (left: [Float], right: [Float]) = ([], [])
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let count = Int(uint32(data, offset + 4))
            let start = offset + 8
            XCTAssertLessThanOrEqual(start + count, data.count)
            if id == "fmt " {
                XCTAssertEqual(data[start], 3)
                XCTAssertEqual(data[start + 2], 2)
                XCTAssertEqual(data[start + 14], 32)
            }
            if id == "fact" { XCTAssertEqual(Int(uint32(data, start)) * 8 + start + count + 8, data.count) }
            if id == "data" {
                for frame in 0..<(count / 8) {
                    result.left.append(Float(bitPattern: uint32(data, start + frame * 8)))
                    result.right.append(Float(bitPattern: uint32(data, start + frame * 8 + 4)))
                }
            }
            offset = start + count + (count & 1)
        }
        XCTAssertEqual(offset, data.count)
        return result
    }

    private func verifySum(mod: Mod, options: ChannelStemExportOptions = .init(sampleRate: 8_000, maximumSeconds: 0.137),
                           file: StaticString = #filePath, line: UInt = #line) throws -> ChannelStemExportReport {
        let target = try temporaryDirectory().appendingPathComponent("stems")
        let report = try ChannelStemRenderer.export(mod: mod, to: target, options: options)
        let reference = try readWAV(target.appendingPathComponent(report.referenceMixFile))
        var sumLeft = [Float](repeating: 0, count: reference.left.count)
        var sumRight = sumLeft
        for name in report.channelFiles {
            let stem = try readWAV(target.appendingPathComponent(name))
            XCTAssertEqual(stem.left.count, reference.left.count, file: file, line: line)
            for frame in stem.left.indices {
                sumLeft[frame] += stem.left[frame]
                sumRight[frame] += stem.right[frame]
            }
        }
        for frame in sumLeft.indices {
            // Höchstens 256 IT-Stimmen werden anders gruppiert addiert. Die
            // gemeinsame Skalierung hält den absoluten Fehler unter 1e-5 FS.
            XCTAssertEqual(sumLeft[frame], reference.left[frame], accuracy: 0.00001, file: file, line: line)
            XCTAssertEqual(sumRight[frame], reference.right[frame], accuracy: 0.00001, file: file, line: line)
        }
        let decoded = try JSONDecoder().decode(ChannelStemExportReport.self,
            from: Data(contentsOf: target.appendingPathComponent("manifest.json")))
        XCTAssertEqual(decoded, report, file: file, line: line)
        XCTAssertEqual(reference.left.count, Int(report.frameCount), file: file, line: line)
        return report
    }

    func testStereoOppositionSurvivesChannelExport() throws {
        let target = try temporaryDirectory().appendingPathComponent("stereo")
        let report = try ChannelStemRenderer.export(mod: module(format: .it, stereo: true), to: target,
            options: .init(sampleRate: 8_000, maximumSeconds: 0.05))
        let stem = try readWAV(target.appendingPathComponent(report.channelFiles[0]))
        XCTAssertGreaterThan(stem.left.map(abs).max() ?? 0, 0.1)
        XCTAssertLessThan(stem.right.min() ?? 0, -0.01)
        _ = try verifySum(mod: module(format: .it, stereo: true))
    }

    func testEveryFormatReconstructsMixAndOrdinaryLimitedWAVWithPartialBlock() throws {
        for format in [ModuleFormat.protracker, .s3m, .xm, .it] {
            let mod = module(format: format)
            let target = try temporaryDirectory().appendingPathComponent("reference")
            let report = try ChannelStemRenderer.export(mod: mod, to: target,
                options: .init(sampleRate: 8_000, maximumSeconds: 0.137))
            let mix = try readWAV(target.appendingPathComponent(report.referenceMixFile))
            let baseline = try ModuleRenderer.renderWavData(mod: mod, sampleRate: 8_000,
                maxDurationSeconds: 0.137, normalize: false)
            XCTAssertEqual(mix.left.count, (baseline.count - 44) / 4)
            XCTAssertEqual(report.frameCount, 1096)
            for frame in mix.left.indices {
                for side in 0..<2 {
                    let offset = 44 + frame * 4 + side * 2
                    let original = Int(Int16(bitPattern: UInt16(baseline[offset]) | UInt16(baseline[offset + 1]) << 8))
                    let raw = (side == 0 ? mix.left[frame] : mix.right[frame]) / report.commonGain
                    let reconstructed = Int(Int16(max(-1, min(1, tanh(raw))) * 32767))
                    XCTAssertLessThanOrEqual(abs(original - reconstructed), 1)
                }
            }
            _ = try verifySum(mod: mod)
        }
    }

    func testStreamingStereoMixMatchesOrdinaryOutputForEveryFormat() throws {
        for format in [ModuleFormat.protracker, .s3m, .xm, .it] {
            let mod = module(format: format)
            let target = try temporaryDirectory().appendingPathComponent("mix")
            let report = try ChannelStemRenderer.export(mod: mod, to: target,
                options: .init(sampleRate: 8_000, maximumSeconds: 0.137), output: .stereoMix)
            let mix = try readWAV(target.appendingPathComponent("Mix.wav"))
            let baseline = try ModuleRenderer.renderWavData(mod: mod, sampleRate: 8_000,
                maxDurationSeconds: 0.137, normalize: false)
            XCTAssertEqual(mix.left.count, (baseline.count - 44) / 4)
            XCTAssertTrue(report.channelFiles.isEmpty)
            XCTAssertEqual(report.commonGain, 1)
            for frame in mix.left.indices {
                for side in 0..<2 {
                    let offset = 44 + frame * 4 + side * 2
                    let expected = Int(Int16(bitPattern: UInt16(baseline[offset]) | UInt16(baseline[offset + 1]) << 8))
                    let sample = side == 0 ? mix.left[frame] : mix.right[frame]
                    XCTAssertLessThanOrEqual(abs(expected - Int(Int16(sample * 32767))), 1)
                }
            }
        }
    }

    func testMuteSoloAndNaturalEndKeepSynchronousSilentFiles() throws {
        let target = try temporaryDirectory().appendingPathComponent("muted")
        let options = ChannelStemExportOptions(sampleRate: 8_000, maximumSeconds: 1,
            mutedChannels: [0], soloChannels: [1])
        let report = try ChannelStemRenderer.export(mod: module(), to: target, options: options)
        XCTAssertTrue(report.endedNaturally)
        XCTAssertEqual(report.frameCount, 1280)
        let muted = try readWAV(target.appendingPathComponent(report.channelFiles[0]))
        XCTAssertTrue(muted.left.allSatisfy { $0 == 0 })
        XCTAssertTrue(muted.right.allSatisfy { $0 == 0 })
        _ = try verifySum(mod: module(format: .it), options: options)
    }

    func testModuleHeaderMuteIsPreservedUnlessPlayerStateExplicitlyOverridesIt() throws {
        let base = module(format: .it)
        let mod = Mod(name: "Header mute", length: 1, patternTable: [0], instruments: base.instruments,
            samplePool: base.samplePool, patterns: base.patterns, channelCount: 2, format: .it,
            initialSpeed: 1, initialGlobalVolume: 128, channelDisabled: [true, false])
        let parent = try temporaryDirectory()
        let preserved = try ChannelStemRenderer.export(mod: mod, to: parent.appendingPathComponent("default"),
            options: .init(sampleRate: 8_000, maximumSeconds: 0.05))
        let unmuted = try ChannelStemRenderer.export(mod: mod, to: parent.appendingPathComponent("override"),
            options: .init(sampleRate: 8_000, maximumSeconds: 0.05, mutedChannels: []))
        XCTAssertEqual(preserved.unscaledChannelPeaks[0], 0)
        XCTAssertEqual(preserved.options.mutedChannels, [0])
        XCTAssertEqual(unmuted.options.mutedChannels, [])
        XCTAssertGreaterThan(unmuted.unscaledChannelPeaks[0], 0.1)
    }

    func testFullITVoicePoolRandomPanningAndSurroundShareOneGain() throws {
        let base = module(format: .it, stereo: true)
        let mapping = try NoteSampleMapping(entries: try (0..<120).map {
            try NoteSampleMapping.Entry(targetNote: $0, sampleID: 1)
        })
        let properties = ITInstrumentProperties(newNoteAction: .continuePlaying,
            duplicateCheckType: .off, duplicateCheckAction: .cut, globalVolume: 128,
            defaultPanning: nil, pitchPanSeparation: 0, pitchPanCenter: 60,
            randomVolumeVariation: 20, randomPanningVariation: 20,
            initialFilterCutoff: 80, initialFilterResonance: 20)
        let instrument = Instrument(index: 1, name: "NNA stereo", samples: base.instruments[1]!.samples,
            noteSampleMapping: mapping, itProperties: properties)
        let moduleProperties = ITModuleProperties(createdWithVersion: 0x0214, compatibleWithVersion: 0x0214,
            usesInstruments: true, stereo: true, volumeZeroMixOptimization: false, linearSlides: true,
            patternHighlight: 0, mixVolume: 96, panSeparation: 128, pitchWheelDepth: 0,
            hasSongMessage: false, songMessageLength: 0, songMessageOffset: 0,
            usesMIDIPitchController: false, hasEmbeddedMIDIConfiguration: false,
            unknownHeaderFlags: 0, unknownSpecialFlags: 0)
        let rows = (0..<8).map { row in
            Row(notes: (0..<64).map { channel in
                Note(instrument: 1, period: 0,
                     effectId: row == 2 && channel == 0 ? ModuleEffect.impulseTrackerCommand(19) : 0,
                     effectData: row == 2 && channel == 0 ? 0x91 : 0, key: 48 + (row + channel) % 12)
            })
        }
        let mod = Mod(name: "Full stereo IT pool", length: 1, patternTable: [0],
            instruments: [nil, instrument], samplePool: base.samplePool, patterns: [Pattern(rows: rows)],
            channelCount: 64, format: .it, initialSpeed: 1, initialGlobalVolume: 128,
            linearFrequency: true, itProperties: moduleProperties)
        let channels = RenderEngine.makeRenderChannels(for: mod)
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: 8_000)
        let visualization = RealtimeVisualizationExchange(channelCapacity: 64)
        let block = RenderEngine.createRenderBlock(state: state, vuBuffer: visualization.makeVUBuffer(),
            waveBuffer: visualization.makeWaveBuffer(), dspChannels: channels, mod: mod, sampleRate: 8_000)
        let buffer = StereoRenderBuffer(capacity: 640)
        block(640, buffer.left, buffer.right)
        XCTAssertEqual(channels.first?.itVoicePool?.activeVoiceCount, 256)
        let report = try verifySum(mod: mod, options: .init(sampleRate: 8_000, maximumSeconds: 1))
        XCTAssertEqual(report.channelFiles.count, 64)
        XCTAssertTrue(report.endedNaturally)
        XCTAssertLessThan(report.commonGain, 1)
        let peak = max(report.unscaledMixPeak, report.unscaledChannelPeaks.max() ?? 0)
        XCTAssertEqual(peak * report.commonGain, 0.98, accuracy: 0.000001)
    }

    func testPatternLoopsDelaysAndFractionalTempoEndAtOrdinaryRendererFrame() throws {
        let base = module()
        let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
        var rows = base.patterns[0].rows
        for (row, effect, value) in [(1, 0xE6, 0), (3, 0xE6, 2), (4, 0xF, 150), (6, 0xEE, 2)] {
            rows[row] = Row(notes: [Note(instrument: 0, period: 0, effectId: effect, effectData: value), empty])
        }
        let mod = Mod(name: "Timing", length: 1, patternTable: [0], instruments: base.instruments,
            patterns: [Pattern(rows: rows)], channelCount: 2, initialSpeed: 1)
        let report = try verifySum(mod: mod, options: .init(sampleRate: 8_000, maximumSeconds: 1))
        let ordinary = try ModuleRenderer.renderWavData(mod: mod, sampleRate: 8_000, maxDurationSeconds: 1, normalize: false)
        XCTAssertEqual(report.frameCount, UInt64((ordinary.count - 44) / 4))
        XCTAssertTrue(report.endedNaturally)
        XCTAssertGreaterThan(report.frameCount, 1280)
        XCTAssertNotEqual(report.frameCount % 1024, 0)
    }

    func testInvalidParametersAndDisappearingStagingFailWithoutPublishing() throws {
        let parent = try temporaryDirectory()
        let target = parent.appendingPathComponent("bad")
        #if os(Linux)
        // Darwin entfernt diesen Null-Abschnitt bereits beim Aufbau der URL.
        XCTAssertThrowsError(try ChannelStemRenderer.export(mod: module(), to: target.appendingPathComponent("\0"))) {
            XCTAssertEqual($0 as? ChannelStemExportError, .invalidDestination)
        }
        #endif
        for options in [ChannelStemExportOptions(sampleRate: .nan), .init(sampleRate: 8_000.5),
                        .init(maximumSeconds: .infinity), .init(stereoSeparation: .nan), .init(mutedChannels: [2])] {
            XCTAssertThrowsError(try ChannelStemRenderer.export(mod: module(), to: target, options: options))
        }
        XCTAssertThrowsError(try ChannelStemRenderer.export(mod: module(), to: target,
            options: .init(sampleRate: 8_000, maximumSeconds: 0.137), progress: { value in
                if value == 0.5 {
                    for item in (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? [] {
                        if item.lastPathComponent.hasPrefix(".savage-stems-") { try? FileManager.default.removeItem(at: item) }
                    }
                }
            }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), [])
    }

    func testExistingAndLateDestinationConflictsPreserveUserFilesAndRemoveStaging() throws {
        let parent = try temporaryDirectory()
        let target = parent.appendingPathComponent("existing")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let sentinel = target.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        XCTAssertThrowsError(try ChannelStemRenderer.export(mod: module(), to: target)) {
            XCTAssertEqual($0 as? ChannelStemExportError, .destinationExists)
        }
        let late = parent.appendingPathComponent("late")
        XCTAssertThrowsError(try ChannelStemRenderer.export(mod: module(), to: late,
            options: .init(sampleRate: 8_000, maximumSeconds: 0.137), progress: { value in
                if value >= 0.5 {
                    try? FileManager.default.createDirectory(at: late, withIntermediateDirectories: false)
                    try? Data("late user data".utf8).write(to: late.appendingPathComponent("keep.txt"))
                }
            })) { XCTAssertEqual($0 as? ChannelStemExportError, .destinationExists) }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: late.appendingPathComponent("keep.txt")), Data("late user data".utf8))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: parent.path)), ["existing", "late"])
    }

    func testCancellationDuringWritingRemovesOnlyOwnTemporaryOutput() async throws {
        let parent = try temporaryDirectory()
        let target = parent.appendingPathComponent("cancelled")
        let mod = module()
        let task = Task.detached {
            try ChannelStemRenderer.export(mod: mod, to: target,
                options: .init(sampleRate: 8_000, maximumSeconds: 1), progress: { value in
                    if value >= 0.5 { withUnsafeCurrentTask { $0?.cancel() } }
                })
        }
        do { _ = try await task.value; XCTFail("Cancelled export succeeded") }
        catch is CancellationError { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), [])
    }
}

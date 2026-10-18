import Foundation
import XCTest
@testable import SavageModPlayerCore

final class NoteRainVideoTests: XCTestCase {
    func testQualityKeepsPreviousOptionsReadableAndBoundsRequestedBitRate() throws {
        let options = NoteRainVideoOptions()
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any])
        encoded.removeValue(forKey: "quality")
        let old = try JSONDecoder().decode(NoteRainVideoOptions.self, from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertEqual(old, options)
        for (width, height) in [(640, 360), (1280, 720), (1920, 1080)] {
            for rate in [24, 25, 30, 60] {
                var high = NoteRainVideoOptions(width: width, height: height, framesPerSecond: rate)
                let highRate = high.videoBitRate
                high.quality = .compact
                XCTAssertLessThan(high.videoBitRate, highRate)
                XCTAssertTrue((600_000...24_000_000).contains(high.videoBitRate))
                XCTAssertTrue((600_000...24_000_000).contains(highRate))
            }
        }
    }
    func testIntegerClockCoversEveryAudioFrameWithoutDriftOrOverflow() throws {
        for rate in [24, 25, 30, 60] {
            let clock = try NoteRainVideoClock(framesPerSecond: rate)
            XCTAssertEqual(try clock.sampleFrame(forVideoFrame: UInt64(rate)), 48_000)
            for audioFrames in [UInt64(0), 1, 799, 800, 1_599, 1_600, 1_601, 47_877, 48_000, 48_001, 172_800_000, .max] {
                let count = clock.videoFrameCount(audioFrames: audioFrames)
                if count == 0 { XCTAssertEqual(audioFrames, 0); continue }
                let last = try clock.sampleFrame(forVideoFrame: count - 1)
                XCTAssertLessThan(last, audioFrames)
                XCTAssertLessThanOrEqual(audioFrames - last, clock.samplesPerVideoFrame)
            }
            XCTAssertThrowsError(try clock.sampleFrame(forVideoFrame: .max))
        }
    }

    func testOptionsRejectInvalidDimensionsClocksAudioAndRangesBeforeAllocation() throws {
        XCTAssertEqual(try NoteRainVideoOptions().validate(channelCount: 4), 28_800_000)
        XCTAssertEqual(NoteRainVideoOptions().keyRange, 0...119)
        var options = NoteRainVideoOptions()
        options.audio.maximumSeconds = 3600
        XCTAssertEqual(try options.validate(channelCount: 4), 172_800_000)
        let invalid: [(inout NoteRainVideoOptions) -> Void] = [
            { $0.width = .max }, { $0.width = 321 }, { $0.height = .min }, { $0.height = 181 },
            { $0.framesPerSecond = 0 }, { $0.framesPerSecond = .max }, { $0.lookaheadSeconds = .max },
            { $0.keyRange = Int.min...Int.max }, { $0.keyRange = 12...15 },
            { $0.audio.sampleRate = .nan }, { $0.audio.sampleRate = 44_100 },
            { $0.audio.maximumSeconds = .nan }, { $0.audio.maximumSeconds = .infinity },
            { $0.audio.maximumSeconds = 0 }, { $0.audio.maximumSeconds = 3600.1 },
            { $0.audio.stereoSeparation = .nan }, { $0.audio.stereoSeparation = -0.1 },
            { $0.audio.mutedChannels = [4] }, { $0.audio.soloChannels = [-1] }
        ]
        for mutate in invalid {
            var candidate = options; mutate(&candidate)
            XCTAssertThrowsError(try candidate.validate(channelCount: 4)) {
                XCTAssertEqual($0 as? NoteRainVideoError, .invalidOptions)
            }
        }
    }

    func testAudioAdapterMatchesExistingPCMSourceForAllFormatsAndPartialBlock() throws {
        for format in VideoTestModules.formats {
            let mod = VideoTestModules.module(format)
            let options = ChannelStemExportOptions(sampleRate: 48_000, maximumSeconds: 0.137)
            let audio = NoteRainVideoAudio(mod: mod, options: options, maximumFrames: 6_577)
            let reference = ModulePCMSource(mod: mod, format: PCMFormat(sampleRate: 48_000, channels: 2), maxFrames: 6_577).renderBlock()
            var actual = [Float](repeating: 0, count: 8192), expected = actual
            while true {
                let count = try actual.withUnsafeMutableBufferPointer { try audio.read(into: $0) }
                let expectedCount = expected.withUnsafeMutableBufferPointer { reference($0, 4096) }
                XCTAssertEqual(count, expectedCount, format.rawValue)
                if count == 0 { break }
                XCTAssertTrue(actual.prefix(count * 2).elementsEqual(expected.prefix(count * 2)), format.rawValue)
            }
            XCTAssertEqual(audio.frames, 6_577)
            XCTAssertFalse(audio.endedNaturally)
        }
    }

    func testAudioOptionsAndMuteSoloMatchExistingFloatWAVExporter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-audio-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for format in VideoTestModules.formats {
            let mod = VideoTestModules.module(format)
            let options = ChannelStemExportOptions(sampleRate: 48_000, maximumSeconds: 0.137, stereoSeparation: 0.31,
                useInterpolation: false, palClock: false, mutedChannels: [0], soloChannels: [1])
            let destination = root.appendingPathComponent(format.rawValue)
            let reference = try ChannelStemRenderer.export(mod: mod, to: destination, options: options, output: .stereoMix)
            let audio = NoteRainVideoAudio(mod: mod, options: options, maximumFrames: 6_576)
            var samples = [Float](repeating: 0, count: 8192), actual = Data()
            while true {
                let count = try samples.withUnsafeMutableBufferPointer { try audio.read(into: $0) }
                if count == 0 { break }
                samples.withUnsafeBytes { actual.append(contentsOf: $0.prefix(count * 8)) }
            }
            XCTAssertEqual(audio.frames, reference.frameCount)
            XCTAssertEqual(actual, try VideoTestModules.wavePCM(destination.appendingPathComponent("Mix.wav")), format.rawValue)
        }
    }
}

enum VideoTestModules {
    static let formats: [ModuleFormat] = [.protracker, .soundtracker, .multichannel, .s3m, .xm, .it]
    static func module(_ format: ModuleFormat = .protracker) -> Mod {
        let sample = Sample(pcm: [0.5, -0.5], loopStart: 0, loopLength: 2, loopType: .forward, volume: 64, finetune: 0,
            rightPCM: format == .it ? [-0.5, 0.5] : nil, itProperties: .init(c5Speed: 8_000, globalVolume: 64, defaultPanning: nil))
        let instrument = Instrument(index: 1, name: "Synthetic", samples: [sample])
        let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
        var rows = (0..<8).map { _ in Row(notes: [empty, empty]) }
        rows[0] = Row(notes: (0..<2).map { _ in Note(instrument: 1, period: 428, effectId: 0, effectData: 0, key: 60) })
        return Mod(name: "Video reference", length: 1, patternTable: [0], instruments: [nil, instrument], samplePool: [nil, sample],
            patterns: [Pattern(rows: rows)], channelCount: 2, format: format, initialSpeed: 1,
            initialGlobalVolume: format == .it ? 128 : 64, channelPannings: [0, 1])
    }
    static func longModule() -> Mod {
        let base = module(.xm)
        return Mod(name: "Long video reference", length: 256, patternTable: [Int](repeating: 0, count: 256),
            instruments: base.instruments, samplePool: base.samplePool, patterns: base.patterns,
            channelCount: 2, format: .xm, initialSpeed: 1, channelPannings: [0, 1])
    }
    static func nna(channelCount: Int = 2, rowCount: Int = 3, tempo: Int = 125) throws -> Mod {
        let sample = Sample(pcm: [0.25, -0.25, 0.25, -0.25], loopStart: 0, loopLength: 4, loopType: .forward,
            volume: 64, finetune: 0, itProperties: .init(c5Speed: 8_000, globalVolume: 64, defaultPanning: nil))
        let mapping = try NoteSampleMapping(entries: (0..<120).map { try .init(targetNote: min(119, $0 + 12), sampleID: 1) })
        let properties = ITInstrumentProperties(newNoteAction: .continuePlaying, duplicateCheckType: .off,
            duplicateCheckAction: .cut, globalVolume: 128, defaultPanning: nil, pitchPanSeparation: 0,
            pitchPanCenter: 60, randomVolumeVariation: 0, randomPanningVariation: 0,
            initialFilterCutoff: nil, initialFilterResonance: nil)
        let instrument = Instrument(index: 1, name: "NNA", samples: [sample], noteSampleMapping: mapping, itProperties: properties)
        let moduleProperties = ITModuleProperties(createdWithVersion: 0x0214, compatibleWithVersion: 0x0214, usesInstruments: true,
            stereo: true, volumeZeroMixOptimization: false, linearSlides: true, patternHighlight: 0,
            mixVolume: 64, panSeparation: 128, pitchWheelDepth: 0, hasSongMessage: false, songMessageLength: 0,
            songMessageOffset: 0, usesMIDIPitchController: false, hasEmbeddedMIDIConfiguration: false,
            unknownHeaderFlags: 0, unknownSpecialFlags: 0)
        let rows = (0..<rowCount).map { row in
            Row(notes: (0..<channelCount).map { channel in
                if channelCount == 2 {
                    return channel == 1 && row < 2 ? Note(instrument: 1, period: 0, effectId: 0, effectData: 0, key: row == 0 ? 48 : 52)
                        : Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
                }
                return Note(instrument: 1, period: 0, effectId: 0, effectData: 0, key: 48 + (row + channel) % 12)
            })
        }
        return Mod(name: "Mapped NNA", length: 1, patternTable: [0], instruments: [nil, instrument], samplePool: [nil, sample],
            patterns: [Pattern(rows: rows)], channelCount: channelCount, format: .it,
            initialSpeed: tempo > 255 ? 1 : 6, initialTempo: tempo, initialGlobalVolume: 128,
            linearFrequency: true, itProperties: moduleProperties)
    }
    static func wavePCM(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard data.count >= 12, data[0..<4] == Data("RIFF".utf8), data[8..<12] == Data("WAVE".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        var offset = 12
        while offset + 8 <= data.count {
            let size = (0..<4).reduce(0) { $0 | Int(data[offset + 4 + $1]) << ($1 * 8) }
            guard size <= data.count - offset - 8 else { throw CocoaError(.fileReadCorruptFile) }
            if data[offset..<offset + 4] == Data("data".utf8) { return Data(data[offset + 8..<offset + 8 + size]) }
            offset += 8 + size + size % 2
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}

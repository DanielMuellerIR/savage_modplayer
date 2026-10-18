#if os(macOS)
import XCTest
import AVFoundation
import CoreMedia
import CoreGraphics
@testable import SavageModPlayerCore

@MainActor
final class NoteRainVideoRendererTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-renderer-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func options(seconds: Double = 0.137, rate: Int = 30) -> NoteRainVideoOptions {
        var options = NoteRainVideoOptions(width: 320, height: 180, framesPerSecond: rate, lookaheadSeconds: 2)
        options.audio.maximumSeconds = seconds
        return options
    }
    private func noStaging(_ root: URL) throws {
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".savage-video-") })
    }
    private func audio(_ url: URL) async throws -> (pcm: Data, frames: Int, duration: Int64) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false])
        reader.add(output); XCTAssertTrue(reader.startReading())
        var data = Data(), frames = 0
        while let sample = output.copyNextSampleBuffer() {
            frames += CMSampleBufferGetNumSamples(sample)
            let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
            var bytes = Data(count: CMBlockBufferGetDataLength(block))
            let status = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }
            XCTAssertEqual(status, noErr); data.append(bytes)
        }
        XCTAssertEqual(reader.status, .completed, reader.error?.localizedDescription ?? "")
        let range = try await track.load(.timeRange)
        return (data, frames, CMTimeConvertScale(range.duration, timescale: 48_000, method: .default).value)
    }
    private func video(_ url: URL) async throws -> (frames: [Int64], duration: Int64) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output); XCTAssertTrue(reader.startReading())
        var frames: [Int64] = []
        while let sample = output.copyNextSampleBuffer() {
            // Leere Steuerpuffer markieren unter anderem den Schnitt am Trackende.
            guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
            frames.append(CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(sample), timescale: 48_000, method: .default).value)
        }
        XCTAssertEqual(reader.status, .completed, reader.error?.localizedDescription ?? "")
        let range = try await track.load(.timeRange)
        return (frames, CMTimeConvertScale(range.duration, timescale: 48_000, method: .default).value)
    }

    func testPartialFinalImageEndsOnTheExactAudioSample() async throws {
        let root = try directory(), destination = root.appendingPathComponent("partial.mov")
        let report = try NoteRainVideoRenderer.export(mod: VideoTestModules.module(), to: destination,
            options: options(seconds: 1_001.25 / 48_000))
        let audio = try await audio(destination), video = try await video(destination)
        XCTAssertEqual(report.audioFrameCount, 1_001); XCTAssertEqual(report.videoFrameCount, 1)
        XCTAssertEqual(audio.frames, 1_001); XCTAssertEqual(audio.duration, 1_001)
        XCTAssertEqual(video.frames, [0]); XCTAssertEqual(video.duration, 1_001)
        try noStaging(root)
    }

    func testCompressionChoicesPreserveAudioAndExactTrackEndsAtFullHD() async throws {
        let root = try directory(), mod = VideoTestModules.module(.it)
        var reference: Data?
        for quality in NoteRainVideoQuality.allCases {
            var options = NoteRainVideoOptions(width: 1920, height: 1080, framesPerSecond: 60, quality: quality)
            options.audio.maximumSeconds = 0.137
            let url = root.appendingPathComponent(quality.rawValue + ".mov")
            let report = try NoteRainVideoRenderer.export(mod: mod, to: url, options: options)
            let audio = try await audio(url), video = try await video(url)
            if let reference { XCTAssertEqual(audio.pcm, reference) } else { reference = audio.pcm }
            XCTAssertEqual(report.options.quality, quality)
            XCTAssertEqual(audio.duration, Int64(report.audioFrameCount))
            XCTAssertEqual(video.duration, audio.duration)
            XCTAssertEqual(video.frames.count, Int(report.videoFrameCount))
        }
        try noStaging(root)
    }

    func testFourFormatsAndFrameRatesKeepLosslessControlledAudioAndTimestamps() async throws {
        let root = try directory()
        for (format, rate) in zip([ModuleFormat.protracker, .s3m, .xm, .it], [24, 25, 30, 60]) {
            let mod = VideoTestModules.module(format)
            var options = options(rate: rate)
            options.audio.stereoSeparation = 0.31; options.audio.palClock = false; options.audio.useInterpolation = false
            options.audio.mutedChannels = [0]; options.audio.soloChannels = [1]
            let referenceURL = root.appendingPathComponent(format.rawValue + "-reference")
            let reference = try ChannelStemRenderer.export(mod: mod, to: referenceURL, options: options.audio, output: .stereoMix)
            let destination = root.appendingPathComponent(format.rawValue + ".mov")
            let report = try NoteRainVideoRenderer.export(mod: mod, to: destination, options: options)
            let audio = try await audio(destination), video = try await video(destination)
            XCTAssertEqual(report.audioFrameCount, reference.frameCount)
            XCTAssertEqual(audio.pcm, try VideoTestModules.wavePCM(referenceURL.appendingPathComponent("Mix.wav")))
            XCTAssertEqual(audio.frames, Int(reference.frameCount)); XCTAssertEqual(audio.duration, Int64(reference.frameCount))
            XCTAssertEqual(video.duration, audio.duration)
            XCTAssertEqual(video.frames, (0..<Int(report.videoFrameCount)).map { Int64($0 * (48_000 / rate)) })
        }
        try noStaging(root)
    }

    func testNaturalEndClosesBothTracksWithoutRestartAudio() async throws {
        let root = try directory(), destination = root.appendingPathComponent("natural.mov")
        let report = try NoteRainVideoRenderer.export(mod: VideoTestModules.module(), to: destination, options: options(seconds: 2))
        XCTAssertTrue(report.endedNaturally); XCTAssertEqual(report.audioFrameCount, 7_680); XCTAssertEqual(report.videoFrameCount, 5)
        let audio = try await audio(destination), video = try await video(destination)
        XCTAssertEqual(audio.duration, 7_680); XCTAssertEqual(video.duration, 7_680); XCTAssertEqual(audio.frames, 7_680)
        try noStaging(root)
    }

    func testExistingLateAndDanglingDestinationsRemainUntouched() throws {
        let root = try directory(), sentinel = Data("retained original".utf8)
        let existing = root.appendingPathComponent("existing.mov")
        try sentinel.write(to: existing)
        XCTAssertThrowsError(try NoteRainVideoRenderer.export(mod: VideoTestModules.module(), to: existing, options: options())) {
            XCTAssertEqual($0 as? NoteRainVideoError, .destinationExists)
        }
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        let link = root.appendingPathComponent("dangling.mov")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: root.appendingPathComponent("absent").path)
        XCTAssertThrowsError(try NoteRainVideoRenderer.export(mod: VideoTestModules.module(), to: link, options: options())) {
            XCTAssertEqual($0 as? NoteRainVideoError, .destinationExists)
        }
        XCTAssertTrue(try FileManager.default.destinationOfSymbolicLink(atPath: link.path).hasSuffix("absent"))
        let race = root.appendingPathComponent("race.mov")
        XCTAssertThrowsError(try NoteRainVideoRenderer.export(mod: VideoTestModules.module(), to: race, options: options()) { value in
            if value == 0 { try? sentinel.write(to: race, options: .atomic) }
        }) { XCTAssertEqual($0 as? NoteRainVideoError, .destinationExists) }
        XCTAssertEqual(try Data(contentsOf: race), sentinel)
        try noStaging(root)
    }

    func testCancellationBeforeDuringAndAfterPublicationPreservesTheCommitPoint() async throws {
        let root = try directory(), mod = VideoTestModules.module()
        let beforeURL = root.appendingPathComponent("before.mov"), beforeOptions = options()
        let before = Task.detached { [mod, beforeURL, beforeOptions] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try NoteRainVideoRenderer.export(mod: mod, to: beforeURL, options: beforeOptions)
        }
        do { _ = try await before.value; XCTFail("Initial cancellation ignored") } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: beforeURL.path))
        let duringURL = root.appendingPathComponent("during.mov"), duringOptions = options(seconds: 30)
        let duringMod = VideoTestModules.longModule()
        let during = Task.detached { [duringMod, duringURL, duringOptions] in
            try NoteRainVideoRenderer.export(mod: duringMod, to: duringURL, options: duringOptions) { value in
                if value > 0 && value < 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await during.value; XCTFail("Mid-export cancellation ignored") } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: duringURL.path))
        let committedURL = root.appendingPathComponent("committed.mov"), committedOptions = options()
        let committed = Task.detached { [mod, committedURL, committedOptions] in
            try NoteRainVideoRenderer.export(mod: mod, to: committedURL, options: committedOptions) { value in
                if value == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        let report = try await committed.value
        XCTAssertGreaterThan(report.audioFrameCount, 0); XCTAssertTrue(FileManager.default.fileExists(atPath: committedURL.path))
        try noStaging(root)
    }

    func testMappedITBackgroundVoicesKeepLogicalMuteAndLosslessAudio() async throws {
        let root = try directory(), mod = try VideoTestModules.nna()
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: 48_000)
        let simulation = NotePreviewSimulation(configuration: .init(mod: mod, sampleRate: 48_000, state: state))
        try simulation.advance(to: 14_000, commands: [])
        let notes = simulation.snapshot(since: 0).notes
        XCTAssertEqual(notes.map(\.key), [60, 64]); XCTAssertEqual(notes.map(\.channel), [1, 1])
        XCTAssertGreaterThan(notes[0].end, notes[1].start)
        var options = options(seconds: 1)
        let reference = root.appendingPathComponent("nna-reference")
        let expected = try ChannelStemRenderer.export(mod: mod, to: reference, options: options.audio, output: .stereoMix)
        let file = root.appendingPathComponent("nna.mov")
        let report = try NoteRainVideoRenderer.export(mod: mod, to: file, options: options)
        XCTAssertTrue(report.endedNaturally); XCTAssertEqual(report.audioFrameCount, expected.frameCount)
        let result = try await audio(file)
        XCTAssertEqual(result.pcm, try VideoTestModules.wavePCM(reference.appendingPathComponent("Mix.wav")))
        options.audio.mutedChannels = [1]
        let mutedFile = root.appendingPathComponent("nna-muted.mov")
        let muted = try NoteRainVideoRenderer.export(mod: mod, to: mutedFile, options: options)
        let silence = try await audio(mutedFile)
        XCTAssertEqual(muted.audioFrameCount, report.audioFrameCount)
        XCTAssertEqual(silence.pcm, Data(count: silence.frames * 8))
        try noStaging(root)
    }

    func testTempoPatternLoopDelayAndJumpMatchTheExistingRenderer() async throws {
        let root = try directory(), empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
        func note(_ period: Int) -> Note { Note(instrument: 1, period: period, effectId: 0, effectData: 0) }
        func effect(_ id: Int, _ data: Int) -> Note { Note(instrument: 0, period: 0, effectId: id, effectData: data) }
        let mod = Mod(name: "Video flow", length: 2, patternTable: [0, 1], instruments: VideoTestModules.module().instruments,
            patterns: [Pattern(rows: [Row(notes: [note(428), effect(0xE6, 0)]), Row(notes: [note(381), effect(0xE6, 1)]),
                Row(notes: [note(339), effect(0x0F, 3)]), Row(notes: [note(320), effect(0x0F, 150)]),
                Row(notes: [empty, effect(0xEE, 2)]), Row(notes: [effect(0x0B, 1), effect(0x0D, 2)])]),
                Pattern(rows: [Row(notes: [empty, empty]), Row(notes: [empty, empty]), Row(notes: [note(285), empty]), Row(notes: [empty, empty])])], channelCount: 2)
        let options = options(seconds: 2, rate: 25), reference = root.appendingPathComponent("flow-reference")
        let expected = try ChannelStemRenderer.export(mod: mod, to: reference, options: options.audio, output: .stereoMix)
        let file = root.appendingPathComponent("flow.mov")
        let report = try NoteRainVideoRenderer.export(mod: mod, to: file, options: options)
        XCTAssertTrue(report.endedNaturally); XCTAssertEqual(report.audioFrameCount, expected.frameCount)
        let audio = try await audio(file), video = try await video(file)
        XCTAssertEqual(audio.pcm, try VideoTestModules.wavePCM(reference.appendingPathComponent("Mix.wav")))
        XCTAssertEqual(video.duration, Int64(expected.frameCount)); XCTAssertEqual(audio.duration, video.duration)
        try noStaging(root)
    }

    func testEventBudgetRejectsExtremeVoiceDensityWithoutPublishing() throws {
        let root = try directory(), file = root.appendingPathComponent("dense.mov")
        let mod = try VideoTestModules.nna(channelCount: 64, rowCount: 1024, tempo: 65_535)
        XCTAssertThrowsError(try NoteRainVideoRenderer.export(mod: mod, to: file, options: options(seconds: 1))) {
            XCTAssertEqual($0 as? NoteRainVideoError, .tooManyNotes)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)); try noStaging(root)
    }

    func testRasterIsDeterministicForOverlappingVoicesInBothAppearances() throws {
        let notes = [PreviewNote(id: 1, key: 36, channel: 0, start: 0, end: 5, isOpen: false),
                     PreviewNote(id: 2, key: 36, channel: 2, start: 0.5, end: 1.5, isOpen: false),
                     PreviewNote(id: 3, key: 42, channel: 1, start: 2.5, end: 3.5, isOpen: false)]
        for appearance in NoteRainVideoAppearance.allCases {
            var options = options(); options.appearance = appearance
            let painter = NoteRainVideoPainter(options: options, title: "Synthetic", format: "MOD", channelCount: 4)
            func raster(_ notes: [PreviewNote]) -> Data {
                let context = CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 1280,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
                painter.draw(context, notes: notes, sampleFrame: 48_000)
                return Data(bytes: context.data!, count: 320 * 180 * 4)
            }
            XCTAssertEqual(raster(notes), raster(notes.reversed()))
        }
    }
}
#endif

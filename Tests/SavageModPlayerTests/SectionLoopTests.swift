import XCTest
@testable import SavageModPlayerCore

final class SectionLoopTests: XCTestCase {
    private let rate = 8_000.0
    private let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)

    private final class Run {
        let state: RealtimePlaybackState
        let channels: [DSPChannel]
        let loop: SectionLoopPlayback?
        let exchange = NotePreviewExchange()
        let block: ModuleRenderBlock
        private let left = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
        private let right = UnsafeMutablePointer<Float>.allocate(capacity: 1024)

        init(_ mod: Mod, rate: Double, prepared: PreparedSectionLoop? = nil,
             options: SectionLoopOptions = .init()) {
            state = RenderEngine.makeRenderState(for: mod, sampleRate: rate)
            options.apply(to: state)
            channels = RenderEngine.makeRenderChannels(for: mod)
            loop = prepared.map(SectionLoopPlayback.init)
            state.notePreviewExchange = exchange
            let visualization = RealtimeVisualizationExchange(channelCapacity: min(64, mod.channelCount))
            block = RenderEngine.createRenderBlock(state: state, vuBuffer: visualization.makeVUBuffer(),
                waveBuffer: visualization.makeWaveBuffer(), dspChannels: channels, mod: mod,
                sampleRate: rate, sectionLoop: loop)
        }

        deinit { left.deallocate(); right.deallocate() }

        func render(_ frames: Int, blockSize: Int = 127) -> [Float] {
            var result: [Float] = []
            var remaining = frames
            while remaining > 0 {
                let count = min(remaining, blockSize)
                block(UInt32(count), left, right)
                for index in 0..<count { result.append(left[index]); result.append(right[index]) }
                remaining -= count
            }
            return result
        }
    }

    private func section(_ a: Int, _ b: Int, position: Int = 0) -> SongSection {
        SongSection(start: .init(position: position, row: a), end: .init(position: position, row: b))!
    }

    private func module(format: ModuleFormat = .protracker, tempo: Int = 127, speed: Int = 3,
                        rowNotes: [Int: Note] = [:], nna: Bool = false) throws -> Mod {
        let sound = Sample(pcm: (0..<64).map { Float(sin(Double($0) * .pi / 32)) * 0.35 },
            loopStart: 0, loopLength: 64, loopType: .pingpong, volume: 64, finetune: 0,
            itProperties: ITSampleProperties(c5Speed: 8_000, globalVolume: 64, defaultPanning: nil))
        let envelope = Envelope(points: [EnvelopePoint(frame: 0, value: 64), EnvelopePoint(frame: 50, value: 24)],
            sustainStart: 1, sustainEnd: 1, loopStart: 0, loopEnd: 0,
            sustainEnabled: true, loopEnabled: false)
        let mapping = try NoteSampleMapping(entries: try (0..<120).map {
            try NoteSampleMapping.Entry(targetNote: $0, sampleID: 1)
        })
        let instrumentProperties = ITInstrumentProperties(newNoteAction: .continuePlaying,
            duplicateCheckType: .off, duplicateCheckAction: .cut, globalVolume: 128, defaultPanning: nil,
            pitchPanSeparation: 0, pitchPanCenter: 60, randomVolumeVariation: 20,
            randomPanningVariation: 20, initialFilterCutoff: 60, initialFilterResonance: 25)
        let instrument = Instrument(index: 1, name: "Synthetic loop", samples: [sound],
            volumeEnvelope: envelope, panningEnvelope: envelope, fadeout: 128,
            noteSampleMapping: mapping, itProperties: instrumentProperties)
        let properties = ITModuleProperties(createdWithVersion: 0x0214, compatibleWithVersion: 0x0214,
            usesInstruments: nna, stereo: true, volumeZeroMixOptimization: false, linearSlides: true,
            patternHighlight: 0, mixVolume: 64, panSeparation: 128, pitchWheelDepth: 0,
            hasSongMessage: false, songMessageLength: 0, songMessageOffset: 0,
            usesMIDIPitchController: false, hasEmbeddedMIDIConfiguration: false,
            unknownHeaderFlags: 0, unknownSpecialFlags: 0)
        var rows = (0..<12).map { _ in Row(notes: [empty, empty]) }
        rows[0] = Row(notes: [Note(instrument: 1, period: 428, effectId: 0, effectData: 0, key: 48), empty])
        for (row, note) in rowNotes { rows[row] = Row(notes: [note, empty]) }
        return Mod(name: "Section loop", length: 1, patternTable: [0], instruments: [nil, instrument],
            samplePool: [nil, sound], patterns: [Pattern(rows: rows)], channelCount: 2, format: format,
            initialSpeed: speed, initialTempo: tempo, initialGlobalVolume: format == .it ? 128 : 64,
            linearFrequency: true, itProperties: format == .it ? properties : nil)
    }

    private func verify(_ mod: Mod, section: SongSection, options: SectionLoopOptions = .init(),
                        blocks: [Int] = [1, 64, 127, 256, 1024], file: StaticString = #filePath, line: UInt = #line) throws {
        let prepared = try PreparedSectionLoop.prepare(mod: mod, section: section, sampleRate: rate, options: options)
        let continuous = Run(mod, rate: rate, options: options)
        _ = continuous.render(Int(prepared.startFrame))
        let reference = continuous.render(Int(prepared.frameCount))
        XCTAssertGreaterThan(reference.map(abs).max() ?? 0, 0.01, file: file, line: line)
        for size in blocks {
            let looped = Run(mod, rate: rate, prepared: prepared, options: options)
            let actual = looped.render(Int(prepared.frameCount) * 10, blockSize: size)
            for repeatIndex in 0..<10 {
                let start = repeatIndex * reference.count
                XCTAssertEqual(Array(actual[start..<start + reference.count]), reference,
                    "\(mod.format), Block \(size), Wiederholung \(repeatIndex)", file: file, line: line)
            }
            XCTAssertEqual(looped.exchange.frame, prepared.frameCount * 10, file: file, line: line)
        }
    }

    func testSustainedVoiceFractionalTimingAndEveryBlockSizeMatchContinuousAudio() throws {
        try verify(module(), section: section(3, 5))
    }

    func testAllFormatsKeepEffectMemoryAndEnvelopes() throws {
        for format in [ModuleFormat.protracker, .s3m, .xm, .it] {
            let command = format == .it ? ModuleEffect.impulseTrackerCommand(4) : (format == .s3m ? 0xA : 0xA)
            let mod = try module(format: format, rowNotes: [
                1: Note(instrument: 0, period: 0, effectId: command, effectData: 1),
                4: Note(instrument: 0, period: 0, effectId: command, effectData: 0, effectPresent: true)
            ])
            try verify(mod, section: section(3, 5), blocks: [127, 1024])
        }
    }

    func testITNNAFilterHistoryRandomSwingAndNewVoicesAfterEveryRestore() throws {
        let mod = try module(format: .it, rowNotes: [
            1: Note(instrument: 1, period: 0, effectId: 0, effectData: 0, key: 52),
            4: Note(instrument: 1, period: 0, effectId: 0, effectData: 0, key: 55)
        ], nna: true)
        try verify(mod, section: section(3, 5), blocks: [64, 127, 1024])
    }

    func testRenderOptionsAndDisabledLoopContinueFromCurrentState() throws {
        let options = SectionLoopOptions(stereoSeparation: 0.2, useInterpolation: false, palClock: false)
        let mod = try module()
        try verify(mod, section: section(3, 5), options: options, blocks: [127])
        let prepared = try PreparedSectionLoop.prepare(mod: mod, section: section(3, 5), sampleRate: rate)
        let looped = Run(mod, rate: rate, prepared: prepared)
        _ = looped.render(250)
        looped.loop?.disable()
        let actual = looped.render(Int(prepared.frameCount) * 2)
        let reference = Run(mod, rate: rate)
        _ = reference.render(Int(prepared.startFrame) + 250)
        XCTAssertEqual(actual, reference.render(Int(prepared.frameCount) * 2))
        XCTAssertEqual(looped.exchange.takeCommands().map(\.kind), [.sectionLoopDisabled])
    }

    func testInclusiveMODAndITDelayEndsAndSingleRowSections() throws {
        for (format, command, data, duration) in [
            (ModuleFormat.protracker, 0xEE, 2, 640),
            (.it, ModuleEffect.impulseTrackerCommand(19), 0x62, 480),
            (.it, ModuleEffect.impulseTrackerCommand(19), 0xE2, 480)
        ] {
            let mod = try module(format: format, tempo: 125, speed: 1, rowNotes: [
                1: Note(instrument: 0, period: 0, effectId: command, effectData: data)
            ])
            let prepared = try PreparedSectionLoop.prepare(mod: mod, section: section(1, 1), sampleRate: rate)
            XCTAssertEqual(prepared.startFrame, 160)
            XCTAssertEqual(prepared.frameCount, UInt64(duration))
            try verify(mod, section: section(1, 1), blocks: [127])
        }
    }

    func testSkippedOrderDoesNotChangeTempoAndMissingTargetIsRejected() throws {
        let base = try module(tempo: 150, speed: 1)
        var first = base.patterns[0].rows
        first[1] = Row(notes: [Note(instrument: 0, period: 0, effectId: 0xB, effectData: 2), empty])
        let mod = Mod(name: "Jump", length: 3, patternTable: [0, 1, 2], instruments: base.instruments,
            patterns: [Pattern(rows: first), Pattern(rows: [Row(notes: [
                Note(instrument: 0, period: 0, effectId: 0xF, effectData: 75), empty])]), base.patterns[0]],
            channelCount: 2, initialSpeed: 1, initialTempo: 150)
        let prepared = try PreparedSectionLoop.prepare(mod: mod, section: section(0, 1, position: 2), sampleRate: rate)
        let live = Run(mod, rate: rate, prepared: prepared)
        _ = live.render(1)
        XCTAssertEqual(live.state.bpm, 150)
        XCTAssertThrowsError(try PreparedSectionLoop.prepare(mod: mod, section: section(0, 0, position: 1), sampleRate: rate))
    }

    func testPreparationBudgetValidationAndCancellation() async throws {
        let mod = try module()
        XCTAssertThrowsError(try PreparedSectionLoop.prepare(mod: mod, section: section(11, 11), sampleRate: rate,
            maximumSeconds: 0.001)) { XCTAssertEqual($0 as? SectionLoopError, .budgetExceeded) }
        XCTAssertThrowsError(try PreparedSectionLoop.prepare(mod: mod, section: section(99, 99), sampleRate: rate))
        let exact = try PreparedSectionLoop.prepare(mod: module(tempo: 125, speed: 1), section: section(0, 0),
            sampleRate: rate, maximumSeconds: 0.02)
        XCTAssertEqual(exact.frameCount, 160)
        let selected = section(3, 5)
        let sampleRate = rate
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try PreparedSectionLoop.prepare(mod: mod, section: selected, sampleRate: sampleRate)
        }
        do { _ = try await task.value; XCTFail("Abbruch wurde ignoriert") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testPreviewUsesTheSameLoopFramesAndKeepsPreAAlreadyPlayingNotes() throws {
        let mod = try module(tempo: 125, speed: 1)
        let prepared = try PreparedSectionLoop.prepare(mod: mod, section: section(3, 3), sampleRate: rate)
        let live = Run(mod, rate: rate, prepared: prepared)
        _ = live.render(500, blockSize: 127)
        let preview = NotePreviewSimulation(configuration: .init(mod: mod, sampleRate: rate, state: live.state,
            sectionLoop: prepared))
        try preview.advance(to: 500, commands: [])
        let notes = preview.snapshot(since: 0).notes.sorted { $0.start < $1.start }
        XCTAssertEqual(notes.count, 4)
        XCTAssertEqual(notes.map(\.start), [0, 0.02, 0.04, 0.06])
        XCTAssertEqual(Set(notes.map(\.id)).count, 4)
        XCTAssertEqual(notes.first?.end, 0.02)
        live.loop?.disable()
        _ = live.render(127)
        let commands = live.exchange.takeCommands()
        XCTAssertEqual(commands.first?.frame, 500)
        let newPreview = NotePreviewSimulation(configuration: .init(mod: mod, sampleRate: rate, state: live.state,
            sectionLoop: prepared))
        try newPreview.advance(to: 1_000, commands: commands)
        XCTAssertEqual(newPreview.snapshot(since: 0).notes.count, 4)
    }

    func testRepeatedPatternOrdersAreDistinctAndMuteRemainsAUserSetting() throws {
        let base = try module(tempo: 125, speed: 1)
        let mod = Mod(name: "Repeated", length: 2, patternTable: [0, 0], instruments: base.instruments,
            patterns: base.patterns, channelCount: 2, initialSpeed: 1, initialTempo: 125)
        let selected = section(3, 4, position: 1)
        let prepared = try PreparedSectionLoop.prepare(mod: mod, section: selected, sampleRate: rate)
        XCTAssertEqual(prepared.startFrame, 15 * 160)
        let run = Run(mod, rate: rate, prepared: prepared)
        run.channels[0].isMuted = true
        XCTAssertEqual(run.render(Int(prepared.frameCount) * 3).map(abs).max(), 0)
        XCTAssertTrue(run.channels[0].isMuted)
        run.channels[0].isMuted = false
        XCTAssertGreaterThan(run.render(20).map(abs).max() ?? 0, 0.01)
        XCTAssertEqual(run.state.position, 1)
    }

    func testCombinedITDelaysPatternLoopsAndLastRowEnd() throws {
        let base = try module(format: .it, tempo: 125, speed: 1)
        var rows = base.patterns[0].rows
        rows[1] = Row(notes: [
            Note(instrument: 0, period: 0, effectId: ModuleEffect.impulseTrackerCommand(19), effectData: 0x62),
            Note(instrument: 0, period: 0, effectId: ModuleEffect.impulseTrackerCommand(19), effectData: 0xE2)
        ])
        let combined = Mod(name: "Combined IT delays", length: 1, patternTable: [0], instruments: base.instruments,
            samplePool: base.samplePool, patterns: [Pattern(rows: rows)], channelCount: 2, format: .it,
            initialSpeed: 1, initialTempo: 125, initialGlobalVolume: 128, itProperties: base.itProperties)
        let prepared = try PreparedSectionLoop.prepare(mod: combined, section: section(1, 1), sampleRate: rate)
        XCTAssertEqual(prepared.frameCount, 1440)
        try verify(combined, section: section(1, 1), blocks: [127])
        let looping = try module(tempo: 125, speed: 1, rowNotes: [
            1: Note(instrument: 0, period: 0, effectId: 0xE6, effectData: 0),
            2: Note(instrument: 0, period: 0, effectId: 0xE6, effectData: 2)
        ])
        try verify(looping, section: section(2, 2), blocks: [127])
        try verify(module(), section: section(11, 11), blocks: [127])
    }

    func testSeekAndTempoCommandsDisableTheSnapshotBeforeTheyAreApplied() throws {
        let mod = try module()
        let prepared = try PreparedSectionLoop.prepare(mod: mod, section: section(3, 5), sampleRate: rate)
        let run = Run(mod, rate: rate, prepared: prepared)
        _ = run.render(10)
        _ = run.state.requestBPM(140)
        _ = run.render(1)
        XCTAssertFalse(run.loop?.isEnabled ?? true)
        XCTAssertEqual(run.state.bpm, 140)
        _ = run.state.requestSeek(position: 0, row: 8, ticksPerRow: 3, bpm: 125, globalVolume: 64, elapsedFrames: 0)
        _ = run.render(1)
        XCTAssertEqual(run.state.rowIndex, 8)
    }

    func testCommonSourceSampleRatesKeepTheFirstFrameAndFractionalTickRemainder() throws {
        let mod = try module()
        for sampleRate in [44_100.0, 48_000, 96_000] {
            let prepared = try PreparedSectionLoop.prepare(mod: mod, section: section(3, 5), sampleRate: sampleRate)
            let continuous = Run(mod, rate: sampleRate)
            _ = continuous.render(Int(prepared.startFrame))
            let reference = continuous.render(Int(prepared.frameCount))
            let looped = Run(mod, rate: sampleRate, prepared: prepared)
            let actual = looped.render(Int(prepared.frameCount) * 3, blockSize: 127)
            for index in 0..<3 {
                XCTAssertEqual(Array(actual[index * reference.count..<(index + 1) * reference.count]), reference)
            }
        }
    }

    func testFullITVoicePoolRestoresAllOwnersAndStealsVoicesDeterministically() throws {
        let base = try module(format: .it, nna: true)
        let rows = (0..<8).map { row in
            Row(notes: (0..<64).map { channel in
                Note(instrument: 1, period: 0, effectId: 0, effectData: 0, key: 48 + (row + channel) % 12)
            })
        }
        let mod = Mod(name: "Full IT pool", length: 1, patternTable: [0], instruments: base.instruments,
            samplePool: base.samplePool, patterns: [Pattern(rows: rows)], channelCount: 64, format: .it,
            initialSpeed: 1, initialTempo: 125, initialGlobalVolume: 1, linearFrequency: true,
            itProperties: base.itProperties)
        let continuous = Run(mod, rate: rate)
        _ = continuous.render(4 * 160)
        XCTAssertEqual(continuous.channels.first?.itVoicePool?.activeVoiceCount, 256)
        try verify(mod, section: section(4, 5), blocks: [127, 1024])
    }

    func testLocalMODCorpusLoopsMatchTheContinuousReferenceWhenAvailable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("audio")
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .allObjects as? [URL] ?? []).filter { $0.pathExtension.lowercased() == "mod" }
        guard !files.isEmpty else { throw XCTSkip("Lokaler MOD-Korpus fehlt") }
        for url in files.sorted(by: { $0.path < $1.path }) {
            let mod = try ModuleLoader.parse(data: Data(contentsOf: url))
            let probe = Run(mod, rate: rate)
            _ = probe.render(4_000)
            let address = SongAddress(position: probe.state.position, row: probe.state.rowIndex)
            let selected = try XCTUnwrap(SongSection(start: address, end: address))
            let prepared = try PreparedSectionLoop.prepare(mod: mod, section: selected,
                sampleRate: rate, maximumSeconds: 10)
            let continuous = Run(mod, rate: rate)
            _ = continuous.render(Int(prepared.startFrame))
            let reference = continuous.render(Int(prepared.frameCount))
            let looped = Run(mod, rate: rate, prepared: prepared)
            let actual = looped.render(Int(prepared.frameCount) * 3, blockSize: 127)
            for index in 0..<3 {
                XCTAssertEqual(Array(actual[index * reference.count..<(index + 1) * reference.count]), reference,
                    url.lastPathComponent)
            }
        }
        print("A/B-Korpus: \(files.count) MODs, je drei Wiederholungen samplegenau verglichen")
    }

}

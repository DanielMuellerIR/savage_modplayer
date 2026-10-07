import XCTest
@testable import SavageModPlayerCore

final class NotePreviewTests: XCTestCase {
    private let rate = 8_000.0
    private let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)

    private func note(_ period: Int = 428, effect: Int = 0, data: Int = 0) -> Note {
        Note(instrument: 1, period: period, effectId: effect, effectData: data)
    }

    private func mod(_ rows: [[Note]], loop: Bool = true) -> Mod {
        let sample = Sample(pcm: [Float](repeating: 0.25, count: 100), loopStart: 0,
            loopLength: loop ? 100 : 0, loopType: loop ? .forward : .none, volume: 64, finetune: 0)
        return Mod(name: "Note preview", length: 1, patternTable: [0],
            instruments: [nil, Instrument(index: 1, name: "Synthetic", samples: [sample])],
            patterns: [Pattern(rows: rows.map { Row(notes: $0) })], channelCount: rows.first?.count ?? 1)
    }

    private func simulation(_ mod: Mod) -> NotePreviewSimulation {
        NotePreviewSimulation(configuration: .init(mod: mod, sampleRate: rate,
            state: RenderEngine.makeRenderState(for: mod, sampleRate: rate)))
    }

    func testDelayedNoteRetriggerAndCutHaveTheirActualTickTimes() throws {
        let module = mod([
            [note(effect: 0xED, data: 2)],
            [Note(instrument: 0, period: 0, effectId: 0xE9, effectData: 2)],
            [Note(instrument: 0, period: 0, effectId: 0xEC, effectData: 1)],
            [empty]
        ])
        let preview = simulation(module)
        try preview.advance(to: 3_000, commands: [])
        let notes = preview.snapshot(since: 0).notes
        XCTAssertEqual(notes.map(\.key), [36, 36, 36])
        XCTAssertEqual(notes.count, 3)
        let starts = [0.04, 0.16, 0.20]
        let ends = [0.16, 0.20, 0.26]
        for (index, note) in notes.enumerated() {
            XCTAssertEqual(note.start, starts[index], accuracy: 1 / rate)
            XCTAssertEqual(note.end, ends[index], accuracy: 1 / rate)
        }
    }

    func testShortSampleEndsBeforeNextRowAndMatchesAudioVoice() throws {
        let module = mod([[note()], [empty], [empty]], loop: false)
        let preview = simulation(module)
        try preview.advance(to: 1_000, commands: [])
        let actual = try XCTUnwrap(preview.snapshot(since: 0).notes.first)
        let channels = RenderEngine.makeRenderChannels(for: module)
        let state = RenderEngine.makeRenderState(for: module, sampleRate: rate)
        let visualization = RealtimeVisualizationExchange(channelCapacity: 1)
        let render = RenderEngine.createRenderBlock(state: state, vuBuffer: visualization.makeVUBuffer(), waveBuffer: visualization.makeWaveBuffer(),
            dspChannels: channels, mod: module, sampleRate: rate)
        var left: Float = 0
        var right: Float = 0
        var endedAt = 0
        for frame in 0..<1_000 {
            render(1, &left, &right)
            if !channels[0].playing { endedAt = frame + 1; break }
        }
        XCTAssertGreaterThan(endedAt, 1)
        XCTAssertLessThan(actual.end, 0.02)
        XCTAssertEqual(actual.end, Double(endedAt) / rate, accuracy: 1 / rate)
    }

    func testTempoChangesLoopsAndForwardJumpUseSequencedTime() throws {
        let sound = mod([[note()]]).instruments
        func fx(_ id: Int, _ data: Int) -> Note {
            Note(instrument: 0, period: 0, effectId: id, effectData: data)
        }
        let module = Mod(name: "Flow", length: 2, patternTable: [0, 1], instruments: sound,
            patterns: [Pattern(rows: [
                Row(notes: [note(), fx(0xE6, 0)]),
                Row(notes: [note(381), fx(0xE6, 1)]),
                Row(notes: [note(339), fx(0x0F, 3)]),
                Row(notes: [note(320), fx(0x0F, 150)]),
                Row(notes: [fx(0x0B, 1), fx(0x0D, 2)])
            ]), Pattern(rows: [Row(notes: [empty, empty]), Row(notes: [empty, empty]),
                Row(notes: [note(285), empty]), Row(notes: [empty, empty])])], channelCount: 2)
        let preview = simulation(module)
        try preview.advance(to: 5_700, commands: [])
        let notes = preview.snapshot(since: 0).notes
        XCTAssertEqual(Array(notes.prefix(7).map(\.key)), [36, 38, 36, 38, 40, 41, 43])
        let expected = [0.0, 0.12, 0.24, 0.36, 0.48, 0.54, 5121.0 / rate]
        for (note, time) in zip(notes, expected) { XCTAssertEqual(note.start, time, accuracy: 1 / rate) }
    }

    func testAppliedControlFramesAndClockSurviveSeekAndDisplayClockReset() throws {
        let module = mod([[note()], [note(381)], [note(339)], [empty]])
        let state = RenderEngine.makeRenderState(for: module, sampleRate: rate)
        let config = NotePreviewConfiguration(mod: module, sampleRate: rate, state: state)
        let exchange = NotePreviewExchange()
        state.notePreviewExchange = exchange
        let channels = RenderEngine.makeRenderChannels(for: module)
        let visualization = RealtimeVisualizationExchange(channelCapacity: 1)
        let render = RenderEngine.createRenderBlock(state: state, vuBuffer: visualization.makeVUBuffer(),
            waveBuffer: visualization.makeWaveBuffer(), dspChannels: channels, mod: module, sampleRate: rate)
        let buffer = StereoRenderBuffer(capacity: 320)
        render(320, buffer.left, buffer.right)
        _ = state.requestBPM(250)
        render(320, buffer.left, buffer.right)
        _ = state.requestSeek(position: 0, row: 2, ticksPerRow: 6, bpm: 125,
            globalVolume: 64, elapsedFrames: 99_000)
        state.pendingElapsedFrames = 0
        render(320, buffer.left, buffer.right)
        XCTAssertEqual(exchange.frame, 960)
        let commands = exchange.takeCommands()
        XCTAssertEqual(commands.map(\.frame), [320, 640])
        let preview = NotePreviewSimulation(configuration: config)
        try preview.advance(to: 960, commands: commands)
        let notes = preview.snapshot(since: 0).notes
        XCTAssertEqual(notes.map(\.key), [36, 40])
        XCTAssertEqual(notes[0].end, 0.08, accuracy: 1 / rate)
        XCTAssertEqual(notes[1].start, 0.08, accuracy: 1 / rate)
    }

    func testControlRingReportsOverflowAndReusesConsumedSlots() {
        let exchange = NotePreviewExchange(capacity: 2)
        exchange.append(.init(bpm: 125))
        exchange.finishBlock(frames: 10)
        exchange.append(.init(bpm: 150))
        XCTAssertEqual(exchange.takeCommands().map(\.frame), [0, 10])
        exchange.append(.init(bpm: 160))
        exchange.append(.init(bpm: 170))
        XCTAssertFalse(exchange.hasOverflowed)
        exchange.append(.init(bpm: 180))
        XCTAssertTrue(exchange.hasOverflowed)
        XCTAssertEqual(exchange.takeCommands().map(\.bpm), [160, 170])
    }

    func testITMappedNotesAndNNAOverlapKeepTheirLogicalChannel() throws {
        let sample = Sample(pcm: [0.25, -0.25, 0.25, -0.25], loopStart: 0,
            loopLength: 4, loopType: .forward, volume: 64, finetune: 0,
            itProperties: .init(c5Speed: 8_000, globalVolume: 64, defaultPanning: nil))
        let mapping = try NoteSampleMapping(entries: (0..<120).map {
            try .init(targetNote: min(119, $0 + 12), sampleID: 1)
        })
        let properties = ITInstrumentProperties(newNoteAction: .continuePlaying,
            duplicateCheckType: .off, duplicateCheckAction: .cut, globalVolume: 128,
            defaultPanning: nil, pitchPanSeparation: 0, pitchPanCenter: 60,
            randomVolumeVariation: 0, randomPanningVariation: 0,
            initialFilterCutoff: nil, initialFilterResonance: nil)
        let instrument = Instrument(index: 1, name: "NNA", samples: [sample],
            noteSampleMapping: mapping, itProperties: properties)
        let it = ITModuleProperties(createdWithVersion: 0x0214, compatibleWithVersion: 0x0214,
            usesInstruments: true, stereo: true, volumeZeroMixOptimization: false, linearSlides: true,
            patternHighlight: 0, mixVolume: 64, panSeparation: 128, pitchWheelDepth: 0,
            hasSongMessage: false, songMessageLength: 0, songMessageOffset: 0,
            usesMIDIPitchController: false, hasEmbeddedMIDIConfiguration: false,
            unknownHeaderFlags: 0, unknownSpecialFlags: 0)
        let module = Mod(name: "NNA", length: 1, patternTable: [0], instruments: [nil, instrument],
            samplePool: [nil, sample], patterns: [Pattern(rows: [
                Row(notes: [empty, Note(instrument: 1, period: 0, effectId: 0, effectData: 0, key: 48)]),
                Row(notes: [empty, Note(instrument: 1, period: 0, effectId: 0, effectData: 0, key: 52)]),
                Row(notes: [empty, empty])
            ])], channelCount: 2, format: .it, initialGlobalVolume: 128,
            linearFrequency: true, itProperties: it)
        let preview = simulation(module)
        try preview.advance(to: 2_000, commands: [])
        let notes = preview.snapshot(since: 0).notes
        XCTAssertEqual(notes.map(\.key), [60, 64])
        XCTAssertEqual(notes.map(\.channel), [1, 1])
        XCTAssertTrue(notes.allSatisfy(\.isOpen))
        XCTAssertEqual(notes[0].start, 0)
        XCTAssertEqual(notes[1].start, 0.12, accuracy: 1 / rate)
        XCTAssertGreaterThan(notes[0].end, notes[1].start)
    }

    func testPortamentoDoesNotInventANewAttack() throws {
        let preview = simulation(mod([[note()], [note(320, effect: 3, data: 4)], [empty]]))
        try preview.advance(to: 2_000, commands: [])
        let notes = preview.snapshot(since: 0).notes
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].key, 36)
        XCTAssertTrue(notes[0].isOpen)
    }

    func testWorkerDiscardsPredictedFutureAfterManualTempoChange() async throws {
        let module = mod([[note()], [note(381)], [note(339)], [empty]])
        let source = NotePreviewSource(configuration: .init(mod: module, sampleRate: rate,
            state: RenderEngine.makeRenderState(for: module, sampleRate: rate)), exchange: .init())
        let worker = NotePreviewWorker()
        let original = try await worker.preview(source: source, commands: [], currentTime: 0, horizon: 0.3)
        XCTAssertEqual(original.notes[1].start, 0.12, accuracy: 1 / rate)
        let changed = try await worker.preview(source: source,
            commands: [.init(frame: 320, bpm: 250)], currentTime: 0.04, horizon: 0.2)
        XCTAssertEqual(changed.notes[1].start, 0.08, accuracy: 1 / rate)
        XCTAssertEqual(changed.notes[2].start, 0.14, accuracy: 1 / rate)
    }

    func testCommandPublicationAcrossThreadsKeepsOrderAndFrameIdentity() {
        let exchange = NotePreviewExchange(capacity: 2_048)
        let done = expectation(description: "Audio producer")
        DispatchQueue.global().async {
            for index in 0..<2_000 {
                exchange.append(.init(bpm: index + 1))
                exchange.finishBlock(frames: 1)
            }
            done.fulfill()
        }
        var commands: [NotePreviewCommand] = []
        let deadline = Date().addingTimeInterval(5)
        while commands.count < 2_000, Date() < deadline {
            commands += exchange.takeCommands()
        }
        wait(for: [done], timeout: 5)
        commands += exchange.takeCommands()
        XCTAssertFalse(exchange.hasOverflowed)
        XCTAssertEqual(commands.map(\.frame), Array(0..<2_000).map(UInt64.init))
        XCTAssertEqual(commands.map(\.bpm), Array(1...2_000).map { Optional($0) })
        XCTAssertEqual(exchange.frame, 2_000)
    }

    func testSongEndSeparatesPlaylistPreviewFromRepeatedNotes() throws {
        let preview = simulation(mod([[note()], [note(381)]]))
        try preview.advance(to: 4_000, commands: [])
        let first = preview.snapshot(since: 0, currentTime: 0.1)
        XCTAssertEqual(try XCTUnwrap(first.nextSongEnd), 0.24, accuracy: 1 / rate)
        XCTAssertEqual(first.notes.filter { $0.start < first.nextSongEnd! }.count, 2)
        let second = preview.snapshot(since: 0, currentTime: 0.3)
        XCTAssertEqual(try XCTUnwrap(second.nextSongEnd), 0.48, accuracy: 1 / rate)
    }
}

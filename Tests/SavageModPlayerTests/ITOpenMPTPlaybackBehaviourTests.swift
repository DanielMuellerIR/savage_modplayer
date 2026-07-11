import XCTest
@testable import SavageModPlayerCore

final class ITOpenMPTPlaybackBehaviourTests: XCTestCase {
    func testMSF6ExecutesNormalPortamentoOnceAtSpeedOne() {
        let channel = channel(instrumentMode: false)
        channel.itSlidesAtSpeedOne = true
        channel.playNote(
            note(key: -1, command: 5, parameter: 2),
            instruments: [nil]
        )
        channel.period = 1_000
        channel.currentPeriod = 1_000

        channel.performTick(
            tick: 0,
            sampleRate: 44_100,
            clockRate: 14_317_056,
            ticksPerRow: 1
        )
        XCTAssertEqual(channel.currentPeriod, 1_008, accuracy: 0.0001)

        // Dasselbe Bit darf bei Speed > 1 keinen zusaetzlichen Tick-0-Schritt
        // erzeugen; dort laufen normale Slides weiterhin erst auf Folgeticks.
        channel.currentPeriod = 1_000
        channel.performTick(
            tick: 0,
            sampleRate: 44_100,
            clockRate: 14_317_056,
            ticksPerRow: 6
        )
        XCTAssertEqual(channel.currentPeriod, 1_000, accuracy: 0.0001)
    }

    func testMSF119ResetsFilterHistoryOnSampleModePortamentoSwap() {
        let first = sample(name: "A")
        let second = sample(name: "B")
        let instruments: [Instrument?] = [
            nil,
            Instrument(index: 1, name: "A", samples: [first]),
            Instrument(index: 2, name: "B", samples: [second]),
        ]
        let channel = channel(instrumentMode: false)
        channel.itResetFilterOnPortamentoSampleChange = true
        channel.playNote(note(key: 60, instrument: 1), instruments: instruments)
        channel.itFilterNeedsReset = false

        channel.playNote(
            note(key: 64, instrument: 2, command: 7, parameter: 3),
            instruments: instruments
        )

        XCTAssertTrue(channel.itFilterNeedsReset)
        XCTAssertEqual(channel.instrument?.index, 2)
        XCTAssertNil(channel.setSampleIndex, "Gxx darf das neue Sample nicht retriggern")
    }

    func testMSF127UsesOriginalITPortamentoMemoryOrderingAcrossBothColumns() {
        let channel = channel(instrumentMode: false)
        channel.itDoublePortamentoSlides = true

        // Volume-Column E2 schreibt zuerst 8; Effektspalten-E02 gewinnt danach
        // mit 2. Beide Spalten lesen bei der Ausführung denselben Endwert.
        channel.playNote(
            note(key: -1, volume: 107, command: 5, parameter: 2),
            instruments: [nil]
        )
        XCTAssertEqual(channel.periodDelta, 8, accuracy: 0.0001)

        // Bei zwei Tone-Portamentos wird erst G05 und danach Volume-G2 (=4)
        // initialisiert; der rechte/Volume-Wert bestimmt somit beide Slides.
        channel.playNote(
            note(key: -1, volume: 195, command: 7, parameter: 5),
            instruments: [nil]
        )
        XCTAssertEqual(channel.portamentoSpeed, 16, accuracy: 0.0001)
    }

    func testMSF134DefersSCxNextToPortamentoUntilPatternDelayRepeat() {
        let smp = sample(name: "Cut")
        let instruments: [Instrument?] = [
            nil,
            Instrument(index: 1, name: "Cut", samples: [smp]),
        ]
        let channel = channel(instrumentMode: false)
        channel.itNoteCutWithPortamento = true
        channel.playNote(note(key: 60, instrument: 1), instruments: instruments)
        channel.playNote(
            note(key: 64, volume: 194, command: 19, parameter: 0xC1),
            instruments: instruments
        )

        channel.performTick(tick: 1, sampleRate: 44_100, clockRate: 14_317_056)
        XCTAssertTrue(channel.playing, "Erste Zeilenausführung ignoriert SCx neben Porta")

        channel.itPatternState?.rowRepeatIndex = 1
        channel.performTick(tick: 1, sampleRate: 44_100, clockRate: 14_317_056)
        XCTAssertFalse(channel.playing)
        XCTAssertEqual(channel.currentPeriod, 0)
    }

    func testMSF136AppliesStoppedFilterEnvelopeAtMidpoint() throws {
        let filterEnvelope = Envelope(
            points: [
                EnvelopePoint(frame: 0, value: 8),
                EnvelopePoint(frame: 8, value: 56),
            ],
            sustainStart: 0,
            sustainEnd: 0,
            loopStart: 0,
            loopEnd: 0,
            sustainEnabled: false,
            loopEnabled: false,
            valueMode: .filter
        )
        let smp = sample(name: "Filter")
        let mapping = try NoteSampleMapping(entries: (0..<120).map {
            try NoteSampleMapping.Entry(targetNote: $0, sampleID: 1)
        })
        let instrument = Instrument(
            index: 1,
            name: "Filter",
            samples: [],
            pitchEnvelope: filterEnvelope,
            noteSampleMapping: mapping,
            itProperties: instrumentProperties(cutoff: 64, resonance: 32)
        )
        let channel = channel(instrumentMode: true)
        channel.itSamplePool = [nil, smp]
        channel.itStoppedFilterEnvelopeAtStart = true
        channel.playNote(
            note(key: 60, instrument: 1, command: 19, parameter: 0x7B),
            instruments: [nil, instrument]
        )

        XCTAssertFalse(channel.itPitchEnvelopeEnabled)
        XCTAssertTrue(channel.itStoppedFilterMidpointActive)
        channel.performTick(tick: 0, sampleRate: 44_100, clockRate: 14_317_056)
        XCTAssertTrue(channel.itFilterActive)
        XCTAssertLessThan(channel.itFilterA0, 0.5)
    }

    private func channel(instrumentMode: Bool) -> DSPChannel {
        let channel = DSPChannel(index: 1)
        channel.itMode = true
        channel.itLinearMode = true
        channel.itInstrumentMode = instrumentMode
        channel.periodScale = 4
        channel.periodMin = 1
        channel.periodMax = 7_680
        channel.itPatternState = ITPatternChannelState(channelVolume: 64)
        return channel
    }

    private func sample(name: String) -> Sample {
        Sample(
            pcm: [0.25, -0.25, 0.125, -0.125],
            loopStart: 0,
            loopLength: 4,
            loopType: .forward,
            volume: 64,
            finetune: 0,
            name: name,
            itProperties: ITSampleProperties(
                c5Speed: 8_363,
                globalVolume: 64,
                defaultPanning: nil
            )
        )
    }

    private func instrumentProperties(cutoff: Int? = nil, resonance: Int? = nil) -> ITInstrumentProperties {
        ITInstrumentProperties(
            newNoteAction: .cut,
            duplicateCheckType: .off,
            duplicateCheckAction: .cut,
            globalVolume: 128,
            defaultPanning: 32,
            pitchPanSeparation: 0,
            pitchPanCenter: 60,
            randomVolumeVariation: 0,
            randomPanningVariation: 0,
            initialFilterCutoff: cutoff,
            initialFilterResonance: resonance
        )
    }

    private func note(
        key: Int,
        instrument: Int = 0,
        volume: Int = -1,
        command: Int = 0,
        parameter: Int = 0
    ) -> Note {
        Note(
            instrument: instrument,
            period: 0,
            effectId: command > 0 ? ModuleEffect.impulseTrackerCommand(command) : 0,
            effectData: parameter,
            key: key,
            volume: volume,
            effectPresent: command > 0
        )
    }
}

import XCTest
@testable import SavageModPlayerCore

/// Regressionstests fuer die Song-Sequenzierung im Render-/Probe-Pfad des
/// `ModPlayerCoordinator` (Pattern-Break, Wrap, Loop).
final class CoordinatorSequencingTests: XCTestCase {

    /// Baut ein minimal gueltiges 2-Positionen-M.K.-MOD. In Pattern 0, Row 0,
    /// Kanal 0 steht eine Note plus ein per Parameter waehlbarer Effekt.
    private func makeMod(effectId: UInt8, effectData: UInt8) -> Data {
        var data = Data(repeating: 0, count: 1084 + 1024 + 8)

        // Instrument 1: Laenge 2 Words? Wir setzen Laenge = 4 Bytes (Word 2),
        // Volume 64, kein Loop.
        data[20 + 22] = 0x00 // length hi
        data[20 + 23] = 0x02 // length lo (2 words = 4 bytes)
        data[20 + 25] = 64   // volume

        // Songlaenge 2, Pattern-Table [0, 0].
        data[950] = 2
        data[952] = 0
        data[953] = 0

        // Signatur M.K.
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))

        // Pattern 0, Row 0, Kanal 0: Instrument 1, Period 428 (C-3), + Effekt.
        // Byte-Layout: b0=Period-Hi(+SampleHi), b1=Period-Lo, b2=SampleLo<<4|EffId, b3=EffData
        let period = 428
        let b0 = UInt8((period >> 8) & 0x0F)            // SampleHi=0
        let b1 = UInt8(period & 0xFF)
        let b2 = UInt8((1 << 4) | (Int(effectId) & 0x0F)) // SampleLo=1
        let b3 = effectData
        let noteOffset = 1084
        data[noteOffset + 0] = b0
        data[noteOffset + 1] = b1
        data[noteOffset + 2] = b2
        data[noteOffset + 3] = b3

        return data
    }

    // Ein rein synthetischer Ablauf, der alle fuer IT-003 verpflichtenden
    // Sequencer-Zweige wirklich erreicht: Tempo/Speed/Global Volume, Pattern-
    // Loop, Pattern-Delay sowie kombinierten Position-Jump + Pattern-Break.
    private func makeTraceMod() -> Mod {
        let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
        func effect(_ id: Int, _ data: Int) -> Note {
            Note(instrument: 0, period: 0, effectId: id, effectData: data)
        }
        func emptyRow() -> Row { Row(notes: [Note](repeating: empty, count: 4)) }

        let pattern0 = Pattern(rows: [
            Row(notes: [
                effect(0x0F, 3),
                effect(0x0F, 150),
                effect(ModuleEffect.globalVolume, 32),
                effect(0xE6, 0)
            ]),
            Row(notes: [empty, empty, empty, effect(0xE6, 1)]),
            Row(notes: [effect(0xEE, 2), empty, empty, empty]),
            Row(notes: [effect(0x0B, 1), effect(0x0D, 5), empty, empty])
        ])
        let pattern1 = Pattern(rows: (0..<8).map { _ in emptyRow() })
        return Mod(
            name: "sequencer-trace",
            length: 2,
            patternTable: [0, 1],
            instruments: [nil],
            patterns: [pattern0, pattern1],
            channelCount: 4
        )
    }

    // Treibt denselben Block wie App, WAV-Export und Quick Look ohne Engine oder
    // Audiogeraet. Der erste Aufruf rendert Frame 0; danach folgen 256 Frames,
    // sodass die Zustandsgrenzen exakt der bestehenden Probe-Abtastung entsprechen.
    private func renderBlockTraces(
        mod: Mod,
        durationSeconds: Double,
        sampleRate: Double = 44100.0
    ) throws -> [SequencerTraceSnapshot] {
        let channels = RenderEngine.makeRenderChannels(for: mod)
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: sampleRate)
        state.stereoSeparation = 0.8
        state.useInterpolation = true
        state.palClock = true

        let channelCount = channels.count
        let peaks = UnsafeMutablePointer<Float>.allocate(capacity: channelCount)
        defer { peaks.deallocate() }
        peaks.initialize(repeating: 0, count: channelCount)
        let waves = UnsafeMutablePointer<Float>.allocate(capacity: channelCount * 32)
        defer { waves.deallocate() }
        waves.initialize(repeating: 0, count: channelCount * 32)
        let masterWaves = UnsafeMutablePointer<Float>.allocate(capacity: 128)
        defer { masterWaves.deallocate() }
        masterWaves.initialize(repeating: 0, count: 128)

        let block = RenderEngine.createRenderBlock(
            state: state,
            vuBuffer: RealtimeVUBuffer(pointer: peaks),
            waveBuffer: RealtimeWaveBuffer(channelWaves: waves, masterWaves: masterWaves),
            dspChannels: channels,
            mod: mod,
            sampleRate: sampleRate
        )
        let buffer = StereoRenderBuffer(capacity: 256)
        let totalFrames = Int(sampleRate * durationSeconds)
        var renderedFrames = 0
        var traces: [SequencerTraceSnapshot] = []

        for frame in stride(from: 0, to: totalFrames, by: 256) {
            let frameCount = frame + 1 - renderedFrames
            block(UInt32(frameCount), buffer.left, buffer.right)
            renderedFrames += frameCount
            traces.append(SequencerTraceSnapshot(frame: frame, state: state, mod: mod))
        }
        return traces
    }

    // Braucht die AVAudioEngine-gebundene Live-Klasse — entfällt unter Linux.
#if canImport(AVFoundation) && canImport(Combine)
    /// Pause haelt die Engine an, ohne den Zustand zu verwerfen; resume() setzt
    /// fort; stop() raeumt beide Flags auf. Braucht ein echtes Audio-Geraet —
    /// ohne (z.B. CI) startet play() nicht und der Test wird uebersprungen.
    @MainActor
    func testPauseAndResumeKeepPlaybackState() async throws {
        let coordinator = ModPlayerCoordinator()
        coordinator.setMod(ModParser.generateDemoMod())
        coordinator.play()
        guard coordinator.isPlaying else { return }

        try await Task.sleep(nanoseconds: 200_000_000)
        coordinator.pause()
        XCTAssertTrue(coordinator.isPaused)
        XCTAssertTrue(coordinator.isPlaying, "Pause darf die Engine nicht abbauen")
        let pausedPosition = coordinator.currentPosition

        try await Task.sleep(nanoseconds: 200_000_000)
        coordinator.resume()
        XCTAssertFalse(coordinator.isPaused)
        XCTAssertTrue(coordinator.isPlaying)
        // Nach dem Fortsetzen laeuft es an derselben Stelle weiter (die
        // Position kann nur >= der Pausen-Position sein, nie zurueckspringen).
        XCTAssertGreaterThanOrEqual(coordinator.currentPosition, pausedPosition)

        coordinator.stop()
        XCTAssertFalse(coordinator.isPlaying)
        XCTAssertFalse(coordinator.isPaused)
    }
#endif

    // Braucht die AVAudioEngine-gebundene Live-Klasse — entfällt unter Linux.
#if canImport(AVFoundation) && canImport(Combine)
    /// Seek im gestoppten Zustand merkt die Position vor; play() startet dort.
    @MainActor
    func testSeekWhileStoppedStartsPlaybackAtPosition() async throws {
        // makeMod liefert einen 2-Positionen-Song.
        let mod = try ModParser.parse(data: makeMod(effectId: 0x00, effectData: 0x00))
        let coordinator = ModPlayerCoordinator()
        coordinator.setMod(mod)

        coordinator.seek(toPosition: 1)
        XCTAssertEqual(coordinator.currentPosition, 1, "Slider-Position muss auch gestoppt sichtbar sein")

        coordinator.play()
        guard coordinator.isPlaying else { return } // kein Audio-Geraet -> skip
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(coordinator.currentPosition, 1, "Wiedergabe muss an der vorgemerkten Position starten")
        coordinator.stop()
    }
#endif

    // Braucht die AVAudioEngine-gebundene Live-Klasse — entfällt unter Linux.
#if canImport(AVFoundation) && canImport(Combine)
    /// Relativer Zeitsprung (+30s) rechnet Sekunden in Zeilen um und springt
    /// zeilengenau; das Ziel wird ans Songende geklemmt.
    @MainActor
    func testSeekBySecondsJumpsForward() async throws {
        let mod = try ModParser.parse(data: makeMod(effectId: 0x00, effectData: 0x00))
        let coordinator = ModPlayerCoordinator()
        coordinator.setMod(mod)
        coordinator.play()
        guard coordinator.isPlaying else { return }

        try await Task.sleep(nanoseconds: 200_000_000)
        // Bei 125 BPM / Speed 6 dauert eine Zeile 0,12s -> +10s = ~83 Zeilen,
        // also mitten in Position 1 (weit genug vor dem Songende, damit der
        // Song waehrend der Pruef-Wartezeit nicht auf Position 0 wrappt).
        coordinator.seek(bySeconds: 10)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(coordinator.currentPosition, 1)
        coordinator.stop()
    }
#endif

    // Braucht die AVAudioEngine-gebundene Live-Klasse — entfällt unter Linux.
#if canImport(AVFoundation) && canImport(Combine)
    /// Vor dem Fix: ein Dxx mit BCD-Wert > 63 (z.B. D99 = 99) setzte rowIndex
    /// auf 99; der Wrap-Test `== 64` traf nie, also kletterte die Zeile endlos
    /// und der Song hing stumm fest. Jetzt muss rowIndex immer 0..63 bleiben.
    @MainActor
    func testOutOfRangePatternBreakDoesNotHang() throws {
        // Effekt 0x0D (Pattern Break), Daten 0x99 -> BCD 9*10+9 = 99 (> 63).
        let mod = try ModParser.parse(data: makeMod(effectId: 0x0D, effectData: 0x99))
        let coordinator = ModPlayerCoordinator()
        let samples = coordinator.renderProbe(mod: mod, durationSeconds: 3.0)

        XCTAssertFalse(samples.isEmpty, "Probe sollte Samples liefern")
        let maxRow = samples.map { $0.row }.max() ?? -1
        XCTAssertLessThanOrEqual(maxRow, 63, "rowIndex darf nie ueber 63 klettern (kein Hang)")
        XCTAssertGreaterThanOrEqual(samples.map { $0.row }.min() ?? -1, 0)
    }
#endif

    // Braucht die AVAudioEngine-gebundene Live-Klasse — entfällt unter Linux.
#if canImport(AVFoundation) && canImport(Combine)
    /// Hardware-freier Render-Smoke-Test: Das eingebaute Demo-Mod muss ueber
    /// renderProbe hoerbares Audio erzeugen. Laeuft OHNE audio/-Ordner und OHNE
    /// Audio-Geraet (reine Berechnung) — die DSP-Regression skippt also nie still,
    /// auch auf CI / frischem Checkout.
    @MainActor
    func testDemoModRenderProducesAudio() {
        let mod = ModParser.generateDemoMod()
        let coordinator = ModPlayerCoordinator()
        let samples = coordinator.renderProbe(mod: mod, durationSeconds: 2.0)
        XCTAssertFalse(samples.isEmpty)
        let peak = samples.flatMap { $0.channelOutputs }.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.001, "Demo-Mod muss hoerbares Audio rendern")
    }
#endif

    // Braucht die AVAudioEngine-gebundene Live-Klasse — entfällt unter Linux.
#if canImport(AVFoundation) && canImport(Combine)
    /// Regressionstest fuer die toten BPM-/Speed-Stepper: vor dem Fix hatten
    /// `coordinator.bpm`/`coordinator.speed` keinen `didSet`, der den Wert an den
    /// Echtzeit-Zustand durchreichte. Eine Stepper-Aenderung wurde deshalb nie
    /// wirksam und ausserdem beim naechsten VU-Poll wieder vom Render-Zustand
    /// ueberschrieben. Nach dem Fix muss eine gesetzte BPM/Speed bestehen bleiben,
    /// auch nachdem der VU-Poller mehrfach gelaufen ist.
    @MainActor
    func testTempoSteppersPersistThroughVUPoll() async throws {
        let mod = try ModParser.parse(data: makeMod(effectId: 0, effectData: 0))
        let coordinator = ModPlayerCoordinator()
        coordinator.setMod(mod)
        coordinator.play()
        XCTAssertTrue(coordinator.isPlaying)

        // Vom Default (125 BPM / Speed 6) bewusst weg auf eindeutige Testwerte.
        coordinator.bpm = 140
        coordinator.speed = 4

        // Laenger warten als ein VU-Poll-Intervall (0,02 s), damit der Poller
        // mehrfach gelaufen ist und einen alten Render-Zustand wieder
        // zurueckschreiben koennte — was er nach dem Fix nicht mehr tut.
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(coordinator.bpm, 140, "Stepper-BPM darf nicht vom VU-Poll ueberschrieben werden")
        XCTAssertEqual(coordinator.speed, 4, "Stepper-Speed darf nicht vom VU-Poll ueberschrieben werden")

        coordinator.seek(toPosition: 1)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(coordinator.bpm, 140,
                       "Positionsslider darf die manuelle BPM-Aenderung nicht verwerfen")
        XCTAssertEqual(coordinator.speed, 4,
                       "Positionsslider darf die manuelle Speed-Aenderung nicht verwerfen")

        coordinator.stop()
    }
#endif

    // Braucht die AVAudioEngine-gebundene Live-Klasse — entfällt unter Linux.
#if canImport(AVFoundation) && canImport(Combine)
    /// Ein wohlgeformtes Break (D32 = Zeile 32) muss exakt diese Zielzeile
    /// erreichen und NICHT umgelenkt werden.
    @MainActor
    func testInRangePatternBreakReachesTargetRow() throws {
        let mod = try ModParser.parse(data: makeMod(effectId: 0x0D, effectData: 0x32))
        let coordinator = ModPlayerCoordinator()
        let samples = coordinator.renderProbe(mod: mod, durationSeconds: 3.0)
        // Nach dem Break auf Position 0 Row 0 springt der Song auf Position 1,
        // Row 32 — diese Zeile muss in den Proben auftauchen.
        let reached = samples.contains { $0.position == 1 && $0.row == 32 }
        XCTAssertTrue(reached, "D32 muss Position 1 / Row 32 erreichen")
    }
#endif

    // Braucht die AVAudioEngine-gebundene Live-Klasse — entfällt unter Linux.
#if canImport(AVFoundation) && canImport(Combine)
    /// Friert die heutige doppelte Sequencer-Implementierung vor dem Refactor
    /// zustandsgenau ein. Coverage-Marker verhindern, dass zwei wirkungslose
    /// Pfade durch lauter identische Defaultwerte versehentlich bestehen.
    @MainActor
    func testRenderBlockAndProbeProduceIdenticalSequencerTrace() throws {
        let mod = makeTraceMod()
        let duration = 0.6
        let coordinator = ModPlayerCoordinator()
        let probe = coordinator.renderProbe(mod: mod, durationSeconds: duration)
        let blockTraces = try renderBlockTraces(mod: mod, durationSeconds: duration)
        let probeTraces = probe.map(\.trace)

        XCTAssertEqual(probe.map(\.frame), Array(stride(from: 0, to: Int(44100 * duration), by: 256)),
                       "Die bestehende 256-Frame-Abtastung darf sich nicht aendern")
        XCTAssertEqual(blockTraces, probeTraces,
                       "Live-/Offline-Block und Probe muessen elementweise gleich bleiben")

        XCTAssertTrue(probeTraces.contains { $0.speed == 3 }, "F03/Speed nicht erreicht")
        XCTAssertTrue(probeTraces.contains { $0.tempo == 150 }, "F96/Tempo nicht erreicht")
        XCTAssertTrue(probeTraces.contains { $0.globalVolume == 32 }, "Global Volume nicht erreicht")
        XCTAssertTrue(probeTraces.contains { $0.patternLoopRow == 0 }, "E61-Loopziel nicht erreicht")
        XCTAssertTrue(probeTraces.contains { $0.patternDelay == 2 }, "EE2-Delay nicht erreicht")
        XCTAssertTrue(probeTraces.contains { $0.patternDelayCounter > 0 }, "EE2-Counter nicht aktiv")
        XCTAssertTrue(probeTraces.contains { $0.positionJump == 1 }, "B01-Jump nicht vorgemerkt")
        XCTAssertTrue(probeTraces.contains { $0.patternBreak == 5 }, "D05-Break nicht vorgemerkt")
        XCTAssertTrue(probeTraces.contains { $0.position == 1 && $0.pattern == 1 && $0.row == 5 },
                      "B01 und D05 muessen gemeinsam Position 1 / Pattern 1 / Row 5 erreichen")

        // E61 muss den vorgemerkten Wert auch wirklich verbrauchen: Zwischen
        // zwei benachbarten Snapshots geht Position 0 von Row 1 zur Loop-Row 0.
        let adjacentSnapshots = Array(zip(probeTraces, probeTraces.dropFirst()))
        XCTAssertTrue(adjacentSnapshots.contains { before, after in
            before.position == 0 && before.row == 1
                && after.position == 0 && after.row == 0
        }, "E61 muss innerhalb Position 0 tatsaechlich von Row 1 zu Row 0 springen")

        // EE2 erzeugt im heutigen Sequencer exakt drei zusaetzliche Tick-Wraps
        // von 2 auf 0, waehrend Position und Row unveraendert auf 0/2 bleiben.
        // Mit 735 Frames pro Tick liegt zwischen zwei 256-Frame-Snapshots nie
        // mehr als eine Tick-Grenze, daher kann die Abtastung keinen Wrap missen.
        let delayWrapCounters = adjacentSnapshots.compactMap { before, after -> Int? in
            guard before.position == 0, before.row == 2, before.tick == 2,
                  after.position == 0, after.row == 2, after.tick == 0 else { return nil }
            return after.patternDelayCounter
        }
        XCTAssertEqual(delayWrapCounters, [2, 1, 0],
                       "EE2 muss die heutigen drei Row-2-Wiederholungen exakt bewahren")
    }
#endif

    // Braucht die AVAudioEngine-gebundene Live-Klasse — entfällt unter Linux.
#if canImport(AVFoundation) && canImport(Combine)
    /// Der Track-Loop setzt die Anzeige-Uhr zurueck. Die veroeffentlichte
    /// Spielzeit muss SOFORT mitziehen: Der Aufrufer aktualisiert direkt danach
    /// den Sperrbildschirm aus `visualizerState.elapsedTime` und zeigte dort
    /// sonst noch einmal die alte, zu lange Zeit. Braucht ein Audio-Geraet —
    /// ohne (z.B. CI) startet play() nicht und der Test endet still.
    @MainActor
    func testResetElapsedToLoopStartPublishesTheNewTimeImmediately() async throws {
        let coordinator = ModPlayerCoordinator()
        coordinator.setMod(ModParser.generateDemoMod())
        coordinator.play()
        guard coordinator.isPlaying else { return }
        defer { coordinator.stop() }

        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertGreaterThan(coordinator.visualizerState.elapsedTime, 0.1,
                             "die Uhr muss vor dem Reset schon gelaufen sein")

        coordinator.resetElapsedToLoopStart()

        // Das Demo-Mod hat den Neustartpunkt 0, die Uhr steht danach also
        // wieder am Songanfang — und zwar ohne auf den naechsten VU-Takt oder
        // Audio-Callback zu warten.
        XCTAssertLessThan(coordinator.visualizerState.elapsedTime, 0.05,
                          "die veroeffentlichte Spielzeit muss sofort am Loop-Punkt stehen")
    }
#endif

    /// XM Hxy senkt (bzw. hebt) die globale Lautstärke auf jedem Folgetick der
    /// Zeile; H00 nutzt das Kanal-Memory. Läuft über den echten Render-Block,
    /// damit der SequencerCore-Pfad (Row-Reset + Per-Tick-Anwendung) geprüft ist.
    func testXMGlobalVolumeSlidePerTickWithMemory() throws {
        let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
        func effect(_ id: Int, _ data: Int) -> Note {
            Note(instrument: 0, period: 0, effectId: id, effectData: data)
        }
        func emptyRow() -> Row { Row(notes: [Note](repeating: empty, count: 4)) }
        var rows: [Row] = [
            Row(notes: [effect(ModuleEffect.globalVolumeSlide, 0x04), empty, empty, empty]),
            Row(notes: [effect(ModuleEffect.globalVolumeSlide, 0x00), empty, empty, empty])
        ]
        rows += (0..<6).map { _ in emptyRow() }
        let mod = Mod(
            name: "hxy",
            length: 1,
            patternTable: [0],
            instruments: [nil],
            patterns: [Pattern(rows: rows)],
            channelCount: 4,
            format: .xm,
            linearFrequency: true
        )
        let traces = try renderBlockTraces(mod: mod, durationSeconds: 0.5)
        let afterRow0 = try XCTUnwrap(traces.first { $0.row == 1 })
        XCTAssertEqual(afterRow0.globalVolume, 44,
                       "H04 muss auf den fünf Folgeticks von Row 0 je 4 abziehen")
        let afterRow1 = try XCTUnwrap(traces.first { $0.row == 2 })
        XCTAssertEqual(afterRow1.globalVolume, 24,
                       "H00 muss den gemerkten 04-Parameter weiterverwenden")
        XCTAssertEqual(try XCTUnwrap(traces.last).globalVolume, 24,
                       "ohne weiteren H-Befehl bleibt die globale Lautstärke stehen")
    }

    // MARK: - Anzeige-Uhr im Track-Loop

    /// Baut einen Renderblock samt Zustand fuer die Uhr-Tests. Kein Audiogeraet,
    /// keine Engine — derselbe Block wie App, WAV-Export und Quick Look.
    private func makeBlockAndState(
        mod: Mod,
        sampleRate: Double = 44100.0,
        existingState: RealtimePlaybackState? = nil
    ) -> (block: ModuleRenderBlock, state: RealtimePlaybackState, hold: [AnyObject]) {
        let channels = RenderEngine.makeRenderChannels(for: mod)
        let state = existingState
            ?? RenderEngine.makeRenderState(for: mod, sampleRate: sampleRate)
        let channelCount = channels.count
        let peaks = UnsafeMutablePointer<Float>.allocate(capacity: channelCount)
        peaks.initialize(repeating: 0, count: channelCount)
        let waves = UnsafeMutablePointer<Float>.allocate(capacity: channelCount * 32)
        waves.initialize(repeating: 0, count: channelCount * 32)
        let masterWaves = UnsafeMutablePointer<Float>.allocate(capacity: 128)
        masterWaves.initialize(repeating: 0, count: 128)
        let vu = RealtimeVUBuffer(pointer: peaks)
        let wave = RealtimeWaveBuffer(channelWaves: waves, masterWaves: masterWaves)
        let block = RenderEngine.createRenderBlock(
            state: state, vuBuffer: vu, waveBuffer: wave,
            dspChannels: channels, mod: mod, sampleRate: sampleRate)
        // Puffer und Kanaele muessen den Block ueberleben; der Aufrufer haelt sie.
        return (block, state, [vu, wave] + channels)
    }

#if canImport(AVFoundation) && canImport(Combine)
    /// Ein altes Songende darf den Seek nicht ueber den MainActor-Poller
    /// ueberholen. Bis zum Audioblock bleibt der Ziel-Snapshot sichtbar; danach
    /// uebernimmt der Poller genau den atomar veroeffentlichten Renderstand.
    @MainActor
    func testPendingSeekKeepsTargetAndDiscardsOldEndTransition() {
        let mod = makeTraceMod()
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: 44_100)
        let coordinator = ModPlayerCoordinator()
        state.publishEndTransition(frame: 1_000, position: 0, row: 3)

        coordinator.requestSeek(
            state: state,
            mod: mod,
            position: 1,
            row: 4,
            speed: 8,
            bpm: 150,
            globalVolume: 32)
        coordinator.synchronizePlaybackState(state)

        XCTAssertEqual(coordinator.songEndPulse, 0)
        XCTAssertEqual(coordinator.currentPosition, 1)
        XCTAssertEqual(coordinator.currentRow, 4)
        let pending = coordinator.seekTransport(for: state)
        XCTAssertEqual(pending.position, 1)
        XCTAssertEqual(pending.row, 4)
        XCTAssertEqual(pending.ticksPerRow, 8)
        XCTAssertEqual(pending.bpm, 150)

        let (block, _, hold) = makeBlockAndState(
            mod: mod, existingState: state)
        let buffer = StereoRenderBuffer(capacity: 64)
        block(64, buffer.left, buffer.right)
        coordinator.synchronizePlaybackState(state)

        XCTAssertEqual(coordinator.songEndPulse, 0)
        XCTAssertEqual(coordinator.currentPosition, 1)
        XCTAssertEqual(coordinator.currentRow, 4)
        XCTAssertEqual(coordinator.speed, 8)
        XCTAssertEqual(coordinator.bpm, 150)
        XCTAssertFalse(state.endReached)
        withExtendedLifetime(hold) {}
    }
#endif

    /// Der Hauptthread darf `elapsedFrames` nicht selbst schreiben — der
    /// Renderblock erhoeht denselben Zaehler pro Frame, und ein direkter
    /// Schreibzugriff koennte zwischen dessen Lesen und Zurueckschreiben
    /// verlorengehen. Stattdessen legt er einen Auftrag ab, den der Block genau
    /// einmal uebernimmt.
    func testRenderBlockAppliesPendingElapsedFramesExactlyOnce() {
        let mod = ModParser.generateDemoMod()
        let (block, state, hold) = makeBlockAndState(mod: mod)
        let buffer = StereoRenderBuffer(capacity: 256)

        block(64, buffer.left, buffer.right)
        XCTAssertEqual(state.elapsedFrames, 64)

        state.pendingElapsedFrames = 5_000
        block(10, buffer.left, buffer.right)
        XCTAssertEqual(state.elapsedFrames, 5_010, "der Auftrag muss am Frame-Anfang greifen")
        XCTAssertEqual(state.pendingElapsedFrames, .max, "der Auftrag gilt genau einmal")

        block(10, buffer.left, buffer.right)
        XCTAssertEqual(state.elapsedFrames, 5_020, "danach zaehlt der Block normal weiter")
        withExtendedLifetime(hold) {}
    }

    func testSeekMutatesSequencerAndChannelsOnlyInsideRenderBlock() {
        let mod = makeTraceMod()
        let channels = RenderEngine.makeRenderChannels(for: mod)
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: 44_100)
        state.outputsUntilNextTick = 100
        state.positionJump = 7
        state.patternBreak = 12
        channels[0].playing = true

        let channelCount = channels.count
        let peaks = UnsafeMutablePointer<Float>.allocate(capacity: channelCount)
        defer { peaks.deallocate() }
        peaks.initialize(repeating: 0, count: channelCount)
        let waves = UnsafeMutablePointer<Float>.allocate(capacity: channelCount * 32)
        defer { waves.deallocate() }
        waves.initialize(repeating: 0, count: channelCount * 32)
        let master = UnsafeMutablePointer<Float>.allocate(capacity: 128)
        defer { master.deallocate() }
        master.initialize(repeating: 0, count: 128)
        let block = RenderEngine.createRenderBlock(
            state: state,
            vuBuffer: RealtimeVUBuffer(pointer: peaks),
            waveBuffer: RealtimeWaveBuffer(channelWaves: waves, masterWaves: master),
            dspChannels: channels,
            mod: mod,
            sampleRate: 44_100)
        let buffer = StereoRenderBuffer(capacity: 1)

        state.requestSeek(
            position: 1,
            row: 3,
            ticksPerRow: 8,
            bpm: 150,
            globalVolume: 32,
            elapsedFrames: 9_000)

        XCTAssertEqual(state.position, 0, "der Producer legt nur einen Auftrag ab")
        XCTAssertTrue(channels[0].playing, "Kanaele gehoeren bis zum Callback dem Audiothread")

        block(1, buffer.left, buffer.right)

        XCTAssertEqual(state.position, 1)
        XCTAssertEqual(state.rowIndex, 3, "der erste Frame muss die Zielzeile laden")
        XCTAssertEqual(state.tick, 0)
        XCTAssertEqual(state.ticksPerRow, 8)
        XCTAssertEqual(state.bpm, 150)
        XCTAssertEqual(state.globalVolume, 32)
        XCTAssertEqual(state.positionJump, -1)
        XCTAssertEqual(state.patternBreak, -1)
        XCTAssertFalse(channels[0].playing)
        XCTAssertEqual(state.elapsedFrames, 9_001)
        XCTAssertEqual(state.publishedElapsedFrames, 9_001)
    }

    func testConsumedEndTransitionNeutralizesFallbackMetadata() throws {
        let state = RealtimePlaybackState()
        state.publishEndTransition(frame: 12_345, position: 7, row: 11)

        let transition = try XCTUnwrap(state.consumeEndTransition())

        XCTAssertEqual(transition.frame, 12_345)
        XCTAssertEqual(transition.position, 7)
        XCTAssertEqual(transition.row, 11)
        XCTAssertEqual(state.endReachedFrame, .max)
        XCTAssertEqual(state.endReachedPosition, -1)
        XCTAssertEqual(state.endReachedRow, 0)
    }

    func testSeekSnapshotClampsToItsPublishedFieldWidths() throws {
        let state = RealtimePlaybackState()
        state.requestSeek(
            position: 70_000,
            row: 40_000,
            ticksPerRow: 300,
            bpm: 70_000,
            globalVolume: 300,
            elapsedFrames: 123)

        let request = try XCTUnwrap(state.takePendingSeek())

        XCTAssertEqual(request.position, Int(UInt16.max))
        XCTAssertEqual(request.row, Int(Int16.max))
        XCTAssertEqual(request.ticksPerRow, Int(UInt8.max))
        XCTAssertEqual(request.bpm, Int(UInt16.max))
        XCTAssertEqual(request.globalVolume, Int(UInt8.max))
        XCTAssertEqual(request.elapsedFrames, 123)
    }

    func testSeekSnapshotStressNeverMixesTwoRequests() {
        let state = RealtimePlaybackState()
        let lastValue = 20_000
        let mismatch = LockFreeAtomicUInt64(.max)
        let producerDone = LockFreeAtomicUInt64(0)
        let producer = expectation(description: "seek producer")
        let consumer = expectation(description: "seek consumer")

        DispatchQueue.global(qos: .userInitiated).async {
            for value in 1...lastValue {
                state.requestSeek(
                    position: value,
                    row: value % 1_000,
                    ticksPerRow: value % 200 + 1,
                    bpm: value % 400 + 32,
                    globalVolume: value % 129,
                    elapsedFrames: UInt64(value * 7))
            }
            producerDone.storeRelease(1)
            producer.fulfill()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            while true {
                if let request = state.takePendingSeek() {
                    let value = request.position
                    if request.row != value % 1_000
                        || request.ticksPerRow != value % 200 + 1
                        || request.bpm != value % 400 + 32
                        || request.globalVolume != value % 129
                        || request.elapsedFrames != UInt64(value * 7) {
                        mismatch.storeRelaxed(UInt64(value))
                        break
                    }
                    if value == lastValue { break }
                } else if producerDone.loadAcquire() != 0 {
                    // Nach Producer-Ende genau einen letzten Versuch machen.
                    // Bleibt er leer, muss der letzte konsistente Snapshot
                    // bereits konsumiert worden sein.
                    guard let finalRequest = state.takePendingSeek() else { break }
                    if finalRequest.position != lastValue {
                        mismatch.storeRelaxed(UInt64(finalRequest.position))
                    }
                    break
                }
            }
            consumer.fulfill()
        }

        wait(for: [producer, consumer], timeout: 10)
        XCTAssertEqual(mismatch.loadRelaxed(), .max)
    }

    /// Echte Producer-/Consumer-Konkurrenz: Jeder Uhr-Auftrag muss genau
    /// einmal und in Reihenfolge aus dem atomaren Sentinel kommen. Der Test
    /// laeuft auch unter TSan; die fruehere normale Swift-Variable meldete dort
    /// einen Zugriffskonflikt beziehungsweise verlor Auftraege.
    func testPendingElapsedFramesAtomicStressConsumesEveryRequestExactlyOnce() {
        let state = RealtimePlaybackState()
        let count: UInt64 = 20_000
        let mismatch = LockFreeAtomicUInt64(.max)
        let producerDone = expectation(description: "producer")
        let consumerDone = expectation(description: "consumer")

        DispatchQueue.global(qos: .userInitiated).async {
            for value in 0..<count {
                while state.pendingElapsedFrames != .max {}
                state.pendingElapsedFrames = value
            }
            producerDone.fulfill()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var expected: UInt64 = 0
            while expected < count {
                let value = state.takePendingElapsedFrames()
                guard value != .max else { continue }
                if value != expected {
                    mismatch.storeRelaxed(value)
                    break
                }
                expected += 1
            }
            consumerDone.fulfill()
        }

        wait(for: [producerDone, consumerDone], timeout: 10)
        XCTAssertEqual(mismatch.loadRelaxed(), .max)
        XCTAssertEqual(state.pendingElapsedFrames, .max)
    }

    /// Der Endtransition-Snapshot wird komplett geschrieben, bevor das
    /// atomare Signal sichtbar wird. Der Leser nimmt Frame/Position/Zeile vor
    /// dem Freigeben des Slots auf; dadurch kann kein gemischtes Wertepaar aus
    /// zwei aufeinanderfolgenden Transitionen entstehen.
    func testEndTransitionSnapshotReleaseAcquireStressStaysConsistent() {
        let state = RealtimePlaybackState()
        let count: UInt64 = 10_000
        let mismatch = LockFreeAtomicUInt64(.max)
        let producerDone = expectation(description: "snapshot producer")
        let consumerDone = expectation(description: "snapshot consumer")

        DispatchQueue.global(qos: .userInitiated).async {
            for value in 0..<count {
                while state.endReached {}
                state.publishEndTransition(
                    frame: value,
                    position: Int(value),
                    row: Int(value * 2))
            }
            producerDone.fulfill()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var expected: UInt64 = 0
            while expected < count {
                guard let snapshot = state.consumeEndTransition() else { continue }
                if snapshot.frame != expected
                    || snapshot.position != Int(expected)
                    || snapshot.row != Int(expected * 2) {
                    mismatch.storeRelaxed(snapshot.frame)
                    break
                }
                expected += 1
            }
            consumerDone.fulfill()
        }

        wait(for: [producerDone, consumerDone], timeout: 10)
        XCTAssertEqual(mismatch.loadRelaxed(), .max)
        XCTAssertFalse(state.endReached)
    }

    /// Ein rueckwaerts gerichteter Bxx-Sprung gilt als Songende, landet aber auf
    /// seinem eigenen Ziel — nicht auf `restartPosition`. Ein zusaetzliches Dxx
    /// setzt dort noch die Zielzeile. Genau dieses Ziel muss der Renderzustand
    /// festhalten, sonst setzt der Track-Loop die Anzeige-Uhr auf einen anderen
    /// Punkt als den, an dem wirklich weitergespielt wird.
    func testBackwardPositionJumpRecordsItsOwnTargetAsLoopPoint() {
        let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
        func effect(_ id: Int, _ data: Int) -> Note {
            Note(instrument: 0, period: 0, effectId: id, effectData: data)
        }
        func emptyRow() -> Row { Row(notes: [Note](repeating: empty, count: 4)) }

        // Position 0: vier leere Zeilen. Position 1, Zeile 0: B00 (zurueck auf
        // Position 0) zusammen mit D02 (dort Zeile 2).
        let pattern0 = Pattern(rows: (0..<4).map { _ in emptyRow() })
        let pattern1 = Pattern(rows: [
            Row(notes: [effect(0x0B, 0), effect(0x0D, 2), empty, empty]),
            emptyRow(), emptyRow(), emptyRow()
        ])
        let mod = Mod(
            name: "bxx-loop",
            length: 2,
            patternTable: [0, 1],
            instruments: [nil],
            patterns: [pattern0, pattern1],
            channelCount: 4
        )

        let (block, state, hold) = makeBlockAndState(mod: mod)
        // Bewusst ein anderer Neustartpunkt: Nur so zeigt der Test, dass die Uhr
        // wirklich das Sprungziel nimmt und nicht `restartPosition`.
        state.restartPosition = 1
        let buffer = StereoRenderBuffer(capacity: 256)
        for _ in 0..<200 { block(256, buffer.left, buffer.right) }   // ~1,2 s

        XCTAssertTrue(state.endReached || state.endReachedFrame != .max,
                      "der rueckwaerts gerichtete Bxx-Sprung muss als Songende gelten")
        XCTAssertEqual(state.endReachedPosition, 0, "Ziel des Bxx-Sprungs, nicht restartPosition")
        XCTAssertEqual(state.endReachedRow, 2, "Dxx setzt die Zielzeile des Sprungs")
        withExtendedLifetime(hold) {}
    }

    func testLoopElapsedTimeIncludesFramesRenderedSinceTransition() {
        XCTAssertEqual(
            RenderEngine.elapsedFramesAfterLoopTransition(
                loopStartFrames: 4_000,
                transitionFrame: 100_000,
                renderedFrame: 101_470),
            5_470)
    }

    // Mute und Solo liegen bei IT am logischen Pattern-Kanal, bei allen anderen
    // Formaten an der Stimme. Setzen und Lesen muessen denselben Traeger
    // treffen — sonst schaltet die Oberflaeche den einen stumm und liest den
    // anderen aus, und der M/S-Schalter zeigt etwas anderes an, als zu hoeren
    // ist. Die Auswahl lag frueher in vier Funktionen getrennt vor.
#if canImport(AVFoundation) && canImport(Combine)
    @MainActor
    func testMuteAndSoloReadBackWhatWasSet() throws {
        let coordinator = ModPlayerCoordinator()
        coordinator.setMod(try ModParser.parse(data: makeMod(effectId: 0, effectData: 0)))

        XCTAssertFalse(coordinator.isMuted(channelIndex: 0))
        XCTAssertFalse(coordinator.isSoloed(channelIndex: 0))

        coordinator.toggleMute(channelIndex: 0)
        XCTAssertTrue(coordinator.isMuted(channelIndex: 0))
        XCTAssertFalse(coordinator.isMuted(channelIndex: 1), "nur der gewaehlte Kanal")
        XCTAssertFalse(coordinator.isSoloed(channelIndex: 0), "Mute darf Solo nicht mitsetzen")

        coordinator.toggleSolo(channelIndex: 2)
        XCTAssertTrue(coordinator.isSoloed(channelIndex: 2))
        XCTAssertFalse(coordinator.isMuted(channelIndex: 2), "Solo darf Mute nicht mitsetzen")

        coordinator.toggleMute(channelIndex: 0)
        XCTAssertFalse(coordinator.isMuted(channelIndex: 0))

        // Indizes ausserhalb des Kanalbereichs bleiben wirkungslos statt zu
        // beenden.
        coordinator.toggleMute(channelIndex: -1)
        coordinator.toggleMute(channelIndex: 999)
        XCTAssertFalse(coordinator.isMuted(channelIndex: -1))
        XCTAssertFalse(coordinator.isSoloed(channelIndex: 999))
    }

    /// Eine vorab ermittelte Spieldauer wird uebernommen statt neu berechnet.
    ///
    /// Hintergrund (2026-08-23): Die Dauerprobe taktet den Sequencer einmal
    /// komplett durch und ist bei einem grossen Modul der teuerste Teil des
    /// Ladens. `setMod` laeuft auf dem MainActor, also rechnet die iPhone-App
    /// sie im Hintergrund aus und reicht sie herein. Dieser Test haelt beide
    /// Haelften des Vertrags fest: ohne Angabe wird gerechnet, mit Angabe wird
    /// der uebergebene Wert genommen.
    @MainActor
    func testPrecomputedDurationIsUsedAsGiven() {
        let mod = ModParser.generateDemoMod()
        let computed = RenderEngine.sequencedDuration(of: mod)
        XCTAssertGreaterThan(computed, 0, "Das Demomodul muss eine messbare Dauer haben")

        let withoutHint = ModPlayerCoordinator()
        withoutHint.setMod(mod)
        XCTAssertEqual(withoutHint.visualizerState.totalDuration, computed, accuracy: 0.0001)

        // Ein bewusst falscher Wert belegt, dass die Angabe wirklich gewinnt —
        // mit dem korrekten Wert waere der Test nicht unterscheidbar.
        let withHint = ModPlayerCoordinator()
        withHint.setMod(mod, precomputedDuration: computed + 42)
        XCTAssertEqual(withHint.visualizerState.totalDuration, computed + 42, accuracy: 0.0001)
    }

    /// Die Bildrate der Visualisierungen wird auf 1…60 Hz geklemmt.
    ///
    /// Hintergrund (2026-08-23): Die Bildrate ist seit 1.6.10 einstellbar. 0 Hz
    /// ergaebe ein Timer-Intervall von unendlich, ein sehr grosser Wert einen
    /// Timer, der den MainActor flutet — beides waere aus einer verstellten
    /// Voreinstellung heraus erreichbar.
    func testVisualizerIntervalIsClampedToASensibleRange() {
        let interval = ModPlayerCoordinator.visualizerUpdateInterval
        XCTAssertEqual(interval(30, true), 1.0 / 30.0, accuracy: 0.00001)
        XCTAssertEqual(interval(10, true), 0.1, accuracy: 0.00001)
        XCTAssertEqual(interval(0, true), 1.0, accuracy: 0.00001, "0 Hz wird auf 1 Hz geklemmt")
        XCTAssertEqual(interval(-5, true), 1.0, accuracy: 0.00001)
        XCTAssertEqual(interval(1000, true), 1.0 / 60.0, accuracy: 0.00001, "Obergrenze 60 Hz")
        XCTAssertEqual(interval(30, false), 0.2, accuracy: 0.00001,
                       "Im Kompaktmodus bleibt es bei 5 Hz, unabhaengig von der Einstellung")
    }
#endif
}

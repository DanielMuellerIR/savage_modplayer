import XCTest
@testable import SavageModPlayerCore

/// Der Echtzeit-Wiedergabepfad (ModulePCMSource -> PCMSink) muss dieselben Samples
/// liefern wie der Offline-Render (ModuleRenderer). Beide holen ihre Daten aus
/// `RenderEngine.createRenderBlock`; laufen sie auseinander, ist genau die
/// Invariante verletzt, dass es EINE Engine gibt.
///
/// Der Test braucht kein Audiogeraet: er ruft den PCMRenderBlock direkt auf.
final class ModulePCMSourceTests: XCTestCase {

    /// Interleavte Echtzeit-Ausgabe gegen den Offline-WAV-Body, Sample fuer Sample.
    ///
    /// Nebenbei ein Test der Chunk-Logik: der Offline-Renderer arbeitet in
    /// 1024er-Bloecken, ModulePCMSource in bis zu 4096ern. Kaeme dabei etwas
    /// anderes heraus, haenge die Ausgabe an der Blockgroesse — der Sequencer
    /// laeuft aber frame-genau, also darf sie es nicht.
    func testRealtimeSourceMatchesOfflineRender() throws {
        let mod = ModParser.generateDemoMod()
        let sampleRate = 44100.0
        let seconds = 1.0
        let frames = Int(sampleRate * seconds)

        let source = ModulePCMSource(mod: mod, format: PCMFormat(sampleRate: sampleRate, channels: 2))
        let block = source.renderBlock()
        var interleaved = [Float](repeating: 0.0, count: frames * 2)
        var produced = 0
        interleaved.withUnsafeMutableBufferPointer { buffer in
            produced = block(buffer, frames)
        }
        XCTAssertGreaterThan(produced, 0, "Der Echtzeitpfad lieferte gar keine Frames")

        // Offline mit denselben Einstellungen, die ModulePCMSource setzt:
        // normalize aus (der Echtzeitpfad normalisiert nicht), Interpolation an.
        let wav = try ModuleRenderer.renderWavData(
            mod: mod,
            sampleRate: sampleRate,
            maxDurationSeconds: seconds,
            normalize: false,
            useInterpolation: true
        )
        let body = wav.dropFirst(44)
        let offlineFrames = body.count / 4
        let comparable = min(produced, offlineFrames)
        XCTAssertGreaterThan(comparable, Int(sampleRate) / 2, "zu wenig Vergleichsmaterial")

        // WAV ist interleaved Int16 LE; die Echtzeitausgabe ist Float. Also
        // denselben Weg gehen, den der Offline-Renderer nimmt (clamp + 32767).
        let pcm = [UInt8](body)
        for frame in 0..<comparable {
            for channel in 0..<2 {
                let byteIndex = frame * 4 + channel * 2
                let expected = Int16(
                    bitPattern: UInt16(pcm[byteIndex]) | (UInt16(pcm[byteIndex + 1]) << 8)
                )
                let live = interleaved[frame * 2 + channel]
                let actual = Int16(max(-1.0, min(1.0, live)) * 32767.0)
                XCTAssertEqual(
                    actual, expected,
                    "Frame \(frame), Kanal \(channel): Echtzeitpfad weicht vom Offline-Render ab"
                )
                if actual != expected { return } // nicht 88200-mal dasselbe melden
            }
        }
    }

    func testVolumeAndPanningChangeAtExactTrackerFramesAcrossBlockSizes() {
        let instrument = Instrument(
            index: 1, name: "constant", length: 4, finetune: 0, volume: 64,
            repeatOffset: 0, repeatLength: 4, bytes: [64, 64, 64, 64], isLooped: true)
        let mod = Mod(
            name: "tick controls", length: 1, patternTable: [0],
            instruments: [nil, instrument],
            patterns: [Pattern(rows: [
                Row(notes: [Note(instrument: 1, period: 428, effectId: 0, effectData: 0)]),
                Row(notes: [Note(instrument: 0, period: 0, effectId: 0xC, effectData: 32)]),
                Row(notes: [Note(instrument: 0, period: 0, effectId: 0x8, effectData: 255)])
            ])], channelCount: 1, initialSpeed: 1, initialTempo: 125,
            channelPannings: [0])

        func render(chunkSize: Int) -> [Float] {
            let source = ModulePCMSource(
                mod: mod, format: PCMFormat(sampleRate: 8_000, channels: 2), maxFrames: 480)
            let block = source.renderBlock()
            var pcm: [Float] = []
            while pcm.count < 960 {
                let wanted = min(chunkSize, (960 - pcm.count) / 2)
                var buffer = [Float](repeating: 0, count: wanted * 2)
                let produced = buffer.withUnsafeMutableBufferPointer { block($0, wanted) }
                XCTAssertEqual(produced, wanted)
                guard produced == wanted else { break }
                pcm.append(contentsOf: buffer)
            }
            return pcm
        }

        let pcm = render(chunkSize: 480)
        XCTAssertEqual(pcm, render(chunkSize: 97))
        XCTAssertEqual(pcm.count, 960)
        guard pcm.count == 960 else { return }
        // Bei Speed 1, 125 BPM und 8 kHz dauert jede Zeile exakt 160 Frames.
        for frame in 0..<480 {
            let amplitude: Float = frame < 160 ? 0.25 : 0.125
            let leftGain: Float = frame < 320 ? 0.9 : 0.1
            let rightGain: Float = frame < 320 ? 0.1 : 0.9
            XCTAssertEqual(pcm[frame * 2], tanh(amplitude * leftGain), accuracy: 0.000_001)
            XCTAssertEqual(pcm[frame * 2 + 1], tanh(amplitude * rightGain), accuracy: 0.000_001)
        }
    }

    /// Ist der Song zu Ende, muss der Block WENIGER Frames melden als angefordert —
    /// nur daran erkennt der Sink das regulaere Ende (`sourceFinished`) und haengt
    /// nicht ewig. Das Demo-Modul ist kuerzer als die hier angeforderten 60 s.
    func testSourceReportsShortReadAtSongEnd() throws {
        let mod = ModParser.generateDemoMod()
        let source = ModulePCMSource(mod: mod, format: PCMFormat(sampleRate: 8000.0, channels: 2))
        let block = source.renderBlock()

        var total = 0
        var lastWasShort = false
        // In Runden holen, bis der Block kurz liefert (= Songende) oder ein
        // grosszuegiges Limit reisst.
        for _ in 0..<600 {
            let want = 4096
            var got = 0
            var buffer = [Float](repeating: 0.0, count: want * 2)
            buffer.withUnsafeMutableBufferPointer { raw in
                got = block(raw, want)
            }
            total += got
            if got < want { lastWasShort = true; break }
        }
        XCTAssertTrue(lastWasShort, "Der Block meldete das Songende nie durch eine kurze Lieferung")
        XCTAssertGreaterThan(total, 0, "Vor dem Songende muss Signal gekommen sein")
    }

    /// Ein langes oder gelooptes Modul darf den CLI-Stream nicht zwingen, den
    /// ganzen Song zu puffern. Selbst bei einer Anfrage groesser als der interne
    /// 4096er Chunk liefert die Quelle exakt bis zum Frame-Budget und danach 0.
    func testSourceStopsExactlyAtFrameBudgetWithBoundedChunks() {
        let limit: UInt64 = 5_000
        let source = ModulePCMSource(
            mod: ModParser.generateDemoMod(),
            format: PCMFormat(sampleRate: 44_100, channels: 2),
            maxFrames: limit
        )
        let block = source.renderBlock()
        let requested = 9_000
        var buffer = [Float](repeating: 0, count: requested * 2)
        var first = 0
        buffer.withUnsafeMutableBufferPointer { first = block($0, requested) }
        XCTAssertEqual(first, Int(limit))

        var second = -1
        buffer.withUnsafeMutableBufferPointer { second = block($0, requested) }
        XCTAssertEqual(second, 0)
        XCTAssertEqual(source.deliveredFrames, limit)
    }
}

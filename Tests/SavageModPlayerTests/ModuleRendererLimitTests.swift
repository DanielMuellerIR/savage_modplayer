import XCTest
@testable import SavageModPlayerCore

final class ModuleRendererLimitTests: XCTestCase {
    func testValidatedFrameLimitAcceptsDocumentedBoundary() throws {
        XCTAssertEqual(
            try ModuleRenderer.validatedFrameLimit(
                sampleRate: ModuleRenderer.maxSampleRate,
                maxDurationSeconds: ModuleRenderer.maxDurationSeconds
            ),
            ModuleRenderer.maxRenderedFrames
        )
    }

    func testRendererRejectsNonFiniteAndOutOfRangeSampleRates() {
        for rate in [Double.nan, Double.infinity, -1, 0, 192_001] {
            XCTAssertThrowsError(
                try ModuleRenderer.renderWavData(
                    mod: ModParser.generateDemoMod(),
                    sampleRate: rate,
                    maxDurationSeconds: 1
                )
            ) { error in
                guard case ModuleRenderer.RenderError.invalidSampleRate = error else {
                    return XCTFail("Falscher Fehler für Samplerate \(rate): \(error)")
                }
            }
        }
    }

    // Die Echtzeit-Wiedergabe streamt und braucht kein Offline-Speicherbudget.
    // Ein Ausgabegeraet mit mehr als 192 kHz (die Offline-Obergrenze) darf sie
    // deshalb nicht verhindern — genau daran scheiterte `savage-cli --play`
    // frueher, bevor ueberhaupt ein Ton kam.
    func testLiveFrameLimitAllowsSampleRatesAboveTheOfflineCeiling() throws {
        let rate = ModuleRenderer.maxSampleRate * 2   // 384 kHz
        XCTAssertThrowsError(
            try ModuleRenderer.validatedFrameLimit(sampleRate: rate, maxDurationSeconds: 600)
        ) { error in
            guard case ModuleRenderer.RenderError.invalidSampleRate = error else {
                return XCTFail("Offline-Pfad muss \(rate) Hz weiterhin ablehnen: \(error)")
            }
        }
        XCTAssertEqual(
            try ModuleRenderer.liveFrameLimit(sampleRate: rate, maxDurationSeconds: 600),
            UInt64(rate * 600)
        )
    }

    // Die Dauergrenze gilt weiter: ein Modul ohne erreichbares Endsignal soll
    // auch live nicht endlos weiterlaufen.
    func testLiveFrameLimitKeepsDurationAndSampleRateFloor() {
        for duration in [Double.nan, Double.infinity, -1, 0, 601] {
            XCTAssertThrowsError(
                try ModuleRenderer.liveFrameLimit(sampleRate: 44_100, maxDurationSeconds: duration)
            ) { error in
                guard case ModuleRenderer.RenderError.invalidDuration = error else {
                    return XCTFail("Falscher Fehler für Dauer \(duration): \(error)")
                }
            }
        }
        for rate in [Double.nan, Double.infinity, -1, 0] {
            XCTAssertThrowsError(
                try ModuleRenderer.liveFrameLimit(sampleRate: rate, maxDurationSeconds: 1)
            ) { error in
                guard case ModuleRenderer.RenderError.invalidSampleRate = error else {
                    return XCTFail("Falscher Fehler für Samplerate \(rate): \(error)")
                }
            }
        }
    }

    func testRendererRejectsNonFiniteAndOutOfRangeDurations() {
        for duration in [Double.nan, Double.infinity, -1, 0, 601] {
            XCTAssertThrowsError(
                try ModuleRenderer.renderWavData(
                    mod: ModParser.generateDemoMod(),
                    sampleRate: 44_100,
                    maxDurationSeconds: duration
                )
            ) { error in
                guard case ModuleRenderer.RenderError.invalidDuration = error else {
                    return XCTFail("Falscher Fehler für Dauer \(duration): \(error)")
                }
            }
        }
    }

    // Ein Modul ohne Playlist beendete den Prozess: `patternRowCount` klemmte
    // `min(patternTable.count - 1, position)` auf -1, `max(0, -1)` machte daraus
    // 0, und der Zugriff auf patternTable[0] lief ins Leere. Alle vier Parser
    // lehnen leere Playlists ab (ParserError.emptySong), aber `Mod` ist
    // oeffentlich und ohne Playlist baubar — der Sequencer muss das aushalten
    // statt abzustuerzen.
    func testSequencerSurvivesModuleWithoutPlaylist() throws {
        let mod = Mod(
            name: "Ohne Playlist", length: 0, patternTable: [], instruments: [nil],
            patterns: [], channelCount: 4, format: .protracker
        )

        XCTAssertEqual(SequencerCore.patternRowCount(mod, at: 0), 64)
        XCTAssertEqual(RenderEngine.cumulativeRows(mod, upTo: 4, row: 2), 2)

        let params = RenderEngine.reconstructGlobalParams(mod, toPosition: 3, row: 5)
        XCTAssertEqual(params.speed, mod.initialSpeed)
        XCTAssertEqual(params.bpm, mod.initialTempo)
        XCTAssertEqual(params.globalVolume, mod.initialGlobalVolume)

        // Der ganze Renderweg muss durchlaufen und stille, aber gueltige
        // WAV-Daten liefern.
        let wav = try ModuleRenderer.renderWavData(
            mod: mod, sampleRate: 8_000, maxDurationSeconds: 0.05, normalize: false
        )
        XCTAssertEqual(Array(wav.prefix(4)), Array("RIFF".utf8))
    }
}

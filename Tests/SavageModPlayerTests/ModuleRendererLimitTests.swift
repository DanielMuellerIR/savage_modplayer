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
}

import XCTest
@testable import SavageProtrackerPlayerCore

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
}

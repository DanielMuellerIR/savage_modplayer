import XCTest
@testable import SavageModPlayerCore

final class TrackerNoteTextTests: XCTestCase {
    func testClassicMODAndExplicitEmptyEffect() {
        let display = TrackerNoteText(Note(instrument: 10, period: 428, effectId: 0xF, effectData: 31))
        XCTAssertEqual(display.note, "C-3")
        XCTAssertEqual(display.instrument, "0A")
        XCTAssertEqual(display.effect, "F1F")
        XCTAssertEqual(TrackerNoteText(Note(instrument: 0, period: 0, effectId: 0, effectData: 0, effectPresent: true)).effect, "000")
    }
    func testSpecialNotesAndTrackerLetterCommands() {
        let cut = Note(instrument: 0, period: 0, effectId: ModuleEffect.setTempo, effectData: 125, key: Note.keyCut, volume: 64)
        XCTAssertEqual(TrackerNoteText(cut).note, "^^^")
        XCTAssertEqual(TrackerNoteText(cut).volume, "v64")
        XCTAssertEqual(TrackerNoteText(cut).effect, "T7D")
        let off = Note(instrument: 0, period: 0, effectId: ModuleEffect.impulseTrackerCommand(24), effectData: 128, key: Note.keyOff)
        XCTAssertEqual(TrackerNoteText(off).note, "===")
        XCTAssertEqual(TrackerNoteText(off).effect, "X80")
    }
}

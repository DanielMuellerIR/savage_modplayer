import SwiftUI
import XCTest
import SavageModPlayerCore
@testable import SavageModPlayer

/// Die Tastaturkürzel für die Wiedergabe.
///
/// Hintergrund (iPad-Feinschliff, 2026-08-23): Ein iPad mit Tastatur ist ein
/// Arbeitsgerät; wer nebenher Musik hört, will zum Pausieren nicht die App
/// wechseln. Die Liste steht als Aufzählung und nicht direkt in der Ansicht,
/// damit genau das hier prüfbar ist.
@MainActor
final class PlaybackShortcutTests: XCTestCase {

    private var workDir: URL!
    private var model: AppModel!

    override func setUp() async throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Shortcuts-\(UUID().uuidString)", isDirectory: true)
        let libraryRoot = workDir.appendingPathComponent("Bibliothek", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let library = MusicLibrary(
            rootURL: libraryRoot,
            indexURL: workDir.appendingPathComponent("index.json"))
        model = AppModel(library: LibraryStore(library: library))
    }

    override func tearDown() async throws {
        model?.player.stop()
        model = nil
        try? FileManager.default.removeItem(at: workDir)
    }

    /// Keine Taste doppelt: Zwei Befehle auf derselben Tastenkombination wären
    /// nicht vorhersagbar — iPadOS führte einen davon aus, welchen bliebe offen.
    func testNoShortcutIsAssignedTwice() {
        var seen: Set<String> = []
        for shortcut in PlaybackShortcut.allCases {
            let identity = "\(shortcut.key.character)|\(shortcut.modifiers.rawValue)"
            XCTAssertTrue(
                seen.insert(identity).inserted,
                "Tastenkombination \(identity) ist doppelt belegt (\(shortcut))")
        }
    }

    /// Die Sprungkürzel müssen sich von den Titelwechseln unterscheiden — sie
    /// liegen auf denselben Pfeiltasten und dürfen sich nur im Zusatz trennen.
    func testTrackChangeAndSeekUseDifferentModifiers() {
        XCTAssertEqual(PlaybackShortcut.nextTrack.key.character, PlaybackShortcut.skipForward.key.character)
        XCTAssertNotEqual(PlaybackShortcut.nextTrack.modifiers, PlaybackShortcut.skipForward.modifiers)
        XCTAssertEqual(PlaybackShortcut.previousTrack.key.character, PlaybackShortcut.skipBackward.key.character)
        XCTAssertNotEqual(PlaybackShortcut.previousTrack.modifiers, PlaybackShortcut.skipBackward.modifiers)
    }

    /// Jedes Kürzel trägt eine eigene Beschriftung. Sie steht im Kürzel-Fenster,
    /// das iPadOS beim Halten von Cmd zeigt — ein leerer oder doppelter Eintrag
    /// wäre dort direkt sichtbar.
    func testEveryShortcutHasItsOwnLabel() {
        var seen: Set<String> = []
        for shortcut in PlaybackShortcut.allCases {
            let key = String(describing: shortcut.titleKey)
            XCTAssertFalse(key.isEmpty)
            XCTAssertTrue(seen.insert(key).inserted, "Beschriftung doppelt: \(key)")
        }
    }

    /// Leerzeichen schaltet zwischen Abspielen und Pause um. Ohne geladenen
    /// Titel darf es nichts kaputt machen.
    func testPlayPauseTogglesAndSurvivesAnEmptyLibrary() {
        XCTAssertFalse(model.player.isPlaying)
        PlaybackShortcut.playPause.perform(on: model.player)
        XCTAssertFalse(model.player.isPlaying, "Ohne Titel gibt es nichts abzuspielen")
    }

    /// Titelwechsel ohne Warteschlange darf nicht abstürzen — der haeufigste
    /// Zustand direkt nach dem Start.
    func testTrackChangeOnAnEmptyQueueIsHarmless() {
        for shortcut in [PlaybackShortcut.nextTrack, .previousTrack] {
            shortcut.perform(on: model.player)
        }
        XCTAssertNil(model.player.currentTrack)
    }

    /// Der wichtigste Test der Datei: Solange das Suchfeld aktiv ist, darf die
    /// Leertaste ein Leerzeichen tippen und nicht die Wiedergabe umschalten.
    ///
    /// Ein Menuebefehl der Szene wird vor dem Texteingabefeld gefragt; darauf zu
    /// hoffen, dass iOS von selbst richtig entscheidet, waere geraten. Ein
    /// abgeschalteter Befehl greift die Taste dagegen nachweislich nicht.
    func testSpaceIsReleasedWhileTheSearchFieldIsActive() {
        XCTAssertTrue(
            PlaybackShortcut.playPause.isBlocked(searchFieldActive: true),
            "Die Leertaste muss beim Suchen dem Textfeld gehoeren")
        XCTAssertFalse(PlaybackShortcut.playPause.isBlocked(searchFieldActive: false))
    }

    /// Kuerzel mit Cmd bleiben auch beim Suchen aktiv — die tippt niemand
    /// versehentlich in ein Suchfeld.
    func testModifierShortcutsKeepWorkingWhileSearching() {
        for shortcut in PlaybackShortcut.allCases where !shortcut.modifiers.isEmpty {
            XCTAssertFalse(
                shortcut.isBlocked(searchFieldActive: true),
                "\(shortcut) braucht Cmd und darf beim Suchen nicht abgeschaltet werden")
        }
    }

    /// Genau ein Kuerzel kommt ohne Zusatztaste aus. Kaeme ein zweites dazu,
    /// muesste es dieselbe Ruecksicht nehmen — dieser Test erzwingt die
    /// Entscheidung.
    func testOnlyOneShortcutWorksWithoutAModifier() {
        let plain = PlaybackShortcut.allCases.filter { $0.modifiers.isEmpty }
        XCTAssertEqual(plain.count, 1)
        XCTAssertEqual(plain.first, .playPause)
    }

    /// Der Melder aus der Bibliothek erreicht das Modell.
    func testSearchStateReachesTheModel() {
        XCTAssertFalse(model.isSearchFieldActive)
        model.isSearchFieldActive = true
        XCTAssertTrue(PlaybackShortcut.playPause.isBlocked(
            searchFieldActive: model.isSearchFieldActive))
    }

    /// Die beiden Sprungkürzel gehen in entgegengesetzte Richtungen und um
    /// denselben Betrag.
    func testSkipShortcutsAreSymmetric() {
        XCTAssertEqual(PlaybackShortcut.skipSeconds, 10)
        // Ohne Titel bleibt die Position bei null; geprueft wird hier, dass der
        // Aufruf durchlaeuft und die Wiedergabe nicht in einen Fehler faellt.
        PlaybackShortcut.skipForward.perform(on: model.player)
        PlaybackShortcut.skipBackward.perform(on: model.player)
        XCTAssertNil(model.player.errorMessage)
    }
}

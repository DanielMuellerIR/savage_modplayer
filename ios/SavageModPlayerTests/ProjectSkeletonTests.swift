import XCTest
import SavageModPlayerCore
@testable import SavageModPlayer

// Rauchtest fuers Projektgeruest: Wenn dieser Test laeuft, ist das App-Target
// gebaut, im Simulator installiert und der Core dazugelinkt worden. Faellt er
// aus, ist etwas am Projekt kaputt und nicht an der Fachlogik.
final class ProjectSkeletonTests: XCTestCase {

    func testSharedTypesAreAvailable() {
        XCTAssertEqual(LoopMode.playlist.rawValue, "playlist")
        // System, Hell, Dunkel. `.system` erzwingt nichts und liefert deshalb
        // bewusst kein Farbschema.
        XCTAssertEqual(PlayerTheme.allCases.count, 3)
        XCTAssertNil(PlayerTheme.system.colorScheme)
    }

    @MainActor
    func testIncompleteResetShowsRescanErrorBeforeExistingFailure() {
        let message = LibraryStore.resetErrorMessage(
            failures: [ImportFailure(path: "Bibliothek", reason: "Loeschen fehlgeschlagen")],
            enumerationError: "Abgleich nach Teilfehler unvollstaendig",
            previous: "Alter Fehler")

        XCTAssertEqual(message, "Abgleich nach Teilfehler unvollstaendig")
    }

    @MainActor
    func testIncompleteScanKeepsKnownAndAddsNewArchives() {
        XCTAssertEqual(
            LibraryStore.reconciledArchives(
                previous: ["Alt/b.zip"],
                discovered: ["Neu/a.zip"],
                scanIsComplete: false),
            ["Alt/b.zip", "Neu/a.zip"])
    }

    @MainActor
    func testCompleteScanReplacesKnownArchives() {
        XCTAssertEqual(
            LibraryStore.reconciledArchives(
                previous: ["Alt.zip"],
                discovered: ["Neu.zip"],
                scanIsComplete: true),
            ["Neu.zip"])
    }
}

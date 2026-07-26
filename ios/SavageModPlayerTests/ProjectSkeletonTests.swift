import XCTest
@testable import SavageModPlayer

// Rauchtest fuers Projektgeruest: Wenn dieser Test laeuft, ist das App-Target
// gebaut, im Simulator installiert und der Core dazugelinkt worden. Faellt er
// aus, ist etwas am Projekt kaputt und nicht an der Fachlogik.
final class ProjectSkeletonTests: XCTestCase {

    func testSharedTypesAreAvailable() {
        XCTAssertEqual(LoopMode.playlist.rawValue, "playlist")
        XCTAssertEqual(PlayerTheme.allCases.count, 2)
    }
}

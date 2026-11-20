import SavageModPlayerCore
import XCTest
@testable import SavageModPlayerApp

final class MacWAVExportModelTests: XCTestCase {
    @MainActor
    func testCloseClearsSnapshotAndRetainsExportChoices() async {
        let player = ModPlayerCoordinator()
        let export = WAVExportModel()
        export.open(coordinator: player)
        XCTAssertFalse(export.showsOverlay)

        player.setMod(ModParser.generateDemoMod())
        player.trackName = "A/B"
        export.open(coordinator: player)
        XCTAssertTrue(export.showsOverlay)
        XCTAssertTrue(export.blocksVideoExport)
        XCTAssertEqual(export.exportTitle, "A/B")
        XCTAssertEqual(export.exportFolderName, "A_B-Kanalspuren")

        export.exportSecondsLimit = 300
        export.exportChannelStems = true
        export.handleEscape()
        XCTAssertFalse(export.showsOverlay)
        XCTAssertFalse(export.blocksVideoExport)

        player.trackName = "Neuer Titel"
        export.open(coordinator: player)
        XCTAssertTrue(export.showsOverlay)
        XCTAssertEqual(export.exportTitle, "Neuer Titel")
        XCTAssertEqual(export.exportSecondsLimit, 300)
        XCTAssertTrue(export.exportChannelStems)
    }
}

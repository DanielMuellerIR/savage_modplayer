import XCTest
import SwiftUI
@testable import SavageModPlayer

// Belegt den sichtbarkeitsgesteuerten Visualizer der App: Der schnelle Takt
// laeuft nur, wenn die App sichtbar ist UND der Visualizer-Abschnitt den
// Scroll-Viewport schneidet.
//
// Warum das ein Test wert ist: Der Zustand haengt an zwei unabhaengigen
// Bedingungen, und beide sind leicht zu vergessen. Faellt eine aus, laeuft der
// Core dauerhaft im 30-Hz-Takt und berechnet Wellenformen fuer einen dunklen
// Bildschirm — das merkt man erst am Akku, nicht beim Ausprobieren.
//
// Was dieser Test NICHT belegt: dass der Ton bei gesperrtem Bildschirm
// weiterlaeuft. Das kann nur ein echtes Geraet zeigen; der Simulator hat keine
// Bildschirmsperre und kein Hintergrund-Audio im eigentlichen Sinn.
@MainActor
final class ScenePhaseVisualizerTests: XCTestCase {

    private var model: AppModel!

    override func setUp() async throws {
        model = AppModel()
    }

    override func tearDown() async throws {
        model = nil
    }

    // Ohne sichtbaren Abschnitt bleibt der Core im sparsamen Takt.
    func testVisualizersAreOffUntilTheirSectionIsVisible() {
        XCTAssertFalse(
            model.player.coordinator.visualizersVisible,
            "Ein Visualizer unterhalb des Viewports darf den schnellen Takt nicht starten"
        )
    }

    // In den Abschnitt gescrollt und App sichtbar: der schnelle Takt darf laufen.
    func testVisualizersRunWhenSectionAndSceneAreVisible() {
        model.player.setVisualizerSectionVisible(true)
        XCTAssertTrue(model.player.coordinator.visualizersVisible)
    }

    // Der eigentliche Punkt: App verschwindet, Visualisierung steht still.
    func testVisualizersStopWhenSceneLeavesForeground() {
        model.player.setVisualizerSectionVisible(true)
        XCTAssertTrue(model.player.coordinator.visualizersVisible)

        model.scenePhaseChanged(to: .background)
        XCTAssertFalse(model.isSceneActive)
        XCTAssertFalse(
            model.player.coordinator.visualizersVisible,
            "Im Hintergrund darf nichts mehr gezeichnet oder berechnet werden"
        )

        // Und beim Zurueckkommen wieder an — sonst blieben die Anzeigen tot.
        model.scenePhaseChanged(to: .active)
        XCTAssertTrue(model.isSceneActive)
        XCTAssertTrue(model.player.coordinator.visualizersVisible)
    }

    // Aus dem Abschnitt herausgescrollt: sofort wieder sparsam.
    func testLeavingVisualizerSectionStopsFastUpdates() {
        model.player.setVisualizerSectionVisible(true)
        XCTAssertTrue(model.player.coordinator.visualizersVisible)
        model.player.setVisualizerSectionVisible(false)
        XCTAssertFalse(model.player.coordinator.visualizersVisible)
    }

    // Die Scope-Puffer sind reine Anzeige-Caches und werden beim Ausblenden
    // wirklich freigegeben, nicht nur nicht mehr gezeichnet.
    func testHiddenVisualizersReleaseWaveformBuffers() {
        let coordinator = model.player.coordinator
        coordinator.visualizersVisible = true
        coordinator.visualizerState.resize(channelCount: 32)
        XCTAssertEqual(coordinator.visualizerState.channelWaveforms.count, 32)
        XCTAssertEqual(coordinator.visualizerState.masterSamples.count, 128)

        coordinator.visualizersVisible = false

        XCTAssertTrue(coordinator.visualizerState.channelWaveforms.isEmpty)
        XCTAssertTrue(coordinator.visualizerState.masterSamples.isEmpty)
    }

    func testUpToThirtyTwoChannelScopesAreTheDefault() {
        XCTAssertEqual(model.settings.maxVisibleChannelScopes, 32)
    }

    // Das Raster darf auf dem Telefon nicht wieder zu einer einzigen, kaum
    // lesbaren Zeile zusammenschrumpfen. 32 Kanaele ergeben dort acht Zeilen
    // mit je vier Scopes; ein breites Layout verwendet vier Zeilen zu acht.
    func testThirtyTwoScopesUseFourPhoneOrEightWideColumns() {
        XCTAssertEqual(
            ChannelScopesView.height(channelCount: 32, availableWidth: 351),
            600)
        XCTAssertEqual(
            ChannelScopesView.height(channelCount: 32, availableWidth: 700),
            296)
    }
}

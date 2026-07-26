import XCTest
import SwiftUI
@testable import SavageModPlayer

// Belegt den Energiespar-Schalter der App: Visualisierungen laufen nur, wenn
// die App sichtbar ist UND der Nutzer sie eingeschaltet hat.
//
// Warum das ein Test wert ist: Der Schalter haengt an zwei unabhaengigen
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

    // Voreinstellung: aus. Der Regelfall auf einem Telefon ist "Musik laeuft,
    // Bildschirm ist dunkel".
    func testVisualizersAreOffByDefault() {
        XCTAssertFalse(model.settings.visualizersEnabled)
        XCTAssertFalse(
            model.player.coordinator.visualizersVisible,
            "Ohne eingeschaltete Visualisierung darf der Core nicht im schnellen Takt laufen"
        )
    }

    // Eingeschaltet und sichtbar: der schnelle Takt darf laufen.
    func testVisualizersRunWhenEnabledAndSceneIsActive() {
        model.settings.visualizersEnabled = true
        model.player.applySettings()
        XCTAssertTrue(model.player.coordinator.visualizersVisible)
    }

    // Der eigentliche Punkt: App verschwindet, Visualisierung steht still.
    func testVisualizersStopWhenSceneLeavesForeground() {
        model.settings.visualizersEnabled = true
        model.player.applySettings()
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

    // Ausgeschaltet bleibt ausgeschaltet, auch wenn die App sichtbar wird.
    func testSceneActivationDoesNotOverrideTheSetting() {
        model.settings.visualizersEnabled = false
        model.player.applySettings()

        model.scenePhaseChanged(to: .background)
        model.scenePhaseChanged(to: .active)

        XCTAssertFalse(model.player.coordinator.visualizersVisible)
    }
}

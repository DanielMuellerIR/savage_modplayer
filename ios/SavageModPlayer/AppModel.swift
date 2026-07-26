import Foundation
import SwiftUI

// Klammer um die drei Bereiche der App. Es gibt genau eine Instanz, erzeugt in
// SavageModPlayerApp; alle Views holen sie sich per @EnvironmentObject.
//
// AppModel selbst enthaelt absichtlich fast keine Logik. Es besitzt die drei
// Bausteine, verdrahtet sie einmal miteinander und reicht den Szenen-Zustand
// weiter. Alles Fachliche liegt in Player/, Library/ und UI/.
@MainActor
final class AppModel: ObservableObject {

    // Klang- und Wiedergabe-Einstellungen (PAL/NTSC, LED-Filter, Interpolation,
    // Stereo-Separation, Lautstaerke, Loop-Modus, Shuffle, Theme).
    let settings: PlayerSettings

    // Bibliothek: Index, Ordnerbaum, Import, Zuruecksetzen, Favoriten.
    let library: LibraryStore

    // Wiedergabe: Core-Coordinator, Titelwechsel, AudioSession, Now Playing.
    let player: PlaybackEngine

    // Ist die App gerade im Vordergrund und sichtbar? Der eine Schalter, an dem
    // saemtliche Visualisierungen haengen. Bei gesperrtem Bildschirm laeuft der
    // Ton weiter, aber es wird nichts mehr gezeichnet und nichts mehr an die
    // Oberflaeche gemeldet — das spart auf einem Telefon spuerbar Akku.
    @Published private(set) var isSceneActive = true

    init() {
        let settings = PlayerSettings()
        let library = LibraryStore()
        self.settings = settings
        self.library = library
        self.player = PlaybackEngine(settings: settings, library: library)
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        let active = (phase == .active)
        guard active != isSceneActive else { return }
        isSceneActive = active
        player.setVisualizersEnabled(active)
    }
}

import SwiftUI

// Einstiegspunkt der iPhone-App. Die eigentliche Oberflaeche liegt in UI/,
// die Wiedergabe in Player/, der Bibliotheks-Import in Library/.
//
// Zwei Dinge passieren hier und nirgends sonst:
// 1. Die AppModel-Instanz wird EINMAL erzeugt und an die gesamte View-Hierarchie
//    weitergereicht. Sie haelt Player, Bibliothek und Einstellungen zusammen.
// 2. Der Szenen-Zustand (aktiv / inaktiv / Hintergrund) wird durchgereicht.
//    Zusammen mit der Scroll-Sichtbarkeit ist das der wichtigste Performance-
//    Hebel der App: bei gesperrtem Bildschirm laeuft die Audio-Engine weiter,
//    aber saemtliche Visualisierungen werden abgeschaltet.
@main
struct SavageModPlayerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onChange(of: scenePhase) { _, newPhase in
                    model.scenePhaseChanged(to: newPhase)
                }
        }
    }
}

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
                // "Oeffnen mit", Doppeltipp in der Dateien-App, Anhang aus Mail:
                // Die Info.plist meldet MOD/S3M/XM/IT und ZIP als eigene
                // Dokumenttypen an, also muss die App die uebergebene Datei auch
                // annehmen. Das Uebernehmen in die Bibliothek und das Abspielen
                // macht AppModel — hier steht nur die Entgegennahme.
                .onOpenURL { url in
                    model.open(url)
                }
        }
        // Tastaturkuerzel fuer die Wiedergabe. Auf einem iPad mit Tastatur
        // erscheinen sie beim Halten von Cmd; ohne Tastatur ist das Menue
        // unsichtbar und kostet nichts.
        .commands { PlaybackCommands(model: model) }
    }
}

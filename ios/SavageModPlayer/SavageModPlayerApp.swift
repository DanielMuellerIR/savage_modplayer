import SwiftUI
import SavageModPlayerCore

// Einstiegspunkt der iPhone-App. Die eigentliche Oberflaeche liegt in UI/,
// die Wiedergabe in Player/, der Bibliotheks-Import in Library/.
//
// Zwei Dinge passieren hier und nirgends sonst:
// 1. Nach der Import-Wiederherstellung wird eine AppModel-Instanz an die View-Hierarchie
//    weitergereicht. Sie haelt Player, Bibliothek und Einstellungen zusammen.
// 2. Der Szenen-Zustand (aktiv / inaktiv / Hintergrund) wird durchgereicht.
//    Zusammen mit der Scroll-Sichtbarkeit ist das der wichtigste Performance-
//    Hebel der App: bei gesperrtem Bildschirm laeuft die Audio-Engine weiter,
//    aber saemtliche Visualisierungen werden abgeschaltet.
@main
struct SavageModPlayerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bootstrap: CollectionExchangeBootstrap
    private let isUnitTestHost: Bool

    init() {
        let environment = ProcessInfo.processInfo.environment
        let runningTests = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["XCInjectBundleInto"] != nil
            || NSClassFromString("XCTestCase") != nil
        isUnitTestHost = runningTests
        // Die Tests besitzen eigene Modelle und Speicher. Ihr Host darf weder
        // die normale Bibliothek laden noch deren offene Übernahme wiederherstellen.
        _bootstrap = StateObject(wrappedValue: CollectionExchangeBootstrap(recoverOnInit: !runningTests))
    }

    var body: some Scene {
        WindowGroup {
            if isUnitTestHost {
                Color.clear
            } else if let model = bootstrap.model {
            RootView()
                .environmentObject(model)
                .onChange(of: scenePhase) { _, newPhase in
                    model.scenePhaseChanged(to: newPhase)
                }
                // "Oeffnen mit", Doppeltipp in der Dateien-App, Anhang aus Mail:
                // Die Info.plist meldet MOD/S3M/XM/IT, ZIP und Sammlungen als eigene
                // Dokumenttypen an, also muss die App die uebergebene Datei auch
                // annehmen. Das Uebernehmen in die Bibliothek und das Abspielen
                // macht AppModel — hier steht nur die Entgegennahme.
                .onOpenURL { url in
                    bootstrap.open(url)
                }
            } else if let error = bootstrap.error {
                CollectionExchangeRecoveryView(error: error) { bootstrap.recover() }
                    .onOpenURL { bootstrap.open($0) }
            }
        }
        // Tastaturkuerzel fuer die Wiedergabe. Auf einem iPad mit Tastatur
        // erscheinen sie beim Halten von Cmd; ohne Tastatur ist das Menue
        // unsichtbar und kostet nichts.
        .commands { if let model = bootstrap.model { PlaybackCommands(model: model) } }
    }
}

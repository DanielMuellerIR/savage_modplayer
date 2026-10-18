import SwiftUI
import SavageModPlayerCore
#if os(macOS)
import AppKit
#endif

// Version + Build-Datum aus dem App-Bundle (Info.plist). Beide Werte setzt
// build_app.sh beim Erzeugen des .app-Bundles (CFBundleShortVersionString aus
// der VERSION-Datei, BuildDate = Build-Tag). Beim reinen `swift run` ohne
// Bundle fehlen die Keys — dann fällt der Titel auf den bloßen Namen zurück.
enum AppInfo {
    static var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    static var buildDate: String? {
        Bundle.main.infoDictionary?["BuildDate"] as? String
    }
    // Fenstertitel: "Savage Mod Player 1.5.31 · 2026-07-12" (Datum nur, wenn im
    // Bundle vorhanden; Version nur, wenn nicht der SwiftPM-Platzhalter "1.0").
    static var windowTitle: String {
        var title = "Savage Mod Player"
        if let version, version != "1.0" { title += " \(version)" }
        if let buildDate { title += " · \(buildDate)" }
        return title
    }
}

@main
struct SavageModPlayerApp: App {
    @StateObject private var collectionRecovery: CollectionExchangeRecovery
    @StateObject private var updates = UpdateController()
    @StateObject private var coordinator = ModPlayerCoordinator()
    @StateObject private var playbackActions = PlaybackActions()
    @StateObject private var playbackSettings = PlaybackPreferences.makeModel()
    @StateObject private var noteRain = NoteRainModel()
    @StateObject private var noteRainWindow = NoteRainWindowState()
    @StateObject private var songMarkers = SongMarkersModel(fileURL: MainView.catalogURL("song-markers.json", environment: "SAVAGE_SONG_MARKER_STORE"))
    @Environment(\.openWindow) private var openWindow
    // Globale UI-Zoom-Stufe (CMD +/-/0), persistiert. Wird als Faktor
    // (savageFontScale) ins Environment gelegt; siehe FontScaling.swift.
    @AppStorage("savage.uiZoom") private var uiZoom = 0

    init() {
        let recovery = CollectionExchangeRecovery()
        _collectionRecovery = StateObject(wrappedValue: recovery)
        #if os(macOS)
        // AppKit deutet ein positionales Startargument als "diese Datei
        // oeffnen". Beim so gestarteten Prozess erzeugt SwiftUI sein
        // Standardfenster nicht — `SavageModPlayer <song.mod>` zeigte deshalb
        // ueberhaupt kein Fenster, und ohne Fenster konnte auch `.onOpenURL` die
        // Datei nicht entgegennehmen (belegt 2026-08-23 mit einer synthetischen
        // .mod: null Fenster nach 15 s, mit dieser Zeile sofort eines).
        // `register` schreibt nichts auf Platte und wirkt nur in diesem Prozess;
        // der Wert muss vor dem Start der Ereignisschleife gesetzt sein, also
        // hier. Den Weg von Finder und Dock ("Oeffnen mit", Doppelklick) beruehrt
        // das nicht: der laeuft ueber ein Apple-Event, nicht ueber argv.
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": false])
        #endif
        // Temp-Kopien frueherer App-Laeufe einmalig beim Start aufraeumen.
        // (Innerhalb einer Sitzung bleiben die pro-Drop-Verzeichnisse bestehen,
        // weil die Playlist sie noch referenziert — siehe cleanStaleTempRoot.)
        MainView.cleanStaleTempRoot()
        #if os(macOS)
        // Zusaetzlich beim regulaeren Beenden aufraeumen (Temp-Kopien und
        // entpackte Archive verschwinden sofort); die Start-Reinigung oben
        // bleibt als Fallnetz fuer Abstuerze/Force-Quit bestehen.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            MainView.cleanStaleTempRoot()
        }
        #endif
    }

    var body: some Scene {
        // Bewusst `Window` (Singleton) statt `WindowGroup`: Es gibt nur EIN
        // Player-Fenster. Man kann ohnehin nicht zwei Module gleichzeitig sinnvoll
        // hören; ein „Öffnen mit"/Dock-Drop soll das bestehende Fenster nutzen
        // (via .onOpenURL) statt ein zweites zu erzeugen. WindowGroup hatte pro
        // geöffneter Datei ein neues, leeres Fenster gespawnt.
        Window(AppInfo.windowTitle, id: "main") {
            if let error = collectionRecovery.error {
                CollectionExchangeRecoveryView(error: error) {
                    collectionRecovery.recover()
                    guard collectionRecovery.error == nil else { return }
                    do {
                        let documents = try CollectionExchangeSupport.persistence().snapshot().documents
                        let preferences = CollectionExchangeSupport.preferences()
                        let defaults = CollectionExchangeSoundPreferences.options(in: try preferences.values(in: preferences.capture()), prefix: "savage.")
                        songMarkers.adoptCommitted(documents.markers)
                        playbackSettings.adoptCommitted(documents.trackSettings, defaults: defaults)
                    } catch { collectionRecovery.block(error) }
                }.frame(minWidth: 640, minHeight: 420)
            } else {
                MainView(coordinator: coordinator, playbackActions: playbackActions)
                .environmentObject(songMarkers)
                .environmentObject(playbackSettings)
                .environmentObject(collectionRecovery)
                // UI-Schriftfaktor an den Szenen-Root haengen — alle
                // `.scaledFont(...)`-Aufrufe im Baum lesen ihn von hier.
                .environment(\.uiFontScale, savageFontScale(uiZoom))
            }
        }
        .commands {
            CommandMenu("Export") {
                Button("Notenregen als Video…") {
                    NotificationCenter.default.post(name: NSNotification.Name("menuVideoExport"), object: nil)
                }.disabled(coordinator.activeMod == nil || collectionRecovery.error != nil)
            }
            CommandMenu("Sammlung") {
                Button("Sammlung abgleichen…") {
                    NotificationCenter.default.post(name: NSNotification.Name("menuCollectionSync"), object: nil)
                }.disabled(collectionRecovery.error != nil)
                Button("Sammlung übertragen…") {
                    NotificationCenter.default.post(name: NSNotification.Name("menuCollectionExchange"), object: nil)
                }.disabled(collectionRecovery.error != nil)
            }
            #if os(macOS)
            // Standard-"Über"-Eintrag im App-Menü durch einen eigenen ersetzen,
            // damit der native macOS-About-Panel Autor und Lizenz zeigt (Icon,
            // Name und Version kommen automatisch aus dem Bundle). Der verspielte
            // Guru-Meditation-Screen bleibt zusätzlich über den ⓘ-Button erhalten.
            CommandGroup(replacing: .appInfo) {
                Button("Über Savage Mod Player") {
                    let credits = NSAttributedString(
                        string: "Entwickelt von Daniel Müller.\n\n"
                            + "ProTracker-/Paula-Engine: Eigenentwicklung (kein libopenmpt), "
                            + "aus dem Schwesterprojekt FraktalLab nach Swift portiert.\n\n"
                            + "Lizenz: WTFPL (Do What The Fuck You Want To Public License).\n",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11),
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen…", action: updates.checkForUpdates)
                    .disabled(!updates.canCheckForUpdates)
            }

            CommandMenu("Wiedergabe") {
                Button("Abspielen / Pause") {
                    NotificationCenter.default.post(name: NSNotification.Name("menuPlayStop"), object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Stopp") {
                    NotificationCenter.default.post(name: NSNotification.Name("menuStop"), object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Button("Nächster Titel") {
                    NotificationCenter.default.post(name: NSNotification.Name("menuNextTrack"), object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                
                Button("Vorheriger Titel") {
                    NotificationCenter.default.post(name: NSNotification.Name("menuPrevTrack"), object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            // Darstellung: globale UI-Schriftgroesse. CMD+ / CMD- / CMD-0.
            // (Zusaetzlich CMD+= als zweiter Zoom-in-Weg — versteckt in MainView
            // verdrahtet, weil ⌘+ auf manchen Layouts erst mit Shift kommt.)
            CommandMenu("Darstellung") {
                Button("Notenregen öffnen") { openWindow(id: "note-rain") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Schrift größer") { uiZoom = min(uiZoom + 1, 5) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Schrift kleiner") { uiZoom = max(uiZoom - 1, -3) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Originalgröße") { uiZoom = 0 }
                    .keyboardShortcut("0", modifiers: .command)
            }
            #endif
        }

        #if os(macOS)
        Window("Notenregen", id: "note-rain") {
            NoteRainView(coordinator: coordinator, playbackActions: playbackActions, model: noteRain, windowState: noteRainWindow)
                .environmentObject(songMarkers)
                .environment(\.uiFontScale, savageFontScale(uiZoom))
        }
        .defaultSize(width: NoteRainWindowState.defaultWidth, height: 760)

        // Gemeinsame Einstellungen für Wiedergabe, Darstellung und Updates.
        Settings {
            SettingsView(updates: updates)
        }
        #endif
    }
}

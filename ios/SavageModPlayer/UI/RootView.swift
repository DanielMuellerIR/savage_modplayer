import SwiftUI
import SavageModPlayerCore

// Die Oberflaeche der iPhone-App: drei Tabs (Bibliothek, Wiedergabe,
// Einstellungen) und eine Mini-Player-Leiste, die ueber der Tab-Leiste steht,
// sobald ein Titel gewaehlt ist.
//
// Diese Datei haelt bewusst nur den Rahmen. Jeder Tab bringt seine eigene
// Ansicht mit und beobachtet selbst genau die Objekte, die er braucht — das ist
// der wichtigste Grundsatz der ganzen Oberflaeche. Wuerde RootView die Wiedergabe
// beobachten, wuerde jede Aktualisierung der Wiedergabe die komplette
// Oberflaeche neu auswerten. Bei bis zu 30 Aktualisierungen pro Sekunde ist das
// der Unterschied zwischen "laeuft nebenbei" und "Telefon wird warm".
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // `model` wird von @EnvironmentObject beobachtet (der Szenen-Zustand
        // aendert sich selten). Die Einstellungen kommen als beobachtetes Objekt
        // in den inneren Aufbau, weil das Erscheinungsbild daran haengt.
        Content(model: model, settings: model.settings)
            .sheet(item: $model.collectionContext) { context in
                CollectionExchangeView(context: context).presentationDetents([.large])
                    .preferredColorScheme(model.settings.theme.colorScheme)
            }
            .task { model.prepareCollectionSync() }
    }

    // Welcher Tab gerade vorn ist.
    private enum Tab: Hashable {
        case library
        case player
        case settings
    }

    private struct Content: View {
        let model: AppModel
        @ObservedObject var settings: PlayerSettings

        @Environment(\.scenePhase) private var scenePhase
        // Breite Fenster (iPad im Vollbild, grosse Split-View-Haelfte) bekommen
        // zwei Spalten; schmale bleiben beim Tab-Layout. Entscheidend ist die
        // Groessenklasse, nicht das Geraet: Ein iPad in Slide Over ist
        // "compact" und soll dort auch das iPhone-Layout zeigen.
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        @State private var selection: Tab = .library
        // Der zuletzt gespielte Titel wird genau einmal wiederhergestellt.
        @State private var didRestoreSession = false
        // Zweispaltiges Layout: Es gibt keinen Einstellungs-Tab, also kommen
        // die Einstellungen als Blatt ueber einen Knopf in der Bibliothek.
        @State private var showSettings = false
        @State private var columnVisibility = NavigationSplitViewVisibility.all

        var body: some View {
            layout
                .tint(.accentColor)
                // Hell, dunkel oder das, was das System vorgibt (nil = nicht
                // erzwingen).
                .preferredColorScheme(settings.theme.colorScheme)
                // Fehler der Wiedergabe als eigener Modifier: er beobachtet die
                // Wiedergabe fuer sich allein. Eine Aenderung dort wertet damit
                // nur den Modifier neu aus, nicht die Ansichten darunter.
                .modifier(PlaybackAlert(player: model.player))
                .onAppear {
                    // Beim ersten Erscheinen: gespeicherten Index anzeigen und im
                    // Hintergrund mit dem Dateisystem abgleichen.
                    model.library.start()
                    // Falls der Bestand schon steht, bevor diese Ansicht
                    // ueberhaupt zuhoert: Der Melder unten liefert nur
                    // Aenderungen, keinen Startwert.
                    libraryDidChange(tracks: model.library.tracks)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Zurueck aus dem Hintergrund: was inzwischen ueber den Finder
                    // oder die Dateien-App abgelegt oder geloescht wurde, soll
                    // stimmen. Laeuft gerade ein Vorgang, tut refresh() nichts.
                    if phase == .active { model.library.refresh() }
                }
                // onReceive statt @ObservedObject: die Bibliothek wird hier NICHT
                // beobachtet. Diese Zeile reagiert nur auf eine neue Titelliste und
                // zeichnet dabei nichts neu.
                //
                // `tracksDidChange` und nicht `$tracks`: Ein @Published-Strom
                // meldet in `willSet`, die Bibliothek liefert dann also noch
                // ihren alten Bestand. Genau daran ist die
                // Sitzungswiederherstellung gescheitert.
                .onReceive(model.library.tracksDidChange) { tracks in
                    libraryDidChange(tracks: tracks)
                }
        }

        // Der Bestand hat sich geaendert — oder stand beim Erscheinen schon da.
        private func libraryDidChange(tracks: [TrackRef]) {
            // Die Wiedergabe bildet ihre Liste aus der Auswahl neu, aus der
            // sie gestartet wurde — Suche oder Favoriten bleiben erhalten.
            model.player.refreshQueueFromLibrary()
            guard !didRestoreSession, !tracks.isEmpty else { return }
            didRestoreSession = true
            // Der zuletzt gespielte Titel ist danach ausgewaehlt — er
            // spielt aber nicht von selbst los.
            model.player.restoreSession()
        }

        @ViewBuilder
        private var layout: some View {
            if horizontalSizeClass == .regular {
                wideLayout
            } else {
                tabLayout
            }
        }

        // Zwei Spalten: links die Bibliothek, rechts die laufende Wiedergabe.
        // Auf einem breiten Bildschirm ist das der Punkt — man sucht einen Titel
        // und sieht dabei weiter, was gerade laeuft. Eine Mini-Player-Leiste
        // braucht es hier nicht mehr; der Player steht ohnehin daneben.
        private var wideLayout: some View {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // Ohne eigene Navigationsleiste: die liefert die Spalte.
                LibraryView(embedsNavigation: false) { showSettings = true }
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            } detail: {
                // `isSelected` steuert den schnellen Visualizer-Takt. Hier ist
                // die Wiedergabe immer sichtbar, also immer wahr.
                NowPlayingView(isSelected: true) {
                    columnVisibility = .all
                }
            }
            .navigationSplitViewStyle(.balanced)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: showSettings) { _, active in model.isLibraryPanelOpen = active }
        }

        private var tabLayout: some View {
            TabView(selection: $selection) {
                LibraryView()
                    .miniPlayerBar(player: model.player) { selection = .player }
                    .tabItem { Label("tab.library", systemImage: "music.note.list") }
                    .tag(Tab.library)

                NowPlayingView(isSelected: selection == .player) {
                    selection = .library
                }
                    .tabItem { Label("tab.player", systemImage: "waveform") }
                    .tag(Tab.player)

                SettingsView()
                    .miniPlayerBar(player: model.player) { selection = .player }
                    .tabItem { Label("tab.settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .toolbarBackground(Color.playerSurface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
    }
}

// MARK: - Fehlermeldung der Wiedergabe

// Eigener Modifier statt eines Alerts mitten in einer Tab-Ansicht: So gibt es
// genau einen Ort fuer die Meldung, und die Beobachtung der Wiedergabe bleibt
// auf diesen Modifier beschraenkt.
private struct PlaybackAlert: ViewModifier {
    @ObservedObject var player: PlaybackEngine

    func body(content: Content) -> some View {
        content.alert(
            "library.error.title",
            isPresented: Binding(
                get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } })
        ) {
            Button("common.ok", role: .cancel) { player.errorMessage = nil }
        } message: {
            // Fehlertexte kommen aus dem Core und sind bereits fertig
            // formuliert — deshalb verbatim.
            Text(verbatim: player.errorMessage ?? "")
        }
    }
}

// MARK: - Mini-Player

extension View {
    // Haengt die Mini-Player-Leiste unten an eine Tab-Ansicht.
    //
    // `safeAreaInset` statt eines Overlays: dadurch weiss die Liste darunter,
    // dass die letzten Zeilen verdeckt waeren, und laesst von sich aus Platz.
    // Ein Overlay wuerde den letzten Titel dauerhaft zudecken.
    func miniPlayerBar(player: PlaybackEngine, onOpen: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerBar(player: player, onOpen: onOpen)
        }
    }
}

// Die Leiste selbst. Sie beobachtet die Wiedergabe — aber nur sie, nicht die
// Ansicht darueber. Ohne gewaehlten Titel liefert sie gar nichts und belegt
// damit auch keinen Platz.
private struct MiniPlayerBar: View {
    @ObservedObject var player: PlaybackEngine
    let onOpen: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                Image(systemName: "opticaldisc.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: track.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    folderPathText(track.folderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Die ganze Textflaeche ist antippbar, nicht nur die Buchstaben.
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("mini.open")

                // Der Typ steht ausdruecklich da: ohne ihn haelt Swift die
                // beiden Schluessel fuer gewoehnliche Zeichenketten und die
                // Sprachausgabe laese den Schluessel statt der Beschriftung vor.
                let playPauseLabel: LocalizedStringKey = isRunning ? "transport.pause" : "transport.play"
                Button(action: player.togglePlayPause) {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(playPauseLabel)

                Button(action: player.next) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("transport.next")
                .disabled(player.queue.isEmpty && player.pendingQueue.items.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.playerSurface)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var isRunning: Bool {
        player.isPlaying && !player.isPaused
    }
}

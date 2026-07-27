import SwiftUI

// Zweistufige Bestaetigung fuers Zuruecksetzen der Bibliothek.
//
// Einbindung durch die spaetere Oberflaeche (Einstellungen):
//
//     .sheet(isPresented: $showReset) { LibraryResetConfirmation(isPresented: $showReset) }
//
// Gebraucht wird nur `AppModel` in der Umgebung; den Store holt sich die Ansicht
// selbst und beobachtet ihn im inneren `Content`.
//
// Warum zwei Stufen: der Knopf loescht die gesamte Sammlung vom Geraet, und
// zurueckholen laesst sich davon nichts. Die erste Stufe erklaert, was passiert.
// Die zweite verlangt eine ausdrueckliche Bestaetigung — ein Schalter, den man
// bewusst umlegen muss — und bietet an, wenigstens die Favoriten zu behalten.
// Ein versehentlicher Doppeltipp kommt so nicht durch.
struct LibraryResetConfirmation: View {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool

    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    var body: some View {
        Content(library: model.library, isPresented: $isPresented)
    }

    private struct Content: View {
        @ObservedObject var library: LibraryStore
        @Binding var isPresented: Bool

        // Welche Stufe gerade sichtbar ist.
        @State private var stage: Stage = .warning
        // Favoriten sind eine reine Merkliste aus relativen Pfaden. Sie
        // ueberleben das Loeschen problemlos und passen wieder, sobald dieselben
        // Titel erneut importiert werden — deshalb ist "behalten" die
        // Voreinstellung.
        @State private var keepFavorites = true
        // Der ausdrueckliche Haken der zweiten Stufe.
        @State private var confirmed = false

        private enum Stage {
            case warning
            case confirm
            case running
        }

        var body: some View {
            NavigationStack {
                List {
                    switch stage {
                    case .warning: warningStage
                    case .confirm: confirmStage
                    case .running: runningStage
                    }
                }
                .navigationTitle("library.reset.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { isPresented = false }
                            .disabled(stage == .running)
                    }
                }
                .interactiveDismissDisabled(stage == .running)
                .onChange(of: library.isBusy) { _, busy in
                    // Fertig ist der Vorgang genau dann, wenn der Store nicht
                    // mehr beschaeftigt ist. Dann schliesst sich das Blatt von
                    // selbst — die leere Bibliothek dahinter ist Beleg genug.
                    if stage == .running && !busy { isPresented = false }
                }
            }
        }

        // MARK: - Stufe 1: Was passiert hier

        @ViewBuilder
        private var warningStage: some View {
            Section {
                Text("library.reset.explain")
                Text("library.reset.count \(library.tracks.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if library.isBusy {
                    // Solange ein Import laeuft, wird nicht geloescht: die
                    // Bibliothek vertraegt immer nur einen Vorgang.
                    Label("library.reset.busy", systemImage: "clock")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        stage = .confirm
                    } label: {
                        Label("library.reset.continue", systemImage: "chevron.forward")
                    }
                    .disabled(library.tracks.isEmpty && library.pendingArchives.isEmpty)
                }
            }
        }

        // MARK: - Stufe 2: Wirklich?

        @ViewBuilder
        private var confirmStage: some View {
            Section {
                Text("library.reset.confirm.explain")
            } header: {
                Text("library.reset.confirm.title")
            }

            Section {
                Toggle("library.reset.keep.favorites", isOn: $keepFavorites)
            } footer: {
                Text("library.reset.keep.favorites.hint")
            }

            Section {
                Toggle("library.reset.confirm.toggle", isOn: $confirmed)
                Button(role: .destructive) {
                    guard confirmed, !library.isBusy else { return }
                    stage = .running
                    library.resetLibrary(clearFavorites: !keepFavorites)
                } label: {
                    Label("library.reset.action", systemImage: "trash")
                }
                .disabled(!confirmed || library.isBusy)
            }
        }

        // MARK: - Stufe 3: Es laeuft

        private var runningStage: some View {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("library.activity.resetting")
                }
            }
        }
    }
}

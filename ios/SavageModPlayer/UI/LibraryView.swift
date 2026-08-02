import SavageModPlayerCore
import SwiftUI

// Der Bibliotheks-Tab: ein echter Ordnerbaum zum Durchklicken, Suche,
// Favoritenfilter und die beiden Wege, Musik auf das Geraet zu bekommen.
//
// Wichtig fuer das Verstaendnis der Abspielreihenfolge: gespielt wird immer die
// FLACHE Liste (`library.tracks` bzw. `library.filteredTracks`), nie nur der
// aufgeklappte Ordner. Weiter und Zurueck laufen deshalb ueber Ordnergrenzen
// hinweg, genau in der Reihenfolge, die auf dem Bildschirm steht.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Content(library: model.library, player: model.player, settings: model.settings)
    }

    private struct Content: View {
        @ObservedObject var library: LibraryStore
        @ObservedObject var player: PlaybackEngine
        let settings: PlayerSettings

        @State private var search = ""
        @State private var favoritesOnly = false
        // Pfade der aufgeklappten Ordner. Alles startet zugeklappt; nur der Weg
        // zum laufenden Titel klappt von selbst auf.
        @State private var expandedFolders: Set<String> = []
        @State private var showImport = false

        var body: some View {
            NavigationStack {
                Group {
                    if library.tracks.isEmpty {
                        emptyState
                    } else {
                        treeList
                    }
                }
                .background(Color.playerBackground)
                .navigationTitle("tab.library")
                .toolbar { toolbarContent }
                .sheet(isPresented: $showImport) { LibraryImportSheet() }
                .onAppear { expandPath(to: player.currentTrack) }
                .onChange(of: player.currentTrack) { _, track in expandPath(to: track) }
            }
        }

        // MARK: - Werkzeugleiste

        @ToolbarContentBuilder
        private var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Label("library.filter.favorites", systemImage: favoritesOnly ? "star.fill" : "star")
                }
                .accessibilityLabel("library.filter.favorites")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImport = true
                } label: {
                    Label("import.title", systemImage: "folder.badge.plus")
                }
                .accessibilityLabel("import.title")
            }
        }

        // MARK: - Leere Bibliothek

        @ViewBuilder
        private var emptyState: some View {
            if library.isBusy {
                // Der erste Abgleich laeuft noch — das ist kein leerer
                // Bestand, sondern schlicht "noch nicht fertig".
                VStack(spacing: 12) {
                    ProgressView()
                    Text("library.loading")
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    // Fehler und offene Archive muessen auch im Leerzustand
                    // sichtbar sein: Scheitert das Auspacken der einzigen
                    // ZIP-Datei, gaebe es sonst weder die Meldung noch den
                    // Wiederholen-Knopf (beide standen nur in der Baumliste).
                    if let message = library.errorMessage {
                        errorRow(message)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    if !library.pendingArchives.isEmpty {
                        pendingRow
                            .padding(.horizontal)
                    }
                    ContentUnavailableView {
                        Label("library.empty.title", systemImage: "music.note.list")
                    } description: {
                        Text("library.empty.hint")
                    } actions: {
                        Button("import.title") { showImport = true }
                            .buttonStyle(.borderedProminent)
                        Text("import.filesharing.hint")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
            }
        }

        // MARK: - Baumansicht

        private var displayTree: PlaylistScanner.FolderNode? {
            library.filteredTree(search: search, favoritesOnly: favoritesOnly)
        }

        // Waehrend Suche oder Favoritenfilter enthaelt der Baum nur noch
        // Treffer. Zugeklappte Ordner wuerden sie verstecken, also ist dann
        // alles offen.
        private var isFiltering: Bool {
            !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || favoritesOnly
        }

        private var rows: [LibraryRow] {
            LibraryTree.rows(of: displayTree, expanded: expandedFolders, expandAll: isFiltering)
        }

        private var treeList: some View {
            List {
                if library.isBusy { activityRow }
                if let message = library.errorMessage { errorRow(message) }
                if !library.pendingArchives.isEmpty { pendingRow }
                if !isFiltering { playAllRows }

                ForEach(rows) { row in
                    switch row.kind {
                    case .folder(let name, let path, let trackCount):
                        folderRow(name: name, path: path, trackCount: trackCount, depth: row.depth)
                    case .track(let relativePath, let displayName):
                        trackRow(relativePath: relativePath, displayName: displayName, depth: row.depth)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.playerBackground)
            // `safeAreaInset` der Mini-Player-Leiste reicht seine Hoehe in
            // verschachtelten Tab-/Navigation-Stacks nicht auf allen iOS-
            // Versionen verlaesslich bis zur List weiter. Dieser zusaetzliche
            // Scroll-Rand garantiert, dass die letzte Datei vollstaendig ueber
            // die Leiste gezogen werden kann; ohne Titel entsteht keine Luecke.
            .contentMargins(
                .bottom,
                player.currentTrack == nil ? 0 : 72,
                for: .scrollContent)
            .searchable(text: $search, prompt: Text("library.search.prompt"))
            .overlay {
                if rows.isEmpty && isFiltering {
                    ContentUnavailableView.search(text: search)
                }
            }
        }

        // MARK: - Zeilen ueber dem Baum

        private var activityRow: some View {
            HStack(spacing: 12) {
                ProgressView()
                Text(Self.activityTitle(library.activity))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("common.cancel") { library.cancelCurrentOperation() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }

        private static func activityTitle(_ activity: LibraryActivity?) -> LocalizedStringKey {
            switch activity {
            case .scanning: return "library.activity.scanning"
            case .importing: return "library.activity.importing"
            case .unpacking: return "library.activity.unpacking"
            case .resetting: return "library.activity.resetting"
            case nil: return "library.activity.scanning"
            }
        }

        // Fehler werden als Zeile gezeigt, nicht als Dialog: waehrend eines
        // Imports steht schon ein Blatt mit eigener Meldung im Weg, und zwei
        // Dialoge auf derselben Meldung vertragen sich nicht.
        private func errorRow(_ message: String) -> some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(verbatim: message)
                    .font(.footnote)
                Spacer()
                Button("common.ok") { library.errorMessage = nil }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }

        // Nur Fehler-/Abbruchfaelle bleiben offen. Normal gefundene ZIPs packt
        // der Bibliotheksabgleich automatisch aus.
        private var pendingRow: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label("import.pending.title", systemImage: "shippingbox")
                    .font(.subheadline.weight(.semibold))
                Text("import.pending.count \(library.pendingArchives.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("import.pending.unpack") { library.unpackPendingArchives() }
                    .buttonStyle(.bordered)
                    .disabled(library.isBusy)
            }
            .padding(.vertical, 4)
        }

        @ViewBuilder
        private var playAllRows: some View {
            Button {
                startPlayback(shuffled: false)
            } label: {
                Label("library.play.all", systemImage: "play.fill")
            }
            Button {
                startPlayback(shuffled: true)
            } label: {
                Label("library.play.shuffle", systemImage: "shuffle")
            }
        }

        // MARK: - Baumzeilen

        private func folderRow(name: String, path: String, trackCount: Int, depth: Int) -> some View {
            Button {
                if expandedFolders.contains(path) {
                    expandedFolders.remove(path)
                } else {
                    expandedFolders.insert(path)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded(path) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                    Text(verbatim: name)
                        .lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(trackCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.leading, indent(depth))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private func trackRow(relativePath: String, displayName: String, depth: Int) -> some View {
            let isCurrent = player.currentTrack?.relativePath == relativePath
            let isFavorite = library.isFavorite(relativePath)
            return Button {
                play(relativePath: relativePath)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCurrent ? "speaker.wave.2.fill" : "music.note")
                        .font(.caption)
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                        .frame(width: 16)
                    Text(verbatim: displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .fontWeight(isCurrent ? .semibold : .regular)
                    Spacer()
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.leading, indent(depth))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    library.toggleFavorite(relativePath)
                } label: {
                    // Der Typ steht ausdruecklich da: ohne ihn haelt Swift die
                    // beiden Schluessel fuer gewoehnliche Zeichenketten und die
                    // Beschriftung bliebe unuebersetzt.
                    let title: LocalizedStringKey = isFavorite
                        ? "library.favorite.remove"
                        : "library.favorite.add"
                    Label(title, systemImage: isFavorite ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
        }

        // Einrueckung je Ebene. Bewusst massvoll: auf einem Telefon ist der
        // Platz knapp, tiefe Sammlungen wuerden sonst am rechten Rand kleben.
        private func indent(_ depth: Int) -> CGFloat {
            CGFloat(min(depth, 6)) * 14
        }

        private func isExpanded(_ path: String) -> Bool {
            isFiltering || expandedFolders.contains(path)
        }

        // MARK: - Wiedergabe starten

        // Die Abspielliste ist immer die vollstaendige (gefilterte) Auswahl,
        // nicht der angetippte Ordner.
        private var playableTracks: [TrackRef] {
            library.filteredTracks(search: search, favoritesOnly: favoritesOnly)
        }

        private func play(relativePath: String) {
            let tracks = playableTracks
            guard let track = tracks.first(where: { $0.relativePath == relativePath }) else { return }
            player.setQueue(tracks)
            player.play(track)
        }

        private func startPlayback(shuffled: Bool) {
            let tracks = playableTracks
            guard !tracks.isEmpty else { return }
            settings.set(\.shuffleEnabled, to: shuffled)
            player.setQueue(tracks)
            // Bei Zufallswiedergabe faengt die Liste auch zufaellig an — sonst
            // begaenne jeder Abend mit demselben Titel.
            player.play(shuffled ? (tracks.randomElement() ?? tracks[0]) : tracks[0])
        }

        // MARK: - Automatisches Aufklappen

        private func expandPath(to track: TrackRef?) {
            guard let track else { return }
            expandedFolders.formUnion(LibraryTree.ancestorPaths(of: track.folderPath))
        }
    }
}

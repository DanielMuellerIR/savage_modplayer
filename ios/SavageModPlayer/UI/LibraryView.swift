import SavageModPlayerCore
import SwiftUI

// Der Bibliotheks-Tab: ein echter Ordnerbaum zum Durchklicken, Suche,
// Favoritenfilter und die beiden Wege, Musik auf das Geraet zu bekommen.
//
// Wichtig fuer das Verstaendnis der Abspielreihenfolge: gespielt wird immer die
// FLACHE, angezeigte Auswahl, nie nur der
// aufgeklappte Ordner. Weiter und Zurueck laufen deshalb ueber Ordnergrenzen
// hinweg, genau in der Reihenfolge, die auf dem Bildschirm steht.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel

    /// Bringt die Ansicht ihre eigene Navigationsleiste mit?
    ///
    /// Im Tab-Layout des iPhones ja — dort steht sie fuer sich. In der
    /// zweispaltigen iPad-Ansicht liefert die Spalte selbst die Leiste; eine
    /// zweite darin ergaebe zwei Titelzeilen uebereinander.
    let embedsNavigation: Bool

    /// Wird im zweispaltigen Layout gesetzt: Dort gibt es keinen
    /// Einstellungs-Tab, also braucht die Werkzeugleiste einen Knopf dafuer.
    let onOpenSettings: (() -> Void)?

    init(embedsNavigation: Bool = true, onOpenSettings: (() -> Void)? = nil) {
        self.embedsNavigation = embedsNavigation
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        Content(
            library: model.library,
            player: model.player,
            playlists: model.playlists,
            catalog: model.catalog,
            settings: model.settings,
            embedsNavigation: embedsNavigation,
            onOpenSettings: onOpenSettings,
            // Nur die Weitergabe, keine Beobachtung: Der innere Aufbau soll
            // AppModel nicht beobachten muessen, um Dateien annehmen zu koennen.
            onDropFiles: { [model] urls in model.importDropped(urls) },
            onOpenCollection: { [model] in model.showCollectionExchange() },
            onSearchActiveChange: { [model] active in model.isSearchFieldActive = active },
            onLibraryPanelChange: { [model] active in model.isLibraryPanelOpen = active })
    }

    private struct Content: View {
        @ObservedObject var library: LibraryStore
        @ObservedObject var player: PlaybackEngine
        @ObservedObject var playlists: PlaylistCollectionStore
        @ObservedObject var catalog: LibraryCatalogModel
        let settings: PlayerSettings
        let embedsNavigation: Bool
        let onOpenSettings: (() -> Void)?
        let onDropFiles: ([URL]) -> Void
        let onOpenCollection: () -> Void
        let onSearchActiveChange: (Bool) -> Void
        let onLibraryPanelChange: (Bool) -> Void

        private var search: String { catalog.query.search }
        private var favoritesOnly: Bool {
            get { catalog.query.favoritesOnly }
            nonmutating set { catalog.query.favoritesOnly = newValue }
        }
        // Pfade der aufgeklappten Ordner. Alles startet zugeklappt; nur der Weg
        // zum laufenden Titel klappt von selbst auf.
        @State private var expandedFolders: Set<String> = []
        @State private var showImport = false
        @State private var showPlaylists = false
        @State private var showQueue = false
        @State private var showFilters = false
        // Schwebt gerade etwas ueber der Bibliothek? Nur fuer die Rueckmeldung.
        @State private var isDropTargeted = false

        var body: some View {
            if embedsNavigation {
                NavigationStack { list }
            } else {
                list
            }
        }

        private var list: some View {
            Group {
                if library.tracks.isEmpty {
                    emptyState
                } else {
                    treeList
                }
            }
            .background(Color.playerBackground)
            // Module und Archive aus der Dateien-App hereinziehen. Der Weg
            // dahinter ist derselbe wie bei "Oeffnen mit": Uebernahme nach
            // `Documents/`, Archive unterwegs ausgepackt. Nur abgespielt wird
            // nichts — wer zehn Dateien ablegt, will sie einsortiert wissen.
            .dropDestination(for: URL.self) { urls, _ in
                onDropFiles(urls)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .overlay {
                if isDropTargeted {
                    dropIndicator
                }
            }
            .navigationTitle("tab.library")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showImport) { LibraryImportSheet() }
            .sheet(isPresented: $showPlaylists) {
                PlaylistsView(store: playlists, library: library, player: player)
            }
            .sheet(isPresented: $showQueue) { PendingQueueView(player: player) }
            .sheet(isPresented: $showFilters) { LibraryFiltersView(catalog: catalog) }
            .onChange(of: showPlaylists || showFilters || showImport || showQueue) { _, active in onLibraryPanelChange(active) }
            .onAppear { expandPath(to: player.currentTrack) }
            .onChange(of: player.currentTrack) { _, track in expandPath(to: track) }
        }

        // Sichtbare Rueckmeldung, solange etwas ueber der Bibliothek schwebt.
        // Ohne sie ist nicht zu erkennen, ob das Ziel ueberhaupt annimmt.
        private var dropIndicator: some View {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                .background(Color.accentColor.opacity(0.08))
                .overlay {
                    Text("library.drop.hint")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                }
                .padding(8)
                .allowsHitTesting(false)
        }

        // MARK: - Werkzeugleiste

        @ToolbarContentBuilder
        private var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Sammlung übertragen", systemImage: "arrow.up.arrow.down", action: onOpenCollection)
                        .disabled(library.isBusy).accessibilityIdentifier("collection-transfer")
                    Button("library.filters.title", systemImage: "line.3.horizontal.decrease") { showFilters = true }
                    Button("playlists.title", systemImage: "music.note.list") { showPlaylists = true }
                    Button("queue.count \(player.pendingQueue.items.count)", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        showQueue = true
                    }
                } label: {
                    Label("playlists.menu", systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("playlists-menu")
            }
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
            if let onOpenSettings {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenSettings) {
                        Label("tab.settings", systemImage: "gearshape")
                    }
                    .accessibilityLabel("tab.settings")
                }
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
                    Spacer(minLength: 0)
                    emptyLibraryMessage
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        // Bewusst von Hand gebaut statt mit `ContentUnavailableView`.
        //
        // Die Systemansicht nimmt sich die Wunschbreite ihres laengsten Textes
        // und ignoriert dabei die angebotene Breite. In der schmalen
        // Bibliotheks-Spalte des zweispaltigen iPad-Layouts stand der Hinweis
        // dadurch an beiden Seiten ueber dem Rand — mitten im Satz
        // abgeschnitten. Weder `fixedSize` am Text noch `frame(maxWidth:)` am
        // Container haben daran etwas geaendert.
        private var emptyLibraryMessage: some View {
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("library.empty.title")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("library.empty.hint")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("import.title") { showImport = true }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                Text("import.filesharing.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            // Auf einem breiten Bildschirm soll der Text nicht ueber die ganze
            // Flaeche laufen — lesbare Zeilenlaenge statt Rand-zu-Rand.
            .frame(maxWidth: 420)
        }

        // MARK: - Baumansicht

        private var displayTree: PlaylistScanner.FolderNode? {
            library.filteredTree(search: search, favoritesOnly: favoritesOnly)
        }

        // Waehrend Suche oder Favoritenfilter enthaelt der Baum nur noch
        // Treffer. Zugeklappte Ordner wuerden sie verstecken, also ist dann
        // alles offen.
        private var isFiltering: Bool {
            catalog.query.usesFlatList
        }

        private var rows: [LibraryRow] {
            if isFiltering {
                return playableTracks.map {
                    LibraryRow(id: "track:" + $0.relativePath, depth: 0, kind: .track(relativePath: $0.relativePath, displayName: $0.displayName))
                }
            }
            return LibraryTree.rows(of: displayTree, expanded: expandedFolders, expandAll: isFiltering)
        }

        private var treeList: some View {
            List {
                if library.isBusy { activityRow }
                if let message = library.errorMessage { errorRow(message) }
                if !library.pendingArchives.isEmpty { pendingRow }
                LibraryIndexProgressView(catalog: catalog)
                if !isFiltering { playAllRows }
                else {
                    Button("library.play.results", systemImage: "play.fill") {
                        let tracks = playableTracks
                        player.setExplicitQueue(tracks)
                        if let track = tracks.first { player.play(track) }
                    }
                    .disabled(playableTracks.isEmpty || catalog.isFiltering)
                }

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
            // Vor `searchable`, damit der Melder INNERHALB des durchsuchbaren
            // Bereichs liegt — nur dort gibt es `isSearching`.
            .background { SearchStateReporter(onChange: onSearchActiveChange) }
            .searchable(text: $catalog.query.search, prompt: Text("library.search.prompt"))
            .overlay {
                if rows.isEmpty && isFiltering && catalog.progress == nil && !catalog.isFiltering {
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: displayName)
                            .lineLimit(1).truncationMode(.middle)
                            .fontWeight(isCurrent ? .semibold : .regular)
                        if let metadata = catalog.records[relativePath]?.metadata {
                            Text(verbatim: metadata.librarySummary)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if isFiltering {
                            Text(verbatim: relativePath).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
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
            .contextMenu {
                if let track = library.track(forRelativePath: relativePath) {
                    Button("queue.next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        player.enqueue(track, next: true)
                    }
                    Button("queue.add", systemImage: "text.badge.plus") { player.enqueue(track) }
                    Menu("playlists.add", systemImage: "music.note.list") {
                        ForEach(playlists.document.playlists) { playlist in
                            Button(playlist.name) { playlists.add(track, to: playlist.id) }
                        }
                        if playlists.document.playlists.isEmpty {
                            Button("playlists.create") { showPlaylists = true }
                        }
                    }
                    .disabled(!playlists.canWrite)
                    if catalog.preferences.heardIDs.contains(relativePath) {
                        Button("library.mark.unheard", systemImage: "arrow.uturn.backward") {
                            catalog.markHeard(relativePath, heard: false)
                        }
                        .disabled(!catalog.preferencesWritable)
                    }
                }
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
            if !catalog.query.usesFlatList { return library.tracks }
            return catalog.filteredIDs.compactMap { library.track(forRelativePath: $0) }
        }

        private func play(relativePath: String) {
            let tracks = playableTracks
            guard let track = tracks.first(where: { $0.relativePath == relativePath }) else { return }
            if catalog.query.usesFlatList { player.setExplicitQueue(tracks) }
            else { player.setQueue(tracks) }
            player.play(track)
        }

        private func startPlayback(shuffled: Bool) {
            let tracks = playableTracks
            guard !tracks.isEmpty else { return }
            settings.set(\.shuffleEnabled, to: shuffled)
            if catalog.query.usesFlatList { player.setExplicitQueue(tracks) }
            else { player.setQueue(tracks) }
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

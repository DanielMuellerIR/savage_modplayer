import SwiftUI
import SavageModPlayerCore

extension MainView {
    var savedPlaylistStore: SavedPlaylistStore {
        let override = ProcessInfo.processInfo.environment["SAVAGE_PLAYLIST_STORE"]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let file = override.map { URL(fileURLWithPath: $0) }
            ?? support.appendingPathComponent("SavageModPlayer/playlists.json")
        return SavedPlaylistStore(fileURL: file)
    }

    func loadSavedPlaylists() {
        do {
            savedPlaylistDocument = try savedPlaylistStore.load()
            favorites = savedPlaylistDocument.favoriteIDs
            savedPlaylistsWritable = true
            playlistStorageError = nil
        } catch {
            savedPlaylistsWritable = false
            playlistStorageError = "Gespeicherte Playlists konnten nicht geladen werden: \(error.localizedDescription) Die Datei bleibt erhalten."
            errorMessage = playlistStorageError
        }
    }

    @discardableResult
    func updateSavedPlaylists(_ change: (inout SavedPlaylistDocument) -> Void) -> Bool {
        guard savedPlaylistsWritable else {
            errorMessage = "Der Playlist-Speicher ist nicht verfügbar. Die vorhandene Datei bleibt erhalten."
            return false
        }
        var next = savedPlaylistDocument
        change(&next)
        do {
            try savedPlaylistStore.save(next)
            savedPlaylistDocument = next
            favorites = next.favoriteIDs
            collectionSync?.metadataDidChange()
            return true
        } catch {
            errorMessage = "Playlists konnten nicht gesichert werden: \(error.localizedDescription)"
            return false
        }
    }

    func registerTracks(_ entries: [PlaylistScanner.Entry]) {
        for entry in entries { trackReferences[entry.url] = entry.reference }
        guard !savedPlaylistDocument.favoritesMigrationCompleted else { return }
        let legacy = Set(UserDefaults.standard.stringArray(forKey: MainView.favoritesDefaultsKey) ?? [])
        var ambiguous = Set<String>()
        if updateSavedPlaylists({ document in
            ambiguous = document.migrateFavorites(names: legacy, among: entries.map(\.reference))
        }), !ambiguous.isEmpty {
            playlistNotice = "\(ambiguous.count) alte Favoriten sind wegen gleicher Dateinamen nicht eindeutig. Bitte neu markieren."
        }
    }

    var currentTrackReferences: [PlaylistTrackReference] {
        filteredPlaylist.compactMap { trackReferences[$0] }
    }

    func createSavedPlaylist(name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return updateSavedPlaylists { $0.playlists.append(SavedPlaylist(name: name, tracks: currentTrackReferences)) }
    }

    func editSavedPlaylist(id: UUID, change: (inout SavedPlaylist) -> Void) {
        updateSavedPlaylists { document in
            guard let index = document.playlists.firstIndex(where: { $0.id == id }) else { return }
            change(&document.playlists[index])
        }
    }

    func openSavedPlaylist(_ saved: SavedPlaylist) {
        playbackActions.observeSleepTimer(coordinator: coordinator)
        let requestID = UUID()
        playlistRequestID = requestID
        collectingPlaylistRequest = requestID
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        let tempDir = Self.newDropTempDir()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SavedPlaylistResolver.resolve(saved.tracks, tempDir: tempDir)
            DispatchQueue.main.async {
                guard playlistRequestID == requestID else { return }
                defer { collectingPlaylistRequest = nil; openNextCollectionIfPossible() }
                guard !result.entries.isEmpty else {
                    playlistNotice = "Keine Quelle für „\(saved.name)“ erreichbar. Die gespeicherten Einträge bleiben erhalten."
                    return
                }
                registerTracks(result.entries)
                playlist = result.entries.map(\.url)
                playlistTree = nil
                expandedFolders = []
                folderPathByURL = [:]
                playbackSelection = nil
                queueResumeURL = nil
                catalog.query = LibraryQuery()
                selectedSidebarTab = 0
                selectPlaylistSong(at: 0, autoPlay: wasPlaying, manualPlayback: false)
                var notices: [String] = []
                if !result.missing.isEmpty { notices.append("\(result.missing.count) Titel aus „\(saved.name)“ fehlen.") }
                if !result.limited.isEmpty { notices.append("\(result.limited.count) Titel konnten wegen der Archiv-Sicherheitsgrenzen nicht geöffnet werden.") }
                playlistNotice = notices.isEmpty ? nil : notices.joined(separator: " ") + " Die gespeicherte Liste bleibt vollständig."
            }
        }
    }

    var savedPlaylistsSheet: some View {
        SavedPlaylistsView(
            playlists: savedPlaylistDocument.playlists,
            currentTrackCount: currentTrackReferences.count,
            writable: savedPlaylistsWritable,
            errorMessage: playlistStorageError ?? errorMessage,
            onCreate: createSavedPlaylist,
            onRename: { id, name in editSavedPlaylist(id: id) { $0.name = name } },
            onDelete: { id in updateSavedPlaylists { $0.playlists.removeAll { $0.id == id } } },
            onOpen: { saved in showSavedPlaylists = false; openSavedPlaylist(saved) },
            onRemove: { id, trackID in editSavedPlaylist(id: id) { $0.tracks.removeAll { $0.id == trackID } } },
            onMove: { id, trackID, offset in
                editSavedPlaylist(id: id) { saved in
                    guard let index = saved.tracks.firstIndex(where: { $0.id == trackID }),
                          saved.tracks.indices.contains(index + offset) else { return }
                    saved.tracks.swapAt(index, index + offset)
                }
            })
            .preferredColorScheme(theme == .workbench ? .light : .dark)
    }
}

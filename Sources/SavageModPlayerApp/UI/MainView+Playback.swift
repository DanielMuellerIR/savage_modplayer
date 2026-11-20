import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// Wiedergabesteuerung der MainView: Play/Pause/Stop, Titel vor/zurueck,
// Zufallsauswahl und Songende-Behandlung.
extension MainView {
    // Play/Pause-Toggle: pausiert statt zu stoppen — resume() setzt nahtlos
    // fort. Endgueltiges Stoppen macht der separate Stop-Button (stopPlayback).
    func togglePlayback() {
        playbackActions.togglePlayback(coordinator: coordinator)
    }

    func stopPlayback() {
        playbackActions.stopPlayback(coordinator: coordinator)
    }

    var navigationPlaylist: PlaylistPlaybackNavigation.Playlist {
        .init(urls: playlist, selection: playbackSelection, wrap: loopMode == .playlist, shuffle: shuffleEnabled)
    }

    var eligiblePlaylistIndices: [Int] { navigationPlaylist.eligibleIndices }

    @discardableResult
    func nextTrack(automatic: Bool = false) -> Bool {
        if automatic && !coordinator.sleepTimer.allowsPlayback() { return false }
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        var navigation = playlistPlayback
        let advanced = navigation.next(in: navigationPlaylist, references: trackReferences) { url in
            loadPlaylistSelection(url, autoPlay: wasPlaying, manualPlayback: !automatic)
        } loadQueued: { url in
            if wasPlaying && !automatic { playbackActions.prepareManualPlayback(coordinator: coordinator) }
            return loadModFile(from: url)
        } startQueuedPlayback: {
            guard wasPlaying else { return true }
            coordinator.play()
            return coordinator.isPlaying
        } missing: { track in
            errorMessage = "Der nächste Titel ist nicht mehr erreichbar: \(track.displayName)"
        }
        playlistPlayback = navigation
        return advanced
    }

    func prevTrack() {
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        var navigation = playlistPlayback
        _ = navigation.previous(in: navigationPlaylist) { url in
            loadPlaylistSelection(url, autoPlay: wasPlaying, manualPlayback: true)
        }
        playlistPlayback = navigation
    }

    // Wird ausgeloest, wenn der Renderblock das Songende erreicht (Wrap auf 0).
    // Wertet den loopMode aus: einmal abspielen -> stoppen; Song wiederholen ->
    // die Engine laeuft bereits in Schleife (nichts tun); Playlist -> naechster Titel.
    func handleSongEnd() {
        guard coordinator.isPlaying, !coordinator.isPaused, coordinator.sleepTimer.allowsPlayback() else { return }
        switch loopMode {
        case .none:
            coordinator.stop()
        case .track:
            // Die Engine spielt am echten Endziel bereits weiter; nur Anzeige-
            // und System-Spielzeit muessen auf denselben Punkt springen.
            coordinator.resetElapsedToLoopStart()
            updateNowPlayingInfo()
        case .playlist:
            if !nextTrack(automatic: true) { coordinator.stop() }
        }
    }

    func enqueueTrack(_ url: URL, next: Bool) {
        guard let reference = trackReferences[url] else { return }
        trackQueue.enqueue(reference, next: next)
    }

    func playFilteredResults() {
        let selected = filteredPlaylist
        guard let first = selected.first, let index = playlist.firstIndex(of: first) else { return }
        playbackSelection = selected
        selectPlaylistSong(at: index)
    }

    var queueSheet: some View {
        TrackQueueView(items: trackQueue.items,
                       onRemove: { trackQueue.remove(id: $0) },
                       onMove: { trackQueue.move(id: $0, by: $1) },
                       onClear: { trackQueue.removeAll() })
            .preferredColorScheme(theme == .workbench ? .light : .dark)
    }

}

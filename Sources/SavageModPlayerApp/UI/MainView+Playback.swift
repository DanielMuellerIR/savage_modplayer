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

    var eligiblePlaylistIndices: [Int] {
        guard let selection = playbackSelection else { return Array(playlist.indices) }
        var indices: [URL: Int] = [:]
        for (index, url) in playlist.enumerated() where indices[url] == nil { indices[url] = index }
        return selection.compactMap { indices[$0] }
    }

    @discardableResult
    func nextTrack(automatic: Bool = false) -> Bool {
        if automatic && !coordinator.sleepTimer.allowsPlayback() { return false }
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        if let queued = trackQueue.items.first {
            guard let url = TrackQueue.playbackURL(for: queued.track,
                playlist: playlist, references: trackReferences) else {
                errorMessage = "Der nächste Titel ist nicht mehr erreichbar: \(queued.track.displayName)"
                return false
            }
            let anchor = queueResumeURL
            if wasPlaying && !automatic { playbackActions.prepareManualPlayback(coordinator: coordinator) }
            if anchor == nil, playlist.indices.contains(currentPlaylistIndex) {
                queueResumeURL = playlist[currentPlaylistIndex]
            }
            guard loadModFile(from: url) else {
                queueResumeURL = anchor
                return false
            }
            currentPlaylistIndex = playlist.firstIndex(of: url) ?? -1
            if wasPlaying {
                coordinator.play()
                guard coordinator.isPlaying else {
                    queueResumeURL = anchor
                    return false
                }
            }
            trackQueue.remove(id: queued.id)
            return true
        }
        let current = shuffleEnabled ? currentPlaylistIndex
            : queueResumeURL.flatMap { playlist.firstIndex(of: $0) } ?? currentPlaylistIndex
        guard let index = PlaylistNavigation.adjacentIndex(current: current, eligible: eligiblePlaylistIndices,
            backwards: false, wrap: loopMode == .playlist, shuffle: shuffleEnabled) else { return false }
        return selectPlaylistSong(at: index, autoPlay: wasPlaying, manualPlayback: !automatic)
    }

    func prevTrack() {
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        if let queueResumeURL, let index = playlist.firstIndex(of: queueResumeURL) {
            selectPlaylistSong(at: index, autoPlay: wasPlaying)
            return
        }
        if let index = PlaylistNavigation.adjacentIndex(current: currentPlaylistIndex,
            eligible: eligiblePlaylistIndices, backwards: true,
            wrap: loopMode == .playlist, shuffle: shuffleEnabled) {
            selectPlaylistSong(at: index, autoPlay: wasPlaying)
        }
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

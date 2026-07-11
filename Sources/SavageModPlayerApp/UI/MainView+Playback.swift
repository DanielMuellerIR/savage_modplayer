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
        guard coordinator.activeMod != nil else { return }
        if coordinator.isPaused {
            coordinator.resume()
        } else if coordinator.isPlaying {
            coordinator.pause()
        } else {
            coordinator.play()
        }
    }

    func stopPlayback() {
        coordinator.stop()
    }

    // Zufaelligen Playlist-Index liefern, der (wenn moeglich) nicht der
    // aktuelle Titel ist.
    func randomPlaylistIndex() -> Int {
        guard playlist.count > 1 else { return 0 }
        var idx = currentPlaylistIndex
        while idx == currentPlaylistIndex {
            idx = Int.random(in: 0..<playlist.count)
        }
        return idx
    }

    func nextTrack() {
        guard !playlist.isEmpty else { return }
        // Transportzustand erhalten: setMod() in loadModFile ruft stop(), daher
        // VOR dem Wechsel merken, ob gerade aktiv (nicht pausiert) gespielt wurde.
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        if shuffleEnabled {
            selectPlaylistSong(at: randomPlaylistIndex(), autoPlay: wasPlaying)
            return
        }
        let nextIndex = currentPlaylistIndex + 1
        if nextIndex < playlist.count {
            selectPlaylistSong(at: nextIndex, autoPlay: wasPlaying)
        } else if loopMode == .playlist {
            selectPlaylistSong(at: 0, autoPlay: wasPlaying)
        }
    }

    func prevTrack() {
        guard !playlist.isEmpty else { return }
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        if shuffleEnabled {
            selectPlaylistSong(at: randomPlaylistIndex(), autoPlay: wasPlaying)
            return
        }
        let prevIndex = currentPlaylistIndex - 1
        if prevIndex >= 0 {
            selectPlaylistSong(at: prevIndex, autoPlay: wasPlaying)
        } else if loopMode == .playlist {
            selectPlaylistSong(at: playlist.count - 1, autoPlay: wasPlaying)
        }
    }

    // Wird ausgeloest, wenn der Renderblock das Songende erreicht (Wrap auf 0).
    // Wertet den loopMode aus: einmal abspielen -> stoppen; Song wiederholen ->
    // die Engine laeuft bereits in Schleife (nichts tun); Playlist -> naechster Titel.
    func handleSongEnd() {
        switch loopMode {
        case .none:
            coordinator.stop()
        case .track:
            break // Engine wrappt bereits auf Position 0 und spielt weiter.
        case .playlist:
            nextTrack()
        }
    }

}

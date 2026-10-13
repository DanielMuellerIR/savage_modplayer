import Foundation
import Combine
import SavageModPlayerCore

@MainActor
final class PlaybackActions: ObservableObject {
    // Beide Fenster teilen den Auftrag auch bei geschlossenem Hauptfenster.
    var fileRequestID = UUID()

    func togglePlayback(coordinator: ModPlayerCoordinator) {
        fileRequestID = UUID()
        guard coordinator.activeMod != nil else { return }
        if coordinator.isPaused {
            coordinator.resume()
        } else if coordinator.isPlaying {
            coordinator.pause()
        } else {
            coordinator.play()
        }
    }

    func playPlayback(coordinator: ModPlayerCoordinator) {
        fileRequestID = UUID()
        guard coordinator.activeMod != nil else { return }
        if coordinator.isPaused {
            coordinator.resume()
        } else if !coordinator.isPlaying {
            coordinator.play()
        }
    }

    func pausePlayback(coordinator: ModPlayerCoordinator) {
        fileRequestID = UUID()
        coordinator.pause()
    }

    func stopPlayback(coordinator: ModPlayerCoordinator) {
        fileRequestID = UUID()
        coordinator.stop()
    }
}

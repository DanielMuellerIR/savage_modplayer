import Foundation
import Combine
import SavageModPlayerCore

@MainActor
final class PlaybackActions: ObservableObject {
    // Beide Fenster teilen den Auftrag auch bei geschlossenem Hauptfenster.
    var fileRequestID = UUID()
    var hasHandledCollectionLaunch = false

    func prepareManualPlayback(coordinator: ModPlayerCoordinator) {
        observeSleepTimer(coordinator: coordinator)
        coordinator.sleepTimer.prepareForManualPlayback()
    }

    func observeSleepTimer(coordinator: ModPlayerCoordinator) {
        coordinator.onSleepTimerExpired = { [weak self] in self?.fileRequestID = UUID() }
    }

    func togglePlayback(coordinator: ModPlayerCoordinator) {
        fileRequestID = UUID()
        guard coordinator.activeMod != nil else { return }
        observeSleepTimer(coordinator: coordinator)
        if coordinator.isPaused {
            coordinator.sleepTimer.prepareForManualPlayback()
            coordinator.resume()
        } else if coordinator.isPlaying {
            coordinator.pause()
        } else {
            coordinator.sleepTimer.prepareForManualPlayback()
            coordinator.play()
        }
    }

    func playPlayback(coordinator: ModPlayerCoordinator) {
        fileRequestID = UUID()
        guard coordinator.activeMod != nil else { return }
        prepareManualPlayback(coordinator: coordinator)
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
        coordinator.sleepTimer.cancel()
        coordinator.stop()
    }
}

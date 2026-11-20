import Foundation
import Combine
import SavageModPlayerCore

@MainActor
final class PlaybackActions: ObservableObject {
    // Beide Fenster teilen den Auftrag auch bei geschlossenem Hauptfenster.
    var fileRequestID = UUID()
    private var dropRequestID = UUID()
    var hasHandledCollectionLaunch = false

    typealias DropLoader = (@escaping @Sendable (URL?) -> Void) -> Void

    func collectDrop(_ loaders: [DropLoader], completion: @escaping @MainActor ([URL]?) -> Void) {
        let request = UUID()
        dropRequestID = request
        let startingFileRequest = fileRequestID
        let group = DispatchGroup()
        let files = DropFiles()
        for load in loaders {
            group.enter()
            load { url in
                if let url, url.isFileURL { files.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = files.snapshot()
            // Sammlungsdateien importieren nur Metadaten und starten keinen Titel.
            let containsAudio = urls.contains { $0.pathExtension.lowercased() != CollectionExchangeCodec.fileExtension }
            guard self.dropRequestID == request, !urls.isEmpty,
                  !containsAudio || self.fileRequestID == startingFileRequest else {
                completion(nil)
                return
            }
            completion(urls)
        }
    }

    @discardableResult
    func beginFileRequest() -> UUID {
        fileRequestID = UUID()
        return fileRequestID
    }

    func prepareManualPlayback(coordinator: ModPlayerCoordinator) {
        observeSleepTimer(coordinator: coordinator)
        coordinator.sleepTimer.prepareForManualPlayback()
    }

    func observeSleepTimer(coordinator: ModPlayerCoordinator) {
        coordinator.onSleepTimerExpired = { [weak self] in self?.beginFileRequest() }
    }

    func togglePlayback(coordinator: ModPlayerCoordinator) {
        beginFileRequest()
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
        beginFileRequest()
        guard coordinator.activeMod != nil else { return }
        prepareManualPlayback(coordinator: coordinator)
        if coordinator.isPaused {
            coordinator.resume()
        } else if !coordinator.isPlaying {
            coordinator.play()
        }
    }

    func pausePlayback(coordinator: ModPlayerCoordinator) {
        beginFileRequest()
        coordinator.pause()
    }

    func stopPlayback(coordinator: ModPlayerCoordinator) {
        beginFileRequest()
        coordinator.sleepTimer.cancel()
        coordinator.stop()
    }
}

// Provider rufen ihre Abschlüsse nebenläufig auf. Jeder Zugriff auf URLs hält den Lock.
private final class DropFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.withLock { urls.append(url) }
    }

    func snapshot() -> [URL] {
        lock.withLock { urls }
    }
}

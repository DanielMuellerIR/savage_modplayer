import Foundation
import Combine
import SavageModPlayerCore

@MainActor
final class NoteRainModel: ObservableObject {
    @Published private(set) var notes: [PreviewNote] = []
    @Published private(set) var time: Double = 0
    @Published private(set) var isPreparing = false
    @Published private(set) var hasOverflowed = false
    @Published private(set) var nextSongEnd: Double?
    private var worker = NotePreviewWorker()
    private var sourceID: UUID?
    private var commands: [NotePreviewCommand] = []
    private var preparedThrough: Double = 0
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var revision = 0
    var horizon: Double = 4

    func start(coordinator: ModPlayerCoordinator) {
        stop()
        tick(coordinator: coordinator, horizon: horizon)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self, weak coordinator] _ in
            MainActor.assumeIsolated {
                guard let self, let coordinator else { return }
                self.tick(coordinator: coordinator, horizon: self.horizon)
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        revision += 1
        isPreparing = false
        worker = NotePreviewWorker()
        notes = []
        commands = []
        sourceID = nil
        preparedThrough = 0
        nextSongEnd = nil
    }

    private func tick(coordinator: ModPlayerCoordinator, horizon: Double) {
        guard let source = coordinator.notePreviewSource else {
            if sourceID != nil {
                stopWork()
                sourceID = nil
                commands = []
                notes = []
                time = 0
                hasOverflowed = false
                nextSongEnd = nil
                worker = NotePreviewWorker()
            }
            return
        }
        if sourceID != source.id {
            stopWork()
            sourceID = source.id
            commands = []
            notes = []
            preparedThrough = 0
            nextSongEnd = nil
            worker = NotePreviewWorker()
        }
        let currentTime = Double(source.exchange.frame) / source.configuration.sampleRate
        if time != currentTime { time = currentTime }
        let overflowed = source.exchange.hasOverflowed
        if hasOverflowed != overflowed { hasOverflowed = overflowed }
        guard !hasOverflowed else { notes = []; stopWork(); return }
        let recorded = source.collectCommands()
        if commands.count != recorded.count {
            commands = recorded
            notes = []
            preparedThrough = 0
            nextSongEnd = nil
            stopWork()
        }
        guard task == nil, preparedThrough < time + horizon + 0.75 else { return }
        let revision = self.revision
        let worker = self.worker
        let commands = self.commands
        isPreparing = preparedThrough < time + horizon
        task = Task { [weak self] in
            do {
                let snapshot = try await worker.preview(source: source, commands: commands,
                    currentTime: currentTime, horizon: horizon + 2)
                guard !Task.isCancelled, let self, self.revision == revision else { return }
                self.notes = snapshot.notes
                self.preparedThrough = snapshot.preparedThrough
                self.nextSongEnd = snapshot.nextSongEnd
                self.isPreparing = false
                self.task = nil
            } catch {
                guard let self, self.revision == revision else { return }
                self.task = nil
                self.isPreparing = false
            }
        }
    }

    private func stopWork() {
        task?.cancel()
        task = nil
        revision += 1
        isPreparing = false
    }
}

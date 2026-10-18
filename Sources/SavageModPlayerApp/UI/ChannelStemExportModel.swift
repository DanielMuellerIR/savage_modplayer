import Foundation
import Combine
import SavageModPlayerCore

@MainActor
final class ChannelStemExportModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var message: String?
    @Published private(set) var completedFolder: URL?
    private var worker: Task<ChannelStemExportReport, Error>?
    private var generation = UUID()

    func start(mod: Mod, destination: URL, options: ChannelStemExportOptions) {
        guard !isRunning else { return }
        let generation = UUID()
        self.generation = generation
        isRunning = true
        progress = 0
        message = nil
        completedFolder = nil
        let throttle = StemExportProgressThrottle { [weak self] value in
            Task { @MainActor in
                guard let self, self.generation == generation, self.isRunning else { return }
                self.progress = value
            }
        }
        let worker = Task.detached(priority: .userInitiated) {
            try ChannelStemRenderer.export(mod: mod, to: destination, options: options,
                progress: { throttle.update($0) })
        }
        self.worker = worker
        Task { [weak self] in
            do {
                let report = try await worker.value
                guard let self, self.generation == generation else { return }
                self.progress = 1
                self.completedFolder = destination
                self.message = "\(report.channelFiles.count) Kanalspuren und Referenzmix gesichert."
                    + (report.endedNaturally ? "" : " Die gewählte Dauergrenze wurde erreicht.")
                self.isRunning = false
                self.worker = nil
            } catch {
                guard let self, self.generation == generation else { return }
                self.message = error is CancellationError ? "Export abgebrochen." : "Export-Fehler: \(error.localizedDescription)"
                self.isRunning = false
                self.worker = nil
            }
        }
    }

    func cancel() { worker?.cancel() }

    func clear() {
        guard !isRunning else { return }
        message = nil
        completedFolder = nil
    }
}

// Nur der einzelne Export-Worker ruft update auf. Die Drosselung verhindert,
// dass schnelle Offline-Blöcke Tausende MainActor-Aufträge aufstauen.
private final class StemExportProgressThrottle: @unchecked Sendable {
    private var lastTime: UInt64 = 0
    private let publish: @Sendable (Double) -> Void

    init(publish: @escaping @Sendable (Double) -> Void) { self.publish = publish }

    func update(_ value: Double) {
        let time = DispatchTime.now().uptimeNanoseconds
        guard value == 0 || value == 0.5 || value == 1 || time - lastTime >= 100_000_000 else { return }
        lastTime = time
        publish(value)
    }
}

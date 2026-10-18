import Foundation
import Combine
import SavageModPlayerCore

@MainActor
final class BatchWAVExportModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: BatchWAVExportProgress?
    @Published private(set) var report: BatchWAVExportReport?
    @Published private(set) var error: String?
    @Published private(set) var destination: URL?
    private var worker: Task<BatchWAVExportReport, Error>?
    private var generation = UUID()

    func start(items: [BatchWAVExportItem], destination: URL, settings: BatchWAVExportSettings) {
        guard !isRunning else { return }
        isRunning = true
        progress = nil
        report = nil
        error = nil
        self.destination = destination
        let generation = UUID()
        self.generation = generation
        let throttle = BatchProgressThrottle { [weak self] value in
            Task { @MainActor in
                guard let self, self.generation == generation, self.isRunning else { return }
                self.progress = value
            }
        }
        let worker = Task.detached(priority: .userInitiated) {
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
            return try BatchWAVExporter.export(items: items, to: destination, settings: settings,
                                                progress: { throttle.update($0) })
        }
        self.worker = worker
        Task { [weak self] in
            do {
                let report = try await worker.value
                guard let self, self.generation == generation else { return }
                self.report = report
                self.finish()
            } catch {
                guard let self, self.generation == generation else { return }
                self.error = error.localizedDescription
                self.finish()
            }
        }
    }

    func cancel() { worker?.cancel() }
    private func finish() { isRunning = false; worker = nil }
}

// Ein Worker liefert höchstens zehn Zwischenstände pro Sekunde und den Endstand.
// Auch Tausende defekte Quellen stauen dadurch keine MainActor-Aufträge auf.
private final class BatchProgressThrottle: @unchecked Sendable {
    private var lastTime: UInt64 = 0
    private let publish: @Sendable (BatchWAVExportProgress) -> Void
    init(publish: @escaping @Sendable (BatchWAVExportProgress) -> Void) { self.publish = publish }
    func update(_ value: BatchWAVExportProgress) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard value.fraction == 1 || now - lastTime >= 100_000_000 else { return }
        lastTime = now
        publish(value)
    }
}

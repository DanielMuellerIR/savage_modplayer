import Foundation
import Combine
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import SavageModPlayerCore
import Darwin

struct NoteRainVideoExportRequest: Identifiable, Sendable {
    let id = UUID()
    let mod: Mod
    let title: String
    let audio: ChannelStemExportOptions
    let appearance: NoteRainVideoAppearance
}

@MainActor
final class NoteRainVideoExportModel: NSObject, ObservableObject, NSOpenSavePanelDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var isChoosingDestination = false
    @Published private(set) var isCancelling = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var message: String?
    @Published private(set) var report: NoteRainVideoReport?
    @Published private(set) var destination: URL?
    @Published private(set) var previewPlayer: AVPlayer?
    @Published private(set) var previewMessage: String?
    private var previewArtifact: NoteRainVideoPreviewArtifact?
    private var worker: Task<NoteRainVideoReport, Error>?
    private var previewWorker: Task<NoteRainVideoPreviewArtifact, Error>?
    private var generation = UUID()
    private var previewGeneration = UUID()
    private var savePanel: NSSavePanel?

    var isBusy: Bool { isRunning || isPreviewing || isChoosingDestination }

    func invalidatePreview() {
        previewGeneration = UUID()
        previewWorker?.cancel(); previewWorker = nil
        isPreviewing = false
        previewPlayer?.pause(); previewPlayer?.replaceCurrentItem(with: nil); previewPlayer = nil
        previewArtifact?.discard(); previewArtifact = nil
        previewMessage = nil
    }

    func preview(request: NoteRainVideoExportRequest, options: NoteRainVideoOptions) {
        guard !isRunning, !isChoosingDestination else { return }
        invalidatePreview()
        let token = UUID(); previewGeneration = token
        isPreviewing = true
        var options = options
        options.audio.maximumSeconds = min(5, options.audio.maximumSeconds)
        let worker = Task.detached(priority: .userInitiated) {
            let artifact = try NoteRainVideoPreviewArtifact()
            do {
                _ = try NoteRainVideoRenderer.export(mod: request.mod, to: artifact.url, options: options)
                try Task.checkCancellation()
                return artifact
            } catch { artifact.discard(); throw error }
        }
        previewWorker = worker
        Task { [weak self] in
            do {
                let artifact = try await worker.value
                guard let self, self.previewGeneration == token else { artifact.discard(); return }
                self.previewArtifact = artifact
                self.previewPlayer = AVPlayer(url: artifact.url)
                self.previewMessage = "Vorschau bereit: bis zu 5 Sekunden ab Songanfang. Zum Anhören Wiedergabe in der Vorschau starten."
                self.isPreviewing = false; self.previewWorker = nil
            } catch {
                guard let self, self.previewGeneration == token else { return }
                self.previewMessage = error is CancellationError ? "Vorschau abgebrochen." : error.localizedDescription
                self.isPreviewing = false; self.previewWorker = nil
            }
        }
    }

    func chooseDestination(request: NoteRainVideoExportRequest, options: NoteRainVideoOptions) {
        guard !isBusy else { return }
        previewPlayer?.pause()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let name = request.title.components(separatedBy: CharacterSet(charactersIn: "/:\0")).joined(separator: "_")
        panel.nameFieldStringValue = (name.isEmpty ? "Notenregen" : name) + ".mov"
        panel.title = "Notenregen als Video exportieren"
        panel.message = "Neue MOV-Datei wählen. Vorhandene Dateien bleiben erhalten."
        panel.prompt = "Exportieren"
        panel.delegate = self
        savePanel = panel; isChoosingDestination = true
        panel.begin { [weak self] response in
            guard let self, self.savePanel === panel else { return }
            self.savePanel = nil; self.isChoosingDestination = false
            guard response == .OK, let url = panel.url else { return }
            self.start(request: request, destination: url, options: options)
        }
    }

    func panel(_ sender: Any, validate url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 { throw NoteRainVideoError.destinationExists }
        if errno != ENOENT { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    func start(request: NoteRainVideoExportRequest, destination: URL, options: NoteRainVideoOptions) {
        guard !isRunning, !isChoosingDestination else { return }
        invalidatePreview()
        let token = UUID(); generation = token
        isRunning = true; isCancelling = false; progress = 0
        message = nil; report = nil; self.destination = nil
        let publish: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in
                guard let self, self.generation == token, self.isRunning else { return }
                self.progress = value
            }
        }
        let worker = Task.detached(priority: .userInitiated) {
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
            return try NoteRainVideoRenderer.export(mod: request.mod, to: destination, options: options, progress: publish)
        }
        self.worker = worker
        Task { [weak self] in
            do {
                let report = try await worker.value
                guard let self, self.generation == token else { return }
                self.progress = 1; self.report = report; self.destination = destination
                let duration = Double(report.audioFrameCount) / Double(NoteRainVideoOptions.sampleRate)
                self.message = String(format: "Video gesichert: %.2f Sekunden, %llu Bilder.", duration, report.videoFrameCount)
                    + (report.endedNaturally ? " Songende erreicht." : " Dauergrenze erreicht.")
                self.finish()
            } catch {
                guard let self, self.generation == token else { return }
                self.message = error is CancellationError ? "Export abgebrochen. Keine neue Zieldatei angelegt." : "Export-Fehler: \(error.localizedDescription)"
                self.finish()
            }
        }
    }

    func cancel() {
        if isRunning { isCancelling = true; worker?.cancel() }
        if isPreviewing { invalidatePreview(); previewMessage = "Vorschau abgebrochen." }
    }

    func close() {
        cancel()
        invalidatePreview()
        let panel = savePanel; savePanel = nil; isChoosingDestination = false
        panel?.cancel(nil)
    }

    private func finish() { isRunning = false; isCancelling = false; worker = nil }
}

private struct NoteRainVideoPreviewArtifact: Sendable {
    let root: URL
    let url: URL
    let device: dev_t
    let inode: ino_t

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("savage-video-preview-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(root.path, &info) == 0 else { throw NoteRainVideoError.invalidDestination }
        device = info.st_dev; inode = info.st_ino
        url = root.appendingPathComponent("preview.mov")
    }

    func discard() {
        var info = stat()
        if lstat(root.path, &info) == 0, info.st_dev == device, info.st_ino == inode {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

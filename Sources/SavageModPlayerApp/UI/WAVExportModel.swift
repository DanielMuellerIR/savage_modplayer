import AppKit
import Combine
import Foundation
import SavageModPlayerCore
import UniformTypeIdentifiers

@MainActor
final class WAVExportModel: ObservableObject {
    @Published var exportSecondsLimit: Double = 180
    @Published var exportChannelStems = false
    @Published var exportFolderName = ""
    @Published private(set) var exportTitle = ""
    @Published private(set) var isExporting = false
    @Published private(set) var exportStatusMessage: String?
    @Published private var showExportDialog = false

    let stemExport = ChannelStemExportModel()
    private var stemObservation: AnyCancellable?
    private var exportModule: Mod?
    private var exportRenderOptions = ChannelStemExportOptions()
    private var destinationRequest: UUID?

    var isRendering: Bool { isExporting || stemExport.isRunning }
    var showsOverlay: Bool { showExportDialog || isRendering || exportStatusMessage != nil || stemExport.message != nil }
    var blocksVideoExport: Bool { showExportDialog || isRendering || destinationRequest != nil }

    init() {
        stemObservation = stemExport.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func handleEscape() {
        if stemExport.isRunning {
            stemExport.cancel()
        } else if !isExporting {
            closeOverlay()
        }
    }

    func closeOverlay() {
        stemExport.clear()
        exportStatusMessage = nil
        showExportDialog = false
        exportModule = nil
    }

    func windowDisappeared() {
        destinationRequest = nil
        stemExport.cancel()
    }

    func chooseDestination(coordinator: ModPlayerCoordinator) {
        guard destinationRequest == nil else { return }
        if exportChannelStems {
            runChannelStemExport()
        } else {
            runWavExport(coordinator: coordinator)
        }
    }

    private func beginDestinationChoice() -> UUID {
        let request = UUID()
        destinationRequest = request
        showExportDialog = false
        return request
    }

    func open(coordinator: ModPlayerCoordinator) {
        guard !isRendering, destinationRequest == nil, let mod = coordinator.activeMod else { return }
        exportStatusMessage = nil
        stemExport.clear()
        exportModule = mod
        exportTitle = coordinator.trackName
        exportRenderOptions = ChannelStemExportOptions(maximumSeconds: exportSecondsLimit,
            stereoSeparation: coordinator.stereoSeparation, useInterpolation: coordinator.useInterpolation,
            palClock: coordinator.palClock,
            mutedChannels: (0..<coordinator.channelCount).filter { coordinator.isMuted(channelIndex: $0) },
            soloChannels: (0..<coordinator.channelCount).filter { coordinator.isSoloed(channelIndex: $0) })
        exportFolderName = coordinator.trackName.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_") + "-Kanalspuren"
        showExportDialog = true
    }

    var validStemFolderName: Bool {
        let name = exportFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":") && !name.contains("\0")
    }

    private func runChannelStemExport() {
        guard let mod = exportModule, validStemFolderName else { return }
        let name = exportFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = exportRenderOptions
        options.maximumSeconds = exportSecondsLimit
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Zielverzeichnis für Kanalspuren"
        panel.prompt = "Hier exportieren"
        panel.message = "Erstellt darin den neuen Ordner „\(name)“. Vorhandene Ordner werden nicht überschrieben."
        let request = beginDestinationChoice()
        panel.begin { response in
            guard self.destinationRequest == request else { return }
            self.destinationRequest = nil
            if response == .OK, let parent = panel.url {
                self.exportModule = nil
                self.stemExport.start(mod: mod, destination: parent.appendingPathComponent(name, isDirectory: true), options: options)
            } else {
                self.showExportDialog = true
            }
        }
    }

    private func runWavExport(coordinator: ModPlayerCoordinator) {
        guard let mod = exportModule else { return }
        let sep = exportRenderOptions.stereoSeparation
        let interp = exportRenderOptions.useInterpolation
        let pal = exportRenderOptions.palClock
        let limit = exportSecondsLimit
        let playerCoordinator = coordinator

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.wav]
        savePanel.nameFieldStringValue = exportTitle.replacingOccurrences(of: " ", with: "_") + ".wav"
        savePanel.title = "Song als WAV exportieren..."

        let request = beginDestinationChoice()
        savePanel.begin { response in
            guard self.destinationRequest == request else { return }
            self.destinationRequest = nil
            if response == .OK, let destURL = savePanel.url {
                self.exportModule = nil
                self.isExporting = true
                self.exportStatusMessage = "Rendert offline..."

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try playerCoordinator.exportActiveModToWav(
                            mod: mod,
                            stereoSeparation: sep,
                            useInterpolation: interp,
                            palClock: pal,
                            destinationURL: destURL,
                            durationSeconds: limit
                        )
                        DispatchQueue.main.async {
                            self.isExporting = false
                            self.exportStatusMessage = "Erfolgreich gesichert!"
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.isExporting = false
                            self.exportStatusMessage = "Export-Fehler: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                self.showExportDialog = true
            }
        }
    }
}

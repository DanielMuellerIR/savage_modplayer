import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// WAV-/Sample-Export der MainView: Export-Logik und der Exporter-Dialog.
extension MainView {
    func openWavExporter() {
        guard !isExporting, !stemExport.isRunning, let mod = coordinator.activeMod else { return }
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

    func runChannelStemExport() {
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
        panel.begin { response in
            if response == .OK, let parent = panel.url {
                exportModule = nil
                stemExport.start(mod: mod, destination: parent.appendingPathComponent(name, isDirectory: true), options: options)
            } else {
                showExportDialog = true
            }
        }
    }

    // MARK: - WAV Export helper
    func runWavExport() {
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
        
        savePanel.begin { response in
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
    
    func runInstrumentSampleExport(index: Int) {
        guard let mod = coordinator.activeMod, index >= 1, index < mod.instruments.count, let inst = mod.instruments[index] else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.wav]
        let name = inst.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "sample_\(index)" : inst.name
        savePanel.nameFieldStringValue = name.replacingOccurrences(of: " ", with: "_") + ".wav"
        savePanel.title = "Instrumenten-Sample als WAV sichern..."
        
        savePanel.begin { response in
            if response == .OK, let destURL = savePanel.url {
                do {
                    try coordinator.exportInstrumentToWav(mod: mod, index: index, destinationURL: destURL)
                    self.errorMessage = "Sample \(index) exportiert!"
                } catch {
                    self.errorMessage = "Fehler: \(error.localizedDescription)"
                }
            }
        }
    }

    var wavExporterDialog: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading, spacing: 16) {
                Text("OFFLINE-WAV-EXPORT")
                    .scaledFont(12, weight: .bold)
                    .foregroundColor(Color.accent(theme))
                Text(exportTitle)
                    .lineLimit(2)
                    .accessibilityIdentifier("wavExportSong")
                if isExporting || stemExport.isRunning {
                    if stemExport.isRunning {
                        Text(stemExport.progress < 0.5 ? "Pegel der Kanalspuren analysieren …" : "Kanalspuren und Referenzmix schreiben …")
                        ProgressView(value: stemExport.progress)
                            .accessibilityLabel("Kanalspuren-Export")
                            .accessibilityIdentifier("stemExportProgress")
                        HStack {
                            Text("\(Int(stemExport.progress * 100)) %")
                                .monospacedDigit()
                            Spacer()
                            Button("Abbrechen") { stemExport.cancel() }
                                .accessibilityIdentifier("cancelStemExport")
                        }
                    } else {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("Stereo-Mix wird exportiert …")
                        }
                    }
                } else if let message = stemExport.message ?? exportStatusMessage {
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let folder = stemExport.completedFolder {
                            Button("Ordner zeigen") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        }
                        Spacer()
                        Button("Schließen") {
                            stemExport.clear()
                            exportStatusMessage = nil
                            showExportDialog = false
                            exportModule = nil
                        }
                    }
                } else {
                    Picker("Ausgabe", selection: $exportChannelStems) {
                        Text("Stereo-Mix").tag(false)
                        Text("Kanalspuren").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("wavExportKind")

                    Text(exportChannelStems
                        ? "Eine Stereo-Float32-WAV je logischem Kanal, dazu Referenzmix und Begleitdatei. Alle Dateien beginnen gemeinsam und verwenden denselben Pegelfaktor."
                        : "Exportiert den gesamten Titel offline in eine Stereo-WAV-Datei.")
                        .fixedSize(horizontal: false, vertical: true)

                    if exportChannelStems {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Neuer Ordnername")
                            TextField("Kanalspuren", text: $exportFolderName)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Neuer Ordnername")
                                .accessibilityIdentifier("stemExportFolderName")
                        }
                        Text("Übernimmt Mute/Solo, Clock, Interpolation und Separation. Limiter, Mixerlautstärke und externer LED-Ausgabefilter sind nicht enthalten.")
                            .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Picker("Dauer begrenzen:", selection: $exportSecondsLimit) {
                        Text("1 Minute").tag(60.0)
                        Text("3 Minuten").tag(180.0)
                        Text("5 Minuten").tag(300.0)
                        Text("10 Minuten").tag(600.0)
                    }
                    HStack(spacing: 12) {
                        Button("Abbrechen") { showExportDialog = false; exportModule = nil }
                        Spacer()
                        Button("Ziel wählen …") {
                            showExportDialog = false
                            if exportChannelStems { runChannelStemExport() } else { runWavExport() }
                        }
                        .disabled(exportChannelStems && !validStemFolderName)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("startWavExport")
                    }
                }
            }.scaledFont(11)
            .foregroundColor(theme == .workbench ? .lightTextPrimary : .spaceTextPrimary)
            .preferredColorScheme(theme == .workbench ? .light : .dark)
            .padding(20)
            .frame(width: 420)
            .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceSurface)
            .cornerRadius(theme == .workbench ? 0 : 10)
            .overlay(RoundedRectangle(cornerRadius: theme == .workbench ? 0 : 10)
                .stroke(theme == .workbench ? Color.lightTextPrimary : Color.spaceAccent.opacity(0.3), lineWidth: 1))
        }
    }

}

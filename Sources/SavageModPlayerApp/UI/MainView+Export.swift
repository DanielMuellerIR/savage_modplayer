import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// WAV-/Sample-Export der MainView: Export-Logik und der Exporter-Dialog.
extension MainView {
    // MARK: - WAV Export helper
    func runWavExport() {
        guard let mod = coordinator.activeMod else { return }
        let sep = coordinator.stereoSeparation
        let interp = coordinator.useInterpolation
        let pal = coordinator.palClock
        let limit = exportSecondsLimit
        let playerCoordinator = coordinator
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.wav]
        savePanel.nameFieldStringValue = coordinator.trackName.replacingOccurrences(of: " ", with: "_") + ".wav"
        savePanel.title = "Song als WAV exportieren..."
        
        savePanel.begin { response in
            if response == .OK, let destURL = savePanel.url {
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
            }
        }
    }
    
    func runInstrumentSampleExport(index: Int) {
        guard let mod = coordinator.activeMod, index < mod.instruments.count, let inst = mod.instruments[index] else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.wav]
        let name = inst.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "sample_\(index)" : inst.name
        savePanel.nameFieldStringValue = name.replacingOccurrences(of: " ", with: "_") + ".wav"
        savePanel.title = "Instrumenten-Sample als WAV sichern..."
        
        savePanel.begin { response in
            if response == .OK, let destURL = savePanel.url {
                do {
                    try coordinator.exportInstrumentToWav(index: index, destinationURL: destURL)
                    self.errorMessage = "Sample \(index) exportiert!"
                } catch {
                    self.errorMessage = "Fehler: \(error.localizedDescription)"
                }
            }
        }
    }

    // WAV offline exporter dialog
    var wavExporterDialog: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                Text("OFFLINE-WAV-EXPORT")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.accent(theme))
                
                Text("Exportiert den gesamten Track offline in eine WAV Datei.")
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.spaceTextSecondary)
                
                Picker("Dauer begrenzen:", selection: $exportSecondsLimit) {
                    Text("1 Minute").tag(60.0)
                    Text("3 Minuten").tag(180.0)
                    Text("5 Minuten").tag(300.0)
                    Text("10 Minuten").tag(600.0)
                }
                .pickerStyle(DefaultPickerStyle())
                .font(.system(size: 10))
                
                HStack(spacing: 12) {
                    Button("ABBRECHEN") {
                        showExportDialog = false
                    }
                    .font(.system(size: 10))
                    
                    Button("STARTEN") {
                        showExportDialog = false
                        runWavExport()
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                }
            }
            .padding(20)
            .background(Color.spaceSurface)
            .cornerRadius(10)
            .frame(width: 320)
        }
    }

}

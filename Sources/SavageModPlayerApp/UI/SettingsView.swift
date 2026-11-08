import SwiftUI
#if os(macOS)
import AppKit

// Einstellungs-Fenster (macOS-Standard: App-Menue > Einstellungen, Cmd+,).
struct SettingsView: View {
    @ObservedObject var updates: UpdateController
    // Gleicher Schluessel wie in MainView.loadLocalAudioFolder — @AppStorage
    // haelt beide Stellen automatisch synchron.
    @AppStorage("savage.autoplayFolder") private var autoplayFolderPath: String = ""

    // Bildrate der Visualisierungen im Vollmodus. Gleicher Schluessel wie in
    // MainView, das den Wert an den Coordinator weiterreicht.
    @AppStorage("savage.visualizerHz") private var visualizerHz: Double = 60

    private static let frameRates: [Double] = [60, 30, 24, 15, 10]

    var body: some View {
        Form {
            Section {
                LabeledContent("Autoplay-Ordner:") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(autoplayFolderPath.isEmpty ? "Nicht gesetzt" : autoplayFolderPath)
                            .font(.system(size: 11))
                            .foregroundColor(autoplayFolderPath.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button("Auswählen…") { chooseFolder() }
                            if !autoplayFolderPath.isEmpty {
                                Button("Entfernen") { autoplayFolderPath = "" }
                            }
                        }
                    }
                }
                Text("Aus diesem Ordner (inklusive Unterordnern und Zip-/7z-Archiven) füllt der Player beim Start die Playlist und beginnt zu spielen. Änderungen wirken ab dem nächsten Start.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section {
                Picker("Bildrate der Visualisierungen:", selection: $visualizerHz) {
                    ForEach(Self.frameRates, id: \.self) { rate in
                        Text(rate == 60 ? "60 Bilder/s (Standard)" : rate == 15 ? "15 Bilder/s (Sparmodus)" : "\(Int(rate)) Bilder/s").tag(rate)
                    }
                }
                Text("60 Bilder pro Sekunde sorgen für flüssige Pegel und Oszilloskope; der Sparmodus verwendet 15 Bilder pro Sekunde. Die Änderung wirkt sofort. Verkleinere das Fenster, um die Visualizer ganz auszublenden: Erfassung und Zeichnen entfallen dann vollständig. Nur Transport und Spielzeit werden weiter aktualisiert. Der Klang bleibt unverändert.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section("Updates") {
                Toggle("Automatisch nach Updates suchen", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticChecks($0) }
                ))
                .disabled(!updates.isAvailable)
                Button("Nach Updates suchen…", action: updates.checkForUpdates)
                    .disabled(!updates.canCheckForUpdates)
                Text("Neue Versionen werden nur nach Bestätigung installiert. Es werden keine Systemprofildaten übertragen.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        // Beim vorhandenen Pfad starten, sonst im Home-Verzeichnis.
        if !autoplayFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (autoplayFolderPath as NSString).expandingTildeInPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            autoplayFolderPath = url.path
        }
    }
}
#endif

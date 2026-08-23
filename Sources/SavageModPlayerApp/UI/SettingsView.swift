import SwiftUI
#if os(macOS)
import AppKit

// Einstellungs-Fenster (macOS-Standard: App-Menue > Einstellungen, Cmd+,).
// Aktuell eine Einstellung: der Autoplay-Ordner, aus dem die Playlist beim
// App-Start befuellt wird. Leer = nur die audio/-Fallback-Ordner neben
// Arbeitsverzeichnis bzw. App werden probiert (Verhalten ohne Konfiguration).
struct SettingsView: View {
    // Gleicher Schluessel wie in MainView.loadLocalAudioFolder — @AppStorage
    // haelt beide Stellen automatisch synchron.
    @AppStorage("savage.autoplayFolder") private var autoplayFolderPath: String = ""

    // Bildrate der Visualisierungen im Vollmodus. Gleicher Schluessel wie in
    // MainView, das den Wert an den Coordinator weiterreicht.
    @AppStorage("savage.visualizerHz") private var visualizerHz: Double = 30

    // Die angebotenen Stufen. 30 ist die Vorgabe (volle Optik), 10 der
    // sparsamste sinnvolle Wert — darunter ruckeln die Oszilloskope sichtbar.
    private static let frameRates: [Double] = [30, 24, 15, 10]

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
                        Text(rate == 30 ? "30 Hz (Standard)" : "\(Int(rate)) Hz").tag(rate)
                    }
                }
                Text("Wie oft Pegel, Oszilloskope und Spielzeit neu gezeichnet werden. Nicht der Klang hängt daran, sondern die Rechenlast der Oberfläche: Auf einem Mac mit M5-Chip kostete dieselbe Wiedergabe bei 30 Hz rund 22 % eines Kerns, bei 15 Hz rund 18 % und bei 10 Hz rund 14 %. Die Änderung wirkt sofort. Im kompakten Fenster bleibt es unabhängig davon bei 5 Hz, weil dort keine Oszilloskope zu sehen sind.")
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

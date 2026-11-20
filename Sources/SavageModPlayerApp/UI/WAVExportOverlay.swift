import SwiftUI

struct WAVExportOverlay: View {
    @ObservedObject var model: WAVExportModel
    let theme: PlayerTheme
    let chooseDestination: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading, spacing: 16) {
                Text("OFFLINE-WAV-EXPORT")
                    .scaledFont(12, weight: .bold)
                    .foregroundColor(Color.accent(theme))
                Text(model.exportTitle)
                    .lineLimit(2)
                    .accessibilityIdentifier("wavExportSong")
                if model.isExporting || model.stemExport.isRunning {
                    if model.stemExport.isRunning {
                        Text(model.stemExport.progress < 0.5 ? "Pegel der Kanalspuren analysieren …" : "Kanalspuren und Referenzmix schreiben …")
                        ProgressView(value: model.stemExport.progress)
                            .accessibilityLabel("Kanalspuren-Export")
                            .accessibilityIdentifier("stemExportProgress")
                        HStack {
                            Text("\(Int(model.stemExport.progress * 100)) %")
                                .monospacedDigit()
                            Spacer()
                            Button("Abbrechen") { model.stemExport.cancel() }
                                .accessibilityIdentifier("cancelStemExport")
                        }
                    } else {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("Stereo-Mix wird exportiert …")
                        }
                    }
                } else if let message = model.stemExport.message ?? model.exportStatusMessage {
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let folder = model.stemExport.completedFolder {
                            Button("Ordner zeigen") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        }
                        Spacer()
                        Button("Schließen") {
                            model.closeOverlay()
                        }
                    }
                } else {
                    Picker("Ausgabe", selection: $model.exportChannelStems) {
                        Text("Stereo-Mix").tag(false)
                        Text("Kanalspuren").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("wavExportKind")

                    Text(model.exportChannelStems
                        ? "Eine Stereo-Float32-WAV je logischem Kanal, dazu Referenzmix und Begleitdatei. Alle Dateien beginnen gemeinsam und verwenden denselben Pegelfaktor."
                        : "Exportiert den gesamten Titel offline in eine Stereo-WAV-Datei.")
                        .fixedSize(horizontal: false, vertical: true)

                    if model.exportChannelStems {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Neuer Ordnername")
                            TextField("Kanalspuren", text: $model.exportFolderName)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Neuer Ordnername")
                                .accessibilityIdentifier("stemExportFolderName")
                        }
                        Text("Übernimmt Mute/Solo, Clock, Interpolation und Separation. Limiter, Mixerlautstärke und externer LED-Ausgabefilter sind nicht enthalten.")
                            .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Picker("Dauer begrenzen:", selection: $model.exportSecondsLimit) {
                        Text("1 Minute").tag(60.0)
                        Text("3 Minuten").tag(180.0)
                        Text("5 Minuten").tag(300.0)
                        Text("10 Minuten").tag(600.0)
                    }
                    HStack(spacing: 12) {
                        Button("Abbrechen", action: model.closeOverlay)
                        Spacer()
                        Button("Ziel wählen …") {
                            chooseDestination()
                        }
                        .disabled(model.exportChannelStems && !model.validStemFolderName)
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

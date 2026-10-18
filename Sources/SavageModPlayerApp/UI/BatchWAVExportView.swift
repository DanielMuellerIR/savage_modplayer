import SwiftUI
import SavageModPlayerCore

struct BatchWAVExportRequest: Identifiable {
    let id = UUID()
    let items: [BatchWAVExportItem]
}

struct BatchWAVExportView: View {
    let request: BatchWAVExportRequest
    @Environment(\.dismiss) private var dismiss
    @AppStorage("savage.batchWAVSettings") private var savedSettings = ""
    @State private var settings: BatchWAVExportSettings
    @State private var selected: Set<UUID>
    @StateObject private var model = BatchWAVExportModel()

    init(request: BatchWAVExportRequest) {
        self.request = request
        _selected = State(initialValue: Set(request.items.map(\.id)))
        let stored = UserDefaults.standard.string(forKey: "savage.batchWAVSettings") ?? ""
        let decoded = stored.utf8.count <= 4096
            ? try? JSONDecoder().decode(BatchWAVExportSettings.self, from: Data(stored.utf8)) : nil
        var settings = decoded ?? .init()
        if ![60.0, 180, 300, 600].contains(settings.audio.maximumSeconds) { settings.audio.maximumSeconds = 300 }
        if !settings.audio.stereoSeparation.isFinite || !(0...1).contains(settings.audio.stereoSeparation) {
            settings.audio.stereoSeparation = 0.8
        }
        settings.audio.sampleRate = 44_100
        settings.audio.mutedChannels = nil
        settings.audio.soloChannels = []
        _settings = State(initialValue: settings)
    }

    private var editable: Bool { !model.isRunning }
    private var chosenItems: [BatchWAVExportItem] { request.items.filter { selected.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Stapel-Export").font(.title2.bold())
                    Text("Die Titelliste ist beim Öffnen festgehalten. Jeder Titel beginnt am Songanfang; die normale Wiedergabe kann weiterlaufen.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("\(selected.count) von \(request.items.count) Titeln ausgewählt")
                        Spacer()
                        Button("Alle") { selected = Set(request.items.map(\.id)) }.disabled(!editable)
                        Button("Keine") { selected.removeAll() }.disabled(!editable)
                    }
                    List(request.items) { item in
                        Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: {
                            if $0 { selected.insert(item.id) } else { selected.remove(item.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayName).lineLimit(1).truncationMode(.middle)
                                Text(item.sourceDescription).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }.toggleStyle(.checkbox).disabled(!editable)
                            .accessibilityIdentifier("batchExportItem-\(item.id.uuidString)")
                            .accessibilityLabel(item.displayName)
                            .accessibilityHint(item.sourceDescription)
                    }.frame(minHeight: 100, idealHeight: 160, maxHeight: 180)
                        .accessibilityIdentifier("batchExportTitles")
                    Form {
                        Picker("Ausgabe", selection: $settings.output) {
                            Text("Stereo-Mix").tag(ChannelStemRenderer.Output.stereoMix)
                            Text("Kanalspuren und Referenzmix").tag(ChannelStemRenderer.Output.channelStems)
                        }.accessibilityIdentifier("batchExportOutput")
                        Picker("Vorhandene Ziele", selection: $settings.conflictPolicy) {
                            Text("Überspringen").tag(BatchWAVExportSettings.ConflictPolicy.skipExisting)
                            Text("Beide behalten (neuer Name)").tag(BatchWAVExportSettings.ConflictPolicy.keepBoth)
                        }.accessibilityIdentifier("batchExportConflict")
                        Picker("Dauer je Titel", selection: $settings.audio.maximumSeconds) {
                            Text("1 Minute").tag(60.0)
                            Text("3 Minuten").tag(180.0)
                            Text("5 Minuten").tag(300.0)
                            Text("10 Minuten").tag(600.0)
                        }.accessibilityIdentifier("batchExportDuration")
                        Picker("MOD-Clock", selection: $settings.audio.palClock) {
                            Text("PAL").tag(true)
                            Text("NTSC").tag(false)
                        }
                        Toggle("Sample-Interpolation", isOn: $settings.audio.useInterpolation)
                        HStack {
                            Text("Separation: \(Int(settings.audio.stereoSeparation * 100)) %").frame(width: 140, alignment: .leading)
                            Slider(value: $settings.audio.stereoSeparation, in: 0...1).accessibilityLabel("Export-Separation")
                        }
                    }.disabled(!editable)
                    Text("Stereo-Float32 mit 44.100 Hz. Kanalspuren verwenden einen gemeinsamen Pegelfaktor je Titel. Mute/Solo aus dem Player, Mixerlautstärke und externer LED-Ausgabefilter werden nicht übernommen.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.isRunning {
                let progress = model.progress
                VStack(alignment: .leading, spacing: 6) {
                    Text("Titel \((progress?.itemIndex ?? 0) + 1) von \(progress?.itemCount ?? chosenItems.count): \(progress?.sourceName ?? "Vorbereitung …")")
                        .lineLimit(2)
                    ProgressView(value: progress?.fraction ?? 0).accessibilityIdentifier("batchExportProgress")
                    Text("\(Int((progress?.fraction ?? 0) * 100)) % insgesamt · \(Int((progress?.itemProgress ?? 0) * 100)) % im Titel")
                        .font(.caption).monospacedDigit()
                }
            }
            if let report = model.report { resultView(report) }
            if let error = model.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(model.isRunning ? "Abbrechen" : "Schließen") {
                    if model.isRunning { model.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).accessibilityIdentifier("batchExportClose")
                Spacer()
                Button("Ziel wählen …") { chooseDestination() }
                    .disabled(!editable || selected.isEmpty || selected.count > BatchWAVExporter.maximumItems)
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("batchExportStart")
            }
        }.padding(20).frame(minWidth: 560, idealWidth: 600, maxWidth: 720, minHeight: 480, idealHeight: 600, maxHeight: 640)
            .interactiveDismissDisabled(model.isRunning)
            .onDisappear { model.cancel() }
    }

    private func resultView(_ report: BatchWAVExportReport) -> some View {
        let exported = report.results.filter { $0.status == .exported }.count
        let skipped = report.results.filter { $0.status == .skipped }.count
        let failed = report.results.filter { $0.status == .failed }.count
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(report.wasCancelled ? "Abgebrochen" : "Stapel beendet"): \(exported) exportiert, \(skipped) übersprungen, \(failed) fehlgeschlagen.")
                .fontWeight(.semibold).accessibilityIdentifier("batchExportSummary")
            Text("Fertige Ausgaben bleiben erhalten. \(report.reportWriteError ?? "Details und Einstellungen stehen im Stapelbericht.")")
                .font(.caption).foregroundStyle(report.reportWriteError == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            if let destination = model.destination {
                Text(destination.path).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(report.results.indices, id: \.self) { index in
                        let result = report.results[index]
                        Text("\(result.sourceName): \(statusText(result.status))\(result.detail.map { " – " + $0 } ?? "")")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 100)
        }
    }

    private func statusText(_ status: BatchWAVExportResult.Status) -> String {
        switch status {
        case .exported: "exportiert"
        case .skipped: "übersprungen"
        case .failed: "fehlgeschlagen"
        case .cancelled: "abgebrochen"
        case .notStarted: "nicht begonnen"
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Stapel-Export: Zielordner"
        panel.prompt = "Hier exportieren"
        panel.message = "Jeder Titel erhält einen eigenen Ordner. Vorhandene Ausgaben werden niemals überschrieben."
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            if let data = try? JSONEncoder().encode(settings), let value = String(data: data, encoding: .utf8) { savedSettings = value }
            model.start(items: chosenItems, destination: destination, settings: settings)
        }
    }
}

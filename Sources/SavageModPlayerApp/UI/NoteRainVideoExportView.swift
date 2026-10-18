import SwiftUI
import AVKit
import SavageModPlayerCore

struct NoteRainVideoExportView: View {
    let request: NoteRainVideoExportRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiFontScale) private var fontScale
    @StateObject private var model: NoteRainVideoExportModel
    @State private var resolution = 1280
    @State private var framesPerSecond = 30
    @State private var quality = NoteRainVideoQuality.high
    @State private var appearance: NoteRainVideoAppearance
    @State private var lookahead = 4
    @State private var maximumSeconds = 600.0

    init(request: NoteRainVideoExportRequest, model: NoteRainVideoExportModel = .init()) {
        self.request = request
        _model = StateObject(wrappedValue: model)
        _appearance = State(initialValue: request.appearance)
    }

    private var options: NoteRainVideoOptions {
        var audio = request.audio
        audio.sampleRate = Double(NoteRainVideoOptions.sampleRate)
        audio.maximumSeconds = maximumSeconds
        return .init(width: resolution, height: resolution * 9 / 16,
                     framesPerSecond: framesPerSecond, lookaheadSeconds: lookahead,
                     appearance: appearance, quality: quality, audio: audio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Notenregen als Video").scaledFont(20, weight: .bold)
                    Text(request.title).fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityIdentifier("videoExportTitle")
                    Text("Titel und Klang sind beim Öffnen festgehalten. Der Export beginnt am Songanfang; die normale Wiedergabe kann weiterlaufen.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    preview
                    Form {
                        Picker("Auflösung", selection: $resolution) {
                            Text("640 × 360 · klein").tag(640)
                            Text("1280 × 720 · HD").tag(1280)
                            Text("1920 × 1080 · Full HD").tag(1920)
                        }.accessibilityIdentifier("videoResolution")
                        Picker("Bildrate", selection: $framesPerSecond) {
                            ForEach([24, 25, 30, 60], id: \.self) { rate in Text("\(rate) Bilder/s").tag(rate) }
                        }.accessibilityIdentifier("videoFrameRate")
                        Picker("Bildqualität", selection: $quality) {
                            Text("Hoch · größere Datei").tag(NoteRainVideoQuality.high)
                            Text("Kompakt · kleinere Datei").tag(NoteRainVideoQuality.compact)
                        }.accessibilityIdentifier("videoQuality")
                        Picker("Darstellung", selection: $appearance) {
                            Text("Dunkel").tag(NoteRainVideoAppearance.dark)
                            Text("Hell").tag(NoteRainVideoAppearance.light)
                        }.accessibilityIdentifier("videoAppearance")
                        Picker("Vorlauf", selection: $lookahead) {
                            ForEach([2, 4, 8], id: \.self) { seconds in Text("\(seconds) Sekunden").tag(seconds) }
                        }.accessibilityIdentifier("videoLookahead")
                        Picker("Dauer begrenzen", selection: $maximumSeconds) {
                            Text("1 Minute").tag(60.0)
                            Text("3 Minuten").tag(180.0)
                            Text("5 Minuten").tag(300.0)
                            Text("10 Minuten").tag(600.0)
                            Text("30 Minuten").tag(1800.0)
                            Text("60 Minuten").tag(3600.0)
                        }.accessibilityIdentifier("videoDuration")
                    }.disabled(model.isBusy)
                    Text("MOV mit H.264-Bild und verlustfreiem Float32-Stereo bei 48 kHz. Mute/Solo, Clock, Interpolation und Separation werden übernommen. Mixerlautstärke, externer LED-Filter und manuelle Tempoänderungen bleiben außerhalb des Exports.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(capturedSound).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("videoExportSound")
                    if model.isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.isCancelling ? "Abbruch wird abgeschlossen …" : "Audio und Notenregen werden gerendert …")
                            ProgressView(value: model.progress)
                                .accessibilityLabel("Videoexport").accessibilityIdentifier("videoExportProgress")
                            Text("\(Int(model.progress * 100)) % der Dauergrenze")
                                .monospacedDigit().foregroundStyle(.secondary)
                            Text("Am natürlichen Songende wird früher abgeschlossen.").foregroundStyle(.secondary)
                        }.accessibilityIdentifier("videoExportRunning")
                    }
                    if let message = model.message {
                        Text(message).foregroundStyle(model.report == nil ? Color.primary : Color.green)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            .accessibilityIdentifier("videoExportResult")
                    }
                    if let destination = model.destination {
                        Text(destination.path).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle)
                            .textSelection(.enabled).accessibilityIdentifier("videoExportDestination")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("videoExportScroll")
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { closeButton; Spacer(); resultButton; actionButton }
                VStack(alignment: .trailing, spacing: 10) {
                    actionButton
                    HStack { closeButton; Spacer(); resultButton }
                }
            }
        }
        .scaledFont(13)
        .padding(20)
        .frame(width: 640, height: 720)
        .interactiveDismissDisabled(model.isRunning || model.isChoosingDestination)
        .onChange(of: options) { _ in model.invalidatePreview() }
        .onDisappear { model.close() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.close() }
    }

    private var capturedSound: String {
        let muted = request.audio.mutedChannels?.count ?? 0
        let solo = request.audio.soloChannels.count
        let usesClock = [ModuleFormat.protracker, .soundtracker, .multichannel].contains(request.mod.format)
        let clock = usesClock ? (request.audio.palClock ? "PAL · " : "NTSC · ") : ""
        return clock + "Interpolation \(request.audio.useInterpolation ? "an" : "aus") · Separation \(Int(request.audio.stereoSeparation * 100)) % · \(muted) stumm · \(solo) solo"
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let player = model.previewPlayer {
                    VideoPlayer(player: player)
                        .accessibilityLabel("Notenregen-Vorschau, bis zu fünf Sekunden")
                        .accessibilityIdentifier("videoPreviewPlayer")
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                    VStack(spacing: 10) {
                        if model.isPreviewing { ProgressView() }
                        Image(systemName: "film").font(.system(size: 26 * fontScale))
                        Text(model.isPreviewing ? "Vorschau wird gerendert …" : "Vorschau ab Songanfang")
                            .multilineTextAlignment(.center)
                    }.padding()
                }
            }.aspectRatio(16.0 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button(model.isPreviewing ? "Vorschau abbrechen" : "Vorschau erstellen") {
                    if model.isPreviewing { model.cancel() }
                    else { model.preview(request: request, options: options) }
                }.disabled(model.isRunning || model.isChoosingDestination)
                    .buttonStyle(NoteRainVideoButtonStyle())
                    .accessibilityIdentifier("videoPreview")
                Spacer()
                Text("Bis zu 5 Sekunden").foregroundStyle(.secondary)
            }
            if let message = model.previewMessage {
                Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("videoPreviewStatus")
            }
        }
    }

    private var closeButton: some View {
        Button("Schließen") { model.close(); dismiss() }
            .disabled(model.isRunning || model.isChoosingDestination)
            .buttonStyle(NoteRainVideoButtonStyle())
            .keyboardShortcut(.cancelAction).accessibilityIdentifier("videoExportClose")
    }
    @ViewBuilder private var resultButton: some View {
        if let destination = model.destination {
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
                .buttonStyle(NoteRainVideoButtonStyle())
                .accessibilityIdentifier("videoExportReveal")
        }
    }
    private var actionButton: some View {
        Button(model.isRunning ? "Export abbrechen" : "Ziel wählen und exportieren …") {
            if model.isRunning { model.cancel() }
            else { model.chooseDestination(request: request, options: options) }
        }.disabled(model.isPreviewing || model.isChoosingDestination || model.isCancelling)
            .buttonStyle(NoteRainVideoButtonStyle(isPrimary: true))
            .keyboardShortcut(.defaultAction).accessibilityIdentifier("videoExportStart")
    }
}

private struct NoteRainVideoButtonStyle: ButtonStyle {
    var isPrimary = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        // Der native Bezel wächst nicht mit der vergrößerten UI-Schrift.
        configuration.label.fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(minHeight: 28)
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .background(isPrimary ? Color.accentColor : Color(nsColor: .controlColor),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isPrimary ? Color.accentColor : Color(nsColor: .separatorColor)))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
    }
}

import SwiftUI
import SavageModPlayerCore

struct NoteRainView: View {
    @ObservedObject var coordinator: ModPlayerCoordinator
    @ObservedObject var playbackActions: PlaybackActions
    @ObservedObject var model: NoteRainModel
    @ObservedObject var windowState: NoteRainWindowState
    @AppStorage("savage.theme") private var theme: PlayerTheme = .cyber
    @AppStorage("savage.noteRainHorizon") private var horizon: Double = 4
    @AppStorage("savage.noteRainZoomToSong") private var zoomToSong = false
    @AppStorage("savage.loopMode") private var loopMode: LoopMode = .playlist
    @State private var songKeyRange: ClosedRange<Int>?
    @State private var mutedChannels: Set<Int> = []
    @State private var canvasSize = CGSize.zero

    private static let pianoKeyRange = 9...96

    private var primary: Color { theme == .workbench ? .lightTextPrimary : .spaceTextPrimary }
    private var secondary: Color { theme == .workbench ? .lightTextSecondary : .spaceTextSecondary }
    private var background: Color { theme == .workbench ? .lightSurface : .spaceBackground }
    private var lookahead: Double { [2, 4, 8].contains(horizon) ? horizon : 4 }
    private var fullKeyRange: ClosedRange<Int> {
        guard let songKeyRange else { return Self.pianoKeyRange }
        let low = min(Self.pianoKeyRange.lowerBound, songKeyRange.lowerBound)
        let high = max(Self.pianoKeyRange.upperBound, songKeyRange.upperBound)
        return (NoteRainLayout.isBlack(low) ? low - 1 : low)...(NoteRainLayout.isBlack(high) ? high + 1 : high)
    }
    private var keyRange: ClosedRange<Int> {
        guard zoomToSong, let songKeyRange else { return fullKeyRange }
        var low = max(fullKeyRange.lowerBound, songKeyRange.lowerBound / 12 * 12)
        var high = min(fullKeyRange.upperBound, max(low + 23, (songKeyRange.upperBound / 12 + 1) * 12 - 1))
        low = max(fullKeyRange.lowerBound, min(low, high - 23))
        if NoteRainLayout.isBlack(low) { low -= 1 }
        if NoteRainLayout.isBlack(high) { high += 1 }
        return low...high
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    heading.frame(minWidth: 210, alignment: .leading)
                    Spacer(minLength: 12)
                    controls
                }
                VStack(alignment: .leading, spacing: 12) {
                    heading
                    controls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            Divider()
            ZStack {
                NoteRainCanvas(notes: displayedNotes,
                    time: model.time, horizon: lookahead, keyRange: keyRange, theme: theme,
                    fixedKeyWidth: zoomToSong ? windowState.keyWidth : nil,
                    onSizeChange: { size in canvasSize = size; configureWindow() })
                if coordinator.activeMod == nil {
                    message("Keine Musik geladen", detail: "Öffne ein MOD-, S3M-, XM- oder IT-Modul im Player.")
                } else if !coordinator.isPlaying {
                    message("Bereit für den nächsten Anschlag", detail: "Starte die Wiedergabe. Die kommenden Noten fallen zur Klaviatur.")
                } else if model.hasOverflowed {
                    message("Vorschau neu starten", detail: "Starte die Wiedergabe erneut, um die Notenvorschau zu synchronisieren.")
                } else if model.isPreparing && model.notes.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Notenvorschau wird berechnet …").foregroundStyle(secondary)
                    }.padding(22).background(background.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(coordinator.activeMod?.displayChannelIndices ?? [], id: \.self) { channel in
                                HStack(spacing: 5) {
                                    Circle().fill(NoteRainPalette.color(channel)).frame(width: 8, height: 8)
                                    Text("K\(channel + 1)").font(.system(size: 11, weight: .medium, design: .monospaced))
                                }.opacity(mutedChannels.contains(channel) ? 0.3 : 1)
                            }
                        }.padding(.vertical, 2)
                    }.scrollIndicators(.hidden)
                    Text("\(PreviewNote.name(for: keyRange.lowerBound))–\(PreviewNote.name(for: keyRange.upperBound)) · \(keyRange.count) Tasten")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(secondary).fixedSize()
                }
                HStack(spacing: 12) {
                    Text(status).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("Balken: Stimmenlaufzeit · Farbe: Kanal")
                        .font(.system(size: 11)).foregroundStyle(secondary).lineLimit(1)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .foregroundStyle(primary)
        .background(background)
        .frame(minWidth: zoomToSong ? NoteRainWindowState.minimumFocusedWidth : NoteRainWindowState.minimumKeyboardWidth,
            minHeight: NoteRainWindowState.minimumHeight)
        .background(NoteRainWindowAccess { windowState.attach($0) })
        .preferredColorScheme(theme == .workbench ? .light : .dark)
        .onAppear {
            updateMuteState()
            horizon = lookahead
            model.horizon = lookahead
            model.start(coordinator: coordinator)
        }
        .onDisappear { model.stop() }
        .onChange(of: zoomToSong) { _ in configureWindow() }
        .onChange(of: keyRange) { _ in configureWindow() }
        .onChange(of: fullKeyRange) { _ in configureWindow() }
        .onChange(of: horizon) { _ in model.horizon = lookahead }
        // setMod setzt activeMod vor trackName; dessen Publisher meldet auch
        // gleichnamige neue Module, wenn die Wiedergabe noch gestoppt ist.
        .onReceive(coordinator.$trackName) { _ in updateRange(for: coordinator.activeMod) }
        .onChange(of: coordinator.notePreviewSource?.id) { _ in updateMuteState() }
        .onReceive(coordinator.visualizerState.objectWillChange) { updateMuteState() }
        .onReceive(model.$notes) { notes in
            guard let low = notes.map(\.key).min(), let high = notes.map(\.key).max() else { return }
            let lower = min(songKeyRange?.lowerBound ?? low, max(0, low))
            let upper = max(songKeyRange?.upperBound ?? high, min(119, high))
            if songKeyRange != lower...upper {
                songKeyRange = lower...upper
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOTENREGEN").font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(secondary)
            Text(coordinator.trackName).font(.system(size: 18, weight: .semibold))
                .lineLimit(1).help(coordinator.trackName)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Tonbereich", selection: $zoomToSong) {
                Text("Klaviatur").tag(false)
                Text("Tonumfang").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 172)
            .help("Tonumfang verkleinert das Fenster bei gleicher Tastenbreite. Klaviatur stellt die vorherige Fensterbreite wieder her.")
            Picker("Vorlauf", selection: $horizon) {
                Text("2 s").tag(2.0)
                Text("4 s").tag(4.0)
                Text("8 s").tag(8.0)
            }.fixedSize().help("So viele Sekunden der kommenden Noten sind sichtbar.")
            Button(action: togglePlayback) {
                Image(systemName: coordinator.isPlaying && !coordinator.isPaused ? "pause.fill" : "play.fill")
                    .frame(width: 18, height: 18)
            }
            .help(coordinator.isPlaying && !coordinator.isPaused ? "Pause" : "Abspielen")
            .accessibilityLabel(coordinator.isPlaying && !coordinator.isPaused ? "Pause" : "Abspielen")
            .disabled(coordinator.activeMod == nil)
            Button(action: stopPlayback) {
                Image(systemName: "stop.fill").frame(width: 18, height: 18)
            }.help("Stopp").accessibilityLabel("Stopp").disabled(!coordinator.isPlaying)
        }.controlSize(.small).fixedSize(horizontal: true, vertical: false)
    }

    private func configureWindow() {
        windowState.configure(zoomed: zoomToSong, fullKeyRange: fullKeyRange,
            keyRange: keyRange, canvasSize: canvasSize)
    }

    private var status: String {
        if coordinator.activeMod == nil { return "Kein Modul" }
        if !coordinator.isPlaying { return "Gestoppt" }
        if coordinator.isPaused { return "Pausiert" }
        return model.isPreparing ? "Vorschau wird ergänzt …" : "Spielt"
    }

    private var displayedNotes: [PreviewNote] {
        let end = loopMode == .track ? nil : model.nextSongEnd
        return model.notes.compactMap { original in
            guard !mutedChannels.contains(original.channel), end == nil || original.start < end! else { return nil }
            var note = original
            if let end, note.end > end { note.end = end; note.isOpen = false }
            return note
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(secondary).multilineTextAlignment(.center)
        }.padding(24).background(background.opacity(0.96), in: RoundedRectangle(cornerRadius: 10)).padding(24)
    }

    private func togglePlayback() {
        playbackActions.togglePlayback(coordinator: coordinator)
    }

    private func stopPlayback() {
        playbackActions.stopPlayback(coordinator: coordinator)
    }

    private func updateMuteState() {
        let channels = Array(0..<coordinator.channelCount)
        let hasSolo = channels.contains { coordinator.isSoloed(channelIndex: $0) }
        let next = Set(channels.filter {
            coordinator.isMuted(channelIndex: $0) || (hasSolo && !coordinator.isSoloed(channelIndex: $0))
        })
        if mutedChannels != next { mutedChannels = next }
    }

    private func updateRange(for mod: Mod?) {
        guard let mod else { songKeyRange = nil; return }
        var lowest: Int?
        var highest: Int?
        func include(_ key: Int) {
            guard (0..<120).contains(key) else { return }
            lowest = min(lowest ?? key, key)
            highest = max(highest ?? key, key)
        }
        for index in Set(mod.patternTable) where mod.patterns.indices.contains(index) {
            let pattern = mod.patterns[index]
            for row in pattern.rows {
                for note in row.notes {
                    let key = note.period > 0 ? Int((36 + 12 * log2(428.0 / Double(note.period))).rounded()) : note.key
                    if (0..<120).contains(key) {
                        include(key)
                        if mod.format == .it, mod.instruments.indices.contains(note.instrument),
                           let mapping = mod.instruments[note.instrument]?.noteSampleMapping,
                           let entry = mapping.entry(forSourceNote: key), entry.sampleID > 0 {
                            include(entry.targetNote)
                        }
                    }
                }
            }
        }
        if let lowest, let highest { songKeyRange = lowest...highest }
        else { songKeyRange = nil }
    }
}

enum NoteRainPalette {
    static func color(_ channel: Int) -> Color {
        // Versetzte Farben bleiben auch bei benachbarten Kanaelen unterscheidbar.
        Color(hue: (Double(channel) * 0.381966 + 0.54).truncatingRemainder(dividingBy: 1), saturation: 0.58, brightness: 0.88)
    }
}

struct NoteRainCanvas: View {
    let notes: [PreviewNote]
    let time: Double
    let horizon: Double
    let keyRange: ClosedRange<Int>
    let theme: PlayerTheme
    var fixedKeyWidth: CGFloat? = nil
    var onSizeChange: (CGSize) -> Void = { _ in }
    @State private var hoverPoint: CGPoint?

    var body: some View {
        GeometryReader { proxy in
        Canvas { context, size in
            let layout = NoteRainLayout(size: size, keyRange: keyRange, horizon: horizon, fixedKeyWidth: fixedKeyWidth)
            let left = layout.left
            let right = layout.right
            let width = layout.keyWidth
            let keyboardHeight = layout.keyboardHeight
            let strike = layout.strike
            let top = layout.top
            let scale = layout.scale
            let textColor: Color = theme == .workbench ? .lightTextSecondary : .spaceTextSecondary
            let gridColor: Color = theme == .workbench ? .black.opacity(0.08) : .white.opacity(0.08)
            func x(_ key: Int) -> CGFloat {
                layout.center(key)
            }
            for key in keyRange {
                let center = x(key)
                if NoteRainLayout.isBlack(key) {
                    context.fill(Path(CGRect(x: center - width * 0.31, y: top, width: width * 0.62, height: strike - top)),
                        with: .color(theme == .workbench ? .black.opacity(0.035) : .white.opacity(0.025)))
                }
                if key % 12 == 0 {
                    var line = Path()
                    line.move(to: CGPoint(x: center - width / 2, y: top))
                    line.addLine(to: CGPoint(x: center - width / 2, y: strike))
                    context.stroke(line, with: .color(gridColor), lineWidth: 1)
                }
            }
            for second in 0...Int(horizon) {
                let y = strike - CGFloat(second) * scale
                var line = Path()
                line.move(to: CGPoint(x: left, y: y))
                line.addLine(to: CGPoint(x: size.width - right, y: y))
                context.stroke(line, with: .color(gridColor), lineWidth: 1)
                context.draw(Text(second == 0 ? "JETZT" : "+\(second)s")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(textColor),
                    at: CGPoint(x: left - 6, y: y), anchor: .trailing)
            }
            var rain = context
            rain.clip(to: Path(CGRect(x: left, y: top, width: size.width - left - right, height: strike - top)))
            for note in notes where keyRange.contains(note.key) && note.end > time && note.start < time + horizon {
                let rect = layout.bar(note, time: time)
                let bottom = rect.maxY
                let upper = rect.minY
                let barWidth = rect.width
                let color = NoteRainPalette.color(note.channel)
                rain.fill(Path(roundedRect: rect, cornerRadius: min(3, barWidth * 0.15)), with: .color(color))
                let visibleTop = max(top, upper)
                let visibleBottom = min(strike, bottom)
                let visibleHeight = visibleBottom - visibleTop
                guard barWidth >= 12, visibleHeight >= 15 else { continue }
                let label = rain.resolve(Text(note.name)
                    .font(.system(size: barWidth >= 18 ? 10 : 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black.opacity(0.85)))
                let labelSize = label.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                if barWidth >= labelSize.width + 4 && visibleHeight >= labelSize.height + 6 {
                    rain.draw(label, at: CGPoint(x: rect.midX, y: visibleBottom - labelSize.height / 2 - 3))
                } else if barWidth >= labelSize.height + 2 && visibleHeight >= labelSize.width + 6 {
                    var verticalLabel = rain
                    verticalLabel.translateBy(x: rect.midX, y: visibleBottom - labelSize.width / 2 - 3)
                    verticalLabel.rotate(by: .degrees(-90))
                    verticalLabel.draw(label, at: .zero)
                }
            }
            let active = notes.filter { $0.start <= time && $0.end > time }
            for isBlack in [false, true] {
                for key in keyRange where NoteRainLayout.isBlack(key) == isBlack {
                    let keyWidth = width * (isBlack ? 0.62 : 1)
                    let height = keyboardHeight * (isBlack ? 0.63 : 1)
                    let rect = CGRect(x: x(key) - keyWidth / 2, y: strike, width: keyWidth, height: height)
                    let voices = active.filter { $0.key == key }
                    let base: Color = isBlack ? Color(white: 0.10) : Color(white: 0.90)
                    context.fill(Path(rect), with: .color(base))
                    if let voice = voices.first {
                        context.fill(Path(rect), with: .color(NoteRainPalette.color(voice.channel).opacity(isBlack ? 0.32 : 0.22)))
                    }
                    context.stroke(Path(rect), with: .color(.black.opacity(0.5)), lineWidth: 0.6)
                    for (index, voice) in voices.enumerated() {
                        let segment = keyWidth / CGFloat(voices.count)
                        context.fill(Path(CGRect(x: rect.minX + CGFloat(index) * segment, y: rect.minY,
                            width: segment, height: 3)), with: .color(NoteRainPalette.color(voice.channel)))
                    }
                    if key % 12 == 0 || !voices.isEmpty && keyWidth > 22 {
                        context.draw(Text(PreviewNote.name(for: key)).font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(isBlack ? .white.opacity(0.9) : .black.opacity(0.7)),
                            at: CGPoint(x: rect.midX, y: rect.maxY - 14))
                    }
                }
            }
            var line = Path()
            line.move(to: CGPoint(x: left, y: strike))
            line.addLine(to: CGPoint(x: size.width - right, y: strike))
            context.stroke(line, with: .color(Color.accent(theme)), lineWidth: 2)
        }
        .onContinuousHover { phase in
            if case let .active(point) = phase { hoverPoint = point }
            else { hoverPoint = nil }
        }
        .overlay(alignment: .topTrailing) {
            if let point = hoverPoint,
               let note = hoveredNote(at: point, size: proxy.size) {
                Text("\(note.name) · K\(note.channel + 1) · \(note.isOpen ? "≥ " : "")\(String(format: "%.2f", note.end - note.start)) s")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceSurface,
                        in: RoundedRectangle(cornerRadius: 6))
                    .padding(12).allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Fallende Tracker-Noten über einer Klaviatur")
        .accessibilityValue(notes.filter { $0.start <= time && $0.end > time }
            .map { "\($0.name), Kanal \($0.channel + 1)" }.joined(separator: ", "))
        .onAppear { onSizeChange(proxy.size) }
        .onChange(of: proxy.size) { onSizeChange($0) }
        }
    }

    private func hoveredNote(at point: CGPoint, size: CGSize) -> PreviewNote? {
        let layout = NoteRainLayout(size: size, keyRange: keyRange, horizon: horizon, fixedKeyWidth: fixedKeyWidth)
        guard layout.rainBounds.contains(point) else { return nil }
        return notes.reversed().first {
            keyRange.contains($0.key) && $0.end > time && $0.start < time + horizon
                && layout.bar($0, time: time).insetBy(dx: 0, dy: -2).contains(point)
        }
    }
}

struct NoteRainLayout {
    static let horizontalMargins: CGFloat = 60
    let size: CGSize
    let whiteKeys: [Int]
    let keyWidth: CGFloat
    let keyboardHeight: CGFloat
    let strike: CGFloat
    let scale: CGFloat
    let left: CGFloat
    let right: CGFloat
    let top: CGFloat = 18

    init(size: CGSize, keyRange: ClosedRange<Int>, horizon: Double, fixedKeyWidth: CGFloat? = nil) {
        self.size = size
        whiteKeys = keyRange.filter { !Self.isBlack($0) }
        let availableWidth = max(1, size.width - Self.horizontalMargins)
        // Das feste Seitenverhaeltnis verhindert breite, kurze Tasten beim Zoom.
        keyWidth = fixedKeyWidth ?? max(1, min(availableWidth / CGFloat(max(1, whiteKeys.count)), min(144, size.height * 0.28) / 4.8))
        keyboardHeight = keyWidth * 4.8
        left = 42 + (availableWidth - keyWidth * CGFloat(whiteKeys.count)) / 2
        right = size.width - left - keyWidth * CGFloat(whiteKeys.count)
        strike = size.height - keyboardHeight
        scale = max(1, strike - top) / max(1, horizon)
    }

    static func isBlack(_ key: Int) -> Bool { [1, 3, 6, 8, 10].contains(key % 12) }

    func center(_ key: Int) -> CGFloat {
        left + CGFloat(whiteKeys.filter { $0 < key }.count) * keyWidth + (Self.isBlack(key) ? 0 : keyWidth / 2)
    }

    var rainBounds: CGRect {
        CGRect(x: left, y: top, width: max(1, size.width - left - right), height: max(1, strike - top))
    }

    func bar(_ note: PreviewNote, time: Double) -> CGRect {
        let width = max(3, keyWidth * (Self.isBlack(note.key) ? 0.52 : 0.68))
        let bottom = strike - CGFloat(note.start - time) * scale
        let upper = strike - CGFloat(note.end - time) * scale
        return CGRect(x: center(note.key) - width / 2, y: upper, width: width, height: max(2, bottom - upper))
    }
}

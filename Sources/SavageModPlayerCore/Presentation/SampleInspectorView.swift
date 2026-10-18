#if canImport(SwiftUI)
import SwiftUI

public struct SampleInspectorView: View {
    private let inspection: SampleInspection
    private let format: ModuleFormat
    @State private var instrumentID = 0
    @State private var sampleID = ""
    @State private var mappingExpanded = true

    public init(module: Mod, instrumentIndex: Int? = nil) {
        inspection = SampleInspection(module: module)
        format = module.format
        _instrumentID = State(initialValue: instrumentIndex ?? 0)
    }

    private var instrument: InspectedInstrument? { inspection.instruments.first { $0.id == instrumentID } }
    private var available: [InspectedSample] {
        guard let instrument else { return inspection.samples }
        let ids = Set(instrument.sampleIDs)
        return inspection.samples.filter { ids.contains($0.id) }
    }
    private var selected: InspectedSample? { available.first { $0.id == sampleID } ?? available.first }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instrument").font(.caption).foregroundStyle(.secondary)
                        Picker("Instrument", selection: Binding(get: { instrumentID }, set: { instrumentID = $0; sampleID = "" })) {
                            Text("Alle Samples").tag(0)
                            ForEach(inspection.instruments) { item in
                                Text(verbatim: "\(item.id) · \(item.name)").tag(item.id)
                            }
                        }
                        .labelsHidden().accessibilityIdentifier("sample-instrument-picker")
                    }
                    if !available.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sample").font(.caption).foregroundStyle(.secondary)
                            Picker("Sample", selection: Binding(get: { selected?.id ?? "" }, set: { sampleID = $0 })) {
                                ForEach(available) { item in
                                    Text(verbatim: sampleLabel(item)).tag(item.id)
                                }
                            }
                            .labelsHidden().accessibilityIdentifier("sample-picker")
                        }
                    }
                }
                if let selected, let sample = selected.sample {
                    SampleWaveformView(sample: sample).id(selected.id)
                    metadata(sample)
                } else {
                    Text("Kein Sample vorhanden").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
                if let instrument {
                    DisclosureGroup("Tastenzuordnung", isExpanded: $mappingExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            if instrument.keyZones.isEmpty {
                                Text("Keine eigene Tastenzuordnung gespeichert. Die Noten verwenden das direkte Instrument-Sample.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Tracker-Noten: C-0 ist Note 0. Zielnoten enthalten die Instrument-Transposition; Sample-Tuning gilt zusätzlich.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(instrument.keyZones) { zone in
                                HStack(alignment: .top) {
                                    Text(verbatim: noteRange(zone.sourceNotes)).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(verbatim: "→ " + noteRange(zone.targetNotes)).frame(maxWidth: .infinity, alignment: .leading)
                                    if let number = zone.sampleNumber {
                                        Text(verbatim: "#\(number)")
                                            .foregroundStyle(zone.sampleID == selected?.id ? Color.accentColor : Color.primary)
                                    } else { Text("Unbelegt").foregroundStyle(.secondary) }
                                }.font(.caption.monospacedDigit())
                            }
                        }.padding(.top, 8)
                    }
                } else {
                    Text("Instrument wählen, um die Tastenzuordnung zu sehen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
    }

    private func sampleLabel(_ item: InspectedSample) -> String {
        let prefix = item.instrumentIndex.map { "\($0)." } ?? ""
        return "\(prefix)\(item.number) · \(item.sample?.name ?? "—")"
    }
    private func noteRange(_ range: ClosedRange<Int>) -> String {
        let first = SampleInspection.noteName(range.lowerBound)
        return range.count == 1 ? first : first + " – " + SampleInspection.noteName(range.upperBound)
    }
    private func metadata(_ sample: Sample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Frames"); Spacer(); Text(verbatim: "\(sample.pcm.count)") }
            HStack { Text("Kanäle"); Spacer(); Text(LocalizedStringKey(sample.rightPCM == nil ? "Mono" : "Stereo")) }
            HStack { Text("Lautstärke"); Spacer(); Text(verbatim: "\(sample.volume)/64") }
            HStack { Text("Finetune"); Spacer(); Text(verbatim: "\(sample.finetune)") }
            if format == .xm {
                HStack { Text("Relative Note"); Spacer(); Text(verbatim: "\(sample.relativeNote)") }
            }
            if format == .it || format == .s3m {
                HStack {
                    Text(LocalizedStringKey(format == .it ? "Referenzrate bei C-5" : "Referenzrate bei C-4"))
                    Spacer()
                    Text(verbatim: "\(sample.itProperties?.c5Speed ?? sample.c2spd) Hz")
                }
            }
        }.font(.callout.monospacedDigit())
    }
}

public struct SampleWaveformView: View {
    private let sample: Sample
    @State private var zoom = 1
    @State private var position: Double = 0
    @State private var focus: SampleFrameRange?
    @State private var waveform: SampleWaveform?
    @State private var isLoading = false

    public init(sample: Sample) { self.sample = sample }
    private var range: SampleFrameRange {
        focus ?? SampleFrameRange(frameCount: sample.pcm.count, zoom: zoom, position: position)
    }
    private var visibleWaveform: SampleWaveform? { waveform?.range == range ? waveform : nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sample.pcm.isEmpty {
                Text("Leeres Sample").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ZStack {
                    VStack(spacing: 4) {
                        channel(visibleWaveform?.left, label: sample.rightPCM == nil ? "Mono" : "Links")
                        if sample.rightPCM != nil { channel(visibleWaveform?.right, label: "Rechts") }
                    }
                    if isLoading { ProgressView().controlSize(.small) }
                }
                .frame(height: sample.rightPCM == nil ? 180 : 240)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sample-Wellenform")
                .accessibilityValue(Text(verbatim: "\(range.lowerBound) – \(range.upperBound)"))
                HStack {
                    Text("Frames").foregroundStyle(.secondary)
                    Text(verbatim: "\(range.lowerBound) – \(range.upperBound) / \(sample.pcm.count)").monospacedDigit()
                }.font(.caption)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zoom").font(.caption).foregroundStyle(.secondary)
                    Picker("Zoom", selection: Binding(get: { focus == nil ? zoom : 0 }, set: {
                        if $0 > 0 { zoom = $0; focus = nil }
                    })) {
                        if focus != nil { Text("Bereich").tag(0) }
                        ForEach([1, 2, 4, 8, 16, 32, 64], id: \.self) { Text(verbatim: "\($0)×").tag($0) }
                    }.labelsHidden().accessibilityIdentifier("sample-zoom")
                }
                HStack {
                    Text("Position").font(.caption)
                    Slider(value: Binding(get: { position }, set: { value in
                        position = value
                        if let focus {
                            let start = Int((Double(sample.pcm.count - focus.count) * value).rounded())
                            self.focus = SampleFrameRange(frameCount: sample.pcm.count, start: start, length: focus.count)
                        }
                    }), in: 0...1)
                        .disabled(range.count == 0 || range.count == sample.pcm.count).accessibilityLabel("Sample-Ausschnitt")
                }
                HStack {
                    Button("Gesamt") { zoom = 1; position = 0; focus = nil }
                    if sample.isLooped { Button("Loop") { focusLoop(sample.loopStart, sample.loopLength) } }
                    if let sustain = sample.sustainLoop, sustain.type != .none, sustain.length > 0 {
                        Button("Sustain") { focusLoop(sustain.start, sustain.length) }
                    }
                }.buttonStyle(.bordered)
            }
            loopLabel("Loop", start: sample.loopStart, length: sample.loopLength, type: sample.loopType, color: .accentColor)
            if let sustain = sample.sustainLoop {
                loopLabel("Sustain", start: sustain.start, length: sustain.length, type: sustain.type, color: .orange)
            }
        }
        .task(id: range) {
            waveform = nil
            guard range.count > 0 else { isLoading = false; return }
            isLoading = true
            let sound = sample, visible = range
            let worker = Task.detached(priority: .userInitiated) { try SampleWaveform.make(sample: sound, range: visible) }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                waveform = result
                isLoading = false
            } catch {
                if !Task.isCancelled { isLoading = false }
            }
        }
    }

    private func loopRange(_ start: Int, _ length: Int) -> SampleFrameRange {
        SampleFrameRange(frameCount: sample.pcm.count, start: start, length: length)
    }
    private func focusLoop(_ start: Int, _ length: Int) {
        let visible = loopRange(start, length)
        focus = visible
        let remaining = sample.pcm.count - visible.count
        position = remaining > 0 ? Double(visible.lowerBound) / Double(remaining) : 0
    }
    private func loopLabel(_ title: LocalizedStringKey, start: Int, length: Int, type: LoopType, color: Color) -> some View {
        HStack(alignment: .top) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 5)
            Text(title)
            Spacer()
            if type == .none || length <= 0 { Text("Aus").foregroundStyle(.secondary) }
            else {
                let clipped = loopRange(start, length)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(clipped.lowerBound) – \(clipped.upperBound)").monospacedDigit()
                    Text(LocalizedStringKey(type == .pingpong ? "Ping-Pong" : "Vorwärts")).foregroundStyle(.secondary)
                }
            }
        }.font(.caption)
    }
    private func channel(_ peaks: [SampleWaveform.Peak]?, label: LocalizedStringKey) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let center = size.height / 2
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: center)); baseline.addLine(to: CGPoint(x: size.width, y: center))
                context.stroke(baseline, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                drawLoop(&context, size: size, start: sample.loopStart, length: sample.loopLength, type: sample.loopType, color: .accentColor)
                if let sustain = sample.sustainLoop {
                    drawLoop(&context, size: size, start: sustain.start, length: sustain.length, type: sustain.type, color: .orange)
                }
                guard let peaks, !peaks.isEmpty else { return }
                var envelope = Path()
                for (index, peak) in peaks.enumerated() {
                    let x = (Double(index) + 0.5) / Double(peaks.count) * size.width
                    // PCM hat nominal ±0,5; derselbe feste Maßstab bleibt beim Zoomen erhalten.
                    let point = CGPoint(x: x, y: center - CGFloat(peak.maximum) * size.height * 0.9)
                    if index == 0 { envelope.move(to: point) } else { envelope.addLine(to: point) }
                }
                for index in peaks.indices.reversed() {
                    let x = (Double(index) + 0.5) / Double(peaks.count) * size.width
                    envelope.addLine(to: CGPoint(x: x, y: center - CGFloat(peaks[index].minimum) * size.height * 0.9))
                }
                envelope.closeSubpath()
                context.fill(envelope, with: .color(.primary.opacity(0.7)))
                context.stroke(envelope, with: .color(.primary.opacity(0.85)), lineWidth: 1)
                if peaks.count == range.count, let first = peaks.first, let last = peaks.last {
                    var detail = Path()
                    detail.move(to: CGPoint(x: 0, y: center - CGFloat(first.maximum) * size.height * 0.9))
                    for (index, peak) in peaks.enumerated() {
                        let x = (Double(index) + 0.5) / Double(peaks.count) * size.width
                        detail.addLine(to: CGPoint(x: x, y: center - CGFloat(peak.maximum) * size.height * 0.9))
                    }
                    detail.addLine(to: CGPoint(x: size.width, y: center - CGFloat(last.maximum) * size.height * 0.9))
                    context.stroke(detail, with: .color(.primary.opacity(0.85)), lineWidth: 1)
                }
            }
            Text(label).font(.caption2).foregroundStyle(.primary.opacity(0.8)).padding(4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3)).padding(4)
        }.clipped()
    }
    private func drawLoop(_ context: inout GraphicsContext, size: CGSize, start: Int, length: Int, type: LoopType, color: Color) {
        guard type != .none, length > 0, range.count > 0 else { return }
        let loop = loopRange(start, length)
        let lower = max(loop.lowerBound, range.lowerBound), upper = min(loop.upperBound, range.upperBound)
        guard lower < upper else { return }
        let x = Double(lower - range.lowerBound) / Double(range.count) * size.width
        let width = Double(upper - lower) / Double(range.count) * size.width
        let rect = CGRect(x: x, y: 0, width: width, height: size.height)
        context.fill(Path(rect), with: .color(color.opacity(0.12)))
        context.stroke(Path(rect), with: .color(color.opacity(0.65)), lineWidth: 1)
    }
}
#endif

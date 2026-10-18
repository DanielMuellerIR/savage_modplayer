#if canImport(SwiftUI)
import SwiftUI

public enum ModuleInspectorSection: String, CaseIterable, Identifiable, Sendable {
    case overview, instruments, effects
    public var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .overview: "Übersicht"; case .instruments: "Instrumente"; case .effects: "Effekte" }
    }
}

public struct ModuleInspectorView: View {
    private let module: Mod
    @Environment(\.locale) private var locale
    @State private var section: ModuleInspectorSection
    @State private var instrumentIndex: Int
    @State private var inspection: ModuleInspection?

    public init(module: Mod, section: ModuleInspectorSection = .overview) {
        self.module = module
        _section = State(initialValue: section)
        _instrumentIndex = State(initialValue: module.instruments.indices.dropFirst().first { module.instruments[$0] != nil } ?? 0)
    }
    private var languageCode: String {
        #if os(macOS)
        "de"
        #else
        locale.language.languageCode?.identifier ?? "en"
        #endif
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $section) {
                ForEach(ModuleInspectorSection.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).padding(16).accessibilityIdentifier("module-inspector-section")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let inspection {
                        switch section {
                        case .overview: overview(inspection)
                        case .instruments: instruments(inspection)
                        case .effects: effects(inspection)
                        }
                    } else { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
                }.padding(20).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
        }
        .task {
            let source = module
            let worker = Task.detached(priority: .userInitiated) { try ModuleInspection(module: source) }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                inspection = result
            } catch { }
        }
    }

    private func overview(_ inspection: ModuleInspection) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: module.name).font(.title2.bold()).textSelection(.enabled)
                field("Format", module.format.displayName)
                field("Songpositionen", "\(inspection.orders.count)")
                field("Patterns", "\(module.patterns.count)")
                field("Kanalplätze / benutzt", "\(module.channelCount) / \(module.usedChannelCount)")
                field("Instrumentplätze", "\(inspection.instrumentIndices.count)")
                field("Sampleplätze", "\(inspection.sampleCount)")
                field("Starttempo / Ticks pro Zeile", "\(module.initialTempo) BPM / \(module.initialSpeed)")
                field("Startlautstärke", "\(module.initialGlobalVolume)/\(module.globalVolumeScale.rawValue)")
                if module.format == .xm || module.format == .it {
                    stateField("Frequenzmodell", module.linearFrequency ? "Linear" : "Amiga")
                }
            }
            GroupBox("Herkunft") {
                VStack(alignment: .leading, spacing: 8) {
                    if let tracker = inspection.tracker { field("Tracker", tracker) }
                    else { Text("Trackerherkunft ist im geladenen Modell nicht enthalten.").foregroundStyle(.secondary) }
                    if let artist = inspection.artist { field("Künstlerfeld", artist) }
                    else { Text("Kein explizites Künstlerfeld vorhanden.").foregroundStyle(.secondary) }
                    if let properties = module.itProperties {
                        field("Erstellerversion (cwtv)", String(format: "0x%04X", properties.createdWithVersion))
                        field("Benötigte IT-Version (cmwt)", String(format: "0x%04X", properties.compatibleWithVersion))
                        stateField("IT-Modus", properties.usesInstruments ? "Instrumente" : "Samples")
                        if let version = properties.openMPTExtensions?.lastSavedWithVersion {
                            field("Zuletzt mit OpenMPT gespeichert", version.displayName)
                        }
                    }
                    Text("Namen und Textzeilen werden nicht als Künstlerangaben interpretiert.").font(.caption).foregroundStyle(.secondary)
                }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            DisclosureGroup("Songpositionen und Pattern-Aufbau") {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(inspection.orders) { order in
                        HStack {
                            Text(verbatim: "\(order.position + 1)").frame(width: 42, alignment: .leading)
                            Text(verbatim: "→ Pattern \(order.pattern)")
                            Spacer()
                            if let rows = order.rowCount { Text(verbatim: "\(rows)"); Text("Zeilen") }
                            else { Text("Nicht vorhanden").foregroundStyle(.red) }
                        }.font(.caption.monospacedDigit())
                    }
                    Divider()
                    ForEach(module.patterns.indices, id: \.self) { index in
                        HStack {
                            Text(verbatim: "Pattern \(index)")
                            Spacer()
                            Text(verbatim: "\(module.patterns[index].rows.count)"); Text("Zeilen")
                            Text(verbatim: "· \(inspection.patternUseCounts[index] ?? 0)×"); Text("in der Liste")
                        }.font(.caption.monospacedDigit())
                    }
                }.padding(.top, 8)
            }
            compatibility(inspection)
        }
    }

    private func compatibility(_ inspection: ModuleInspection) -> some View {
        GroupBox("Kompatibilität") {
            VStack(alignment: .leading, spacing: 12) {
                if inspection.compatibilityWarnings.isEmpty {
                    Text("Keine erfassten Kompatibilitätswarnungen.").foregroundStyle(.secondary)
                }
                ForEach(Array(inspection.compatibilityWarnings.enumerated()), id: \.offset) { _, warning in
                    Text(verbatim: warning).foregroundStyle(.orange).textSelection(.enabled)
                }
                ForEach(Array(inspection.compatibilityFindings.enumerated()), id: \.offset) { _, finding in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Text(verbatim: finding.identifier).font(.caption.monospaced())
                            Spacer()
                            Text(supportTitle(finding.support)).font(.caption.weight(.semibold))
                        }
                        Text(LocalizedStringKey(finding.used ? "Verwendet" : "Gespeichert, nicht verwendet")).font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: finding.detail).font(.caption).textSelection(.enabled)
                    }
                }
                Text("Die Diagnose unterscheidet erhaltene Metadaten von tatsächlich verwendeten klangrelevanten Merkmalen.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
    }

    private func instruments(_ inspection: ModuleInspection) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if inspection.instrumentIndices.isEmpty {
                Text("Keine Instrumentplätze vorhanden.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Instrument").font(.caption).foregroundStyle(.secondary)
                    Picker("Instrument", selection: $instrumentIndex) {
                        ForEach(inspection.instrumentIndices, id: \.self) { index in
                            Text(verbatim: "\(index) · \(module.instruments[index]?.name ?? "")").tag(index)
                        }
                    }.labelsHidden().accessibilityIdentifier("module-instrument-picker")
                }
                if module.instruments.indices.contains(instrumentIndex), let instrument = module.instruments[instrumentIndex] {
                    instrumentDetails(instrument)
                }
            }
        }
    }

    private func instrumentDetails(_ instrument: Instrument) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            field("Fadeout", "\(instrument.fadeout)")
            if let vibrato = instrument.autoVibrato {
                GroupBox("Auto-Vibrato") {
                    VStack(spacing: 6) {
                        stateField("Wellenform", vibratoTitle(vibrato.type))
                        field("Anlauf", "\(vibrato.sweep)")
                        field("Tiefe / Rate", "\(vibrato.depth) / \(vibrato.rate)")
                    }.font(.callout).padding(4)
                }
            }
            if let envelope = instrument.volumeEnvelope { EnvelopeInspectorView(title: "Lautstärke-Hüllkurve", envelope: envelope) }
            if let envelope = instrument.panningEnvelope { EnvelopeInspectorView(title: "Panning-Hüllkurve", envelope: envelope) }
            if let envelope = instrument.pitchEnvelope {
                EnvelopeInspectorView(title: envelope.valueMode == .filter ? "Filter-Hüllkurve" : "Tonhöhen-Hüllkurve", envelope: envelope)
            }
            if instrument.volumeEnvelope == nil && instrument.panningEnvelope == nil && instrument.pitchEnvelope == nil {
                Text("Keine aktivierten Hüllkurven gespeichert.").foregroundStyle(.secondary)
            }
            if let properties = instrument.itProperties {
                GroupBox("IT-Instrumentregeln") {
                    VStack(spacing: 8) {
                        field("Neue Note (NNA)", properties.newNoteAction.rawValue.description)
                        field("Duplikatprüfung / Aktion", "\(properties.duplicateCheckType.rawValue) / \(properties.duplicateCheckAction.rawValue)")
                        field("Globale Instrumentlautstärke", "\(properties.globalVolume)/128")
                        if let panning = properties.defaultPanning { field("Standard-Panning", "\(panning)/64") }
                        field("Pitch-Pan-Separation / Zentrum", "\(properties.pitchPanSeparation) / \(properties.pitchPanCenter)")
                        field("Zufalls-Lautstärke / Panning", "\(properties.randomVolumeVariation) / \(properties.randomPanningVariation)")
                        field("MIDI-Kanal / Programm / Bank", "\(properties.midiChannel) / \(properties.midiProgram) / \(properties.midiBank)")
                        if let slot = properties.pluginSlot { field("Plugin-Slot", "\(slot)") }
                        if let cutoff = properties.initialFilterCutoff { field("Filter-Cutoff", "\(cutoff)") }
                        if let resonance = properties.initialFilterResonance { field("Filterresonanz", "\(resonance)") }
                        Text("NNA: 0 abschneiden, 1 weiterklingen, 2 Note Off, 3 ausblenden. Duplikatprüfung: 0 aus, 1 Note, 2 Sample, 3 Instrument. Duplikataktion: 0 abschneiden, 1 Note Off, 2 ausblenden.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.font(.callout).padding(4)
                }
            }
        }
    }

    private func effects(_ inspection: ModuleInspection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Übernommene Befehle in gespeicherten Patterns").font(.headline)
            Text("Die Häufigkeit zählt gespeicherte Zellen einmal je Pattern, auch außerhalb der Abspielliste. Sie ist keine Anzahl tatsächlich abgespielter Effekte. Parameter können beim Import normalisiert worden sein.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Ein Tick ist ein Tracker-Zeitschritt. Speed zählt Ticks pro Zeile; Tempo steuert ihre Dauer. Nullparameter können früheres Effekt-Memory übernehmen. Sprünge, Loops und Delays verändern die Spielreihenfolge.")
                .font(.caption).foregroundStyle(.secondary)
            if inspection.effects.isEmpty { Text("Keine übernommenen Effektbefehle vorhanden.").foregroundStyle(.secondary) }
            ForEach(inspection.effects) { effect in
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(verbatim: effect.code).font(.body.monospaced().bold())
                            Text(verbatim: effect.title.value(languageCode: languageCode)).font(.body.weight(.semibold))
                            Spacer()
                            Text(verbatim: "\(effect.count)×").monospacedDigit()
                        }
                        Text(LocalizedStringKey(effect.isVolumeColumn ? "Volume-Spalte" : "Effektspalte")).font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: effect.detail.value(languageCode: languageCode)).font(.callout)
                        if !effect.implemented { Text("Derzeit ignoriert").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                        HStack(alignment: .top) {
                            let decimal = effect.isVolumeColumn && module.format != .xm
                            Text(LocalizedStringKey(decimal ? "Übernommene Parameter (dezimal)" : "Übernommene Parameter (hexadezimal)"))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: effect.parameters.prefix(32).map { decimal ? "\($0)" : String(format: "%02X", $0) }.joined(separator: " ")
                                 + (effect.parameters.count > 32 ? " …" : ""))
                                .font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
            }
        }
    }

    private func field(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top) { Text(title); Spacer(); Text(verbatim: value).multilineTextAlignment(.trailing).textSelection(.enabled) }
            .font(.callout.monospacedDigit())
    }
    private func stateField(_ title: LocalizedStringKey, _ value: LocalizedStringKey) -> some View {
        HStack(alignment: .top) { Text(title); Spacer(); Text(value) }.font(.callout)
    }
    private func supportTitle(_ support: ITCapabilitySupport) -> LocalizedStringKey {
        switch support {
        case .supported: "Unterstützt"
        case .irrelevantForPCM: "Keine PCM-Wirkung"
        case .metadataOnly: "Nur Metadaten"
        case .midiOrPluginOnly: "Externer MIDI-/Pluginpfad"
        case .unsupported: "Nicht unterstützt"
        case .differentPlayback: "Abweichende Wiedergabe"
        }
    }
    private func vibratoTitle(_ type: Int) -> LocalizedStringKey {
        switch type { case 0: "Sinus"; case 1: "Rechteck"; case 2: "Rampe"; case 3: "Umgekehrte Rampe"; default: "Unbekannt" }
    }
}

struct EnvelopeInspectorView: View {
    let title: LocalizedStringKey
    let envelope: Envelope
    private var inspection: EnvelopeInspection { EnvelopeInspection(envelope: envelope) }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                if envelope.points.isEmpty {
                    Text("Keine Hüllkurvenpunkte vorhanden.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    graph.frame(height: 160).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    Text("Ticks seit Note-Start").font(.caption).foregroundStyle(.secondary)
                }
                if envelope.valueMode == .pitch { Text("Wert 32 ist die neutrale Tonhöhe.").font(.caption).foregroundStyle(.secondary) }
                bounds("Loop", enabled: envelope.loopEnabled, ticks: inspection.loopTicks, color: .accentColor)
                bounds("Sustain", enabled: envelope.sustainEnabled, ticks: inspection.sustainTicks, color: .orange)
                HStack { Text("Carry"); Spacer(); Text(LocalizedStringKey(envelope.carryEnabled ? "Ein" : "Aus")) }.font(.caption)
                DisclosureGroup("Hüllkurvenpunkte") {
                    VStack(spacing: 6) {
                        ForEach(Array(envelope.points.enumerated()), id: \.offset) { index, point in
                            HStack {
                                Text(verbatim: "\(index)").foregroundStyle(.secondary)
                                Text("Tick"); Text(verbatim: "\(point.frame)")
                                Spacer(); Text("Wert"); Text(verbatim: "\(point.value)")
                            }.font(.caption.monospacedDigit())
                        }
                    }.padding(.top, 6)
                }.font(.caption)
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func bounds(_ title: LocalizedStringKey, enabled: Bool, ticks: ClosedRange<Int>?, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title); Spacer()
            if !enabled { Text("Aus").foregroundStyle(.secondary) }
            else if let ticks { Text(verbatim: "\(ticks.lowerBound) – \(ticks.upperBound)").monospacedDigit() }
            else { Text("Ungültige Grenzen").foregroundStyle(.red) }
        }.font(.caption)
    }
    private var graph: some View {
        let inspection = self.inspection
        return Canvas { context, size in
            let plot = CGRect(x: 28, y: 12, width: max(1, size.width - 40), height: max(1, size.height - 34))
            func point(tick: Int, value: Int) -> CGPoint {
                CGPoint(x: plot.minX + Double(max(0, min(inspection.lastTick, tick))) / Double(inspection.lastTick) * plot.width,
                        y: plot.maxY - Double(max(0, min(64, value))) / 64 * plot.height)
            }
            func region(_ range: ClosedRange<Int>?, color: Color) {
                guard let range else { return }
                let x1 = point(tick: range.lowerBound, value: 0).x, x2 = point(tick: range.upperBound, value: 0).x
                let rect = CGRect(x: x1, y: plot.minY, width: max(1, x2 - x1), height: plot.height)
                context.fill(Path(rect), with: .color(color.opacity(0.14)))
                context.stroke(Path(rect), with: .color(color.opacity(0.65)), lineWidth: 1)
            }
            region(inspection.loopTicks, color: .accentColor); region(inspection.sustainTicks, color: .orange)
            var grid = Path()
            for value in [0, 32, 64] {
                grid.move(to: point(tick: 0, value: value)); grid.addLine(to: point(tick: inspection.lastTick, value: value))
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            var line = Path()
            for (index, value) in envelope.points.enumerated() {
                let p = point(tick: value.frame, value: value.value)
                if index == 0 { line.move(to: p) } else { line.addLine(to: p) }
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.primary))
            }
            context.stroke(line, with: .color(.primary), lineWidth: 1.5)
            context.draw(Text("64").font(.caption2).foregroundColor(.secondary), at: CGPoint(x: 12, y: plot.minY))
            context.draw(Text("0").font(.caption2).foregroundColor(.secondary), at: CGPoint(x: 12, y: plot.maxY))
            context.draw(Text("0").font(.caption2).foregroundColor(.secondary), at: CGPoint(x: plot.minX, y: size.height - 9))
            context.draw(Text(verbatim: "\(inspection.lastTick)").font(.caption2).foregroundColor(.secondary), at: CGPoint(x: plot.maxX, y: size.height - 9))
        }
    }
}
#endif

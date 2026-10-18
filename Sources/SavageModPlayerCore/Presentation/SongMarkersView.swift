#if canImport(SwiftUI) && canImport(Combine)
import SwiftUI

public struct SongMarkersView: View {
    @ObservedObject private var model: SongMarkersModel
    private let current: () -> SongAddress
    private let seek: (SongAddress) -> Bool
    private let transport: TransportState?
    private let coordinator: ModPlayerCoordinator?
    private let startLoop: ((SongSection) -> Void)?
    @State private var address = SongAddress(position: 0, row: 0)
    @State private var name = ""
    @State private var editingID: UUID?
    @State private var hasChosenTarget = true
    @State private var seekFailed = false

    public init(model: SongMarkersModel, transport: TransportState? = nil, coordinator: ModPlayerCoordinator? = nil,
                startLoop: ((SongSection) -> Void)? = nil,
                current: @escaping () -> SongAddress, seek: @escaping (SongAddress) -> Bool) {
        self.model = model; self.transport = transport; self.current = current; self.seek = seek
        self.coordinator = coordinator
        self.startLoop = startLoop
    }
    private var rowCount: Int { model.layout.rowCounts.indices.contains(address.position) ? model.layout.rowCounts[address.position] : 0 }
    private var positionBinding: Binding<Int> {
        Binding(get: { address.position }, set: {
            address.position = $0
            address.row = min(address.row, max(0, rowCount - 1)); hasChosenTarget = true
        })
    }
    private var rowBinding: Binding<Int> {
        Binding(get: { address.row }, set: { address.row = $0; hasChosenTarget = true })
    }
    public var body: some View {
        VStack(spacing: 0) {
        if let transport { SongSectionStrip(model: model, transport: transport).padding(16) }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(verbatim: model.title).font(.headline)
                Text("Songpositionen beginnen bei 1, Zeilen bei 0. Ein Sprung erhält Play/Pause/Stopp; Tempo wird wie beim Tracker-Zeilenklick rekonstruiert. Laufende Stimmen und Effekte sind dabei näherungsweise.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.issue == .load {
                    Text("Songstellen konnten nicht geladen werden. Speichern ist gesperrt; die Datei bleibt erhalten.").foregroundStyle(.red)
                } else if model.issue == .save {
                    Text("Songstellen konnten nicht gespeichert werden. Der bisherige Stand bleibt erhalten.").foregroundStyle(.red)
                }
                if model.sourceID == nil { Text("Für diese Quelle können keine dauerhaften Songstellen gespeichert werden.").font(.caption).foregroundStyle(.secondary) }
                if seekFailed { Text("Der Titel hat gewechselt. Bitte die Songstellen erneut öffnen.").foregroundStyle(.red) }
                editor
                selection
                GroupBox("Gespeicherte Songstellen") {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.issue == .load { Text("Gespeicherte Songstellen sind nicht verfügbar.").foregroundStyle(.secondary) }
                        else if !model.isLoaded { ProgressView() }
                        else if model.markers.isEmpty { Text("Noch keine Songstellen für diesen Titel.").foregroundStyle(.secondary) }
                        ForEach(model.markers) { marker in markerRow(marker) }
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(20).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        }
        .task(id: model.contextID) { resetEditor() }
    }
    private var editor: some View {
        GroupBox("Ziel wählen") {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: positionBinding, in: 0...max(0, model.layout.rowCounts.count - 1)) {
                    HStack { Text("Songposition"); Spacer(); Text(verbatim: "\(address.position + 1)").monospacedDigit() }
                }.disabled(model.layout.rowCounts.isEmpty).accessibilityIdentifier("marker-position")
                Stepper(value: rowBinding, in: 0...max(0, rowCount - 1)) {
                    HStack { Text("Zeile"); Spacer(); Text(verbatim: "\(address.row)").monospacedDigit() }
                }.disabled(rowCount == 0).accessibilityIdentifier("marker-row")
                HStack {
                    Button("Aktuelle Stelle") { chooseCurrent() }
                    Spacer()
                    Button("Zum Ziel springen") { seekFailed = !seek(address) }
                        .disabled(!model.layout.contains(address)).accessibilityIdentifier("marker-jump")
                }.buttonStyle(.bordered)
                TextField("Name der Songstelle", text: $name).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("marker-name")
                if name.trimmingCharacters(in: .whitespacesAndNewlines).count > SongMarker.maximumNameLength {
                    Text("Der Name darf höchstens 200 Zeichen haben.").font(.caption).foregroundStyle(.red)
                }
                if !hasChosenTarget { Text("Das bisherige Ziel fehlt. Bitte ein neues Ziel wählen.").font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button(LocalizedStringKey(editingID == nil ? "Songstelle hinzufügen" : "Änderungen speichern")) {
                        let value = name, target = address, id = editingID
                        Task { if await model.save(name: value, address: target, editingID: id) { resetEditor() } }
                    }
                    .disabled(!model.canSave || !hasChosenTarget || !model.layout.contains(address)
                              || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || name.trimmingCharacters(in: .whitespacesAndNewlines).count > SongMarker.maximumNameLength)
                    .accessibilityIdentifier("marker-save")
                    if editingID != nil { Button("Neu") { resetEditor() } }
                }.buttonStyle(.bordered)
            }.padding(6).disabled(model.isSaving)
        }
    }
    private var selection: some View {
        GroupBox("Bereich markieren") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Anfang (A)") { model.setBoundary(address, isStart: true) }
                    Button("Ende (B)") { model.setBoundary(address, isStart: false) }
                    Spacer()
                    Button("Lösen") { model.clearSelection() }
                }.buttonStyle(.bordered).disabled(!model.layout.contains(address))
                HStack {
                    Text("Position:Zeile").foregroundStyle(.secondary)
                    Text(verbatim: "\(label(model.start)) – \(label(model.end))").monospacedDigit()
                }.font(.caption)
                if model.isSelectionInvalid { Text("Das Ende liegt vor dem Anfang.").foregroundStyle(.red) }
                Text("Die Auswahl markiert den Bereich im Tracker und in der Positionsleiste. Der gewählte Wiedergabe-Loop-Modus gilt weiter.")
                    .font(.caption).foregroundStyle(.secondary)
                if let coordinator { SectionLoopControls(coordinator: coordinator, section: model.section, start: startLoop) }
            }.padding(6)
        }
    }
    private func markerRow(_ marker: SongMarker) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                editingID = marker.id; name = marker.name
                hasChosenTarget = model.layout.contains(marker.address)
                address = hasChosenTarget ? marker.address : validCurrent()
            } label: {
                HStack(alignment: .top) {
                    Text(verbatim: marker.name).multilineTextAlignment(.leading)
                    Spacer(); Text(verbatim: label(marker.address)).monospacedDigit()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.isSaving)
            HStack {
                Button("Springen") { seekFailed = !seek(marker.address) }
                    .disabled(!model.layout.contains(marker.address))
                Button("Löschen", role: .destructive) {
                    Task { await model.delete(id: marker.id); if editingID == marker.id { resetEditor() } }
                }.disabled(!model.canSave)
                if !model.layout.contains(marker.address) { Text("Ziel nicht mehr vorhanden").font(.caption).foregroundStyle(.red) }
            }.buttonStyle(.bordered)
            Divider()
        }
    }
    private func label(_ value: SongAddress?) -> String { value.map { "\($0.position + 1):\($0.row)" } ?? "—" }
    private func validCurrent() -> SongAddress {
        let value = current()
        return model.layout.contains(value) ? value : SongAddress(position: model.layout.rowCounts.firstIndex { $0 > 0 } ?? 0, row: 0)
    }
    private func chooseCurrent() { address = validCurrent(); hasChosenTarget = model.layout.contains(address) }
    private func resetEditor() { editingID = nil; name = ""; seekFailed = false; chooseCurrent() }
}

public struct SectionLoopControls: View {
    @ObservedObject private var coordinator: ModPlayerCoordinator
    private let section: SongSection?
    private let start: (SongSection) -> Void

    public init(coordinator: ModPlayerCoordinator, section: SongSection?, start: ((SongSection) -> Void)? = nil) {
        self.coordinator = coordinator
        self.section = section
        self.start = start ?? {
            coordinator.sleepTimer.prepareForManualPlayback()
            coordinator.startSectionLoop($0)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if coordinator.sectionLoopIsPreparing {
                    ProgressView().controlSize(.small)
                    Text("A/B wird vorbereitet …")
                    Spacer()
                    Button("Abbrechen") { coordinator.cancelSectionLoop() }
                        .accessibilityIdentifier("section-loop-cancel")
                } else if coordinator.sectionLoopIsActive {
                    Label("A/B-Schleife aktiv", systemImage: "repeat")
                    Spacer()
                    Button("A/B ausschalten") { coordinator.cancelSectionLoop() }
                        .accessibilityIdentifier("section-loop-stop")
                } else {
                    Button("A/B vorbereiten und abspielen") {
                        if let section { start(section) }
                    }
                    .disabled(section == nil).accessibilityIdentifier("section-loop-start")
                }
            }.buttonStyle(.bordered)
            if coordinator.sectionLoopIsPreparing {
                ProgressView(value: coordinator.sectionLoopProgress)
                Text("Maximal 10 Minuten Songverlauf; die bestehende Wiedergabe läuft während der Vorbereitung weiter.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = coordinator.sectionLoopError {
                Text(LocalizedStringKey(error.errorDescription ?? ""))
                    .font(.caption).foregroundStyle(.red).accessibilityIdentifier("section-loop-error")
            }
            Text("A/B beginnt mit dem rekonstruierten Zustand bei A und schließt alle Ticks von B ein. Ausschalten spielt an der aktuellen Stelle weiter. Sprünge oder Audioeinstellungen lösen die Schleife.")
                .font(.caption).foregroundStyle(.secondary)
        }
        #if os(iOS)
        .onChange(of: section) { _, value in selectionChanged(value) }
        #else
        .onChange(of: section) { value in selectionChanged(value) }
        #endif
    }

    private func selectionChanged(_ value: SongSection?) {
        if coordinator.sectionLoopTarget != nil, coordinator.sectionLoopTarget != value { coordinator.cancelSectionLoop() }
    }
}

public struct SectionLoopBadge: View {
    @ObservedObject private var coordinator: ModPlayerCoordinator

    public init(coordinator: ModPlayerCoordinator) { self.coordinator = coordinator }

    public var body: some View {
        if coordinator.sectionLoopIsActive {
            Text(verbatim: "A/B").font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .accessibilityLabel("A/B-Schleife aktiv")
        }
    }
}

public struct SongSectionStrip: View {
    @ObservedObject private var model: SongMarkersModel
    @ObservedObject private var transport: TransportState
    public init(model: SongMarkersModel, transport: TransportState) { self.model = model; self.transport = transport }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let section = model.section {
                    Text("Auswahl")
                    Text(verbatim: "\(label(section.start)) – \(label(section.end))").monospacedDigit()
                } else { Text("Keine Bereichsauswahl") }
                Spacer()
                Text("Position:Zeile").foregroundStyle(.secondary)
                Text(verbatim: label(SongAddress(position: transport.currentPosition, row: transport.currentRow))).monospacedDigit()
            }.font(.caption)
            Canvas { context, size in
                guard model.layout.totalRows > 0 else { return }
                let total = Double(model.layout.totalRows)
                if let section = model.section, let start = model.layout.index(of: section.start), let end = model.layout.index(of: section.end) {
                    let rect = CGRect(x: Double(start) / total * size.width, y: 0,
                                      width: max(2, Double(end + 1 - start) / total * size.width), height: size.height)
                    context.fill(Path(rect), with: .color(.accentColor.opacity(0.25)))
                    context.stroke(Path(rect), with: .color(.accentColor), lineWidth: 1)
                }
                var ticks = Path()
                for index in model.markerIndices {
                    let x = (Double(index) + 0.5) / total * size.width
                    ticks.move(to: CGPoint(x: x, y: 2)); ticks.addLine(to: CGPoint(x: x, y: size.height - 2))
                }
                context.stroke(ticks, with: .color(.secondary), lineWidth: 1)
                if let current = model.layout.index(of: SongAddress(position: transport.currentPosition, row: transport.currentRow)) {
                    let x = (Double(current) + 0.5) / total * size.width
                    context.fill(Path(ellipseIn: CGRect(x: x - 3, y: size.height / 2 - 3, width: 6, height: 6)), with: .color(.primary))
                }
            }
            .frame(height: 14).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 2))
            .accessibilityLabel("Songstellen und Auswahl")
            .help("Die Leiste zeigt Songpositionen und Zeilen, keine Zeitachse.")
        }
    }
    private func label(_ address: SongAddress) -> String { "\(address.position + 1):\(address.row)" }
}
#endif

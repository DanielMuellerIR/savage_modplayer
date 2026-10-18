#if canImport(SwiftUI)
import SwiftUI

public struct CollectionSyncContext: Identifiable {
    public let id = UUID()
    public let model: CollectionSyncModel
    public init(model: CollectionSyncModel) { self.model = model }
}

public struct CollectionSyncView: View {
    @ObservedObject private var model: CollectionSyncModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var choice: CollectionSyncModel.TrackChoice?
    @State private var query = ""
    @State private var unresolvedOnly = true
    public init(model: CollectionSyncModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sammlung abgleichen").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Playlists, Favoriten, Songstellen und Klang-Einstellungen werden über dein privates iCloud-Konto abgeglichen.")
                        Text("Musikdateien bleiben auf ihrem Gerät.")
                    }.font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Label(statusText, systemImage: statusIcon).font(.headline)
                        .accessibilityIdentifier("syncStatus")
                    if let date = model.lastSuccessfulSync {
                        Text("Letzter erfolgreicher Abgleich: \(date.formatted(.dateTime.day().month().year().hour().minute().locale(locale)))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if model.hasPendingChanges {
                        Text("Lokale Änderungen sind gespeichert und warten auf den Abgleich.")
                            .accessibilityIdentifier("syncPending").fixedSize(horizontal: false, vertical: true)
                    }
                    if model.cleanupPending {
                        Text("Die Daten sind übernommen. Bitte vor einer weiteren Übertragung die App neu starten.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.isConfigured {
                        Text("Für diese App-Version ist der iCloud-Abgleich noch nicht eingerichtet. Der Austausch über Dateien bleibt verfügbar.")
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("syncNotConfigured")
                    } else {
                        Toggle("Automatisch abgleichen", isOn: Binding(get: { model.isEnabled }, set: { enabled in
                            Task { if enabled { await model.beginSetup() } else { await model.disable() } }
                        })).disabled(model.isBusy).accessibilityIdentifier("syncEnabled")
                        if model.isEnabled {
                            Button("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath") {
                                Task { await model.synchronize() }
                            }.disabled(model.isBusy).accessibilityIdentifier("syncNow")
                        } else if model.status != .review {
                            Button("Abgleich einrichten…") { Task { await model.beginSetup() } }
                                .disabled(model.isBusy).accessibilityIdentifier("syncSetup")
                        }
                    }
                    if model.status == .review {
                        Text(LocalizedStringKey(model.isFirstSetup ? "Einrichtung prüfen" : "Änderungen prüfen")).font(.headline)
                        if model.isRelinking {
                            Text("Du verknüpfst die gespeicherte Sammlung mit dem aktuell angemeldeten iCloud-Konto. Der bisherige Cloud-Stand bleibt im vorherigen Konto erhalten.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Bestätige die Titelzuordnung und entscheide jeden Konflikt vor der Übernahme. Fehlende Musikdateien werden dadurch weder übertragen noch gelöscht.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if !model.tracks.isEmpty { trackChoices }
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(model.conflicts) { conflict in conflictRow(conflict) }
                        }
                        if model.tracks.isEmpty && model.conflicts.isEmpty {
                            Text("Die vorhandenen Metadaten werden zusammengeführt. Es bestehen keine Zuordnungsfragen oder Konflikte.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(LocalizedStringKey(model.isFirstSetup ? "Einrichtung bestätigen" : "Entscheidungen übernehmen")) {
                            Task { await model.confirm() }
                        }.disabled(!model.canConfirm).accessibilityIdentifier("syncConfirm")
                    }
                    if model.isBusy { ProgressView("Abgleich wird vorbereitet …").accessibilityIdentifier("syncProgress") }
                    if let error = model.error {
                        errorText(error).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier("syncError")
                        if error as? CollectionSyncError == .staleAccount {
                            Text("Melde das bisherige iCloud-Konto wieder an oder prüfe die Verknüpfung mit dem neuen Konto. Gespeicherte Änderungen werden erst nach deiner Bestätigung dorthin übertragen.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Konto neu verknüpfen…") { Task { await model.beginSetup() } }
                                .disabled(model.isBusy).accessibilityIdentifier("syncRelink")
                        }
                        Button("Erneut versuchen") {
                            Task { if model.isEnabled { await model.synchronize() } else { await model.beginSetup() } }
                        }.disabled(model.isBusy || !model.isConfigured).accessibilityIdentifier("syncRetry")
                    }
                    Text("Lautstärke, Warteschlange, Timer und Darstellung bleiben lokal. Ausschalten beendet den automatischen Abgleich und lässt die Metadaten auf diesem Gerät und in iCloud erhalten.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("syncScroll")
            HStack { Spacer(); Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("syncClose") }
        }.padding(20).buttonStyle(.bordered).lineLimit(nil)
            .task { await model.synchronize() }
            .onDisappear { model.cancelReview() }
            .sheet(item: $choice) { choice in
                CollectionSyncTrackChooser(model: model, track: choice)
                    #if os(macOS)
                    .frame(width: 600, height: 560)
                    #else
                    .presentationDetents([.large])
                    #endif
            }
    }
    private var statusText: LocalizedStringKey {
        switch model.status {
        case .off: "Automatischer Abgleich ist ausgeschaltet"
        case .notConfigured: "iCloud-Abgleich ist noch nicht eingerichtet"
        case .syncing: "Sammlung wird abgeglichen"
        case .review: "Bestätigung erforderlich"
        case .current: "Sammlung ist aktuell"
        case .waiting: "Abgleich wartet auf die Verbindung"
        case .failed: "Abgleich konnte nicht abgeschlossen werden"
        }
    }
    private var statusIcon: String {
        switch model.status {
        case .current: "checkmark.icloud"
        case .review: "person.crop.circle.badge.questionmark"
        case .failed: "exclamationmark.icloud"
        default: "icloud"
        }
    }
    private var filteredTracks: [CollectionSyncModel.TrackChoice] {
        model.tracks.filter {
            (!unresolvedOnly || model.mapping[$0.id] == nil)
                && (query.isEmpty || $0.descriptor.fileName.localizedCaseInsensitiveContains(query)
                    || ($0.descriptor.relativePath?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }
    private var trackChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Titelzuordnung: \(model.tracks.filter { model.mapping[$0.id] != nil }.count) von \(model.tracks.count) bestätigt")
                .font(.headline).accessibilityIdentifier("syncMappingSummary")
            TextField("Titel suchen", text: $query).textFieldStyle(.roundedBorder)
            Toggle("Nur offene Zuordnungen", isOn: $unresolvedOnly)
            Button("Eindeutige Vorschläge bestätigen") { Task { await model.assignUniqueSuggestions() } }
                .disabled(model.isBusy).accessibilityIdentifier("syncAssignUnique")
            ForEach(Array(filteredTracks.prefix(500))) { track in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: track.descriptor.fileName).font(.headline).lineLimit(3).truncationMode(.middle)
                    if let path = track.descriptor.relativePath { Text(verbatim: path).font(.caption).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle) }
                    if let reference = model.mapping[track.id] {
                        Text("Zugeordnet: \(reference.displayName)").lineLimit(3)
                    } else { Text("Noch keinem lokalen Titel zugeordnet").foregroundStyle(.secondary) }
                    actionLayout {
                        Button("Titel wählen…") { choice = track }.disabled(model.isBusy)
                            .accessibilityIdentifier("syncChoose-\(track.id.uuidString)")
                        if model.mapping[track.id] != nil {
                            Button("Zuordnung aufheben") { Task { await model.unassign(track.id) } }.disabled(model.isBusy)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if filteredTracks.count > 500 {
                Text("Die ersten 500 Treffer werden gezeigt. Suche gezielt oder bestätige offene Titel, um weitere Zuordnungen zu sehen.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
    }
    @ViewBuilder private func errorText(_ error: Error) -> some View {
        if case CollectionSyncError.unsupportedVersion(let version) = error {
            Text("Nicht unterstützte Abgleichversion: \(version)")
        } else if error is CollectionSyncError || error is CollectionSyncTransportError
                    || error is CollectionExchangeError || error is CollectionExchangePersistenceError {
            Text(LocalizedStringKey(error.localizedDescription))
        } else { Text(verbatim: error.localizedDescription) }
    }
    private enum Decision: Hashable { case undecided, local, remote, both }
    private func conflictRow(_ conflict: CollectionSyncConflict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(conflictTitle(conflict.id)).font(.headline)
            Text("Auf diesem Gerät: \(valueText(conflict.local))").fixedSize(horizontal: false, vertical: true)
            Text("In iCloud: \(valueText(conflict.remote))").fixedSize(horizontal: false, vertical: true)
            Picker("Entscheidung", selection: Binding<Decision>(get: {
                switch model.resolutions[conflict.id] {
                case .keepLocal: .local
                case .useRemote: .remote
                case .keepBoth: .both
                case nil: .undecided
                }
            }, set: { value in
                let resolution: CollectionSyncResolution? = switch value {
                case .undecided: nil
                case .local: .keepLocal
                case .remote: .useRemote
                case .both: .keepBoth(copyID: UUID())
                }
                model.resolve(conflict.id, with: resolution)
            })) {
                Text("Bitte wählen").tag(Decision.undecided)
                Text("Dieses Gerät behalten").tag(Decision.local)
                Text("iCloud übernehmen").tag(Decision.remote)
                if conflict.allowsKeepingBoth { Text("Beide behalten").tag(Decision.both) }
            }.disabled(model.isBusy).accessibilityIdentifier("syncConflict-\(conflict.id.sortKey)")
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func conflictTitle(_ key: CollectionSyncKey) -> LocalizedStringKey {
        switch key {
        case .playlist: "Playlist-Konflikt"
        case .marker: "Songstellen-Konflikt"
        case .favorite: "Favoriten-Konflikt"
        case .track: "Titelzuordnung-Konflikt"
        case .trackSetting(_, let field): "Titel-Einstellung: \(fieldName(field))"
        case .defaultSetting(let field): "Globale Klang-Vorgabe: \(fieldName(field))"
        }
    }
    private func fieldName(_ field: CollectionSyncField) -> String {
        switch field {
        case .palClock: String(localized: "PAL-Takt", locale: locale)
        case .stereoSeparation: String(localized: "Stereo-Trennung", locale: locale)
        case .useInterpolation: String(localized: "Interpolation", locale: locale)
        case .ledFilterActive: String(localized: "LED-Filter", locale: locale)
        }
    }
    private func valueText(_ value: CollectionSyncValue) -> String {
        switch value {
        case .playlist(let value): String(localized: "\(value.name) (\(value.trackIDs.count) Titel)", locale: locale)
        case .marker(let value): String(localized: "\(value.name) (Position \(value.address.position), Zeile \(value.address.row))", locale: locale)
        case .track(let value): value.fileName
        case .flag(let value): value ? String(localized: "Ein", locale: locale) : String(localized: "Aus", locale: locale)
        case .number(let value): value.formatted(.number.precision(.fractionLength(0...3)).locale(locale))
        case .inherit: String(localized: "Globale Vorgabe", locale: locale)
        case .deleted: String(localized: "Entfernt", locale: locale)
        }
    }
}

struct CollectionSyncTrackChooser: View {
    @ObservedObject var model: CollectionSyncModel
    let track: CollectionSyncModel.TrackChoice
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var candidates: [CollectionExchangeLocalTrack] {
        let sources = query.isEmpty ? track.suggestions : model.sources.filter {
            $0.reference.displayName.localizedCaseInsensitiveContains(query)
                || CollectionExchangeView.localSourceDescription($0.reference).localizedCaseInsensitiveContains(query)
        }
        let assigned = Set(model.mapping.filter { $0.key != track.id }.values.map(\.id))
        return sources.filter { !assigned.contains($0.reference.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lokalen Titel zuordnen").font(.title2.bold())
            Text(verbatim: track.descriptor.fileName).font(.headline).lineLimit(3).truncationMode(.middle)
            TextField("In der lokalen Sammlung suchen", text: $query).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("syncSourceSearch")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if candidates.isEmpty { Text("Keine passenden Titel. Importiere die fehlende Musik zuerst oder suche mit einem anderen Namen.") }
                    ForEach(Array(candidates.prefix(100)), id: \.reference.id) { source in
                        Button { Task { await model.assign(source, to: track.id); if model.error == nil { dismiss() } } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: source.reference.displayName).foregroundStyle(.primary).lineLimit(3).truncationMode(.middle)
                                Text(verbatim: CollectionExchangeView.localSourceDescription(source.reference)).font(.caption).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(CollectionSyncTrackButtonStyle()).accessibilityIdentifier("syncSource-\(source.reference.id)")
                    }
                    if candidates.count > 100 { Text("Die ersten 100 Treffer werden gezeigt. Bitte genauer suchen.").font(.callout).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.error {
                Text(LocalizedStringKey(error.localizedDescription)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack { Spacer(); Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("syncSourceClose") }
        }.padding(20).buttonStyle(.bordered)
    }
}

private struct CollectionSyncTrackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(12)
            .background(Color.secondary.opacity(configuration.isPressed ? 0.22 : 0.10),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}
#endif

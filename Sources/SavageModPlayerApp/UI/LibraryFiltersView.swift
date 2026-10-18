import SwiftUI
import SavageModPlayerCore

struct LibraryFiltersView: View {
    @ObservedObject var catalog: LibraryCatalogModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Anzeige und Filter").font(.title2.bold())
            Text("Die Anzeige ersetzt die laufende Wiedergabeauswahl erst mit „Diese Ergebnisse abspielen“.")
                .font(.callout).foregroundStyle(.secondary)
            if let issue = catalog.preferencesIssue {
                Text(issue == .load
                     ? "Gespeicherte Filter und Hörstatus konnten nicht geladen werden. Änderungen sind gesperrt; die Datei bleibt erhalten."
                     : "Die Bibliotheksdaten konnten nicht gespeichert werden. Der bisherige Stand bleibt erhalten.")
                    .font(.callout).foregroundStyle(.red)
            }
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gespeicherte Filter").font(.headline)
                    List(selection: $selectedID) {
                        ForEach(catalog.preferences.savedFilters) { saved in Text(saved.name).tag(saved.id) }
                    }.frame(minHeight: 180)
                    Button("Ausgewählten Filter löschen") {
                        guard let id = selectedID else { return }
                        Task { await catalog.deleteFilter(id: id); selectedID = nil }
                    }.disabled(selectedID == nil || !catalog.preferencesWritable || catalog.isSaving)
                }.frame(minWidth: 180, idealWidth: 210).padding(.trailing, 8)
                Form {
                    TextField("Datei, Titel oder Instrument", text: $catalog.query.search)
                        .accessibilityIdentifier("metadata-search")
                    Picker("Format", selection: $catalog.query.format) {
                        Text("Alle").tag(Optional<LibraryFormatFamily>.none)
                        ForEach(LibraryFormatFamily.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Stepper(value: $catalog.query.minimumChannels, in: 0...64) {
                        Text(catalog.query.minimumChannels == 0 ? "Alle Kanalzahlen" : "Mindestens \(catalog.query.minimumChannels) Kanäle")
                    }
                    Toggle("Nur Favoriten", isOn: $catalog.query.favoritesOnly)
                    Toggle("Nur ungehörte Titel", isOn: $catalog.query.unheardOnly)
                    Picker("Neu hinzugefügt", selection: $catalog.query.addedWithinDays) {
                        Text("Alle").tag(Optional<Int>.none)
                        Text("Letzte 7 Tage").tag(Optional(7))
                        Text("Letzte 30 Tage").tag(Optional(30))
                    }
                    Picker("Sortierung", selection: $catalog.query.sort) {
                        ForEach(LibrarySort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("Reihenfolge umkehren", isOn: $catalog.query.reversed)
                }.frame(minWidth: 330).padding(.leading, 12)
            }
            HStack {
                TextField("Name des Filters", text: $name).textFieldStyle(.roundedBorder)
                    .disabled(!catalog.preferencesWritable).accessibilityIdentifier("saved-filter-name")
                Button("Aktuellen Filter speichern") {
                    let value = name, query = catalog.query
                    Task { if await catalog.saveFilter(name: value, query: query) { name = "" } }
                }
                .disabled(!catalog.preferencesWritable || catalog.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("saved-filter-create")
            }
            GroupBox("Sammlung") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Indiziert: \(catalog.summary.indexed) von \(catalog.summary.total) · Fehler: \(catalog.summary.failed)")
                    Text(LibraryFormatFamily.allCases.map { "\($0.rawValue): \(catalog.summary.formats[$0] ?? 0)" }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    if catalog.summary.duplicateNameGroups > 0 {
                        Text("\(catalog.summary.duplicateNameGroups) Gruppen gleicher Dateinamen. Der Inhalt kann unterschiedlich sein.")
                            .foregroundStyle(.secondary)
                    }
                    if catalog.summary.failed > 0 {
                        DisclosureGroup("Nicht indizierbare Titel (\(catalog.summary.failed))") {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(catalog.sources.filter { catalog.records[$0.id]?.failure != nil }, id: \.id) { source in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source.displayName).fontWeight(.medium)
                                            Text(source.folderPath).font(.caption).foregroundStyle(.secondary)
                                            if let failure = catalog.records[source.id]?.failure {
                                                Text(failure.title).font(.caption)
                                            }
                                            if let detail = catalog.records[source.id]?.detail {
                                                Text(detail).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxHeight: 140)
                        }
                    }
                    LibraryIndexProgressView(status: catalog.indexStatus, cancel: catalog.cancelIndexing)
                }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Anzeige zurücksetzen") { catalog.query = LibraryQuery(); selectedID = nil }
                Button("Metadaten erneut prüfen") { catalog.refreshMetadata() }
                Spacer()
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(minWidth: 650, idealWidth: 700, minHeight: 540)
        .onChange(of: selectedID) { id in
            if let saved = catalog.preferences.savedFilters.first(where: { $0.id == id }) {
                catalog.query = saved.query
            }
        }
    }
}

struct LibraryIndexProgressView: View {
    @ObservedObject var status: LibraryCatalogStatus
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let progress = status.progress, progress.total > 0 {
                HStack {
                    Text("Metadaten: \(progress.completed)/\(progress.total)")
                    Spacer()
                    Button("Abbrechen", action: cancel).buttonStyle(.borderless)
                }
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
            }
            if status.warnings.contains(.capacityLimited) { Text("Indexgrenze erreicht; einige Metadaten fehlen.") }
            if status.warnings.contains(.cacheWriteFailed) { Text("Metadatenindex konnte nicht gesichert werden.") }
            if status.warnings.contains(.invalidSource) { Text("Einige Quellen konnten nicht indiziert werden.") }
        }
    }
}

extension LibrarySort {
    var title: String {
        switch self {
        case .sourceOrder: return "Ordnerreihenfolge"
        case .filename: return "Dateiname"
        case .title: return "Interner Modultitel"
        case .format: return "Format"
        case .channels: return "Kanalzahl"
        case .duration: return "Spieldauer"
        case .newest: return "Neueste zuerst"
        }
    }
}

extension ModuleMetadataFailure {
    var title: String {
        switch self {
        case .unavailable: return "Datei nicht erreichbar"
        case .invalidModule: return "Ungültiges Modul"
        case .oversizedFile: return "Zu groß für den Metadatenindex"
        case .changedDuringRead: return "Datei wurde während der Prüfung geändert"
        }
    }
}

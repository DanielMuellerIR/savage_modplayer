import SavageModPlayerCore
import SwiftUI

struct LibraryFiltersView: View {
    @ObservedObject var catalog: LibraryCatalogModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let issue = catalog.preferencesIssue {
                        Text(LocalizedStringKey(issue == .load ? "library.preferences.load.error" : "library.preferences.save.error"))
                            .foregroundStyle(.orange)
                    }
                    Text("library.filters.scope.hint").font(.footnote).foregroundStyle(.secondary)
                }
                Section("library.filters.selection") {
                    TextField("library.search.prompt", text: $catalog.query.search)
                        .accessibilityIdentifier("metadata-search")
                    Picker("library.filters.format", selection: $catalog.query.format) {
                        Text("library.filters.any").tag(Optional<LibraryFormatFamily>.none)
                        ForEach(LibraryFormatFamily.allCases, id: \.self) {
                            Text(verbatim: $0.rawValue).tag(Optional($0))
                        }
                    }
                    Stepper(value: $catalog.query.minimumChannels, in: 0...64) {
                        if catalog.query.minimumChannels == 0 { Text("library.filters.channels.any") }
                        else { Text("library.filters.channels \(catalog.query.minimumChannels)") }
                    }
                    Toggle("library.filter.favorites", isOn: $catalog.query.favoritesOnly)
                    Toggle("library.filters.unheard", isOn: $catalog.query.unheardOnly)
                    Picker("library.filters.recent", selection: $catalog.query.addedWithinDays) {
                        Text("library.filters.any").tag(Optional<Int>.none)
                        Text("library.filters.recent.7").tag(Optional(7))
                        Text("library.filters.recent.30").tag(Optional(30))
                    }
                }
                Section("library.sort.title") {
                    Picker("library.sort.title", selection: $catalog.query.sort) {
                        ForEach(LibrarySort.allCases, id: \.self) { value in
                            Text(value.localizedTitle).tag(value)
                        }
                    }
                    Toggle("library.sort.reverse", isOn: $catalog.query.reversed)
                    Button("library.filters.reset") { catalog.query = LibraryQuery() }
                }
                Section("library.filters.saved") {
                    ForEach(catalog.preferences.savedFilters) { saved in
                        Button(saved.name) { catalog.query = saved.query }
                            .swipeActions {
                                Button("library.filters.delete", role: .destructive) {
                                    Task { await catalog.deleteFilter(id: saved.id) }
                                }
                                .disabled(!catalog.preferencesWritable || catalog.isSaving)
                            }
                    }
                    TextField("library.filters.name", text: $name)
                        .disabled(!catalog.preferencesWritable)
                        .accessibilityIdentifier("saved-filter-name")
                    Button("library.filters.save", systemImage: "plus") {
                        let value = name
                        let query = catalog.query
                        Task { if await catalog.saveFilter(name: value, query: query) { name = "" } }
                    }
                    .disabled(!catalog.preferencesWritable || catalog.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(!catalog.preferencesWritable || catalog.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? Color.secondary : Color.accentColor)
                    .accessibilityIdentifier("saved-filter-create")
                }
                Section("library.collection.title") {
                    Text("library.collection.indexed \(catalog.summary.indexed) \(catalog.summary.total)")
                    ForEach(LibraryFormatFamily.allCases, id: \.self) { family in
                        if let count = catalog.summary.formats[family] {
                            LabeledContent(family.rawValue, value: String(count))
                        }
                    }
                    if catalog.summary.duplicateNameGroups > 0 {
                        Text("library.collection.names \(catalog.summary.duplicateNameGroups)")
                            .foregroundStyle(.secondary)
                        Text("library.collection.names.hint").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(catalog.sources.filter { catalog.records[$0.id]?.failure != nil }, id: \.id) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: source.displayName)
                            Text(verbatim: source.folderPath).font(.caption).foregroundStyle(.secondary)
                            if let failure = catalog.records[source.id]?.failure { Text(failure.localizedTitle).font(.caption) }
                            if let detail = catalog.records[source.id]?.detail { Text(verbatim: detail).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    LibraryIndexProgressView(catalog: catalog)
                    Button("library.metadata.refresh") { catalog.refreshMetadata() }
                        .disabled(catalog.progress != nil)
                }
            }
            .navigationTitle("library.filters.title")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() } } }
        }
    }
}

struct LibraryIndexProgressView: View {
    let catalog: LibraryCatalogModel
    var body: some View { Content(status: catalog.indexStatus, cancel: catalog.cancelIndexing) }
    private struct Content: View {
        @ObservedObject var status: LibraryCatalogStatus
        let cancel: () -> Void
        var body: some View {
            if let progress = status.progress, progress.total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("library.metadata.progress \(progress.completed) \(progress.total)").font(.caption)
                        Spacer()
                        Button("common.cancel", action: cancel).font(.caption)
                    }
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                }
            }
            if status.warnings.contains(.capacityLimited) { Text("library.metadata.limit").font(.caption).foregroundStyle(.orange) }
            if status.warnings.contains(.cacheWriteFailed) { Text("library.metadata.save.error").font(.caption).foregroundStyle(.orange) }
            if status.warnings.contains(.invalidSource) { Text("library.metadata.source.error").font(.caption).foregroundStyle(.orange) }
        }
    }
}

extension LibrarySort {
    var localizedTitle: LocalizedStringKey { LocalizedStringKey("library.sort." + (self == .title ? "moduleTitle" : rawValue)) }
}
extension ModuleMetadataFailure {
    var localizedTitle: LocalizedStringKey { LocalizedStringKey("library.metadata.failure." + rawValue) }
}
extension ModuleMetadata {
    var librarySummary: String {
        let seconds = max(0, Int(durationSeconds.rounded()))
        let duration = (durationIsLimited ? "≥" : "") + String(format: "%d:%02d", seconds / 60, seconds % 60)
        return [format.libraryFamily.rawValue, "\(channelCount)ch", duration, title].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

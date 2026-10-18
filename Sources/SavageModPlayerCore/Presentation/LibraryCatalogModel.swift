#if canImport(Combine)
import Combine
import Foundation

public struct LibraryCatalogSource: Sendable {
    public let id: String
    public let url: URL
    public let displayName: String
    public let folderPath: String
    public let addedAt: Date?
    public init(id: String, url: URL, displayName: String, folderPath: String, addedAt: Date? = nil) {
        self.id = id; self.url = url; self.displayName = displayName
        self.folderPath = folderPath; self.addedAt = addedAt
    }
}

public struct LibraryCatalogSummary: Sendable {
    public var total = 0
    public var indexed = 0
    public var failed = 0
    public var duplicateNameGroups = 0
    public var formats: [LibraryFormatFamily: Int] = [:]
}

public enum LibraryPreferencesIssue: Sendable { case load, save }

@MainActor
public final class LibraryCatalogStatus: ObservableObject {
    @Published public fileprivate(set) var progress: ModuleMetadataProgress?
    @Published public fileprivate(set) var warnings: [ModuleMetadataWarning] = []
}

// Optionale native Bindung; die Library-Typen selbst bleiben ohne Combine.
@MainActor
public final class LibraryCatalogModel: ObservableObject {
    @Published public var query = LibraryQuery() {
        didSet { if query != oldValue { scheduleFilter() } }
    }
    @Published public private(set) var records: [String: ModuleMetadataRecord] = [:]
    @Published public private(set) var preferences = LibraryPreferencesDocument()
    @Published public private(set) var preferencesLoaded = false
    @Published public private(set) var preferencesWritable = true
    @Published public private(set) var preferencesIssue: LibraryPreferencesIssue?
    @Published public private(set) var filteredIDs: [String] = []
    @Published public private(set) var isFiltering = false
    @Published public private(set) var isSaving = false
    public let indexStatus = LibraryCatalogStatus()
    public var progress: ModuleMetadataProgress? { indexStatus.progress }
    public var indexWarnings: [ModuleMetadataWarning] { indexStatus.warnings }
    @Published public private(set) var summary = LibraryCatalogSummary()
    public private(set) var sources: [LibraryCatalogSource] = []
    private var favoriteIDs: Set<String> = []
    private let index: ModuleMetadataIndex
    private let store: LibraryPreferencesStore
    private var preferencesRevision: UInt64 = 0
    private var metadataTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var metadataRequest = UUID()
    private var filterRequest = UUID()

    public init(metadataURL: URL, preferencesURL: URL) {
        index = try! ModuleMetadataIndex(cacheURL: metadataURL, durationLimit: 600)
        store = LibraryPreferencesStore(fileURL: preferencesURL)
        Task { [weak self, store] in
            do { self?.accept(try await store.snapshot()) }
            catch { self?.preferencesIssue = .load; self?.preferencesWritable = false }
        }
    }

    deinit { metadataTask?.cancel(); filterTask?.cancel() }

    public func setSources(_ values: [LibraryCatalogSource]) {
        var seen: Set<String> = []
        sources = values.filter { seen.insert($0.id).inserted }
        refreshSummary()
        scheduleFilter()
        refreshMetadata()
    }

    public func setFavorites(_ ids: Set<String>) {
        guard favoriteIDs != ids else { return }
        favoriteIDs = ids
        if query.favoritesOnly { scheduleFilter() }
    }

    public func refreshMetadata() {
        metadataTask?.cancel()
        let request = UUID(); metadataRequest = request
        let sources = sources, index = index, store = store
        indexStatus.progress = ModuleMetadataProgress(completed: 0, total: sources.count)
        let relay = CatalogProgressRelay()
        metadataTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.accept(try await store.snapshot())
                let now = Date()
                let dates = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.addedAt ?? now) })
                self.accept(try await store.registerSources(dates))
            } catch {
                self.preferencesIssue = self.preferencesLoaded ? .save : .load
                if !self.preferencesLoaded { self.preferencesWritable = false }
            }
            guard !Task.isCancelled, request == self.metadataRequest else { return }
            let inputs = sources.map { ModuleMetadataInput(id: $0.id, url: $0.url) }
            let result = await index.refresh(inputs, progress: { [weak self] value in
                guard relay.shouldDeliver() || value.completed == value.total else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.metadataRequest == request, self.metadataTask != nil else { return }
                    self.indexStatus.progress = value
                }
            })
            guard request == self.metadataRequest else { return }
            self.records = result.records
            self.indexStatus.warnings = result.warnings
            self.indexStatus.progress = nil
            self.metadataTask = nil
            self.refreshSummary()
            self.scheduleFilter()
        }
    }

    public func cancelIndexing() { metadataTask?.cancel(); metadataTask = nil; indexStatus.progress = nil }

    public func markHeard(_ id: String, heard: Bool = true) {
        guard preferencesWritable else { return }
        Task { [weak self, store] in
            do { self?.accept(try await store.markHeard(id, heard: heard)) }
            catch { self?.preferencesIssue = self?.preferencesLoaded == true ? .save : .load }
        }
    }

    @discardableResult
    public func saveFilter(name: String, query: LibraryQuery) async -> Bool {
        guard preferencesWritable, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let saved = SavedLibraryFilter(name: name, query: query)
        do {
            accept(try await store.update { $0.savedFilters.append(saved) })
            return true
        } catch { preferencesIssue = .save; return false }
    }

    public func deleteFilter(id: UUID) async {
        guard preferencesWritable, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do { accept(try await store.update { $0.savedFilters.removeAll { $0.id == id } }) }
        catch { preferencesIssue = .save }
    }

    private func accept(_ snapshot: LibraryPreferencesStore.Snapshot) {
        guard snapshot.revision >= preferencesRevision else { return }
        guard !preferencesLoaded || snapshot.revision > preferencesRevision else { return }
        let needsFilter = !preferencesLoaded || query.unheardOnly
            || query.addedWithinDays != nil || query.sort == .newest
        preferencesRevision = snapshot.revision
        preferences = snapshot.document
        preferencesLoaded = true
        preferencesWritable = true
        preferencesIssue = nil
        if needsFilter { scheduleFilter() }
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        let request = UUID(); filterRequest = request
        if !query.usesFlatList {
            filteredIDs = sources.map(\.id)
            isFiltering = false
            return
        }
        isFiltering = true
        let sources = sources, records = records, preferences = preferences
        let knownPreferences = preferencesLoaded, favorites = favoriteIDs, query = query
        filterTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                let items = sources.map {
                    LibraryQueryItem(id: $0.id, displayName: $0.displayName, folderPath: $0.folderPath,
                                     metadata: records[$0.id]?.metadata,
                                     addedAt: preferences.firstSeenAt[$0.id] ?? $0.addedAt,
                                     isFavorite: favorites.contains($0.id),
                                     wasPlayed: knownPreferences ? preferences.heardIDs.contains($0.id) : nil)
                }
                let ids = try query.selectIDs(from: items)
                await MainActor.run { [weak self] in
                    guard let self, self.filterRequest == request else { return }
                    self.filteredIDs = ids
                    self.isFiltering = false
                }
            } catch { }
        }
    }

    private func refreshSummary() {
        var value = LibraryCatalogSummary()
        value.total = sources.count
        var names: [String: Int] = [:]
        for source in sources {
            names[source.displayName.lowercased(), default: 0] += 1
            if let metadata = records[source.id]?.metadata {
                value.indexed += 1
                value.formats[metadata.format.libraryFamily, default: 0] += 1
            } else if records[source.id]?.failure != nil { value.failed += 1 }
        }
        value.duplicateNameGroups = names.values.filter { $0 > 1 }.count
        summary = value
    }
}

private final class CatalogProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    func shouldDeliver() -> Bool {
        lock.withLock {
            let now = Date()
            guard now.timeIntervalSince(last) >= 0.1 else { return false }
            last = now
            return true
        }
    }
}
#endif

#if canImport(Combine)
import Combine
import Foundation

@MainActor
public final class SongMarkersModel: ObservableObject {
    public enum Issue: Sendable { case load, save }
    @Published public private(set) var sourceID: String?
    @Published public private(set) var contextID = UUID()
    @Published public private(set) var title = ""
    @Published public private(set) var layout = SongPositionLayout(module: Mod(name: "", length: 0, patternTable: [], instruments: [], patterns: []))
    @Published public private(set) var markers: [SongMarker] = []
    public private(set) var markerRowsByPosition: [Int: Set<Int>] = [:]
    public private(set) var markerIndices: Set<Int> = []
    @Published public private(set) var isLoaded = false
    @Published public private(set) var isSaving = false
    @Published public private(set) var issue: Issue?
    @Published public private(set) var start: SongAddress?
    @Published public private(set) var end: SongAddress?
    public var section: SongSection? {
        guard let start, let end, layout.contains(start), layout.contains(end) else { return nil }
        return SongSection(start: start, end: end)
    }
    public var isSelectionInvalid: Bool { start != nil && end != nil && section == nil }
    public var canSave: Bool { isLoaded && issue != .load && sourceID != nil && !isSaving }
    private var store: SongMarkerStore
    private let fileURL: URL
    private var generation = UUID()
    private var document = SongMarkerDocument()
    private var revision: UInt64 = 0
    public private(set) var moduleID: UUID?
    public let metadataDidChange = PassthroughSubject<Void, Never>()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        store = SongMarkerStore(fileURL: fileURL)
        Task { [weak self] in
            guard let self else { return }
            let token = generation, store = store
            do {
                let snapshot = try await store.snapshot()
                guard generation == token else { return }
                accept(snapshot)
            }
            catch { if generation == token { issue = .load; isLoaded = true } }
        }
    }
    public func adoptCommitted(_ document: SongMarkerDocument) {
        guard !isSaving else { return }
        generation = UUID(); store = SongMarkerStore(fileURL: fileURL)
        self.document = document; revision = 0; isLoaded = true; issue = nil; refreshMarkers()
    }
    public func setContext(sourceID: String?, module: Mod?, moduleID: UUID?) {
        guard self.sourceID != sourceID || self.moduleID != moduleID else { return }
        self.sourceID = sourceID; self.moduleID = moduleID; title = module?.name ?? ""
        if let module { layout = SongPositionLayout(module: module) }
        else { layout = SongPositionLayout(module: Mod(name: "", length: 0, patternTable: [], instruments: [], patterns: [])) }
        start = nil; end = nil; contextID = UUID(); refreshMarkers()
    }
    public func setBoundary(_ address: SongAddress, isStart: Bool) {
        guard layout.contains(address) else { return }
        if isStart { start = address } else { end = address }
    }
    public func clearSelection() { start = nil; end = nil }
    public func save(name: String, address: SongAddress, editingID: UUID? = nil) async -> Bool {
        guard canSave, let sourceID, layout.contains(address) else { return false }
        let marker = SongMarker(sourceID: sourceID, name: name, address: address)
        isSaving = true
        var saved = false
        defer { isSaving = false; if saved { metadataDidChange.send() } }
        do {
            let snapshot = try await store.update { document in
                if let editingID {
                    guard let index = document.markers.firstIndex(where: { $0.id == editingID && $0.sourceID == sourceID }) else {
                        throw SongMarkerStoreError.invalidDocument
                    }
                    document.markers[index].name = marker.name
                    document.markers[index].address = marker.address
                } else { document.markers.append(marker) }
            }
            accept(snapshot); saved = true; return true
        } catch { issue = .save; return false }
    }
    public func delete(id: UUID) async {
        guard canSave, let sourceID else { return }
        isSaving = true
        var saved = false
        defer { isSaving = false; if saved { metadataDidChange.send() } }
        do {
            accept(try await store.update { $0.markers.removeAll { $0.id == id && $0.sourceID == sourceID } })
            saved = true
        } catch { issue = .save }
    }
    private func accept(_ snapshot: SongMarkerStore.Snapshot) {
        guard !isLoaded || snapshot.revision >= revision else { return }
        revision = snapshot.revision; document = snapshot.document; isLoaded = true; issue = nil
        refreshMarkers()
    }
    private func refreshMarkers() {
        markers = document.markers.filter { $0.sourceID == sourceID }.sorted {
            $0.address != $1.address ? $0.address < $1.address : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        markerRowsByPosition = [:]; markerIndices = []
        for marker in markers {
            guard let index = layout.index(of: marker.address) else { continue }
            markerRowsByPosition[marker.address.position, default: []].insert(marker.address.row)
            markerIndices.insert(index)
        }
    }
}
#endif

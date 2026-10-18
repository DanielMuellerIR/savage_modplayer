#if canImport(Combine)
import Foundation
import Combine

@MainActor
public final class CollectionExchangeModel: ObservableObject {
    public struct State: Sendable {
        public let snapshot: CollectionExchangeSnapshot
        public let sources: [CollectionExchangeLocalTrack]
        public init(snapshot: CollectionExchangeSnapshot, sources: [CollectionExchangeLocalTrack]) {
            self.snapshot = snapshot; self.sources = sources
        }
    }
    public enum Completion: Equatable { case imported, cleanupPending, exported }
    @Published public private(set) var state: State?
    @Published public private(set) var incoming: CollectionExchangeDocument?
    @Published public private(set) var sourceFileName: String?
    @Published public private(set) var mapping: [UUID: PlaylistTrackReference] = [:]
    @Published public private(set) var skipped: Set<UUID> = []
    @Published public private(set) var resolutions: [CollectionExchangeConflictID: CollectionExchangeResolution] = [:]
    @Published public private(set) var preview: CollectionExchangeImportPreview?
    @Published public private(set) var visibleTracks: [ExchangeTrack] = []
    @Published public private(set) var matchingTrackCount = 0
    @Published public private(set) var isBusy = false
    @Published public private(set) var error: Error?
    @Published public private(set) var completion: Completion?
    @Published public var query = "" { didSet { filterTracks() } }
    @Published public var unresolvedOnly = false { didSet { filterTracks() } }
    public nonisolated static let maximumVisibleRows = 500
    @Published public private(set) var isApplying = false
    @Published public private(set) var isFiltering = false
    public var isReady: Bool { !isBusy && !isFiltering && preview?.isReady == true && completion == nil && error == nil }
    private let capture: @MainActor () async throws -> State
    private let apply: @MainActor (CollectionExchangeImportPreview) async throws -> Bool
    private let read: @Sendable (URL, @escaping @Sendable () -> Bool) throws -> CollectionExchangeDocument
    private var task: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var filterRequest = UUID()
    private var request = UUID()
    private var matches: [UUID: ExchangeTrackMatch] = [:]
    private var sourcesByID: [String: CollectionExchangeLocalTrack] = [:]
    private var allTracks: [ExchangeTrack] = []
    private var tracksByID: [UUID: ExchangeTrack] = [:]
    private var readingCancellation: ReadingCancellation?
    private final class ReadingCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        func isCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    public init(capture: @escaping @MainActor () async throws -> State,
                apply: @escaping @MainActor (CollectionExchangeImportPreview) async throws -> Bool,
                read: @escaping @Sendable (URL, @escaping @Sendable () -> Bool) throws -> CollectionExchangeDocument = { url, cancelled in
                    try CollectionExchangeCodec.load(from: url, isCancelled: cancelled)
                }) {
        self.capture = capture; self.apply = apply; self.read = read
    }
    deinit { task?.cancel(); filterTask?.cancel(); readingCancellation?.cancel() }

    public func load() async {
        guard !isBusy else { return }
        isBusy = true; error = nil; completion = nil
        let token = UUID(); request = token
        do {
            let state = try await capture()
            guard !Task.isCancelled, request == token else { throw CancellationError() }
            try state.snapshot.validate()
            guard state.sources.count <= CollectionExchangeCodec.maximumTracks,
                  Set(state.sources.map { $0.reference.id }).count == state.sources.count else { throw CollectionExchangeError.invalidMapping }
            self.state = state; sourcesByID = Dictionary(uniqueKeysWithValues: state.sources.map { ($0.reference.id, $0) })
            isBusy = false
            if let incoming { try await receive(incoming) }
        } catch {
            guard request == token else { return }
            if !(error is CancellationError) { self.error = error }
            isBusy = false
        }
    }

    public func loadFile(_ url: URL) async {
        guard !isBusy, state != nil else { return }
        isBusy = true; error = nil; completion = nil
        incoming = nil; preview = nil; mapping = [:]; skipped = []; resolutions = [:]; allTracks = []; filterTracks()
        sourceFileName = url.lastPathComponent; tracksByID = [:]
        let token = UUID(); request = token
        let cancellation = ReadingCancellation(); readingCancellation = cancellation
        let read = read
        do {
            let document = try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) { try read(url, { cancellation.isCancelled() }) }.value
            } onCancel: { cancellation.cancel() }
            guard !Task.isCancelled, !cancellation.isCancelled(), request == token else { throw CancellationError() }
            readingCancellation = nil
            isBusy = false; try await receive(document)
        } catch {
            guard request == token else { return }
            readingCancellation = nil
            if !(error is CancellationError) { self.error = error }
            isBusy = false
        }
    }

    public func receive(_ document: CollectionExchangeDocument) async throws {
        guard let state else { throw CollectionExchangeError.invalidLocalState }
        task?.cancel(); let token = UUID(); request = token; isBusy = true; error = nil; completion = nil
        do {
            let matches = try await Task.detached(priority: .userInitiated) {
                try CollectionExchangeMatcher.match(document, against: state.sources)
            }.value
            guard !Task.isCancelled, request == token else { throw CancellationError() }
            incoming = document; self.matches = matches
            tracksByID = Dictionary(uniqueKeysWithValues: document.tracks.map { ($0.id, $0) })
            mapping = [:]; skipped = []; resolutions = [:]; preview = nil
            allTracks = []; filterTracks()
            let automatic = document.tracks.compactMap { track -> (UUID, String)? in
                if case .matched(let id) = matches[track.id] { return (track.id, id) }; return nil
            }
            let counts = Dictionary(grouping: automatic, by: { $0.1 }).mapValues(\.count)
            for (trackID, sourceID) in automatic where counts[sourceID] == 1 {
                mapping[trackID] = sourcesByID[sourceID]?.reference
            }
            isBusy = false; recompute()
        } catch {
            if request == token {
                if !(error is CancellationError) { self.error = error }
                isBusy = false
            }
            throw error
        }
    }

    public func suggestions(for trackID: UUID) -> [CollectionExchangeLocalTrack] {
        switch matches[trackID] {
        case .matched(let id): return sourcesByID[id].map { [$0] } ?? []
        case .ambiguous(let ids, _): return ids.compactMap { sourcesByID[$0] }
        default: return []
        }
    }
    public func source(withID id: String) -> CollectionExchangeLocalTrack? { sourcesByID[id] }
    public func track(withID id: UUID) -> ExchangeTrack? { tracksByID[id] }
    public func suggestionCount(for trackID: UUID) -> Int {
        if case .ambiguous(_, let count) = matches[trackID] { return count }
        return suggestions(for: trackID).count
    }
    public func isAssignedElsewhere(_ sourceID: String, than trackID: UUID) -> Bool {
        mapping.contains { $0.key != trackID && $0.value.id == sourceID }
    }
    public func assign(_ source: CollectionExchangeLocalTrack, to trackID: UUID) {
        guard !isBusy, incoming?.tracks.contains(where: { $0.id == trackID }) == true,
              sourcesByID[source.reference.id] != nil, !isAssignedElsewhere(source.reference.id, than: trackID) else { return }
        mapping[trackID] = source.reference; skipped.remove(trackID); resolutions = [:]; recompute()
    }
    public func skip(_ trackID: UUID) {
        guard !isBusy, incoming?.tracks.contains(where: { $0.id == trackID }) == true else { return }
        mapping.removeValue(forKey: trackID); skipped.insert(trackID); resolutions = [:]; recompute()
    }
    public func skipUnresolved() {
        guard !isBusy, let incoming else { return }
        for track in incoming.tracks where mapping[track.id] == nil { skipped.insert(track.id) }
        resolutions = [:]; recompute()
    }
    public func resolve(_ conflict: CollectionExchangeConflictID, with value: CollectionExchangeResolution?) {
        guard !isBusy else { return }
        resolutions[conflict] = value; recompute()
    }
    public func exportData() async throws -> Data {
        guard !isBusy, let state else { throw CollectionExchangeError.invalidLocalState }
        isBusy = true; error = nil
        let token = UUID(); request = token
        defer { if request == token { isBusy = false } }
        let fresh = try await capture()
        guard fresh.snapshot == state.snapshot else { throw CollectionExchangeError.stalePreview }
        let data = try await Task.detached(priority: .userInitiated) {
            try CollectionExchangeCodec.encode(CollectionExchangeExporter.makeDocument(from: fresh.snapshot, sources: fresh.sources))
        }.value
        guard !Task.isCancelled, request == token else { throw CancellationError() }
        return data
    }
    public func applyImport() async {
        guard isReady, let preview else { return }
        isBusy = true; isApplying = true; error = nil
        do { completion = try await apply(preview) ? .cleanupPending : .imported }
        catch { self.error = error }
        isBusy = false; isApplying = false
    }
    public func exported() { completion = .exported; error = nil }
    public func report(_ error: Error) { self.error = error }
    public func cancel() {
        task?.cancel(); filterTask?.cancel(); filterRequest = UUID(); isFiltering = false
        readingCancellation?.cancel(); readingCancellation = nil; request = UUID()
        if !isApplying { isBusy = false }
    }

    private func recompute() {
        task?.cancel()
        guard let incoming, let state else { return }
        let token = UUID(); request = token
        let mapping = mapping, skipped = skipped, resolutions = resolutions
        isBusy = true; error = nil; preview = nil
        task = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let preview = try CollectionExchangeImporter.preview(incoming, into: state.snapshot, mapping: mapping,
                                                                         skippedTrackIDs: skipped, resolutions: resolutions)
                    let tracks = incoming.tracks.sorted {
                        let left = mapping[$0.id] == nil && !skipped.contains($0.id), right = mapping[$1.id] == nil && !skipped.contains($1.id)
                        if left != right { return left }
                        if $0.descriptor.fileName != $1.descriptor.fileName { return $0.descriptor.fileName < $1.descriptor.fileName }
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return (preview, tracks)
                }.value
                guard let self, !Task.isCancelled, request == token else { return }
                preview = result.0; isBusy = false; allTracks = result.1
                filterTracks()
            } catch {
                guard let self, !Task.isCancelled, request == token else { return }
                self.error = error; isBusy = false
            }
        }
    }
    private func filterTracks() {
        filterTask?.cancel()
        let token = UUID(); filterRequest = token
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tracks = allTracks, unresolved = unresolvedOnly, mapping = mapping, skipped = skipped
        if tracks.isEmpty { matchingTrackCount = 0; visibleTracks = []; isFiltering = false; return }
        isFiltering = true
        filterTask = Task { [weak self] in
            do {
                if !query.isEmpty { try await Task.sleep(for: .milliseconds(120)) }
                let result = await Task.detached(priority: .userInitiated) {
                    let filtered = tracks.filter {
                        (!unresolved || (mapping[$0.id] == nil && !skipped.contains($0.id)))
                            && (query.isEmpty || ($0.descriptor.fileName + " " + ($0.descriptor.relativePath ?? "")
                                + " " + $0.descriptor.archiveMembers.joined(separator: " ")).localizedCaseInsensitiveContains(query))
                    }
                    return (filtered.count, Array(filtered.prefix(Self.maximumVisibleRows)))
                }.value
                guard let self, !Task.isCancelled, filterRequest == token else { return }
                matchingTrackCount = result.0; visibleTracks = result.1; isFiltering = false
            } catch { }
        }
    }
}
#endif

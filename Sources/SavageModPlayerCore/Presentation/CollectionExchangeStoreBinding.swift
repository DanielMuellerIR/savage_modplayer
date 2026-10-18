#if canImport(Combine)
import Foundation

@MainActor
public final class CollectionExchangeStoreBinding {
    public struct Capture: Sendable {
        public let snapshot: CollectionExchangeSnapshot
        public let sources: [CollectionExchangeLocalTrack]
        public let disk: CollectionExchangeDiskSnapshot
        public let preferences: Data
    }
    public struct StoredResult {
        public let documents: CollectionExchangeStoredDocuments
        public let preferences: [String: Any]
        public init(documents: CollectionExchangeStoredDocuments, preferences: [String: Any]) {
            self.documents = documents; self.preferences = preferences
        }
    }
    private let persistence: CollectionExchangePersistence
    private let preferences: CollectionExchangePreferences
    private let normalize: @MainActor (CollectionExchangeStoredDocuments, Data) throws -> CollectionExchangeSnapshot
    private let encode: @MainActor (CollectionExchangeSnapshot, CollectionExchangeStoredDocuments, Data) throws -> StoredResult
    private let available: @MainActor (CollectionExchangeSnapshot) -> [CollectionExchangeResolvedTrack]
    private let libraryRoot: URL?
    private let canCapture: @MainActor () -> Bool
    private let adopt: @MainActor (CollectionExchangeStoredDocuments, CollectionExchangeSnapshot) -> Void
    private let recoveryFailed: @MainActor (Error) -> Void

    public init(persistence: CollectionExchangePersistence, preferences: CollectionExchangePreferences,
                normalize: @escaping @MainActor (CollectionExchangeStoredDocuments, Data) throws -> CollectionExchangeSnapshot,
                encode: @escaping @MainActor (CollectionExchangeSnapshot, CollectionExchangeStoredDocuments, Data) throws -> StoredResult,
                available: @escaping @MainActor (CollectionExchangeSnapshot) -> [CollectionExchangeResolvedTrack], libraryRoot: URL? = nil,
                canCapture: @escaping @MainActor () -> Bool,
                adopt: @escaping @MainActor (CollectionExchangeStoredDocuments, CollectionExchangeSnapshot) -> Void,
                recoveryFailed: @escaping @MainActor (Error) -> Void = { _ in }) {
        self.persistence = persistence; self.preferences = preferences; self.normalize = normalize; self.encode = encode
        self.available = available; self.libraryRoot = libraryRoot; self.canCapture = canCapture
        self.adopt = adopt; self.recoveryFailed = recoveryFailed
    }

    public func makeModel(read: (@Sendable (URL, @escaping @Sendable () -> Bool) throws -> CollectionExchangeDocument)? = nil) -> CollectionExchangeModel {
        CollectionExchangeModel(capture: { try await self.capture() }, apply: { try await self.apply($0) },
                                read: read ?? { url, cancelled in try CollectionExchangeCodec.load(from: url, isCancelled: cancelled) })
    }

    private func capture() async throws -> CollectionExchangeModel.State {
        let capture = try await captureStorage()
        return .init(snapshot: capture.snapshot, sources: capture.sources)
    }

    public func captureStorage() async throws -> Capture {
        try await readStorage(includeSources: true)
    }

    private func readStorage(includeSources: Bool) async throws -> Capture {
        guard canCapture() else { throw CollectionExchangePersistenceError.busy }
        let recovery: CollectionExchangePersistence.Recovery
        do { recovery = try persistence.recover { try preferences.replace(expected: $0, replacement: $1) } }
        catch { recoveryFailed(error); throw error }
        let persistence = persistence
        let disk = try await Task.detached(priority: .userInitiated) { try persistence.snapshot() }.value
        try Task.checkCancellation()
        guard canCapture() else { throw CollectionExchangePersistenceError.busy }
        let auxiliary = try preferences.capture()
        let snapshot = try normalize(disk.documents, auxiliary)
        if recovery == .rolledBack || recovery == .completed { adopt(disk.documents, snapshot) }
        guard includeSources else { return .init(snapshot: snapshot, sources: [], disk: disk, preferences: auxiliary) }
        let available = available(snapshot), root = libraryRoot
        let worker = Task.detached(priority: .userInitiated) {
            try CollectionExchangeSources.make(snapshot: snapshot, available: available, libraryRoot: root, isCancelled: { Task.isCancelled })
        }
        let sources = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return .init(snapshot: snapshot, sources: sources, disk: disk, preferences: auxiliary)
    }

    private func apply(_ preview: CollectionExchangeImportPreview) async throws -> Bool {
        let captured = try await readStorage(includeSources: false)
        let candidate = try preview.result(ifUnchanged: captured.snapshot)
        if candidate == captured.snapshot { adopt(captured.disk.documents, captured.snapshot); return false }
        return try commit(candidate, replacing: captured) == .cleanupPending
    }

    @discardableResult
    public func commit(_ candidate: CollectionExchangeSnapshot, replacing captured: Capture,
                       syncState: Data? = nil, adoptMetadata: Bool = true) throws -> CollectionExchangePersistence.CommitResult {
        guard canCapture() else { throw CollectionExchangePersistenceError.busy }
        try Task.checkCancellation()
        try candidate.validate()
        let encoded = try encode(candidate, captured.disk.documents, captured.preferences)
        var documents = encoded.documents
        documents.syncState = syncState
        let after = try preferences.assigning(encoded.preferences, to: captured.preferences)
        let result: CollectionExchangePersistence.CommitResult
        do {
            result = try persistence.commit(documents, replacing: captured.disk,
                auxiliaryBefore: captured.preferences, auxiliaryAfter: after) {
                try preferences.replace(expected: $0, replacement: $1)
            }
        } catch CollectionExchangePersistenceError.recoveryRequired {
            recoveryFailed(CollectionExchangePersistenceError.recoveryRequired)
            throw CollectionExchangePersistenceError.recoveryRequired
        }
        if adoptMetadata { adopt(documents, candidate) }
        return result
    }

    public func storedPreferenceValues(in captured: Capture) throws -> [String: Any] {
        try preferences.values(in: captured.preferences)
    }

    public func preferenceValues(after candidate: CollectionExchangeSnapshot, replacing captured: Capture) throws -> [String: Any] {
        let encoded = try encode(candidate, captured.disk.documents, captured.preferences)
        return try preferences.values(in: preferences.assigning(encoded.preferences, to: captured.preferences))
    }
}
#endif

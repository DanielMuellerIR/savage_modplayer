import Foundation

// Enthält gerätelokale URLs. Nur CollectionSyncSnapshot darf als Cloud-Asset
// veröffentlicht werden; dieser gemeinsame Neustartstand bleibt auf dem Gerät.
public struct CollectionSyncLocalState: Codable, Equatable, Sendable {
    public static let identifier = "org.savage-mod-player.collection-sync-local-state"
    public var format = Self.identifier
    public var schemaVersion = 1
    public private(set) var checkpoint: CollectionSyncCheckpoint
    public private(set) var registry: CollectionSyncTrackRegistry

    public init(checkpoint: CollectionSyncCheckpoint, registry: CollectionSyncTrackRegistry) {
        self.checkpoint = checkpoint
        self.registry = registry
    }

    public func validate() throws {
        guard format == Self.identifier else { throw CollectionSyncError.invalidCheckpoint }
        guard schemaVersion == 1 else {
            throw CollectionSyncError.unsupportedVersion(schemaVersion)
        }
        try checkpoint.validate()
        try registry.validate(completing: checkpoint.account)
        guard registry.collectionID == checkpoint.local.collectionID else {
            throw CollectionSyncError.mismatchedCollection
        }
        guard registry.generation == checkpoint.local.generation else {
            throw CollectionSyncError.staleGeneration
        }
        guard
            checkpoint.local.mappingRequirements().required.isSubset(
                of: Set(registry.bindings.map(\.id)))
        else {
            throw CollectionExchangeError.unmappedSources
        }
    }

    public func applying(
        _ changes: [CollectionSyncCell],
        registry updatedRegistry: CollectionSyncTrackRegistry? = nil,
        ifUnchanged expected: CollectionSyncSnapshot,
        account token: CollectionSyncAccountToken
    ) throws -> Self {
        try validate()
        try checkpoint.validate(completing: token)
        try expected.validate()
        guard expected.collectionID == checkpoint.local.collectionID,
            expected.generation == checkpoint.local.generation,
            expected.indexed() == checkpoint.local.indexed()
        else { throw CollectionSyncError.stalePreview }
        guard changes.count <= CollectionSyncCodec.maximumCells else {
            throw CollectionSyncError.oversized
        }
        guard Set(changes.map(\.id)).count == changes.count else {
            throw CollectionSyncError.invalidDecision
        }

        var result = self
        if let updatedRegistry {
            try updatedRegistry.validate(completing: token)
            let updated = Dictionary(
                uniqueKeysWithValues: updatedRegistry.bindings.map { ($0.id, $0.reference.id) })
            guard registry.bindings.allSatisfy({ updated[$0.id] == $0.reference.id }) else {
                throw CollectionExchangeError.invalidMapping
            }
            result.registry = updatedRegistry
        }
        // Änderungen sind ausdrückliche Ereignisse. Fehlende Schlüssel aus
        // einem unvollständigen Lesevorgang dürfen keine Löschung erzeugen.
        var cells = checkpoint.local.indexed()
        for change in changes { cells[change.id] = change.value }
        result.checkpoint.local = CollectionSyncSnapshot(
            collectionID: expected.collectionID, generation: expected.generation,
            cells: CollectionSyncCell.ordered(cells.map { .init($0.key, $0.value) }))
        try result.validate()
        return result
    }
}

public enum CollectionSyncLocalStateCodec {
    public static let maximumBytes =
        CollectionSyncCodec.maximumCheckpointBytes
        + CollectionSyncRegistryCodec.maximumBytes + 65_536
    private struct Header: Decodable {
        let format: String
        let schemaVersion: Int
    }

    public static func encode(_ state: CollectionSyncLocalState) throws -> Data {
        try state.validate()
        _ = try CollectionSyncCodec.encode(state.checkpoint)
        _ = try CollectionSyncRegistryCodec.encode(state.registry)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        guard data.count <= maximumBytes else { throw CollectionSyncError.oversized }
        return data
    }

    public static func decode(_ data: Data) throws -> CollectionSyncLocalState {
        guard data.count <= maximumBytes else { throw CollectionSyncError.oversized }
        do {
            let decoder = JSONDecoder()
            let header = try decoder.decode(Header.self, from: data)
            guard header.format == CollectionSyncLocalState.identifier else {
                throw CollectionSyncError.invalidCheckpoint
            }
            guard header.schemaVersion == 1 else {
                throw CollectionSyncError.unsupportedVersion(header.schemaVersion)
            }
            let state = try decoder.decode(CollectionSyncLocalState.self, from: data)
            try state.validate()
            _ = try CollectionSyncCodec.encode(state.checkpoint)
            _ = try CollectionSyncRegistryCodec.encode(state.registry)
            return state
        } catch let error as CollectionSyncError { throw error } catch let error
            as CollectionExchangeError
        { throw error } catch { throw CollectionSyncError.invalidCheckpoint }
    }

    public static func load(from url: URL, isCancelled: () -> Bool = { false }) throws
        -> CollectionSyncLocalState
    {
        do {
            guard !isCancelled() else { throw CancellationError() }
            let file = try LibraryFileReader(url)
            defer { file.close() }
            guard file.stamp.size <= Int64(maximumBytes) else {
                throw CollectionSyncError.oversized
            }
            return try decode(file.read(limit: maximumBytes, isCancelled: isCancelled))
        } catch is CancellationError { throw CancellationError() } catch LibraryFileReadError
            .oversized
        { throw CollectionSyncError.oversized } catch let error as CollectionSyncError {
            throw error
        } catch let error as CollectionExchangeError { throw error } catch {
            throw CollectionSyncError.invalidCheckpoint
        }
    }
}

import Foundation

public struct CollectionSyncTrackBinding: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var reference: PlaylistTrackReference
    public init(id: UUID, reference: PlaylistTrackReference) {
        self.id = id
        self.reference = reference
    }
}

public struct CollectionSyncMappedExport: Sendable {
    public let document: CollectionExchangeDocument
    public let registry: CollectionSyncTrackRegistry
}

// Diese Zuordnung enthält lokale URLs. Sie gehört ausschließlich in den
// gerätelokalen Speicher und niemals in einen Cloud-Snapshot oder Austausch-Export.
public struct CollectionSyncTrackRegistry: Codable, Equatable, Sendable {
    public static let identifier = "org.savage-mod-player.collection-sync-local-tracks"
    public var format = Self.identifier
    public var schemaVersion = 1
    public let account: CollectionSyncAccountToken
    public let collectionID: UUID
    public let generation: UUID
    public private(set) var bindings: [CollectionSyncTrackBinding]

    public init(
        account: CollectionSyncAccountToken, collectionID: UUID, generation: UUID,
        bindings: [CollectionSyncTrackBinding] = []
    ) {
        self.account = account
        self.collectionID = collectionID
        self.generation = generation
        self.bindings = bindings
    }

    public func validate(completing token: CollectionSyncAccountToken) throws {
        try validate()
        guard token == account else { throw CollectionSyncError.staleAccount }
    }

    public func assigning(
        _ globalID: UUID, to reference: PlaylistTrackReference,
        account token: CollectionSyncAccountToken
    ) throws -> Self {
        try assigning([globalID: reference], account: token)
    }

    public func assigning(_ references: [UUID: PlaylistTrackReference],
                          account token: CollectionSyncAccountToken) throws -> Self {
        try validate(completing: token)
        var result = self
        guard references.count <= CollectionExchangeCodec.maximumTracks else { throw CollectionSyncError.oversized }
        var owners = Dictionary(uniqueKeysWithValues: bindings.map { ($0.reference.id, $0.id) })
        let indices = Dictionary(uniqueKeysWithValues: bindings.enumerated().map { ($0.element.id, $0.offset) })
        let assignments = references.map { ($0.key.uuidString, $0.key, $0.value) }.sorted { $0.0 < $1.0 }
        for (_, globalID, reference) in assignments {
            guard owners[reference.id] == nil || owners[reference.id] == globalID else {
                throw CollectionExchangeError.invalidMapping
            }
            if let index = indices[globalID] {
                // Ein Dateiumzug benötigt zusätzlich die Migration der alten Metadaten.
                guard bindings[index].reference.id == reference.id else { throw CollectionExchangeError.invalidMapping }
                result.bindings[index].reference = reference
            } else { result.bindings.append(.init(id: globalID, reference: reference)) }
            owners[reference.id] = globalID
        }
        try result.validate()
        return result
    }

    public func mapping(
        for snapshot: CollectionSyncSnapshot, available: [PlaylistTrackReference],
        account token: CollectionSyncAccountToken
    ) throws -> [UUID: PlaylistTrackReference] {
        try validate(completing: token)
        try snapshot.validate()
        guard snapshot.collectionID == collectionID else {
            throw CollectionSyncError.mismatchedCollection
        }
        guard snapshot.generation == generation else { throw CollectionSyncError.staleGeneration }
        guard available.count <= CollectionExchangeCodec.maximumTracks,
            Set(available.map(\.id)).count == available.count,
            available.allSatisfy(Self.validReference)
        else { throw CollectionExchangeError.invalidMapping }
        let live = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        let known = snapshot.mappingRequirements().known
        return Dictionary(
            uniqueKeysWithValues: bindings.filter { known.contains($0.id) }.map {
                ($0.id, live[$0.reference.id] ?? $0.reference)
            })
    }

    public func export(
        from snapshot: CollectionExchangeSnapshot, sources: [CollectionExchangeLocalTrack],
        account token: CollectionSyncAccountToken
    ) throws -> CollectionSyncMappedExport {
        try validate(completing: token)
        var result = self
        var indices = Dictionary(
            uniqueKeysWithValues: bindings.enumerated().map { ($0.element.reference.id, $0.offset) }
        )
        var globalIDs = Set(bindings.map(\.id))
        let document = try CollectionExchangeExporter.makeDocument(
            from: snapshot, sources: sources, id: collectionID
        ) { reference in
            if let index = indices[reference.id] {
                result.bindings[index].reference = reference
                return result.bindings[index].id
            }
            guard result.bindings.count < CollectionExchangeCodec.maximumTracks else {
                throw CollectionSyncError.oversized
            }
            let id = UUID()
            guard globalIDs.insert(id).inserted else {
                throw CollectionExchangeError.invalidMapping
            }
            indices[reference.id] = result.bindings.count
            result.bindings.append(.init(id: id, reference: reference))
            return id
        }
        try result.validate()
        return .init(document: document, registry: result)
    }

    func validate() throws {
        guard format == Self.identifier else { throw CollectionSyncError.invalidCheckpoint }
        guard schemaVersion == 1 else {
            throw CollectionSyncError.unsupportedVersion(schemaVersion)
        }
        try account.validate()
        guard bindings.count <= CollectionExchangeCodec.maximumTracks else {
            throw CollectionSyncError.oversized
        }
        guard Set(bindings.map(\.id)).count == bindings.count,
            Set(bindings.map { $0.reference.id }).count == bindings.count
        else { throw CollectionExchangeError.invalidMapping }
        var bytes = 256
        for binding in bindings {
            let reference = binding.reference
            let url = reference.source.location
            guard Self.validReference(reference) else {
                throw CollectionExchangeError.invalidMapping
            }
            bytes +=
                256 + reference.id.utf8.count + url.absoluteString.utf8.count + reference
                .displayName.utf8
                .count * 6
            guard bytes <= CollectionSyncRegistryCodec.maximumBytes else {
                throw CollectionSyncError.oversized
            }
        }
    }
    private static func validReference(_ reference: PlaylistTrackReference) -> Bool {
        let url = reference.source.location
        return reference.source.isValid && TrackPlaybackSettingsStore.validID(reference.id)
            && url.absoluteString.utf8.count <= 16_384 && url.user == nil && url.password == nil
            && url.query == nil && url.fragment == nil && !reference.displayName.isEmpty
            && reference.displayName.utf8.count <= 2048
    }
}

public enum CollectionSyncRegistryCodec {
    public static let maximumBytes = CollectionSyncCodec.maximumBytes
    private struct Header: Decodable {
        let format: String
        let schemaVersion: Int
    }

    public static func encode(_ registry: CollectionSyncTrackRegistry) throws -> Data {
        try registry.validate()
        let canonical = CollectionSyncTrackRegistry(
            account: registry.account, collectionID: registry.collectionID,
            generation: registry.generation,
            bindings: registry.bindings.map { ($0.id.uuidString, $0) }.sorted { $0.0 < $1.0 }.map(\.1))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(canonical)
        guard data.count <= maximumBytes else { throw CollectionSyncError.oversized }
        return data
    }
    public static func decode(_ data: Data) throws -> CollectionSyncTrackRegistry {
        guard data.count <= maximumBytes else { throw CollectionSyncError.oversized }
        do {
            let decoder = JSONDecoder()
            let header = try decoder.decode(Header.self, from: data)
            guard header.format == CollectionSyncTrackRegistry.identifier else {
                throw CollectionSyncError.invalidCheckpoint
            }
            guard header.schemaVersion == 1 else {
                throw CollectionSyncError.unsupportedVersion(header.schemaVersion)
            }
            let registry = try decoder.decode(CollectionSyncTrackRegistry.self, from: data)
            try registry.validate()
            return registry
        } catch let error as CollectionSyncError { throw error } catch let error
            as CollectionExchangeError
        { throw error } catch { throw CollectionSyncError.invalidCheckpoint }
    }
    public static func load(from url: URL) throws -> CollectionSyncTrackRegistry {
        do {
            let file = try LibraryFileReader(url)
            defer { file.close() }
            return try decode(file.read(limit: maximumBytes))
        } catch LibraryFileReadError.oversized { throw CollectionSyncError.oversized } catch let
            error
            as CollectionSyncError
        { throw error } catch let error as CollectionExchangeError { throw error } catch {
            throw CollectionSyncError.invalidCheckpoint
        }
    }
}

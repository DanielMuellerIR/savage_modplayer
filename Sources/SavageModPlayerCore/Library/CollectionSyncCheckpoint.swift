import Foundation

public struct CollectionSyncAccountToken: Codable, Equatable, Sendable {
    public let scope: String
    public let epoch: UUID
    public init(scope: String, epoch: UUID) { self.scope = scope; self.epoch = epoch }
    func validate() throws {
        guard scope.utf8.count == 64, scope.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw CollectionSyncError.invalidCheckpoint
        }
    }
}

public struct CollectionSyncCheckpoint: Codable, Equatable, Sendable {
    public static let identifier = "org.savage-mod-player.collection-sync-checkpoint"
    public var format = Self.identifier
    public var schemaVersion = 1
    public let account: CollectionSyncAccountToken
    public var base: CollectionSyncSnapshot
    public var local: CollectionSyncSnapshot
    public var serverChangeTag: String?

    public init(account: CollectionSyncAccountToken, base: CollectionSyncSnapshot,
                local: CollectionSyncSnapshot, serverChangeTag: String? = nil) {
        self.account = account; self.base = base; self.local = local; self.serverChangeTag = serverChangeTag
    }
    public func validate() throws {
        guard format == Self.identifier else { throw CollectionSyncError.invalidCheckpoint }
        guard schemaVersion == 1 else { throw CollectionSyncError.unsupportedVersion(schemaVersion) }
        try account.validate(); try base.validate(); try local.validate()
        guard base.collectionID == local.collectionID else { throw CollectionSyncError.mismatchedCollection }
        guard base.generation == local.generation else { throw CollectionSyncError.staleGeneration }
        guard Set(base.cells.map(\.id)).isSubset(of: Set(local.cells.map(\.id))) else { throw CollectionSyncError.incompleteSnapshot }
        if let tag = serverChangeTag {
            guard !tag.isEmpty, tag.utf8.count <= 1024, !tag.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw CollectionSyncError.invalidCheckpoint
            }
        }
    }
    public func pendingChanges() throws -> Bool {
        try validate()
        return base.indexed() != local.indexed()
    }
    public func validate(completing token: CollectionSyncAccountToken) throws {
        try validate()
        guard token == account else { throw CollectionSyncError.staleAccount }
    }
}

public enum CollectionSyncCodec {
    private struct Header: Decodable { let format: String; let schemaVersion: Int }
    public static let maximumBytes = CollectionExchangeCodec.maximumBytes
    public static let maximumCheckpointBytes = 2 * maximumBytes + 65_536
    public static let maximumCells = 6 * CollectionExchangeCodec.maximumTracks
        + CollectionExchangeCodec.maximumPlaylists + CollectionExchangeCodec.maximumMarkers + 4

    public static func encode(_ snapshot: CollectionSyncSnapshot) throws -> Data {
        try snapshot.validate()
        let data = try encoder().encode(canonical(snapshot))
        guard data.count <= maximumBytes else { throw CollectionSyncError.oversized }
        return data
    }
    public static func decode(_ data: Data) throws -> CollectionSyncSnapshot {
        guard data.count <= maximumBytes else { throw CollectionSyncError.oversized }
        do {
            try verifyHeader(data, format: CollectionSyncSnapshot.identifier, invalid: .invalidSnapshot)
            let snapshot = try JSONDecoder().decode(CollectionSyncSnapshot.self, from: data)
            try snapshot.validate(); return canonical(snapshot)
        } catch let error as CollectionSyncError { throw error }
        catch { throw CollectionSyncError.invalidSnapshot }
    }
    public static func encode(_ checkpoint: CollectionSyncCheckpoint) throws -> Data {
        try checkpoint.validate()
        _ = try encode(checkpoint.base); _ = try encode(checkpoint.local)
        var checkpoint = checkpoint
        checkpoint.base = canonical(checkpoint.base); checkpoint.local = canonical(checkpoint.local)
        let data = try encoder().encode(checkpoint)
        guard data.count <= maximumCheckpointBytes else { throw CollectionSyncError.oversized }
        return data
    }
    public static func decodeCheckpoint(_ data: Data) throws -> CollectionSyncCheckpoint {
        guard data.count <= maximumCheckpointBytes else { throw CollectionSyncError.oversized }
        do {
            try verifyHeader(data, format: CollectionSyncCheckpoint.identifier, invalid: .invalidCheckpoint)
            var checkpoint = try JSONDecoder().decode(CollectionSyncCheckpoint.self, from: data)
            try checkpoint.validate()
            _ = try encode(checkpoint.base); _ = try encode(checkpoint.local)
            checkpoint.base = canonical(checkpoint.base); checkpoint.local = canonical(checkpoint.local)
            return checkpoint
        } catch let error as CollectionSyncError { throw error }
        catch { throw CollectionSyncError.invalidCheckpoint }
    }
    public static func loadCheckpoint(from url: URL, isCancelled: () -> Bool = { false }) throws -> CollectionSyncCheckpoint {
        do {
            guard !isCancelled() else { throw CancellationError() }
            let file = try LibraryFileReader(url)
            defer { file.close() }
            return try decodeCheckpoint(file.read(limit: maximumCheckpointBytes, isCancelled: isCancelled))
        } catch is CancellationError { throw CancellationError() }
        catch LibraryFileReadError.oversized { throw CollectionSyncError.oversized }
        catch let error as CollectionSyncError { throw error }
        catch { throw CollectionSyncError.invalidCheckpoint }
    }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Date-Referenzsekunden erhalten auch Bruchteile verlustfrei. Eine
        // ISO-Formatierung mit gekürzten Sekunden erzeugte sonst Scheinkonflikte.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
    private static func verifyHeader(_ data: Data, format: String, invalid: CollectionSyncError) throws {
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.format == format else { throw invalid }
        guard header.schemaVersion == 1 else { throw CollectionSyncError.unsupportedVersion(header.schemaVersion) }
    }
    private static func canonical(_ snapshot: CollectionSyncSnapshot) -> CollectionSyncSnapshot {
        var snapshot = snapshot; snapshot.cells = CollectionSyncCell.ordered(snapshot.cells); return snapshot
    }
}

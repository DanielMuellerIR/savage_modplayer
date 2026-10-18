import Foundation

public struct CollectionSyncCloudAsset: Equatable, Sendable {
    public let data: Data
    public let changeTag: String
    public init(data: Data, changeTag: String) {
        self.data = data
        self.changeTag = changeTag
    }
}

public protocol CollectionSyncAssetBackend: Sendable {
    func currentAccountScope() async throws -> String
    func fetch() async throws -> CollectionSyncCloudAsset?
    func save(_ data: Data, replacing changeTag: String?) async throws -> CollectionSyncCloudAsset
}

public struct CollectionSyncServerVersion: Equatable, Sendable {
    public let snapshot: CollectionSyncSnapshot
    public let changeTag: String
    public let account: CollectionSyncAccountToken

    public func validate(completing token: CollectionSyncAccountToken) throws {
        try account.validate()
        try token.validate()
        guard token == account else { throw CollectionSyncError.staleAccount }
        try snapshot.validate()
        try CollectionSyncTransportClient.validateTag(changeTag)
    }
}

public enum CollectionSyncTransportError: Error, Equatable, LocalizedError, Sendable {
    case missingRecord, configurationRequired, conflict, accountUnavailable, quotaExceeded
    case temporarilyUnavailable(retryAfter: Double?)
    case invalidResponse, serviceFailure
    public var errorDescription: String? {
        switch self {
        case .missingRecord: "Für diese Sammlung wurde noch kein Cloud-Stand gefunden."
        case .configurationRequired:
            "Der Cloud-Abgleich ist für diese Anwendung noch nicht vollständig eingerichtet."
        case .conflict: "Der Cloud-Stand wurde inzwischen geändert. Bitte erneut abgleichen."
        case .accountUnavailable: "Das iCloud-Konto ist momentan nicht verfügbar."
        case .quotaExceeded: "Der verfügbare iCloud-Speicher reicht für den Abgleich nicht aus."
        case .temporarilyUnavailable:
            "Der Cloud-Dienst ist momentan nicht erreichbar. Bitte später erneut versuchen."
        case .invalidResponse: "Der Cloud-Dienst hat keinen gültigen Abgleichstand geliefert."
        case .serviceFailure: "Der Cloud-Abgleich konnte nicht abgeschlossen werden."
        }
    }
}

public struct CollectionSyncTransportClient: Sendable {
    private let backend: any CollectionSyncAssetBackend
    private let account: CollectionSyncAccountToken
    private let collectionID: UUID
    private let generation: UUID

    public init(
        backend: any CollectionSyncAssetBackend, account: CollectionSyncAccountToken,
        collectionID: UUID, generation: UUID
    ) throws {
        try account.validate()
        self.backend = backend
        self.account = account
        self.collectionID = collectionID
        self.generation = generation
    }

    public func fetch(account token: CollectionSyncAccountToken) async throws
        -> CollectionSyncServerVersion
    {
        try validate(token)
        try await checkAccount()
        let asset = try await backend.fetch()
        try Task.checkCancellation()
        try await checkAccount()
        guard let asset else { throw CollectionSyncTransportError.missingRecord }
        return try decode(asset)
    }

    public func save(
        _ snapshot: CollectionSyncSnapshot, replacing expectedTag: String?,
        account token: CollectionSyncAccountToken
    ) async throws -> CollectionSyncServerVersion {
        try validate(token)
        try validate(snapshot)
        if let expectedTag { try Self.validateTag(expectedTag) }
        let data = try CollectionSyncCodec.encode(snapshot)
        try await checkAccount()
        let current = try await backend.fetch()
        guard current?.changeTag == expectedTag else { throw CollectionSyncTransportError.conflict }
        if let current {
            let previous = try decode(current).snapshot
            guard Set(previous.cells.map(\.id)).isSubset(of: Set(snapshot.cells.map(\.id))) else {
                throw CollectionSyncError.incompleteSnapshot
            }
        }
        try Task.checkCancellation()
        try await checkAccount()
        // Der Backend-Vergleich muss serverseitig bedingt sein. Die vorangehende
        // Prüfung allein schützt nicht vor einem zweiten Gerät zwischen Read/Write.
        let saved = try await backend.save(data, replacing: expectedTag)
        let result = try decode(saved)
        guard result.snapshot.indexed() == snapshot.indexed() else {
            throw CollectionSyncTransportError.invalidResponse
        }
        try await checkAccount()
        return result
    }

    private func validate(_ token: CollectionSyncAccountToken) throws {
        try token.validate()
        guard token == account else { throw CollectionSyncError.staleAccount }
        try Task.checkCancellation()
    }
    private func validate(_ snapshot: CollectionSyncSnapshot) throws {
        try snapshot.validate()
        guard snapshot.collectionID == collectionID else {
            throw CollectionSyncError.mismatchedCollection
        }
        guard snapshot.generation == generation else { throw CollectionSyncError.staleGeneration }
    }
    private func checkAccount() async throws {
        guard try await backend.currentAccountScope() == account.scope else {
            throw CollectionSyncError.staleAccount
        }
    }
    private func decode(_ asset: CollectionSyncCloudAsset) throws -> CollectionSyncServerVersion {
        try Self.validateTag(asset.changeTag)
        let snapshot = try CollectionSyncCodec.decode(asset.data)
        try validate(snapshot)
        return .init(snapshot: snapshot, changeTag: asset.changeTag, account: account)
    }
    static func validateTag(_ tag: String) throws {
        guard !tag.isEmpty, tag.utf8.count <= 1024,
            !tag.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw CollectionSyncTransportError.invalidResponse
        }
    }
}

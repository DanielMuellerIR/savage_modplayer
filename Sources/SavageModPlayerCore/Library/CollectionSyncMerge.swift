import Foundation

public enum CollectionSyncResolution: Equatable, Sendable {
    case keepLocal, useRemote, keepBoth(copyID: UUID)
}

public struct CollectionSyncConflict: Equatable, Sendable, Identifiable {
    public let id: CollectionSyncKey
    public let local: CollectionSyncValue
    public let remote: CollectionSyncValue
    public var allowsKeepingBoth: Bool {
        switch (local, remote) {
        case (.playlist, .playlist), (.marker, .marker): true
        default: false
        }
    }
}

public struct CollectionSyncMergePlan: Sendable {
    public let conflicts: [CollectionSyncConflict]
    private let originalLocal: CollectionSyncSnapshot
    private let candidate: [CollectionSyncKey: CollectionSyncValue]
    private let reserved: Set<CollectionSyncKey>

    public init(base: CollectionSyncSnapshot, local: CollectionSyncSnapshot, remote: CollectionSyncSnapshot) throws {
        for snapshot in [base, local, remote] { try snapshot.validate() }
        guard base.collectionID == local.collectionID, base.collectionID == remote.collectionID else { throw CollectionSyncError.mismatchedCollection }
        guard base.generation == local.generation, base.generation == remote.generation else { throw CollectionSyncError.staleGeneration }
        let b = base.indexed(), l = local.indexed(), r = remote.indexed()
        // Fehlende Musik, ein defekter Speicher oder eine unvollständige Projektion
        // dürfen bekannte Metadaten nicht still als gelöscht veröffentlichen.
        guard Set(b.keys).isSubset(of: Set(l.keys)), Set(b.keys).isSubset(of: Set(r.keys)) else { throw CollectionSyncError.incompleteSnapshot }
        let keys = Set(b.keys).union(l.keys).union(r.keys)
        var merged = [CollectionSyncKey: CollectionSyncValue](), conflicts = [CollectionSyncConflict]()
        for key in CollectionSyncKey.ordered(keys) {
            if l[key] == r[key] { merged[key] = l[key] }
            else if l[key] == b[key] { merged[key] = r[key] }
            else if r[key] == b[key] { merged[key] = l[key] }
            else {
                guard let local = l[key], let remote = r[key] else { throw CollectionSyncError.incompleteSnapshot }
                conflicts.append(.init(id: key, local: local, remote: remote))
            }
        }
        self.conflicts = conflicts; originalLocal = local; candidate = merged; reserved = keys
    }

    public func result(ifUnchanged local: CollectionSyncSnapshot,
                       resolutions: [CollectionSyncKey: CollectionSyncResolution] = [:]) throws -> CollectionSyncSnapshot {
        try local.validate()
        guard local.collectionID == originalLocal.collectionID, local.generation == originalLocal.generation,
              local.indexed() == originalLocal.indexed() else { throw CollectionSyncError.stalePreview }
        let conflictKeys = Set(conflicts.map(\.id))
        guard Set(resolutions.keys).isSubset(of: conflictKeys) else { throw CollectionSyncError.invalidDecision }
        guard Set(resolutions.keys) == conflictKeys else { throw CollectionSyncError.unresolvedConflicts }
        var result = candidate
        for conflict in conflicts {
            switch resolutions[conflict.id]! {
            case .keepLocal: result[conflict.id] = conflict.local
            case .useRemote: result[conflict.id] = conflict.remote
            case .keepBoth(let copyID):
                let key: CollectionSyncKey, value: CollectionSyncValue
                switch (conflict.local, conflict.remote) {
                case (.playlist, .playlist(var playlist)):
                    playlist.id = copyID; key = .playlist(copyID); value = .playlist(playlist)
                case (.marker, .marker(var marker)):
                    marker.id = copyID; key = .marker(copyID); value = .marker(marker)
                default: throw CollectionSyncError.invalidDecision
                }
                guard !reserved.contains(key), result[key] == nil else { throw CollectionSyncError.invalidDecision }
                result[conflict.id] = conflict.local; result[key] = value
            }
        }
        let snapshot = CollectionSyncSnapshot(collectionID: local.collectionID, generation: local.generation,
            cells: CollectionSyncCell.ordered(result.map { .init($0.key, $0.value) }))
        try snapshot.validate()
        return snapshot
    }
}

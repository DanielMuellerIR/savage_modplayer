import Foundation

// Beobachtet wird die tatsächlich gespeicherte App-Sammlung. Der vorgemerkte
// gemeinsame Stand kann bereits bestätigte Konfliktentscheidungen enthalten,
// die nach dem Versand noch nicht in die lokalen Metadaten übernommen wurden.
public struct CollectionSyncApplicationState: Codable, Equatable, Sendable {
    public static let identifier = "org.savage-mod-player.collection-sync-application"
    public var format = Self.identifier
    public var schemaVersion = 1
    public private(set) var localState: CollectionSyncLocalState
    public private(set) var observed: CollectionSyncSnapshot
    public var isEnabled: Bool
    public private(set) var hasStoredPreferences: Bool
    public private(set) var storedPreferenceKeys: Set<String>?
    public private(set) var needsProjection: Bool
    public private(set) var lastSuccessfulSync: Date?

    public init(localState: CollectionSyncLocalState, observed: CollectionSyncSnapshot,
                isEnabled: Bool = true, needsProjection: Bool = false, lastSuccessfulSync: Date? = nil,
                hasStoredPreferences: Bool = false, storedPreferenceKeys: Set<String>? = nil) {
        self.localState = localState; self.observed = observed; self.isEnabled = isEnabled
        self.needsProjection = needsProjection; self.lastSuccessfulSync = lastSuccessfulSync
        self.hasStoredPreferences = hasStoredPreferences
        self.storedPreferenceKeys = storedPreferenceKeys
    }

    public func validate() throws {
        guard format == Self.identifier else { throw CollectionSyncError.invalidCheckpoint }
        guard schemaVersion == 1 else { throw CollectionSyncError.unsupportedVersion(schemaVersion) }
        try localState.validate(); try observed.validate()
        if let keys = storedPreferenceKeys {
            guard keys.count <= 64, hasStoredPreferences == !keys.isEmpty,
                  keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else {
                throw CollectionSyncError.invalidCheckpoint
            }
        }
        guard observed.collectionID == localState.checkpoint.local.collectionID else {
            throw CollectionSyncError.mismatchedCollection
        }
        guard observed.generation == localState.checkpoint.local.generation else {
            throw CollectionSyncError.staleGeneration
        }
        guard Set(observed.cells.map(\.id)).isSubset(of: Set(localState.checkpoint.local.cells.map(\.id))),
              observed.mappingRequirements().required.isSubset(of: Set(localState.registry.bindings.map(\.id))),
              lastSuccessfulSync.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true else {
            throw CollectionSyncError.invalidCheckpoint
        }
    }

    public func hasPendingChanges() throws -> Bool {
        try validate()
        return needsProjection || localState.checkpoint.base.indexed() != localState.checkpoint.local.indexed()
    }

    public func capturing(_ metadata: CollectionExchangeSnapshot, sources: [CollectionExchangeLocalTrack],
                          metadataFilesExist: Bool, preferencesAvailable: Bool = true,
                          preferenceKeys: Set<String>? = nil) throws -> Self {
        try validate()
        guard metadataFilesExist, !hasStoredPreferences || preferencesAvailable else {
            throw CollectionExchangeError.invalidLocalState
        }
        if let previous = storedPreferenceKeys {
            guard previous.isSubset(of: preferenceKeys ?? []) else { throw CollectionExchangeError.invalidLocalState }
        }
        let export = try localState.registry.export(from: metadata, sources: sources,
                                                    account: localState.checkpoint.account)
        var observation = try CollectionSyncSnapshot(document: export.document,
            collectionID: observed.collectionID, generation: observed.generation)
        let old = observed.indexed(), shared = localState.checkpoint.local.indexed()
        var values = observation.indexed()
        // Relative Hinweise unterscheiden sich zwischen Geräten. Ein bestätigter
        // globaler Titel behält deshalb seine Beschreibung beim lokalen Erfassen.
        for cell in localState.checkpoint.local.cells {
            guard case .track = cell.id else { continue }
            if case .track = cell.value { values[cell.id] = cell.value }
            else if let previous = old[cell.id] { values[cell.id] = previous }
        }
        observation.cells = CollectionSyncCell.ordered(values.map { .init($0.key, $0.value) })
        try observation.validate()
        var changes: [CollectionSyncCell] = []
        for key in CollectionSyncKey.ordered(Set(old.keys).union(values.keys)) {
            guard old[key] != values[key] else { continue }
            if let value = values[key] { changes.append(.init(key, value)); continue }
            switch key {
            case .track: break
            case .trackSetting: changes.append(.init(key, .inherit))
            case .playlist, .marker, .favorite: changes.append(.init(key, .deleted))
            case .defaultSetting: throw CollectionSyncError.incompleteSnapshot
            }
        }
        // Neue lokale Metadaten dürfen einen zuvor ausdrücklich entfernten
        // Titel wieder benötigen. Ein fehlender Datenträger erzeugt das nicht.
        let required = observation.mappingRequirements().required
        let metadataChanges = changes
        var changedKeys = Set(changes.map(\.id))
        for change in metadataChanges {
            let references: Set<UUID>
            switch (change.id, change.value) {
            case (.favorite(let id), .flag(true)): references = [id]
            case (.playlist, .playlist(let value)): references = Set(value.trackIDs)
            case (.marker, .marker(let value)): references = [value.trackID]
            case (.trackSetting(let id, _), .flag), (.trackSetting(let id, _), .number): references = [id]
            default: references = []
            }
            for id in references.intersection(required) where shared[.track(id)] == .deleted {
                if let value = values[.track(id)], changedKeys.insert(.track(id)).inserted {
                    changes.append(.init(.track(id), value))
                }
            }
        }
        var result = self
        if !changes.isEmpty || export.registry != localState.registry {
            result.localState = try localState.applying(changes, registry: export.registry,
                ifUnchanged: localState.checkpoint.local, account: localState.checkpoint.account)
        }
        if observation.indexed() != old { result.observed = observation }
        result.hasStoredPreferences = preferencesAvailable
        result.storedPreferenceKeys = preferenceKeys ?? storedPreferenceKeys
        try result.validate()
        return result
    }

    public func preparing(_ snapshot: CollectionSyncSnapshot, registry: CollectionSyncTrackRegistry,
                          ifUnchanged expected: Self) throws -> Self {
        try validate(); try expected.validate(); try snapshot.validate()
        guard self == expected else { throw CollectionSyncError.stalePreview }
        guard Set(localState.checkpoint.local.cells.map(\.id)).isSubset(of: Set(snapshot.cells.map(\.id))) else {
            throw CollectionSyncError.incompleteSnapshot
        }
        let updated = Dictionary(uniqueKeysWithValues: registry.bindings.map { ($0.id, $0.reference.id) })
        guard localState.registry.bindings.allSatisfy({ updated[$0.id] == $0.reference.id }) else {
            throw CollectionExchangeError.invalidMapping
        }
        var checkpoint = localState.checkpoint
        checkpoint.local = snapshot
        var result = self
        result.localState = .init(checkpoint: checkpoint, registry: registry)
        result.needsProjection = true
        try result.validate()
        return result
    }

    public func confirming(_ server: CollectionSyncServerVersion, projected metadata: CollectionExchangeSnapshot,
                           sources: [CollectionExchangeLocalTrack], at date: Date = Date(),
                           preferencesAvailable: Bool = true, preferenceKeys: Set<String>? = nil) throws -> Self {
        try validate(); try server.validate(completing: localState.checkpoint.account)
        guard isEnabled, server.snapshot.indexed() == localState.checkpoint.local.indexed() else {
            throw CollectionSyncError.stalePreview
        }
        var result = try capturing(metadata, sources: sources, metadataFilesExist: true,
                                   preferencesAvailable: preferencesAvailable, preferenceKeys: preferenceKeys)
        guard result.localState.checkpoint.local.indexed() == server.snapshot.indexed() else {
            throw CollectionExchangeError.invalidLocalState
        }
        var checkpoint = result.localState.checkpoint
        checkpoint.base = server.snapshot; checkpoint.serverChangeTag = server.changeTag
        result.localState = .init(checkpoint: checkpoint, registry: result.localState.registry)
        result.needsProjection = false; result.lastSuccessfulSync = date
        try result.validate()
        return result
    }
}

public enum CollectionSyncApplicationCodec {
    public static let maximumBytes = CollectionExchangePersistence.maximumSyncStateBytes
    private struct Header: Decodable { let format: String; let schemaVersion: Int }

    public static func encode(_ state: CollectionSyncApplicationState) throws -> Data {
        try state.validate()
        _ = try CollectionSyncLocalStateCodec.encode(state.localState)
        _ = try CollectionSyncCodec.encode(state.observed)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        guard data.count <= maximumBytes else { throw CollectionSyncError.oversized }
        return data
    }
    public static func decode(_ data: Data) throws -> CollectionSyncApplicationState {
        guard data.count <= maximumBytes else { throw CollectionSyncError.oversized }
        do {
            let decoder = JSONDecoder(), header = try decoder.decode(Header.self, from: data)
            guard header.format == CollectionSyncApplicationState.identifier else { throw CollectionSyncError.invalidCheckpoint }
            guard header.schemaVersion == 1 else { throw CollectionSyncError.unsupportedVersion(header.schemaVersion) }
            let state = try decoder.decode(CollectionSyncApplicationState.self, from: data)
            _ = try encode(state)
            return state
        } catch let error as CollectionSyncError { throw error }
        catch let error as CollectionExchangeError { throw error }
        catch { throw CollectionSyncError.invalidCheckpoint }
    }
}

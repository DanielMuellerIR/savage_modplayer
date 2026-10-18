import Foundation

public enum CollectionSyncField: String, Codable, CaseIterable, Sendable {
    case palClock, stereoSeparation, useInterpolation, ledFilterActive
}

public enum CollectionSyncKey: Codable, Hashable, Sendable {
    case track(UUID), playlist(UUID), marker(UUID), favorite(UUID)
    case trackSetting(UUID, CollectionSyncField), defaultSetting(CollectionSyncField)

    var sortKey: String {
        switch self {
        case .track(let id): "track:\(id)"
        case .playlist(let id): "playlist:\(id)"
        case .marker(let id): "marker:\(id)"
        case .favorite(let id): "favorite:\(id)"
        case .trackSetting(let id, let field): "setting:\(id):\(field.rawValue)"
        case .defaultSetting(let field): "default:\(field.rawValue)"
        }
    }

    static func ordered<S: Sequence>(_ keys: S) -> [Self] where S.Element == Self {
        keys.map { ($0.sortKey, $0) }.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

public enum CollectionSyncValue: Codable, Equatable, Sendable {
    case track(ExchangeTrackDescriptor), playlist(ExchangePlaylist), marker(ExchangeSongMarker)
    case flag(Bool), number(Double), inherit, deleted
}

public struct CollectionSyncCell: Codable, Equatable, Sendable, Identifiable {
    public let id: CollectionSyncKey
    public var value: CollectionSyncValue
    public init(_ id: CollectionSyncKey, _ value: CollectionSyncValue) { self.id = id; self.value = value }
    static func ordered(_ cells: [Self]) -> [Self] {
        cells.map { ($0.id.sortKey, $0) }.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

public struct CollectionSyncSnapshot: Codable, Equatable, Sendable {
    public static let identifier = "org.savage-mod-player.collection-sync"
    public var format = Self.identifier
    public var schemaVersion = 1
    public let collectionID: UUID
    public let generation: UUID
    public var cells: [CollectionSyncCell]

    public init(collectionID: UUID, generation: UUID, cells: [CollectionSyncCell] = []) {
        self.collectionID = collectionID; self.generation = generation; self.cells = cells
    }

    // Der Aufrufer liefert bereits dauerhaft zugeordnete globale Titel-IDs.
    // Eine neue manuelle Exportdatei allein begründet keine Cloud-Identität.
    public init(document: CollectionExchangeDocument, collectionID: UUID, generation: UUID) throws {
        try CollectionExchangeCodec.validate(document)
        self.init(collectionID: collectionID, generation: generation)
        cells += document.tracks.map { .init(.track($0.id), .track($0.descriptor)) }
        cells += document.playlists.map { .init(.playlist($0.id), .playlist($0)) }
        cells += document.markers.map { .init(.marker($0.id), .marker($0)) }
        cells += document.favoriteTrackIDs.map { .init(.favorite($0), .flag(true)) }
        for settings in document.trackSettings {
            for field in CollectionSyncField.allCases {
                cells.append(.init(.trackSetting(settings.trackID, field), Self.value(settings.overrides, field: field)))
            }
        }
        if let defaults = document.playbackDefaults {
            for field in CollectionSyncField.allCases {
                let value: CollectionSyncValue = switch field {
                case .palClock: .flag(defaults.palClock)
                case .stereoSeparation: .number(defaults.stereoSeparation)
                case .useInterpolation: .flag(defaults.useInterpolation)
                case .ledFilterActive: .flag(defaults.ledFilterActive)
                }
                cells.append(.init(.defaultSetting(field), value))
            }
        }
        try validate()
    }

    public func exchangeDocument(preservingLocalPlaylistOrder order: [UUID] = []) throws -> CollectionExchangeDocument {
        try validate()
        guard order.count <= CollectionExchangeCodec.maximumPlaylists, Set(order).count == order.count else { throw CollectionSyncError.invalidSnapshot }
        var document = try materialize()
        let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        document.playlists.sort {
            let a = ranks[$0.id] ?? Int.max, b = ranks[$1.id] ?? Int.max
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
        return document
    }

    public func validate() throws {
        guard format == Self.identifier else { throw CollectionSyncError.invalidSnapshot }
        guard schemaVersion == 1 else { throw CollectionSyncError.unsupportedVersion(schemaVersion) }
        guard cells.count <= CollectionSyncCodec.maximumCells else { throw CollectionSyncError.oversized }
        var seen = Set<CollectionSyncKey>(), tracks = 0, playlists = 0, markers = 0, favorites = 0
        var settings = [CollectionSyncField: Int]()
        for cell in cells {
            guard seen.insert(cell.id).inserted else { throw CollectionSyncError.invalidSnapshot }
            switch (cell.id, cell.value) {
            case (.track, .track), (.track, .deleted): tracks += 1
            case (.playlist(let id), .playlist(let value)):
                guard id == value.id else { throw CollectionSyncError.invalidSnapshot }; playlists += 1
            case (.playlist, .deleted): playlists += 1
            case (.marker(let id), .marker(let value)):
                guard id == value.id else { throw CollectionSyncError.invalidSnapshot }; markers += 1
            case (.marker, .deleted): markers += 1
            case (.favorite, .flag(true)), (.favorite, .deleted): favorites += 1
            case (.trackSetting(_, let field), let value):
                guard Self.valid(value, field: field, allowsInheritance: true) else { throw CollectionSyncError.invalidSnapshot }
                settings[field, default: 0] += 1
            case (.defaultSetting(let field), let value):
                guard Self.valid(value, field: field, allowsInheritance: false) else { throw CollectionSyncError.invalidSnapshot }
            default: throw CollectionSyncError.invalidSnapshot
            }
        }
        guard tracks <= CollectionExchangeCodec.maximumTracks,
              playlists <= CollectionExchangeCodec.maximumPlaylists,
              markers <= CollectionExchangeCodec.maximumMarkers,
              favorites <= CollectionExchangeCodec.maximumTracks,
              settings.values.allSatisfy({ $0 <= CollectionExchangeCodec.maximumTracks }) else { throw CollectionSyncError.oversized }
        do { try CollectionExchangeCodec.validate(materialize(sorted: false)) }
        catch CollectionExchangeError.oversized { throw CollectionSyncError.oversized }
        catch { throw CollectionSyncError.invalidSnapshot }
    }

    func indexed() -> [CollectionSyncKey: CollectionSyncValue] { Dictionary(uniqueKeysWithValues: cells.map { ($0.id, $0.value) }) }

    func mappingRequirements() -> (known: Set<UUID>, required: Set<UUID>) {
        var known = Set<UUID>(), required = Set<UUID>()
        for cell in cells {
            switch (cell.id, cell.value) {
            case (.track(let id), _): known.insert(id)
            case (.favorite(let id), _), (.trackSetting(let id, _), _): required.insert(id)
            case (.playlist, .playlist(let playlist)): required.formUnion(playlist.trackIDs)
            case (.marker, .marker(let marker)): required.insert(marker.trackID)
            default: break
            }
        }
        return (known.union(required), required)
    }

    private func materialize(sorted: Bool = true) throws -> CollectionExchangeDocument {
        var document = CollectionExchangeDocument(id: collectionID, createdAt: Date(timeIntervalSince1970: 0))
        var settings = [UUID: TrackPlaybackOverrides](), defaults = [CollectionSyncField: CollectionSyncValue]()
        var referencedSettings = Set<UUID>()
        for cell in sorted ? CollectionSyncCell.ordered(cells) : cells {
            switch (cell.id, cell.value) {
            case (.track(let id), .track(let value)): document.tracks.append(.init(id: id, descriptor: value))
            case (.playlist, .playlist(let value)): document.playlists.append(value)
            case (.marker, .marker(let value)): document.markers.append(value)
            case (.favorite(let id), .flag(true)): document.favoriteTrackIDs.append(id)
            case (.trackSetting(let id, let field), let value):
                referencedSettings.insert(id)
                var overrides = settings[id] ?? .init()
                switch (field, value) {
                case (.palClock, .flag(let flag)): overrides.palClock = flag
                case (.stereoSeparation, .number(let number)): overrides.stereoSeparation = number
                case (.useInterpolation, .flag(let flag)): overrides.useInterpolation = flag
                case (.ledFilterActive, .flag(let flag)): overrides.ledFilterActive = flag
                default: break
                }
                settings[id] = overrides
            case (.defaultSetting(let field), let value): defaults[field] = value
            default: break
            }
        }
        guard referencedSettings.isSubset(of: Set(document.tracks.map(\.id))) else { throw CollectionSyncError.invalidSnapshot }
        let settingIDs = sorted ? settings.keys.map { ($0.uuidString, $0) }.sorted { $0.0 < $1.0 }.map(\.1) : Array(settings.keys)
        document.trackSettings = settingIDs.compactMap { id in
            let overrides = settings[id]!
            return overrides.isEmpty ? nil : .init(trackID: id, overrides: overrides)
        }
        if !defaults.isEmpty {
            guard case .flag(let pal)? = defaults[.palClock], case .number(let separation)? = defaults[.stereoSeparation],
                  case .flag(let interpolation)? = defaults[.useInterpolation], case .flag(let filter)? = defaults[.ledFilterActive] else {
                throw CollectionSyncError.invalidSnapshot
            }
            document.playbackDefaults = .init(.init(palClock: pal, stereoSeparation: separation,
                                                   useInterpolation: interpolation, ledFilterActive: filter))
        }
        return document
    }

    private static func valid(_ value: CollectionSyncValue, field: CollectionSyncField, allowsInheritance: Bool) -> Bool {
        if value == .inherit { return allowsInheritance }
        switch (field, value) {
        case (.stereoSeparation, .number(let number)): return number.isFinite && (0...1).contains(number)
        case (.palClock, .flag), (.useInterpolation, .flag), (.ledFilterActive, .flag): return true
        default: return false
        }
    }
    private static func value(_ overrides: TrackPlaybackOverrides, field: CollectionSyncField) -> CollectionSyncValue {
        switch field {
        case .palClock: overrides.palClock.map(CollectionSyncValue.flag) ?? .inherit
        case .stereoSeparation: overrides.stereoSeparation.map(CollectionSyncValue.number) ?? .inherit
        case .useInterpolation: overrides.useInterpolation.map(CollectionSyncValue.flag) ?? .inherit
        case .ledFilterActive: overrides.ledFilterActive.map(CollectionSyncValue.flag) ?? .inherit
        }
    }
}

public enum CollectionSyncError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedVersion(Int), oversized, invalidSnapshot, mismatchedCollection, staleGeneration
    case incompleteSnapshot, stalePreview, unresolvedConflicts, invalidDecision, invalidCheckpoint, staleAccount, unappliedDecisions
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Die Abgleichdaten verwenden eine nicht unterstützte Version (\(version))."
        case .oversized: "Die Abgleichdaten überschreiten die Größenbegrenzung."
        case .invalidSnapshot: "Die Abgleichdaten enthalten ungültige Werte oder Referenzen."
        case .mismatchedCollection: "Die Abgleichdaten gehören zu einer anderen Sammlung."
        case .staleGeneration: "Die Sammlung wurde für eine neue Abgleichgeneration eingerichtet."
        case .incompleteSnapshot: "Im Abgleichstand fehlen bekannte Einträge. Löschungen müssen ausdrücklich vermerkt sein."
        case .stalePreview: "Die Sammlung hat sich seit der Abgleichvorschau geändert."
        case .unresolvedConflicts: "Die Abgleichkonflikte sind noch nicht vollständig entschieden."
        case .invalidDecision: "Eine Konfliktentscheidung passt nicht zu diesem Abgleich."
        case .invalidCheckpoint: "Der lokale Abgleichstand konnte nicht sicher gelesen werden."
        case .staleAccount: "Das iCloud-Konto hat sich seit Beginn des Vorgangs geändert."
        case .unappliedDecisions: "Vorgemerkte Abgleichentscheidungen müssen zuerst im bisherigen iCloud-Konto übernommen werden."
        }
    }
}

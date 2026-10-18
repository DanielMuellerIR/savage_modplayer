import Foundation

public struct CollectionSyncProjection: Sendable {
    public let unresolvedTrackIDs: [UUID]
    public var isReady: Bool { unresolvedTrackIDs.isEmpty }
    private let original: CollectionExchangeSnapshot
    private let mapping: [UUID: PlaylistTrackReference]
    private let candidate: CollectionExchangeSnapshot?

    public init(snapshot: CollectionSyncSnapshot, into local: CollectionExchangeSnapshot,
                mapping: [UUID: PlaylistTrackReference], collectionID: UUID, generation: UUID) throws {
        try snapshot.validate(); try local.validate()
        guard snapshot.collectionID == collectionID else { throw CollectionSyncError.mismatchedCollection }
        guard snapshot.generation == generation else { throw CollectionSyncError.staleGeneration }
        let (known, required) = snapshot.mappingRequirements()
        guard mapping.count <= 2 * CollectionExchangeCodec.maximumTracks,
              Set(mapping.keys).isSubset(of: known), Set(mapping.values.map(\.id)).count == mapping.count,
              mapping.values.allSatisfy({ $0.source.isValid && !$0.displayName.isEmpty }) else {
            throw CollectionExchangeError.invalidMapping
        }
        original = local; self.mapping = mapping
        unresolvedTrackIDs = required.subtracting(mapping.keys).sorted { $0.uuidString < $1.uuidString }
        guard unresolvedTrackIDs.isEmpty else { candidate = nil; return }
        var result = local
        for cell in CollectionSyncCell.ordered(snapshot.cells) {
            switch (cell.id, cell.value) {
            case (.playlist(let id), .deleted): result.playlists.playlists.removeAll { $0.id == id }
            case (.playlist, .playlist(let playlist)):
                let incoming = SavedPlaylist(id: playlist.id, name: playlist.name, tracks: playlist.trackIDs.map { mapping[$0]! })
                if let index = result.playlists.playlists.firstIndex(where: { $0.id == incoming.id }) {
                    result.playlists.playlists[index] = incoming
                } else { result.playlists.playlists.append(incoming) }
            case (.marker(let id), .deleted): result.markers.markers.removeAll { $0.id == id }
            case (.marker, .marker(let marker)):
                let incoming = SongMarker(id: marker.id, sourceID: mapping[marker.trackID]!.id, name: marker.name,
                                          address: marker.address, createdAt: marker.createdAt)
                if let index = result.markers.markers.firstIndex(where: { $0.id == incoming.id }) {
                    result.markers.markers[index] = incoming
                } else { result.markers.markers.append(incoming) }
            case (.favorite(let id), .deleted): result.playlists.favoriteIDs.remove(mapping[id]!.id)
            case (.favorite(let id), .flag(true)): result.playlists.favoriteIDs.insert(mapping[id]!.id)
            case (.trackSetting(let id, let field), let value):
                let sourceID = mapping[id]!.id
                var overrides = result.trackSettings.tracks[sourceID] ?? .init()
                switch (field, value) {
                case (.palClock, .flag(let flag)): overrides.palClock = flag
                case (.stereoSeparation, .number(let number)): overrides.stereoSeparation = number
                case (.useInterpolation, .flag(let flag)): overrides.useInterpolation = flag
                case (.ledFilterActive, .flag(let flag)): overrides.ledFilterActive = flag
                case (.palClock, .inherit): overrides.palClock = nil
                case (.stereoSeparation, .inherit): overrides.stereoSeparation = nil
                case (.useInterpolation, .inherit): overrides.useInterpolation = nil
                case (.ledFilterActive, .inherit): overrides.ledFilterActive = nil
                default: throw CollectionSyncError.invalidSnapshot
                }
                if overrides.isEmpty { result.trackSettings.tracks.removeValue(forKey: sourceID) }
                else { result.trackSettings.tracks[sourceID] = overrides }
            // Ein Track-Tombstone löscht niemals die lokale Musikdatei.
            case (.track, _): break
            default: break
            }
        }
        if let defaults = try snapshot.exchangeDocument().playbackDefaults { result.playbackDefaults = defaults.options }
        try result.validate(); candidate = result
    }

    public func result(ifUnchanged local: CollectionExchangeSnapshot,
                       mapping currentMapping: [UUID: PlaylistTrackReference]) throws -> CollectionExchangeSnapshot {
        guard local == original, currentMapping == mapping else { throw CollectionSyncError.stalePreview }
        guard let candidate else { throw CollectionExchangeError.unmappedSources }
        return candidate
    }
}

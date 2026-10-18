import Foundation

// Die iPhone-Bibliothek verwendet rohe relative Pfade für Titel-Metadaten,
// Playlists dagegen die daraus abgeleiteten Quellen-IDs. Der Austauschplan
// arbeitet einheitlich mit Quellen-IDs; diese Zuordnung erhält beide Speicherformen.
public struct LibraryCollectionExchangeAdapter: Sendable {
    public let snapshot: CollectionExchangeSnapshot
    private let pathsBySourceID: [String: String]
    private let originalPlaylistFavorites: Set<String>

    public init(documents: CollectionExchangeStoredDocuments, favoritePaths: Set<String>,
                availablePaths: [String], defaults: PlaybackOptions) throws {
        guard availablePaths.count <= CollectionExchangeCodec.maximumTracks,
              documents.playlists.playlists.allSatisfy({ $0.tracks.allSatisfy { $0.source.libraryRelativePath != nil } }) else {
            throw CollectionExchangeError.invalidLocalState
        }
        var paths = favoritePaths.union(availablePaths).union(documents.markers.markers.map(\.sourceID))
            .union(documents.trackSettings.tracks.keys)
        for playlist in documents.playlists.playlists { for track in playlist.tracks { paths.insert(track.source.libraryRelativePath!) } }
        guard paths.count <= CollectionExchangeCodec.maximumTracks else { throw CollectionExchangeError.oversized }
        var idsByPath: [String: String] = [:], reverse: [String: String] = [:]
        for path in paths {
            guard let source = PlaylistTrackSource(libraryRelativePath: path), TrackPlaybackSettingsStore.validID(source.id),
                  reverse[source.id] == nil else { throw CollectionExchangeError.invalidLocalState }
            idsByPath[path] = source.id; reverse[source.id] = path
        }
        var normalized = CollectionExchangeSnapshot(playlists: documents.playlists, markers: documents.markers,
                                                    trackSettings: documents.trackSettings, playbackDefaults: defaults)
        normalized.playlists.favoriteIDs = Set(favoritePaths.map { idsByPath[$0]! })
        normalized.markers.markers = documents.markers.markers.map {
            Self.marker($0, sourceID: idsByPath[$0.sourceID]!)
        }
        normalized.trackSettings.tracks = Dictionary(uniqueKeysWithValues: documents.trackSettings.tracks.map { (idsByPath[$0.key]!, $0.value) })
        try normalized.validate()
        snapshot = normalized; pathsBySourceID = reverse; originalPlaylistFavorites = documents.playlists.favoriteIDs
    }

    public func storedResult(from snapshot: CollectionExchangeSnapshot) throws -> (documents: CollectionExchangeStoredDocuments, favoritePaths: Set<String>) {
        try snapshot.validate()
        let ids = snapshot.playlists.favoriteIDs.union(snapshot.markers.markers.map(\.sourceID)).union(snapshot.trackSettings.tracks.keys)
        guard ids.allSatisfy({ pathsBySourceID[$0] != nil }),
              snapshot.playlists.playlists.allSatisfy({ $0.tracks.allSatisfy { $0.source.libraryRelativePath != nil } }) else {
            throw CollectionExchangeError.invalidMapping
        }
        var playlists = snapshot.playlists, markers = snapshot.markers, settings = snapshot.trackSettings
        playlists.favoriteIDs = originalPlaylistFavorites
        markers.markers = snapshot.markers.markers.map { Self.marker($0, sourceID: pathsBySourceID[$0.sourceID]!) }
        settings.tracks = Dictionary(uniqueKeysWithValues: snapshot.trackSettings.tracks.map { (pathsBySourceID[$0.key]!, $0.value) })
        return (.init(playlists: playlists, markers: markers, trackSettings: settings), Set(snapshot.playlists.favoriteIDs.map { pathsBySourceID[$0]! }))
    }

    private static func marker(_ value: SongMarker, sourceID: String) -> SongMarker {
        var copy = SongMarker(id: value.id, sourceID: sourceID, name: value.name, address: value.address, createdAt: value.createdAt)
        copy.name = value.name
        return copy
    }
}

import Foundation

public struct CollectionExchangeSnapshot: Equatable, Sendable {
    public var playlists: SavedPlaylistDocument
    public var markers: SongMarkerDocument
    public var trackSettings: TrackPlaybackSettingsDocument
    public var playbackDefaults: PlaybackOptions?
    public init(playlists: SavedPlaylistDocument = .init(), markers: SongMarkerDocument = .init(),
                trackSettings: TrackPlaybackSettingsDocument = .init(), playbackDefaults: PlaybackOptions? = nil) {
        self.playlists = playlists; self.markers = markers; self.trackSettings = trackSettings
        self.playbackDefaults = playbackDefaults
    }
    public var referencedSourceIDs: Set<String> {
        var ids = playlists.favoriteIDs
        for playlist in playlists.playlists { for track in playlist.tracks { ids.insert(track.id) } }
        for marker in markers.markers { ids.insert(marker.sourceID) }
        ids.formUnion(trackSettings.tracks.keys)
        return ids
    }

    func validate() throws {
        guard playlists.formatVersion == 1, markers.formatVersion == 1, trackSettings.formatVersion == 1,
              playlists.playlists.count <= CollectionExchangeCodec.maximumPlaylists,
              markers.markers.count <= CollectionExchangeCodec.maximumMarkers,
              trackSettings.tracks.count <= CollectionExchangeCodec.maximumTracks,
              playlists.favoriteIDs.count <= CollectionExchangeCodec.maximumTracks,
              Set(playlists.playlists.map(\.id)).count == playlists.playlists.count,
              Set(markers.markers.map(\.id)).count == markers.markers.count,
              playbackDefaults.map({ CollectionExchangeCodec.validSeparation($0.stereoSeparation) }) ?? true else {
            throw CollectionExchangeError.invalidLocalState
        }
        var entries = 0
        var playlistBytes = 512
        for playlist in playlists.playlists {
            entries += playlist.tracks.count
            guard entries <= CollectionExchangeCodec.maximumPlaylistEntries, playlist.tracks.count <= 50_000,
                  !playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, playlist.name.count <= 200,
                  Set(playlist.tracks.map(\.id)).count == playlist.tracks.count,
                  playlist.tracks.allSatisfy({ $0.source.isValid && !$0.displayName.isEmpty && TrackPlaybackSettingsStore.validID($0.id) }) else {
                throw CollectionExchangeError.invalidLocalState
            }
            playlistBytes += 128 + playlist.name.utf8.count * 6
            for track in playlist.tracks { playlistBytes += 256 + track.id.utf8.count * 12 + track.displayName.utf8.count * 6 }
            guard playlistBytes <= CollectionExchangeCodec.maximumBytes else { throw CollectionExchangeError.oversized }
        }
        guard referencedSourceIDs.count <= CollectionExchangeCodec.maximumTracks,
              playlists.favoriteIDs.allSatisfy(TrackPlaybackSettingsStore.validID) else {
            throw CollectionExchangeError.invalidLocalState
        }
        playlistBytes += playlists.favoriteIDs.reduce(0) { $0 + 32 + $1.utf8.count * 6 }
        guard playlistBytes <= CollectionExchangeCodec.maximumBytes else { throw CollectionExchangeError.oversized }
        var markerBytes = 512
        for marker in markers.markers {
            guard TrackPlaybackSettingsStore.validID(marker.sourceID), marker.address.isValidStorageValue,
                  !marker.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, marker.name.count <= 200,
                  marker.createdAt.timeIntervalSince1970.isFinite else { throw CollectionExchangeError.invalidLocalState }
            markerBytes += 256 + marker.sourceID.utf8.count * 6 + marker.name.utf8.count * 6
            guard markerBytes <= SongMarkerStore.maximumBytes else { throw CollectionExchangeError.oversized }
        }
        guard trackSettings.tracks.allSatisfy({ TrackPlaybackSettingsStore.validID($0.key)
            && CollectionExchangeCodec.validOverrides($0.value) }) else { throw CollectionExchangeError.invalidLocalState }
        let settingsBytes = trackSettings.tracks.keys.reduce(64) { $0 + $1.utf8.count * 6 + 160 }
        guard settingsBytes <= TrackPlaybackSettingsStore.maximumBytes else { throw CollectionExchangeError.oversized }
    }
}

public struct CollectionExchangeLocalTrack: Equatable, Sendable {
    public var reference: PlaylistTrackReference
    public var descriptor: ExchangeTrackDescriptor
    public init(reference: PlaylistTrackReference, descriptor: ExchangeTrackDescriptor) {
        self.reference = reference; self.descriptor = descriptor
    }
}

public enum CollectionExchangeExporter {
    public static func makeDocument(from snapshot: CollectionExchangeSnapshot,
                                    sources: [CollectionExchangeLocalTrack],
                                    id: UUID = UUID(), createdAt: Date = Date()) throws -> CollectionExchangeDocument {
        try makeDocument(from: snapshot, sources: sources, id: id, createdAt: createdAt, trackID: { _ in UUID() })
    }

    public static func makeDocument(from snapshot: CollectionExchangeSnapshot,
                                    sources: [CollectionExchangeLocalTrack], id: UUID = UUID(), createdAt: Date = Date(),
                                    trackID: (PlaylistTrackReference) throws -> UUID) throws -> CollectionExchangeDocument {
        try snapshot.validate()
        guard sources.count <= CollectionExchangeCodec.maximumTracks,
              Set(sources.map { $0.reference.id }).count == sources.count else { throw CollectionExchangeError.invalidMapping }
        let usedIDs = snapshot.referencedSourceIDs
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.reference.id, $0) })
        guard usedIDs.allSatisfy({ sourcesByID[$0] != nil }) else { throw CollectionExchangeError.unmappedSources }
        var document = CollectionExchangeDocument(id: id, createdAt: createdAt)
        var mapping: [String: UUID] = [:]
        for sourceID in usedIDs.sorted() {
            let source = sourcesByID[sourceID]!
            guard source.reference.source.isValid else { throw CollectionExchangeError.invalidMapping }
            try CollectionExchangeCodec.validate(source.descriptor)
            let track = ExchangeTrack(id: try trackID(source.reference), descriptor: source.descriptor)
            mapping[sourceID] = track.id; document.tracks.append(track)
        }
        document.playlists = snapshot.playlists.playlists.map {
            ExchangePlaylist(id: $0.id, name: $0.name, trackIDs: $0.tracks.map { mapping[$0.id]! })
        }
        document.favoriteTrackIDs = snapshot.playlists.favoriteIDs.sorted().map { mapping[$0]! }
        document.markers = snapshot.markers.markers.map {
            ExchangeSongMarker(id: $0.id, trackID: mapping[$0.sourceID]!, name: $0.name,
                               address: $0.address, createdAt: $0.createdAt)
        }
        document.trackSettings = snapshot.trackSettings.tracks.keys.sorted().map {
            ExchangeTrackSettings(trackID: mapping[$0]!, overrides: snapshot.trackSettings.tracks[$0]!)
        }
        document.playbackDefaults = snapshot.playbackDefaults.map(ExchangePlaybackDefaults.init)
        try CollectionExchangeCodec.validate(document)
        return document
    }
}

public enum ExchangeTrackMatch: Equatable, Sendable {
    case matched(String)
    case ambiguous([String], totalCount: Int)
    case missing
}

public enum CollectionExchangeMatcher {
    public static let maximumSuggestions = 8
    private enum Key: Hashable {
        case hash(String, Int64?), path(String, [String], Int64?), name(String, Int64?)
    }
    // Ein vorhandener Inhaltsnachweis darf nicht durch einen bloßen Namensfund
    // ersetzt werden. Mehrere identische Kopien erfordern weiterhin eine Wahl.
    public static func match(_ document: CollectionExchangeDocument,
                             against sources: [CollectionExchangeLocalTrack]) throws -> [UUID: ExchangeTrackMatch] {
        try CollectionExchangeCodec.validate(document)
        guard sources.count <= CollectionExchangeCodec.maximumTracks,
              Set(sources.map { $0.reference.id }).count == sources.count,
              sources.allSatisfy({ $0.reference.source.isValid && TrackPlaybackSettingsStore.validID($0.reference.id) }) else {
            throw CollectionExchangeError.invalidMapping
        }
        var sourceBytes = 0
        for source in sources {
            try CollectionExchangeCodec.validate(source.descriptor)
            sourceBytes += 512 + source.reference.id.utf8.count * 6 + source.descriptor.fileName.utf8.count * 6
                + (source.descriptor.relativePath?.utf8.count ?? 0) * 6
                + source.descriptor.archiveMembers.reduce(0) { $0 + $1.utf8.count * 6 }
            guard sourceBytes <= CollectionExchangeCodec.maximumBytes else { throw CollectionExchangeError.oversized }
        }
        var index: [Key: [String]] = [:]
        for source in sources {
            let descriptor = source.descriptor
            let sizes: [Int64?] = descriptor.byteCount.map { [nil, $0] } ?? [nil]
            for size in sizes {
                index[.name(descriptor.fileName, size), default: []].append(source.reference.id)
                if let hash = descriptor.sha256 { index[.hash(hash, size), default: []].append(source.reference.id) }
                if let path = descriptor.relativePath {
                    index[.path(path, descriptor.archiveMembers, size), default: []].append(source.reference.id)
                }
            }
        }
        for key in Array(index.keys) { index[key]?.sort() }
        var result: [UUID: ExchangeTrackMatch] = [:]
        for track in document.tracks {
            let descriptor = track.descriptor
            let candidates: [String]
            if let hash = descriptor.sha256 {
                candidates = index[.hash(hash, descriptor.byteCount)] ?? []
            } else if let path = descriptor.relativePath,
                      index[.path(path, descriptor.archiveMembers, nil)] != nil {
                candidates = index[.path(path, descriptor.archiveMembers, descriptor.byteCount)] ?? []
            } else {
                candidates = index[.name(descriptor.fileName, descriptor.byteCount)] ?? []
            }
            switch candidates.count {
            case 0: result[track.id] = .missing
            case 1: result[track.id] = .matched(candidates[0])
            default:
                result[track.id] = .ambiguous(Array(candidates.prefix(maximumSuggestions)), totalCount: candidates.count)
            }
        }
        return result
    }
}

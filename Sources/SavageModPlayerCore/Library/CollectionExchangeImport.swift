import Foundation

public enum CollectionExchangeConflictID: Hashable, Sendable {
    case playlist(UUID), playlistName(UUID), marker(UUID), trackSettings(String), playbackDefaults
}

public enum CollectionExchangeResolution: String, CaseIterable, Sendable {
    case keepLocal, useIncoming, keepBoth
}

public struct CollectionExchangeConflict: Equatable, Sendable, Identifiable {
    public enum Value: Equatable, Sendable {
        case playlist(SavedPlaylist), marker(SongMarker), overrides(TrackPlaybackOverrides), defaults(PlaybackOptions)
        case matchingPlaylistNames(Int)
    }
    public let id: CollectionExchangeConflictID
    public let name: String
    public let allowedResolutions: [CollectionExchangeResolution]
    public let local: Value
    public let incoming: Value
}

public struct CollectionExchangeImportPreview: Sendable {
    public let unresolvedTrackIDs: [UUID]
    public let skippedTrackIDs: Set<UUID>
    public let conflicts: [CollectionExchangeConflict]
    public let undecidedConflicts: Set<CollectionExchangeConflictID>
    public var isReady: Bool { unresolvedTrackIDs.isEmpty && undecidedConflicts.isEmpty }
    private let base: CollectionExchangeSnapshot
    private let candidate: CollectionExchangeSnapshot

    fileprivate init(unresolvedTrackIDs: [UUID], skippedTrackIDs: Set<UUID>,
                     conflicts: [CollectionExchangeConflict], undecidedConflicts: Set<CollectionExchangeConflictID>,
                     base: CollectionExchangeSnapshot, candidate: CollectionExchangeSnapshot) {
        self.unresolvedTrackIDs = unresolvedTrackIDs; self.skippedTrackIDs = skippedTrackIDs
        self.conflicts = conflicts; self.undecidedConflicts = undecidedConflicts
        self.base = base; self.candidate = candidate
    }

    // Die Vorschau schreibt nichts. Der Aufrufer übernimmt erst nach Bestätigung
    // und Vergleich mit dem unveränderten Ausgangsstand alle betroffenen Speicher.
    public func result(ifUnchanged current: CollectionExchangeSnapshot) throws -> CollectionExchangeSnapshot {
        guard current == base else { throw CollectionExchangeError.stalePreview }
        guard unresolvedTrackIDs.isEmpty else { throw CollectionExchangeError.invalidMapping }
        guard undecidedConflicts.isEmpty else { throw CollectionExchangeError.invalidDecision }
        try candidate.validate()
        return candidate
    }
}

public enum CollectionExchangeImporter {
    public static func preview(
        _ document: CollectionExchangeDocument, into local: CollectionExchangeSnapshot,
        mapping: [UUID: PlaylistTrackReference], skippedTrackIDs: Set<UUID> = [],
        resolutions: [CollectionExchangeConflictID: CollectionExchangeResolution] = [:]
    ) throws -> CollectionExchangeImportPreview {
        try CollectionExchangeCodec.validate(document)
        try local.validate()
        let trackIDs = Set(document.tracks.map(\.id))
        guard Set(mapping.keys).isSubset(of: trackIDs), skippedTrackIDs.isSubset(of: trackIDs),
              Set(mapping.keys).isDisjoint(with: skippedTrackIDs),
              Set(mapping.values.map(\.id)).count == mapping.count,
              mapping.values.allSatisfy({ $0.source.isValid && !$0.displayName.isEmpty }) else {
            throw CollectionExchangeError.invalidMapping
        }
        let unresolved = document.tracks.map(\.id).filter { mapping[$0] == nil && !skippedTrackIDs.contains($0) }
        var candidate = local
        var conflicts: [CollectionExchangeConflict] = []
        var undecided: Set<CollectionExchangeConflictID> = []

        func decision(_ id: CollectionExchangeConflictID, name: String,
                      allowing allowed: [CollectionExchangeResolution],
                      local: CollectionExchangeConflict.Value, incoming: CollectionExchangeConflict.Value) throws -> CollectionExchangeResolution {
            conflicts.append(CollectionExchangeConflict(id: id, name: name, allowedResolutions: allowed, local: local, incoming: incoming))
            guard let resolution = resolutions[id] else { undecided.insert(id); return .keepLocal }
            guard allowed.contains(resolution) else { throw CollectionExchangeError.invalidDecision }
            return resolution
        }

        for playlist in document.playlists {
            let incoming = SavedPlaylist(id: playlist.id, name: playlist.name,
                                         tracks: playlist.trackIDs.compactMap { mapping[$0] })
            if let index = candidate.playlists.playlists.firstIndex(where: { $0.id == incoming.id }) {
                if candidate.playlists.playlists[index] == incoming { continue }
                switch try decision(.playlist(incoming.id), name: incoming.name, allowing: [.keepLocal, .useIncoming, .keepBoth],
                                    local: .playlist(candidate.playlists.playlists[index]), incoming: .playlist(incoming)) {
                case .keepLocal: break
                case .useIncoming: candidate.playlists.playlists[index] = incoming
                case .keepBoth:
                    candidate.playlists.playlists.append(copy(incoming, among: candidate.playlists.playlists))
                }
            } else if candidate.playlists.playlists.contains(where: { normalizedName($0.name) == normalizedName(incoming.name) }) {
                // Gleiche Namen sind keine Identität. Ohne eindeutige ID darf keine
                // bestehende Liste allein wegen ihres Namens ersetzt werden.
                let count = candidate.playlists.playlists.filter { normalizedName($0.name) == normalizedName(incoming.name) }.count
                switch try decision(.playlistName(incoming.id), name: incoming.name, allowing: [.keepLocal, .keepBoth],
                                    local: .matchingPlaylistNames(count), incoming: .playlist(incoming)) {
                case .keepLocal: break
                case .keepBoth: candidate.playlists.playlists.append(copy(incoming, among: candidate.playlists.playlists, preservingID: true))
                case .useIncoming: throw CollectionExchangeError.invalidDecision
                }
            } else { candidate.playlists.playlists.append(incoming) }
        }
        candidate.playlists.favoriteIDs.formUnion(document.favoriteTrackIDs.compactMap { mapping[$0]?.id })

        for marker in document.markers {
            guard let track = mapping[marker.trackID] else { continue }
            let incoming = SongMarker(id: marker.id, sourceID: track.id, name: marker.name,
                                      address: marker.address, createdAt: marker.createdAt)
            if let index = candidate.markers.markers.firstIndex(where: { $0.id == incoming.id }) {
                let previous = candidate.markers.markers[index]
                if previous.sourceID == incoming.sourceID && previous.name == incoming.name && previous.address == incoming.address { continue }
                switch try decision(.marker(incoming.id), name: incoming.name, allowing: [.keepLocal, .useIncoming, .keepBoth],
                                    local: .marker(previous), incoming: .marker(incoming)) {
                case .keepLocal: break
                case .useIncoming: candidate.markers.markers[index] = incoming
                case .keepBoth:
                    candidate.markers.markers.append(SongMarker(sourceID: incoming.sourceID, name: incoming.name,
                                                               address: incoming.address, createdAt: incoming.createdAt))
                }
            } else { candidate.markers.markers.append(incoming) }
        }
        for settings in document.trackSettings {
            guard let track = mapping[settings.trackID] else { continue }
            if let previous = candidate.trackSettings.tracks[track.id], previous != settings.overrides {
                switch try decision(.trackSettings(track.id), name: track.displayName, allowing: [.keepLocal, .useIncoming],
                                    local: .overrides(previous), incoming: .overrides(settings.overrides)) {
                case .keepLocal: continue
                case .useIncoming: break
                case .keepBoth: throw CollectionExchangeError.invalidDecision
                }
            }
            candidate.trackSettings.tracks[track.id] = settings.overrides
        }
        if let defaults = document.playbackDefaults?.options {
            if let previous = local.playbackDefaults, previous != defaults {
                switch try decision(.playbackDefaults, name: "Klang-Vorgaben", allowing: [.keepLocal, .useIncoming],
                                    local: .defaults(previous), incoming: .defaults(defaults)) {
                case .keepLocal: break
                case .useIncoming: candidate.playbackDefaults = defaults
                case .keepBoth: throw CollectionExchangeError.invalidDecision
                }
            } else { candidate.playbackDefaults = defaults }
        }
        guard Set(resolutions.keys).isSubset(of: Set(conflicts.map(\.id))) else { throw CollectionExchangeError.invalidDecision }
        try candidate.validate()
        return CollectionExchangeImportPreview(unresolvedTrackIDs: unresolved, skippedTrackIDs: skippedTrackIDs,
                                               conflicts: conflicts, undecidedConflicts: undecided,
                                               base: local, candidate: candidate)
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private static func copy(_ incoming: SavedPlaylist, among playlists: [SavedPlaylist], preservingID: Bool = false) -> SavedPlaylist {
        let names = Set(playlists.map { normalizedName($0.name) })
        var suffix = 2
        var name: String
        repeat {
            let ending = " (\(suffix))"
            name = String(incoming.name.prefix(200 - ending.count)) + ending
            suffix += 1
        } while names.contains(normalizedName(name))
        return SavedPlaylist(id: preservingID ? incoming.id : UUID(), name: name, tracks: incoming.tracks)
    }
}

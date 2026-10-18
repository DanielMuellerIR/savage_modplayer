import Foundation

public struct ExchangeTrackDescriptor: Codable, Equatable, Hashable, Sendable {
    public var fileName: String
    public var relativePath: String?
    public var archiveMembers: [String]
    public var byteCount: Int64?
    public var sha256: String?

    public init(fileName: String, relativePath: String? = nil, archiveMembers: [String] = [],
                byteCount: Int64? = nil, sha256: String? = nil) {
        self.fileName = fileName; self.relativePath = relativePath; self.archiveMembers = archiveMembers
        self.byteCount = byteCount; self.sha256 = sha256
    }
}

public struct ExchangeTrack: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var descriptor: ExchangeTrackDescriptor
    public init(id: UUID = UUID(), descriptor: ExchangeTrackDescriptor) {
        self.id = id; self.descriptor = descriptor
    }
}

public struct ExchangePlaylist: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var trackIDs: [UUID]
    public init(id: UUID, name: String, trackIDs: [UUID]) {
        self.id = id; self.name = name; self.trackIDs = trackIDs
    }
}

public struct ExchangeSongMarker: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var trackID: UUID
    public var name: String
    public var address: SongAddress
    public var createdAt: Date
    public init(id: UUID, trackID: UUID, name: String, address: SongAddress, createdAt: Date) {
        self.id = id; self.trackID = trackID; self.name = name
        self.address = address; self.createdAt = createdAt
    }
}

public struct ExchangeTrackSettings: Codable, Equatable, Sendable {
    public var trackID: UUID
    public var overrides: TrackPlaybackOverrides
    public init(trackID: UUID, overrides: TrackPlaybackOverrides) {
        self.trackID = trackID; self.overrides = overrides
    }
}

public struct ExchangePlaybackDefaults: Codable, Equatable, Sendable {
    public var palClock: Bool
    public var stereoSeparation: Double
    public var useInterpolation: Bool
    public var ledFilterActive: Bool
    public init(_ options: PlaybackOptions) {
        palClock = options.palClock; stereoSeparation = options.stereoSeparation
        useInterpolation = options.useInterpolation; ledFilterActive = options.ledFilterActive
    }
    public var options: PlaybackOptions {
        PlaybackOptions(palClock: palClock, stereoSeparation: stereoSeparation,
                        useInterpolation: useInterpolation, ledFilterActive: ledFilterActive)
    }
}

// Austausch-IDs gelten innerhalb der Datei. Lokale Quellen-IDs und URLs kommen
// ausschließlich im Zuordnungsmodell vor und werden niemals mitcodiert.
public struct CollectionExchangeDocument: Codable, Equatable, Sendable {
    public static let identifier = "org.savage-mod-player.collection"
    public var format = Self.identifier
    public var formatVersion = 1
    public var id: UUID
    public var createdAt: Date
    public var tracks: [ExchangeTrack] = []
    public var playlists: [ExchangePlaylist] = []
    public var favoriteTrackIDs: [UUID] = []
    public var markers: [ExchangeSongMarker] = []
    public var trackSettings: [ExchangeTrackSettings] = []
    public var playbackDefaults: ExchangePlaybackDefaults?
    public init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id; self.createdAt = createdAt
    }
}

public enum CollectionExchangeError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedVersion(Int), invalidDocument, oversized, unreadable
    case unmappedSources, invalidMapping, invalidLocalState, stalePreview, invalidDecision
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Die Austauschdatei verwendet eine nicht unterstützte Version (\(version))."
        case .invalidDocument: "Die Austauschdatei enthält ungültige oder widersprüchliche Daten."
        case .oversized: "Die Austauschdaten überschreiten die Größenbegrenzung."
        case .unreadable: "Die Austauschdatei konnte nicht gelesen werden."
        case .unmappedSources: "Einige Titel sind noch keiner portablen Referenz zugeordnet."
        case .invalidMapping: "Die Titelzuordnung ist unvollständig oder mehrdeutig."
        case .invalidLocalState: "Die vorhandenen Sammlungsdaten sind ungültig."
        case .stalePreview: "Die Sammlung hat sich geändert. Bitte die Importvorschau neu erstellen."
        case .invalidDecision: "Eine Konfliktentscheidung passt nicht zu diesem Import."
        }
    }
}

public enum CollectionExchangeCodec {
    public static let fileExtension = "savagecollection"
    public static let contentTypeIdentifier = "com.viben.savage-modplayer.collection"
    public static let maximumBytes = 32 * 1024 * 1024
    public static let maximumTracks = 20_000
    public static let maximumPlaylists = 1_000
    public static let maximumPlaylistEntries = 100_000
    public static let maximumMarkers = 10_000
    private struct Header: Decodable { let format: String; let formatVersion: Int }

    public static func load(from url: URL, isCancelled: () -> Bool = { false }) throws -> CollectionExchangeDocument {
        do {
            guard !isCancelled() else { throw CancellationError() }
            let file = try LibraryFileReader(url)
            defer { file.close() }
            guard file.stamp.size <= maximumBytes else { throw CollectionExchangeError.oversized }
            return try decode(file.read(limit: maximumBytes, isCancelled: isCancelled))
        } catch is CancellationError { throw CancellationError()
        } catch LibraryFileReadError.oversized { throw CollectionExchangeError.oversized }
        catch let error as CollectionExchangeError { throw error }
        catch { throw CollectionExchangeError.unreadable }
    }

    public static func decode(_ data: Data) throws -> CollectionExchangeDocument {
        guard data.count <= maximumBytes else { throw CollectionExchangeError.oversized }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let header = try decoder.decode(Header.self, from: Data(data))
            guard header.formatVersion == 1 else { throw CollectionExchangeError.unsupportedVersion(header.formatVersion) }
            guard header.format == CollectionExchangeDocument.identifier else { throw CollectionExchangeError.invalidDocument }
            let document = try decoder.decode(CollectionExchangeDocument.self, from: Data(data))
            try validate(document)
            return document
        } catch let error as CollectionExchangeError { throw error }
        catch { throw CollectionExchangeError.invalidDocument }
    }

    public static func encode(_ document: CollectionExchangeDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Ungeordnete Mengen werden kanonisch ausgegeben; Playlist-Reihenfolgen bleiben erhalten.
        var canonical = document
        canonical.tracks.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.favoriteTrackIDs.sort { $0.uuidString < $1.uuidString }
        canonical.trackSettings.sort { $0.trackID.uuidString < $1.trackID.uuidString }
        let data = try encoder.encode(canonical)
        guard data.count <= maximumBytes else { throw CollectionExchangeError.oversized }
        return data
    }

    public static func validate(_ document: CollectionExchangeDocument) throws {
        guard document.formatVersion == 1 else { throw CollectionExchangeError.unsupportedVersion(document.formatVersion) }
        guard document.format == CollectionExchangeDocument.identifier,
              validDate(document.createdAt) else { throw CollectionExchangeError.invalidDocument }
        guard document.tracks.count <= maximumTracks, document.playlists.count <= maximumPlaylists,
              document.markers.count <= maximumMarkers, document.trackSettings.count <= maximumTracks,
              document.favoriteTrackIDs.count <= maximumTracks else { throw CollectionExchangeError.oversized }
        let ids = Set(document.tracks.map(\.id))
        guard ids.count == document.tracks.count,
              Set(document.playlists.map(\.id)).count == document.playlists.count,
              Set(document.markers.map(\.id)).count == document.markers.count,
              Set(document.trackSettings.map(\.trackID)).count == document.trackSettings.count,
              Set(document.favoriteTrackIDs).count == document.favoriteTrackIDs.count,
              document.favoriteTrackIDs.allSatisfy(ids.contains),
              document.playbackDefaults.map({ validSeparation($0.stereoSeparation) }) ?? true else {
            throw CollectionExchangeError.invalidDocument
        }
        var estimatedBytes = 512
        for track in document.tracks {
            try validate(track.descriptor)
            estimatedBytes += 512 + 6 * (track.descriptor.fileName.utf8.count
                + (track.descriptor.relativePath?.utf8.count ?? 0)
                + track.descriptor.archiveMembers.reduce(0) { $0 + $1.utf8.count })
        }
        var entries = 0
        for playlist in document.playlists {
            entries += playlist.trackIDs.count
            guard entries <= maximumPlaylistEntries, playlist.trackIDs.count <= 50_000 else {
                throw CollectionExchangeError.oversized
            }
            guard validName(playlist.name), Set(playlist.trackIDs).count == playlist.trackIDs.count,
                  playlist.trackIDs.allSatisfy(ids.contains) else { throw CollectionExchangeError.invalidDocument }
            estimatedBytes += 128 + playlist.name.utf8.count * 6 + playlist.trackIDs.count * 40
        }
        for marker in document.markers {
            guard ids.contains(marker.trackID), validName(marker.name), marker.address.isValidStorageValue,
                  validDate(marker.createdAt) else { throw CollectionExchangeError.invalidDocument }
            estimatedBytes += 256 + marker.name.utf8.count * 6
        }
        for setting in document.trackSettings {
            guard ids.contains(setting.trackID), validOverrides(setting.overrides) else {
                throw CollectionExchangeError.invalidDocument
            }
        }
        estimatedBytes += document.trackSettings.count * 256 + document.favoriteTrackIDs.count * 40
        guard estimatedBytes <= maximumBytes else { throw CollectionExchangeError.oversized }
    }

    static func validate(_ descriptor: ExchangeTrackDescriptor) throws {
        guard validComponent(descriptor.fileName),
              descriptor.relativePath.map(validRelativePath) ?? true,
              descriptor.archiveMembers.count <= PlaylistScanner.maxArchiveDepth,
              descriptor.archiveMembers.allSatisfy(validRelativePath),
              (descriptor.archiveMembers.last ?? descriptor.relativePath).map({ $0.split(separator: "/").last.map(String.init) == descriptor.fileName }) ?? true,
              descriptor.byteCount.map({ $0 >= 0 }) ?? true,
              descriptor.sha256.map({ $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) ?? true
        else { throw CollectionExchangeError.invalidDocument }
    }

    static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 200
            && name.utf8.count <= 800 && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func validSeparation(_ value: Double) -> Bool { value.isFinite && (0...1).contains(value) }
    static func validDate(_ value: Date) -> Bool { (0...253_402_300_799).contains(value.timeIntervalSince1970) }
    static func validOverrides(_ value: TrackPlaybackOverrides) -> Bool {
        !value.isEmpty && (value.stereoSeparation.map(validSeparation) ?? true)
    }
    static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.hasPrefix("~")
            && value.utf8.count <= 1_024 && !value.contains("/") && !value.contains("\\") && !value.contains(":")
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func validRelativePath(_ value: String) -> Bool {
        value.utf8.count <= 4_096
            && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { validComponent(String($0)) }
            && !value.isEmpty
    }
}

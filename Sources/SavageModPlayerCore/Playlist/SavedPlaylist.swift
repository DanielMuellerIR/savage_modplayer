import Foundation

// Die Quelle bleibt unabhaengig von den pro Sitzung neu erzeugten Temp-Kopien.
// Jedes archiveMembers-Element ist ein Pfad innerhalb EINER Archivebene.
public struct PlaylistTrackSource: Codable, Hashable, Sendable {
    public let location: URL
    public let archiveMembers: [String]
    // Links behalten ihren klassifizierenden Namen (.mod/.zip). Die kanonische
    // Identitaet wird separat gespeichert, auch wenn die Quelle spaeter fehlt.
    private let canonicalLocation: URL

    public init(location: URL, archiveMembers: [String] = []) {
        self.location = location.standardizedFileURL
        self.canonicalLocation = location.standardizedFileURL.resolvingSymlinksInPath()
        self.archiveMembers = archiveMembers
    }

    // Bibliotheksquellen enthalten bewusst keinen App-Containerpfad. Erst die
    // jeweilige Bibliothek loest den relativen Pfad in eine aktuelle Datei auf.
    public init?(libraryRelativePath: String) {
        guard Self.isRelativeLibraryPath(libraryRelativePath) else { return nil }
        var components = URLComponents()
        components.scheme = "savage-library"
        components.host = ""
        components.path = "/" + libraryRelativePath
        guard let url = components.url else { return nil }
        location = url
        canonicalLocation = url
        archiveMembers = []
    }

    public var libraryRelativePath: String? {
        guard location.scheme == "savage-library", location.host?.isEmpty != false,
              location.user == nil, location.password == nil, location.port == nil,
              location.query == nil, location.fragment == nil,
              location.path.hasPrefix("/") else { return nil }
        let path = String(location.path.dropFirst())
        return Self.isRelativeLibraryPath(path) ? path : nil
    }

    private static func isRelativeLibraryPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && !path.contains("\0")
            && path.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private init(location: URL, canonicalLocation: URL, archiveMembers: [String]) {
        self.location = location
        self.canonicalLocation = canonicalLocation
        self.archiveMembers = archiveMembers
    }

    // Fehlende Titel dürfen weiterhin ihre Metadaten exportieren. Diese inverse
    // Darstellung liest keine Datei und löst keine inzwischen geänderten Links auf.
    public init?(stableID: String) {
        guard TrackPlaybackSettingsStore.validID(stableID) else { return nil }
        let library = stableID.hasPrefix("library-v1:")
        guard library || stableID.hasPrefix("source-v1:") else { return nil }
        let bytes = Array(stableID.utf8)
        var offset = library ? "library-v1:".utf8.count : "source-v1:".utf8.count
        var values: [String] = []
        while offset < bytes.count {
            let start = offset
            while offset < bytes.count, (48...57).contains(bytes[offset]) { offset += 1 }
            guard offset > start, offset - start <= 5, offset < bytes.count, bytes[offset] == 58,
                  let count = Int(String(decoding: bytes[start..<offset], as: UTF8.self)), count > 0 else { return nil }
            offset += 1
            guard count <= bytes.count - offset,
                  let value = String(bytes: bytes[offset..<(offset + count)], encoding: .utf8) else { return nil }
            values.append(value); offset += count
            guard values.count <= PlaylistScanner.maxArchiveDepth + 1 else { return nil }
        }
        if library {
            guard values.count == 1, let source = Self(libraryRelativePath: values[0]), source.id == stableID else { return nil }
            self = source
        } else {
            guard let first = values.first, let url = URL(string: first), url.isFileURL else { return nil }
            self.init(location: url, canonicalLocation: url, archiveMembers: Array(values.dropFirst()))
            guard isValid, id == stableID else { return nil }
        }
    }

    private enum CodingKeys: String, CodingKey { case location, archiveMembers, canonicalLocation }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        location = try values.decode(URL.self, forKey: .location)
        archiveMembers = try values.decode([String].self, forKey: .archiveMembers)
        canonicalLocation = try values.decodeIfPresent(URL.self, forKey: .canonicalLocation)
            ?? (location.isFileURL ? location.standardizedFileURL.resolvingSymlinksInPath() : location)
    }

    public var id: String {
        if let path = libraryRelativePath { return "library-v1:\(path.utf8.count):\(path)" }
        return "source-v1:" + ([canonicalLocation.absoluteString] + archiveMembers)
            .map { "\($0.utf8.count):\($0)" }.joined()
    }

    public func appendingArchiveMember(_ path: String) -> Self {
        Self(location: location, canonicalLocation: canonicalLocation,
             archiveMembers: archiveMembers + [path])
    }

    var isValid: Bool {
        if libraryRelativePath != nil {
            return canonicalLocation == location && archiveMembers.isEmpty
        }
        return location.isFileURL && canonicalLocation.isFileURL
            && archiveMembers.count <= PlaylistScanner.maxArchiveDepth
            && archiveMembers.allSatisfy { member in
                !member.isEmpty && !member.hasPrefix("/") && !member.contains("\\")
                    && member.split(separator: "/", omittingEmptySubsequences: false)
                        .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
            }
    }
}

public struct PlaylistTrackReference: Codable, Hashable, Sendable, Identifiable {
    public let source: PlaylistTrackSource
    public let displayName: String
    public var id: String { source.id }

    public init(source: PlaylistTrackSource, displayName: String) {
        self.source = source
        self.displayName = displayName
    }
}

public struct SavedPlaylist: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var tracks: [PlaylistTrackReference]

    public init(id: UUID = UUID(), name: String, tracks: [PlaylistTrackReference]) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tracks = tracks
    }
}

public struct SavedPlaylistDocument: Codable, Equatable, Sendable {
    public var formatVersion = 1
    public var playlists: [SavedPlaylist] = []
    public var favoriteIDs: Set<String> = []
    public var favoritesMigrationCompleted = false
    public var pendingLegacyFavoriteNames: Set<String>?

    public init() {}

    // Alte Namen erlauben keine eindeutige Zuordnung bei Namenskollisionen.
    // Solche Eintraege bleiben unmarkiert; die alten Defaults bleiben erhalten.
    @discardableResult
    public mutating func migrateFavorites(
        names: Set<String>, among tracks: [PlaylistTrackReference]
    ) -> Set<String> {
        guard !favoritesMigrationCompleted else { return [] }
        let byName = Dictionary(grouping: tracks, by: \.displayName)
        var pending = pendingLegacyFavoriteNames ?? names
        var ambiguous: Set<String> = []
        for name in pending {
            let ids = Set((byName[name] ?? []).map(\.id))
            if ids.count == 1, let id = ids.first { favoriteIDs.insert(id) }
            if ids.count > 1 { ambiguous.insert(name) }
            if !ids.isEmpty { pending.remove(name) }
        }
        pendingLegacyFavoriteNames = pending
        favoritesMigrationCompleted = pending.isEmpty
        return ambiguous
    }
}

public enum SavedPlaylistError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case invalidDocument
    case oversizedDocument

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Die Playlist-Datei verwendet eine nicht unterstützte Version (\(version))."
        case .invalidDocument:
            return "Die Playlist-Datei enthält ungültige oder doppelte Einträge."
        case .oversizedDocument:
            return "Die Playlist-Datei überschreitet die Größenbegrenzung."
        }
    }
}

// Lesen scheitert sichtbar statt beschaedigte Daten als leere Sammlung zu laden.
// Schreiben ersetzt die Datei erst, wenn das gesamte Dokument validiert ist.
public struct SavedPlaylistStore: Sendable {
    public let fileURL: URL
    static let maximumBytes = 32 * 1024 * 1024

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> SavedPlaylistDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return SavedPlaylistDocument()
        }
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumBytes else { throw SavedPlaylistError.oversizedDocument }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= Self.maximumBytes else { throw SavedPlaylistError.oversizedDocument }
        let document = try JSONDecoder().decode(SavedPlaylistDocument.self, from: data)
        try Self.validate(document)
        return document
    }

    static func encodedData(_ document: SavedPlaylistDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumBytes else { throw SavedPlaylistError.oversizedDocument }
        return data
    }

    public func save(_ document: SavedPlaylistDocument) throws {
        let data = try Self.encodedData(document)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func validate(_ document: SavedPlaylistDocument) throws {
        guard document.formatVersion == 1 else {
            throw SavedPlaylistError.unsupportedVersion(document.formatVersion)
        }
        guard document.playlists.count <= 1_000,
              Set(document.playlists.map(\.id)).count == document.playlists.count,
              document.playlists.allSatisfy({ playlist in
                  !playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && playlist.name.count <= 200 && playlist.tracks.count <= 50_000
                      && Set(playlist.tracks.map(\.id)).count == playlist.tracks.count
                      && playlist.tracks.allSatisfy { $0.source.isValid && !$0.displayName.isEmpty }
              }) else { throw SavedPlaylistError.invalidDocument }
    }
}

public enum SavedPlaylistResolver {
    public struct Result: Sendable {
        public let entries: [PlaylistScanner.Entry]
        public let missing: [PlaylistTrackReference]
        public let limited: [PlaylistTrackReference]
    }

    // Quellen einmal scannen, dann exakt die gespeicherten Mitglieder in ihrer
    // Reihenfolge waehlen. Neue Dateien im Quellarchiv erweitern die Liste nicht.
    public static func resolve(_ tracks: [PlaylistTrackReference], tempDir: URL) -> Result {
        var seen = Set<URL>()
        let sources = tracks.filter { $0.source.isValid && $0.source.location.isFileURL }.map(\.source.location)
            .filter { seen.insert($0).inserted }
        var bytes = PlaylistScanner.ArchiveUnpackLimits.default.maxUncompressedBytes
        var count = PlaylistScanner.ArchiveUnpackLimits.default.maxEntries
        var limitedSources = Set<URL>()
        var byID: [String: PlaylistScanner.Entry] = [:]
        for source in sources {
            guard bytes > 0, count > 0 else { limitedSources.insert(source); continue }
            let result = PlaylistScanner.collectResult(from: [source], tempDir: tempDir,
                archiveLimits: .init(maxUncompressedBytes: bytes, maxEntries: count), maxArchives: 128)
            bytes -= result.consumedBytes
            count -= result.consumedEntries
            if result.limitReached { limitedSources.insert(source) }
            for entry in result.entries { byID[entry.source.id] = entry }
        }
        let unresolved = tracks.filter { byID[$0.id] == nil }
        return Result(entries: tracks.compactMap { byID[$0.id] },
                      missing: unresolved.filter { !limitedSources.contains($0.source.location) },
                      limited: unresolved.filter { limitedSources.contains($0.source.location) })
    }
}

import Foundation

public struct CollectionExchangeResolvedTrack: Sendable {
    public let reference: PlaylistTrackReference
    public let url: URL
    public init(reference: PlaylistTrackReference, url: URL) { self.reference = reference; self.url = url }
}

public enum CollectionExchangeSources {
    public static func make(snapshot: CollectionExchangeSnapshot, available: [CollectionExchangeResolvedTrack],
                            libraryRoot: URL? = nil, isCancelled: () -> Bool = { false }) throws -> [CollectionExchangeLocalTrack] {
        try snapshot.validate()
        guard available.count <= CollectionExchangeCodec.maximumTracks else { throw CollectionExchangeError.oversized }
        var references: [String: PlaylistTrackReference] = [:], resolved: [String: URL] = [:]
        for track in available {
            guard !isCancelled() else { throw CancellationError() }
            references[track.reference.id] = track.reference
            if resolved[track.reference.id] == nil || !FileManager.default.fileExists(atPath: resolved[track.reference.id]!.path) {
                resolved[track.reference.id] = track.url
            }
        }
        for playlist in snapshot.playlists.playlists {
            for reference in playlist.tracks where references[reference.id] == nil { references[reference.id] = reference }
        }
        for id in snapshot.referencedSourceIDs where references[id] == nil {
            guard let source = PlaylistTrackSource(stableID: id) else { throw CollectionExchangeError.unmappedSources }
            let name = source.archiveMembers.last?.split(separator: "/").last.map(String.init)
                ?? source.location.lastPathComponent
            references[id] = PlaylistTrackReference(source: source, displayName: name)
        }
        guard references.count <= CollectionExchangeCodec.maximumTracks else { throw CollectionExchangeError.oversized }
        let root = libraryRoot?.standardizedFileURL.path
        return try references.keys.sorted().map { id in
            guard !isCancelled() else { throw CancellationError() }
            let reference = references[id]!, source = reference.source
            guard source.isValid else { throw CollectionExchangeError.invalidLocalState }
            let fileName = source.archiveMembers.last?.split(separator: "/").last.map(String.init)
                ?? source.location.lastPathComponent
            var relative = source.libraryRelativePath
            if relative == nil, let root, root != "/", source.location.path.hasPrefix(root + "/") {
                relative = String(source.location.path.dropFirst(root.count + 1))
            }
            let url = resolved[id] ?? (source.archiveMembers.isEmpty && source.location.isFileURL ? source.location : nil)
            let values = try? url?.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            let count = values?.isRegularFile == true ? values?.fileSize.map(Int64.init) : nil
            let descriptor = ExchangeTrackDescriptor(fileName: fileName, relativePath: relative,
                                                     archiveMembers: source.archiveMembers, byteCount: count)
            try CollectionExchangeCodec.validate(descriptor)
            return CollectionExchangeLocalTrack(reference: reference, descriptor: descriptor)
        }
    }
}

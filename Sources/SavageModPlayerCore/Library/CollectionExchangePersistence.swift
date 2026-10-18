import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct CollectionExchangeStoredDocuments: Equatable, Sendable {
    public var playlists: SavedPlaylistDocument
    public var markers: SongMarkerDocument
    public var trackSettings: TrackPlaybackSettingsDocument
    public var syncState: Data?
    public init(playlists: SavedPlaylistDocument, markers: SongMarkerDocument, trackSettings: TrackPlaybackSettingsDocument,
                syncState: Data? = nil) {
        self.playlists = playlists; self.markers = markers; self.trackSettings = trackSettings
        self.syncState = syncState
    }
}

public enum CollectionExchangePersistenceError: Error, LocalizedError, Sendable {
    case busy, recoveryRequired, staleState, invalidJournal, invalidLocations, oversized, unreadable
    public var errorDescription: String? {
        switch self {
        case .busy: "Die Sammlung wird gerade von einem anderen Vorgang verwendet."
        case .recoveryRequired: "Die letzte Sammlungsübernahme muss zuerst wiederhergestellt werden."
        case .staleState: "Die Sammlungsdaten wurden inzwischen geändert. Bitte erneut prüfen."
        case .invalidJournal: "Die Sicherung der letzten Sammlungsübernahme konnte nicht vollständig gelesen werden."
        case .invalidLocations: "Die lokalen Sammlungsdateien sind nicht korrekt konfiguriert."
        case .oversized: "Die lokalen Sammlungsdaten überschreiten die Größenbegrenzung."
        case .unreadable: "Die lokalen Sammlungsdateien konnten nicht gelesen werden."
        }
    }
}

public struct CollectionExchangeDiskSnapshot: Sendable {
    public let documents: CollectionExchangeStoredDocuments
    public var metadataFilesExist: Bool { images.prefix(3).allSatisfy(\.exists) }
    fileprivate let images: [CollectionExchangePersistence.Image]
    fileprivate let locations: [URL]
}

public struct CollectionExchangePersistence: Sendable {
    public enum Recovery: Equatable, Sendable { case none, preparationDiscarded, rolledBack, completed }
    public enum CommitResult: Equatable, Sendable { case complete, cleanupPending }
    enum File: String, Codable, CaseIterable, Sendable { case playlists, markers, trackSettings, syncState }
    struct Image: Equatable, Sendable { let exists: Bool; let data: Data }
    struct Manifest: Codable {
        var version = 1
        var completed = false
        let locations: [String]
        let beforeExists: [Bool]
        let beforeSizes: [Int]
        let afterSizes: [Int]
        var afterExists: [Bool]? = nil
        let auxiliaryBefore: Data
        let auxiliaryAfter: Data
    }
    struct Prepared {
        var manifest: Manifest
        let before: [Image]
        let after: [Image]
    }

    public static let maximumAuxiliaryBytes = 8 * 1024 * 1024
    public static let maximumSyncStateBytes = CollectionSyncLocalStateCodec.maximumBytes + 2 * CollectionExchangeCodec.maximumBytes
    private static let maximumManifestBytes = 24 * 1024 * 1024
    private let locations: [URL]
    public let journalURL: URL
    private var pending: URL { journalURL.appendingPathComponent("pending", isDirectory: true) }
    let write: @Sendable (Data, URL) throws -> Void

    public init(playlistsURL: URL, markersURL: URL, trackSettingsURL: URL, journalURL: URL,
                syncStateURL: URL? = nil) throws {
        guard journalURL.isFileURL else { throw CollectionExchangePersistenceError.invalidLocations }
        let targets = ([playlistsURL, markersURL, trackSettingsURL] + (syncStateURL.map { [$0] } ?? [])).map(\.standardizedFileURL)
        let journal = URL(fileURLWithPath: journalURL.standardizedFileURL.path, isDirectory: true)
        let canonical = targets.map { $0.resolvingSymlinksInPath().path }
        let journalPath = journal.resolvingSymlinksInPath().path
        guard (targets + [journal]).allSatisfy({ $0.isFileURL && !$0.path.contains("\0") }),
              Set(canonical).count == targets.count,
              canonical.allSatisfy({ $0 != journalPath && !$0.hasPrefix(journalPath + "/") && !journalPath.hasPrefix($0 + "/") }),
              canonical.allSatisfy({ a in !canonical.contains { b in a != b && a.hasPrefix(b + "/") } }) else {
            throw CollectionExchangePersistenceError.invalidLocations
        }
        locations = targets; self.journalURL = journal
        write = { @Sendable data, url in try data.write(to: url, options: .atomic) }
    }

    init(copying other: Self, write: @escaping @Sendable (Data, URL) throws -> Void) {
        locations = other.locations; journalURL = other.journalURL; self.write = write
    }

    private init(recoveringLegacy other: Self) {
        locations = Array(other.locations.prefix(3)); journalURL = other.journalURL; write = other.write
    }

    public func snapshot() throws -> CollectionExchangeDiskSnapshot {
        try withLock {
            guard !FileManager.default.fileExists(atPath: pending.path) else { throw CollectionExchangePersistenceError.recoveryRequired }
            let images = try readCurrent()
            return CollectionExchangeDiskSnapshot(documents: try decode(images), images: images, locations: locations + [journalURL])
        }
    }

    // Der Zusatzspeicher muss Vergleichen und Ersetzen zusammen ausführen und
    // seine Änderungen vor der Rückkehr sichern. Beide Datenstände bleiben
    // bis zum erfolgreichen Abschluss im Journal erhalten.
    @discardableResult public func commit(
        _ documents: CollectionExchangeStoredDocuments, replacing snapshot: CollectionExchangeDiskSnapshot,
        auxiliaryBefore: Data, auxiliaryAfter: Data,
        replaceAuxiliary: (Data, Data) throws -> Void
    ) throws -> CommitResult {
        try withLock {
            let prepared = try prepare(documents, replacing: snapshot,
                                       auxiliaryBefore: auxiliaryBefore, auxiliaryAfter: auxiliaryAfter)
            do {
                for index in locations.indices { try writePreparedFile(prepared, index: index) }
                try replaceAuxiliary(auxiliaryBefore, auxiliaryAfter)
                try markCompleted(prepared)
            } catch {
                do {
                    try rollback(prepared, replaceAuxiliary: replaceAuxiliary)
                    try removePending()
                } catch { throw CollectionExchangePersistenceError.recoveryRequired }
                throw error
            }
            // Nach dem Abschlussmarker ist der neue Stand verbindlich. Ein
            // Cleanup-Fehler darf daraus keinen nachträglichen Teil-Rollback machen.
            do { try removePending(); return .complete }
            catch { return .cleanupPending }
        }
    }

    public func recover(replaceAuxiliary: (Data, Data) throws -> Void) throws -> Recovery {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return .none }
        return try withLock {
            guard FileManager.default.fileExists(atPath: pending.path) else { return .none }
            try validatePendingShape()
            let manifestURL = pending.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                // Vor dem Manifest wurde noch keine Originaldatei verändert.
                try removePending(); return .preparationDiscarded
            }
            let image = try readImage(manifestURL, limit: Self.maximumManifestBytes)
            let manifest: Manifest
            do { manifest = try JSONDecoder().decode(Manifest.self, from: image.data) }
            catch { throw CollectionExchangePersistenceError.invalidJournal }
            // Ein Upgrade muss auch einen noch offenen Import der bisherigen
            // drei Dateien zurückrollen können, ohne den neuen Stand anzufassen.
            let legacy = locations.count == 4 && manifest.locations == (Array(locations.prefix(3)) + [journalURL]).map(\.absoluteString)
            let recovery = legacy ? Self(recoveringLegacy: self) : self
            try recovery.validatePendingShape()
            let count = recovery.locations.count
            let afterExists = manifest.afterExists ?? Array(repeating: true, count: count)
            guard manifest.version == 1, manifest.locations == (recovery.locations + [journalURL]).map(\.absoluteString),
                  manifest.beforeExists.count == count, manifest.beforeSizes.count == count,
                  manifest.afterSizes.count == count, afterExists.count == count,
                  afterExists.prefix(3).allSatisfy({ $0 }), manifest.auxiliaryBefore.count <= Self.maximumAuxiliaryBytes,
                  manifest.auxiliaryAfter.count <= Self.maximumAuxiliaryBytes else { throw CollectionExchangePersistenceError.invalidJournal }
            guard recovery.locations.indices.allSatisfy({ (0...recovery.limit($0)).contains(manifest.beforeSizes[$0])
                && (0...recovery.limit($0)).contains(manifest.afterSizes[$0])
                && (manifest.beforeExists[$0] || manifest.beforeSizes[$0] == 0)
                && (afterExists[$0] || manifest.afterSizes[$0] == 0) }) else {
                throw CollectionExchangePersistenceError.invalidJournal
            }
            if manifest.completed { try recovery.removePending(); return .completed }
            var before: [Image] = [], after: [Image] = []
            for index in recovery.locations.indices {
                let original = try recovery.readImage(recovery.journalFile("before", index), limit: recovery.limit(index))
                let replacement = try recovery.readImage(recovery.journalFile("after", index), limit: recovery.limit(index))
                guard original.exists == manifest.beforeExists[index], original.data.count == manifest.beforeSizes[index],
                      replacement.exists == afterExists[index], replacement.data.count == manifest.afterSizes[index] else {
                    throw CollectionExchangePersistenceError.invalidJournal
                }
                before.append(original); after.append(replacement)
            }
            _ = try recovery.decode(before); _ = try recovery.decode(after)
            try recovery.rollback(Prepared(manifest: manifest, before: before, after: after), replaceAuxiliary: replaceAuxiliary)
            try recovery.removePending(); return .rolledBack
        }
    }

    func prepare(_ documents: CollectionExchangeStoredDocuments, replacing snapshot: CollectionExchangeDiskSnapshot,
                 auxiliaryBefore: Data, auxiliaryAfter: Data) throws -> Prepared {
        guard !FileManager.default.fileExists(atPath: pending.path) else { throw CollectionExchangePersistenceError.recoveryRequired }
        guard snapshot.locations == locations + [journalURL] else { throw CollectionExchangePersistenceError.staleState }
        guard auxiliaryBefore.count <= Self.maximumAuxiliaryBytes, auxiliaryAfter.count <= Self.maximumAuxiliaryBytes else {
            throw CollectionExchangePersistenceError.oversized
        }
        var after = try [SavedPlaylistStore.encodedData(documents.playlists), SongMarkerStore.encodedData(documents.markers),
                         TrackPlaybackSettingsStore.encodedData(documents.trackSettings)].map { Image(exists: true, data: $0) }
        if locations.count == 4 {
            if let state = documents.syncState {
                guard state.count <= Self.maximumSyncStateBytes else { throw CollectionExchangePersistenceError.oversized }
                after.append(Image(exists: true, data: state))
            } else {
                // Bestehende manuelle Imports verändern die Cloud-Basis nicht.
                after.append(snapshot.images[3])
            }
        } else if documents.syncState != nil { throw CollectionExchangePersistenceError.invalidLocations }
        guard try readCurrent() == snapshot.images else { throw CollectionExchangePersistenceError.staleState }
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: false)
        let prepared = Prepared(manifest: Manifest(locations: (locations + [journalURL]).map(\.absoluteString),
                                                   beforeExists: snapshot.images.map(\.exists), beforeSizes: snapshot.images.map { $0.data.count },
                                                   afterSizes: after.map { $0.data.count }, afterExists: after.map(\.exists),
                                                   auxiliaryBefore: auxiliaryBefore, auxiliaryAfter: auxiliaryAfter),
                                before: snapshot.images, after: after)
        do {
            for index in locations.indices {
                if prepared.before[index].exists { try prepared.before[index].data.write(to: journalFile("before", index), options: .withoutOverwriting) }
                if prepared.after[index].exists { try prepared.after[index].data.write(to: journalFile("after", index), options: .withoutOverwriting) }
            }
            try saveManifest(prepared.manifest)
            return prepared
        } catch { try? removePending(); throw error }
    }

    func writePreparedFile(_ prepared: Prepared, index: Int) throws {
        guard locations.indices.contains(index), try readImage(locations[index], limit: limit(index)) == prepared.before[index] else {
            throw CollectionExchangePersistenceError.staleState
        }
        if prepared.after[index].exists {
            try FileManager.default.createDirectory(at: locations[index].deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(prepared.after[index].data, locations[index])
        } else if prepared.before[index].exists { try FileManager.default.removeItem(at: locations[index]) }
    }
    func markCompleted(_ prepared: Prepared) throws {
        var manifest = prepared.manifest; manifest.completed = true; try saveManifest(manifest)
    }

    private func rollback(_ prepared: Prepared, replaceAuxiliary: (Data, Data) throws -> Void) throws {
        let current = try readCurrent()
        guard locations.indices.allSatisfy({ current[$0] == prepared.before[$0] || current[$0] == prepared.after[$0] }) else {
            throw CollectionExchangePersistenceError.staleState
        }
        for index in locations.indices {
            let current = try readImage(locations[index], limit: limit(index))
            guard current == prepared.before[index] || current == prepared.after[index] else { throw CollectionExchangePersistenceError.staleState }
            if current == prepared.before[index] { continue }
            if prepared.before[index].exists { try write(prepared.before[index].data, locations[index]) }
            else { try FileManager.default.removeItem(at: locations[index]) }
        }
        try replaceAuxiliary(prepared.manifest.auxiliaryAfter, prepared.manifest.auxiliaryBefore)
    }

    private func decode(_ images: [Image]) throws -> CollectionExchangeStoredDocuments {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let playlists = images[0].exists ? try decoder.decode(SavedPlaylistDocument.self, from: images[0].data) : SavedPlaylistDocument()
        let markers = images[1].exists ? try decoder.decode(SongMarkerDocument.self, from: images[1].data) : SongMarkerDocument()
        let settings = images[2].exists ? try decoder.decode(TrackPlaybackSettingsDocument.self, from: images[2].data) : TrackPlaybackSettingsDocument()
        _ = try SavedPlaylistStore.encodedData(playlists); _ = try SongMarkerStore.encodedData(markers)
        _ = try TrackPlaybackSettingsStore.encodedData(settings)
        return .init(playlists: playlists, markers: markers, trackSettings: settings,
                     syncState: images.count == 4 && images[3].exists ? images[3].data : nil)
    }
    private func readCurrent() throws -> [Image] { try locations.indices.map { try readImage(locations[$0], limit: limit($0)) } }
    private func limit(_ index: Int) -> Int {
        index == 3 ? Self.maximumSyncStateBytes : (index == 0 ? SavedPlaylistStore.maximumBytes : TrackPlaybackSettingsStore.maximumBytes)
    }
    private func journalFile(_ prefix: String, _ index: Int) -> URL {
        pending.appendingPathComponent("\(prefix)-\(File.allCases[index].rawValue).json")
    }
    private func saveManifest(_ manifest: Manifest) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        guard data.count <= Self.maximumManifestBytes else { throw CollectionExchangePersistenceError.oversized }
        let next = pending.appendingPathComponent("manifest.next")
        try data.write(to: next)
        guard rename(next.path, pending.appendingPathComponent("manifest.json").path) == 0 else {
            throw CollectionExchangePersistenceError.invalidJournal
        }
    }
    private func validatePendingShape() throws {
        let values = try pending.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CollectionExchangePersistenceError.invalidJournal }
        let allowed = Set(["manifest.json", "manifest.next"] + File.allCases.prefix(locations.count).flatMap { ["before-\($0.rawValue).json", "after-\($0.rawValue).json"] })
        for url in try FileManager.default.contentsOfDirectory(at: pending, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard allowed.contains(url.lastPathComponent), values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CollectionExchangePersistenceError.invalidJournal
            }
        }
    }
    private func removePending() throws { try validatePendingShape(); try FileManager.default.removeItem(at: pending) }

    func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: journalURL, withIntermediateDirectories: true)
        let values = try journalURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CollectionExchangePersistenceError.invalidJournal }
        let fd = open(journalURL.appendingPathComponent("lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw CollectionExchangePersistenceError.unreadable }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw CollectionExchangePersistenceError.invalidJournal }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CollectionExchangePersistenceError.busy }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    private func readImage(_ url: URL, limit: Int) throws -> Image {
        var original = stat()
        guard lstat(url.path, &original) == 0 else {
            if errno == ENOENT { return Image(exists: false, data: Data()) }
            throw CollectionExchangePersistenceError.unreadable
        }
        guard (original.st_mode & S_IFMT) == S_IFREG else { throw CollectionExchangePersistenceError.unreadable }
        do {
            let file = try LibraryFileReader(url); defer { file.close() }
            guard file.stamp.device == UInt64(truncatingIfNeeded: original.st_dev), file.stamp.inode == UInt64(original.st_ino) else {
                throw CollectionExchangePersistenceError.staleState
            }
            guard file.stamp.size <= limit else { throw CollectionExchangePersistenceError.oversized }
            let data = try file.read(limit: limit)
            var after = stat()
            guard lstat(url.path, &after) == 0, after.st_dev == original.st_dev, after.st_ino == original.st_ino,
                  after.st_size == original.st_size, data.count == file.stamp.size else { throw CollectionExchangePersistenceError.staleState }
            #if canImport(Darwin)
            guard after.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec else {
                throw CollectionExchangePersistenceError.staleState
            }
            #else
            guard after.st_mtim.tv_sec == original.st_mtim.tv_sec, after.st_mtim.tv_nsec == original.st_mtim.tv_nsec else {
                throw CollectionExchangePersistenceError.staleState
            }
            #endif
            return Image(exists: true, data: data)
        } catch LibraryFileReadError.oversized { throw CollectionExchangePersistenceError.oversized }
    }
}

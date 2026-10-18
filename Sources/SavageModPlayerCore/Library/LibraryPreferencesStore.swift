import Foundation

public struct SavedLibraryFilter: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var query: LibraryQuery
    public init(id: UUID = UUID(), name: String, query: LibraryQuery) {
        self.id = id; self.name = name.trimmingCharacters(in: .whitespacesAndNewlines); self.query = query
    }
}

public struct LibraryPreferencesDocument: Codable, Equatable, Sendable {
    public var formatVersion = 1
    public var savedFilters: [SavedLibraryFilter] = []
    public var heardIDs: Set<String> = []
    public var firstSeenAt: [String: Date] = [:]
    public init() {}
}

public enum LibraryPreferencesError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int), invalidDocument, oversizedDocument, unreadable
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Die Bibliotheksdaten verwenden eine nicht unterstützte Version (\(version))."
        case .invalidDocument: return "Die Bibliotheksdaten enthalten ungültige Einträge."
        case .oversizedDocument: return "Die Bibliotheksdaten überschreiten die Größenbegrenzung."
        case .unreadable: return "Die Bibliotheksdaten konnten nicht gelesen werden."
        }
    }
}

// Diese Daten sind Nutzereinstellungen, kein rekonstruierbarer Metadaten-Cache.
// Ein Ladefehler sperrt deshalb alle Schreibzugriffe bis zum nächsten Öffnen.
public actor LibraryPreferencesStore {
    public struct Snapshot: Sendable {
        public let revision: UInt64
        public let document: LibraryPreferencesDocument
    }
    public static let maximumBytes = 32 * 1024 * 1024
    public let fileURL: URL
    private var document: LibraryPreferencesDocument?
    private var revision: UInt64 = 0
    private var loadFailure: LibraryPreferencesError?

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func snapshot() throws -> Snapshot {
        if let loadFailure { throw loadFailure }
        if let document { return Snapshot(revision: revision, document: document) }
        do {
            let loaded: LibraryPreferencesDocument
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let file = try LibraryFileReader(fileURL)
                defer { file.close() }
                guard file.stamp.size <= Self.maximumBytes else { throw LibraryPreferencesError.oversizedDocument }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                loaded = try decoder.decode(LibraryPreferencesDocument.self, from: file.read(limit: Self.maximumBytes))
                try validate(loaded)
            } else { loaded = LibraryPreferencesDocument() }
            document = loaded
            return Snapshot(revision: revision, document: loaded)
        } catch let error as LibraryPreferencesError {
            loadFailure = error
            throw error
        } catch LibraryFileReadError.oversized {
            loadFailure = .oversizedDocument
            throw LibraryPreferencesError.oversizedDocument
        } catch {
            loadFailure = .unreadable
            throw LibraryPreferencesError.unreadable
        }
    }

    public func update(
        _ change: @Sendable (inout LibraryPreferencesDocument) throws -> Void
    ) throws -> Snapshot {
        let previous = try snapshot()
        var candidate = previous.document
        try change(&candidate)
        try validate(candidate)
        guard candidate != previous.document else { return previous }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(candidate)
        guard data.count <= Self.maximumBytes else { throw LibraryPreferencesError.oversizedDocument }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        document = candidate
        revision &+= 1
        return Snapshot(revision: revision, document: candidate)
    }

    public func registerSources(_ sources: [String: Date]) throws -> Snapshot {
        try update { document in
            for (id, date) in sources where document.firstSeenAt[id] == nil { document.firstSeenAt[id] = date }
        }
    }

    public func markHeard(_ id: String, heard: Bool = true) throws -> Snapshot {
        try update {
            if heard { $0.heardIDs.insert(id) } else { $0.heardIDs.remove(id) }
        }
    }

    private func validate(_ value: LibraryPreferencesDocument) throws {
        guard value.formatVersion == 1 else { throw LibraryPreferencesError.unsupportedVersion(value.formatVersion) }
        guard value.savedFilters.count <= 1_000,
              Set(value.savedFilters.map(\.id)).count == value.savedFilters.count,
              value.heardIDs.count <= 100_000, value.firstSeenAt.count <= 100_000,
              value.savedFilters.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && $0.name.count <= 200 && $0.query.isValid }),
              value.heardIDs.allSatisfy(Self.validID), value.firstSeenAt.keys.allSatisfy(Self.validID),
              value.firstSeenAt.values.allSatisfy({ $0.timeIntervalSince1970.isFinite }) else {
            throw LibraryPreferencesError.invalidDocument
        }
        var bytes = 512 + value.savedFilters.count * 512
        for id in value.heardIDs { bytes += Self.jsonStringBytes(id) + 1 }
        for id in value.firstSeenAt.keys { bytes += Self.jsonStringBytes(id) + 64 }
        for filter in value.savedFilters {
            bytes += Self.jsonStringBytes(filter.name) + Self.jsonStringBytes(filter.query.search)
        }
        guard bytes <= Self.maximumBytes else { throw LibraryPreferencesError.oversizedDocument }
    }

    private static func validID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= 16_384 }
    private static func jsonStringBytes(_ text: String) -> Int {
        var count = 2
        for byte in text.utf8 {
            switch byte {
            case 0..<32: count += 6
            case 34, 92: count += 2
            default: count += 1
            }
        }
        return count
    }
}

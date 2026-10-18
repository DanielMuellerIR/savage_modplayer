import Foundation

public struct SongMarker: Codable, Equatable, Sendable, Identifiable {
    public static let maximumNameLength = 200
    public let id: UUID
    public let sourceID: String
    public var name: String
    public var address: SongAddress
    public let createdAt: Date
    public init(id: UUID = UUID(), sourceID: String, name: String, address: SongAddress, createdAt: Date = Date()) {
        self.id = id; self.sourceID = sourceID; self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = address; self.createdAt = createdAt
    }

    // Das bisherige ISO-Datum bleibt für ältere Leser erhalten. Die zusätzliche
    // Präzision verhindert Scheinkonflikte nach einem lokalen Speicher-Rundlauf.
    private enum CodingKeys: String, CodingKey {
        case id, sourceID, name, address, createdAt, createdAtReferenceSeconds
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sourceID = try values.decode(String.self, forKey: .sourceID)
        name = try values.decode(String.self, forKey: .name)
        address = try values.decode(SongAddress.self, forKey: .address)
        let legacy = try values.decode(Date.self, forKey: .createdAt)
        if let precise = try values.decodeIfPresent(Double.self, forKey: .createdAtReferenceSeconds) {
            guard precise.isFinite, abs(precise - legacy.timeIntervalSinceReferenceDate) < 1 else {
                throw DecodingError.dataCorruptedError(forKey: .createdAtReferenceSeconds, in: values,
                                                       debugDescription: "Die beiden Songstellen-Zeitstempel widersprechen sich.")
            }
            createdAt = Date(timeIntervalSinceReferenceDate: precise)
        } else { createdAt = legacy }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(sourceID, forKey: .sourceID)
        try values.encode(name, forKey: .name)
        try values.encode(address, forKey: .address)
        try values.encode(createdAt, forKey: .createdAt)
        let seconds = createdAt.timeIntervalSinceReferenceDate
        if seconds != seconds.rounded(.towardZero) { try values.encode(seconds, forKey: .createdAtReferenceSeconds) }
    }
}

public struct SongMarkerDocument: Codable, Equatable, Sendable {
    public var formatVersion = 1
    public var markers: [SongMarker] = []
    public init() {}
}

public enum SongMarkerStoreError: Error, LocalizedError, Sendable {
    case unsupportedVersion, invalidDocument, oversized, unreadable
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "Die Songstellen verwenden eine nicht unterstützte Speicherversion."
        case .invalidDocument: "Die Songstellen enthalten ungültige Daten."
        case .oversized: "Die Songstellen überschreiten die Speichergrenze."
        case .unreadable: "Die Songstellen konnten nicht gelesen werden."
        }
    }
}

public actor SongMarkerStore {
    public struct Snapshot: Sendable {
        public let revision: UInt64
        public let document: SongMarkerDocument
    }
    public static let maximumBytes = 8 * 1024 * 1024
    private let fileURL: URL
    private var document: SongMarkerDocument?
    private var failure: SongMarkerStoreError?
    private var revision: UInt64 = 0
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func snapshot() throws -> Snapshot {
        if let failure { throw failure }
        if let document { return Snapshot(revision: revision, document: document) }
        do {
            var loaded = SongMarkerDocument()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let file = try LibraryFileReader(fileURL)
                defer { file.close() }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                loaded = try decoder.decode(SongMarkerDocument.self, from: file.read(limit: Self.maximumBytes))
            }
            try Self.validate(loaded); document = loaded
            return Snapshot(revision: revision, document: loaded)
        } catch let error as SongMarkerStoreError { failure = error; throw error }
        catch LibraryFileReadError.oversized { failure = .oversized; throw SongMarkerStoreError.oversized }
        catch { failure = .unreadable; throw SongMarkerStoreError.unreadable }
    }
    public func update(_ change: @Sendable (inout SongMarkerDocument) throws -> Void) throws -> Snapshot {
        let previous = try snapshot()
        var candidate = previous.document; try change(&candidate); try Self.validate(candidate)
        guard candidate != previous.document else { return previous }
        let data = try Self.encodedData(candidate)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        document = candidate; revision &+= 1
        return Snapshot(revision: revision, document: candidate)
    }
    static func encodedData(_ document: SongMarkerDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw SongMarkerStoreError.oversized }
        return data
    }

    private static func validate(_ document: SongMarkerDocument) throws {
        guard document.formatVersion == 1 else { throw SongMarkerStoreError.unsupportedVersion }
        guard document.markers.count <= 10_000, Set(document.markers.map(\.id)).count == document.markers.count else {
            throw SongMarkerStoreError.invalidDocument
        }
        var bytes = 512
        for marker in document.markers {
            guard !marker.sourceID.isEmpty, marker.sourceID.utf8.count <= 16_384,
                  !marker.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, marker.name.count <= SongMarker.maximumNameLength,
                  marker.address.isValidStorageValue, marker.createdAt.timeIntervalSince1970.isFinite else {
                throw SongMarkerStoreError.invalidDocument
            }
            bytes += 256 + marker.sourceID.utf8.count * 6 + marker.name.utf8.count * 6
            guard bytes <= Self.maximumBytes else { throw SongMarkerStoreError.oversized }
        }
    }
}

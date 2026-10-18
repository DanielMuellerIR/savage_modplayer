import Foundation

public struct PlaybackOptions: Equatable, Sendable {
    public var palClock: Bool
    public var stereoSeparation: Double
    public var useInterpolation: Bool
    public var ledFilterActive: Bool

    public init(palClock: Bool = true, stereoSeparation: Double = 0.8,
                useInterpolation: Bool = true, ledFilterActive: Bool = false) {
        self.palClock = palClock
        self.stereoSeparation = stereoSeparation.isFinite ? min(1, max(0, stereoSeparation)) : 0.8
        self.useInterpolation = useInterpolation
        self.ledFilterActive = ledFilterActive
    }

    public static func supportsAmigaClock(_ format: ModuleFormat?) -> Bool {
        switch format {
        case .protracker, .soundtracker, .multichannel: return true
        default: return false
        }
    }
}

public struct TrackPlaybackOverrides: Codable, Equatable, Sendable {
    public var palClock: Bool?
    public var stereoSeparation: Double?
    public var useInterpolation: Bool?
    public var ledFilterActive: Bool?

    public init(palClock: Bool? = nil, stereoSeparation: Double? = nil,
                useInterpolation: Bool? = nil, ledFilterActive: Bool? = nil) {
        self.palClock = palClock; self.stereoSeparation = stereoSeparation
        self.useInterpolation = useInterpolation; self.ledFilterActive = ledFilterActive
    }

    public var isEmpty: Bool {
        palClock == nil && stereoSeparation == nil && useInterpolation == nil && ledFilterActive == nil
    }

    public func resolved(defaults: PlaybackOptions, format: ModuleFormat?) -> PlaybackOptions {
        PlaybackOptions(palClock: PlaybackOptions.supportsAmigaClock(format) ? palClock ?? defaults.palClock : true,
                        stereoSeparation: stereoSeparation ?? defaults.stereoSeparation,
                        useInterpolation: useInterpolation ?? defaults.useInterpolation,
                        ledFilterActive: ledFilterActive ?? defaults.ledFilterActive)
    }
}

public struct TrackPlaybackSettingsDocument: Codable, Equatable, Sendable {
    public var formatVersion = 1
    public var tracks: [String: TrackPlaybackOverrides] = [:]
    public init() {}
}

public enum TrackPlaybackSettingsError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int), invalidDocument, oversizedDocument
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Die Titel-Einstellungen verwenden eine nicht unterstützte Version (\(version))."
        case .invalidDocument: return "Die Titel-Einstellungen enthalten ungültige Werte."
        case .oversizedDocument: return "Die Titel-Einstellungen überschreiten die Größenbegrenzung."
        }
    }
}

// Der MainActor besitzt genau einen Dokumentstand. Das begrenzte Laden geschieht
// vor dem ersten Titel, damit keine vorläufigen Klangwerte hörbar werden.
public struct TrackPlaybackSettingsStore: Sendable {
    public static let maximumBytes = 8 * 1024 * 1024
    public static let maximumTracks = 20_000
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> TrackPlaybackSettingsDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return TrackPlaybackSettingsDocument() }
        let file = try LibraryFileReader(fileURL)
        defer { file.close() }
        guard file.stamp.size <= Self.maximumBytes else { throw TrackPlaybackSettingsError.oversizedDocument }
        let document = try JSONDecoder().decode(TrackPlaybackSettingsDocument.self,
                                               from: file.read(limit: Self.maximumBytes))
        try Self.validate(document)
        return document
    }

    static func encodedData(_ document: TrackPlaybackSettingsDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumBytes else { throw TrackPlaybackSettingsError.oversizedDocument }
        return data
    }

    public func save(_ document: TrackPlaybackSettingsDocument) throws {
        let data = try Self.encodedData(document)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func validate(_ document: TrackPlaybackSettingsDocument) throws {
        guard document.formatVersion == 1 else { throw TrackPlaybackSettingsError.unsupportedVersion(document.formatVersion) }
        guard document.tracks.count <= Self.maximumTracks else { throw TrackPlaybackSettingsError.oversizedDocument }
        var bytes = 64
        for (id, value) in document.tracks {
            guard Self.validID(id), !value.isEmpty,
                  value.stereoSeparation.map({ $0.isFinite && (0...1).contains($0) }) ?? true else {
                throw TrackPlaybackSettingsError.invalidDocument
            }
            bytes += id.utf8.count * 6 + 160
            guard bytes <= Self.maximumBytes else { throw TrackPlaybackSettingsError.oversizedDocument }
        }
    }

    public static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 16_384 && !id.contains("\0")
    }
}

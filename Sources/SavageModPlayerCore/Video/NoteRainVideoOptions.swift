import Foundation

public enum NoteRainVideoAppearance: String, Codable, Sendable, CaseIterable {
    case light, dark
}

public enum NoteRainVideoQuality: String, Codable, Sendable, CaseIterable {
    case compact, high
}

public struct NoteRainVideoOptions: Sendable, Codable, Equatable {
    public static let sampleRate = 48_000
    public var width: Int
    public var height: Int
    public var framesPerSecond: Int
    public var lookaheadSeconds: Int
    public var keyRange: ClosedRange<Int>
    public var appearance: NoteRainVideoAppearance
    public var quality: NoteRainVideoQuality
    public var audio: ChannelStemExportOptions

    public init(width: Int = 1280, height: Int = 720, framesPerSecond: Int = 30,
                lookaheadSeconds: Int = 4, keyRange: ClosedRange<Int> = 0...119,
                appearance: NoteRainVideoAppearance = .dark,
                quality: NoteRainVideoQuality = .high,
                audio: ChannelStemExportOptions = .init(sampleRate: 48_000, maximumSeconds: 600)) {
        self.width = width; self.height = height; self.framesPerSecond = framesPerSecond
        self.lookaheadSeconds = lookaheadSeconds; self.keyRange = keyRange
        self.appearance = appearance; self.audio = audio
        self.quality = quality
    }

    private enum CodingKeys: String, CodingKey {
        case width, height, framesPerSecond, lookaheadSeconds, keyRange, appearance, quality, audio
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        width = try values.decode(Int.self, forKey: .width)
        height = try values.decode(Int.self, forKey: .height)
        framesPerSecond = try values.decode(Int.self, forKey: .framesPerSecond)
        lookaheadSeconds = try values.decode(Int.self, forKey: .lookaheadSeconds)
        keyRange = try values.decode(ClosedRange<Int>.self, forKey: .keyRange)
        appearance = try values.decode(NoteRainVideoAppearance.self, forKey: .appearance)
        quality = try values.decodeIfPresent(NoteRainVideoQuality.self, forKey: .quality) ?? .high
        audio = try values.decode(ChannelStemExportOptions.self, forKey: .audio)
    }

    func validate(channelCount: Int) throws -> UInt64 {
        guard (320...1920).contains(width), width.isMultiple(of: 2),
              (180...1080).contains(height), height.isMultiple(of: 2),
              [24, 25, 30, 60].contains(framesPerSecond), [2, 4, 8].contains(lookaheadSeconds),
              (0...119).contains(keyRange.lowerBound), (0...119).contains(keyRange.upperBound),
              keyRange.count >= 12, audio.sampleRate == Double(Self.sampleRate),
              audio.maximumSeconds.isFinite, audio.maximumSeconds > 0, audio.maximumSeconds <= 3600,
              audio.stereoSeparation.isFinite, (0...1).contains(audio.stereoSeparation),
              ((audio.mutedChannels ?? []) + audio.soloChannels).allSatisfy({ (0..<channelCount).contains($0) }) else {
            throw NoteRainVideoError.invalidOptions
        }
        let frames = (audio.maximumSeconds * Double(Self.sampleRate)).rounded(.down)
        guard frames >= 1 else { throw NoteRainVideoError.invalidOptions }
        return UInt64(frames)
    }

    var videoBitRate: Int {
        let bitsPerPixel = quality == .high ? 0.16 : 0.08
        return max(600_000, min(24_000_000, Int(Double(width) * Double(height) * Double(framesPerSecond) * bitsPerPixel)))
    }
}

public struct NoteRainVideoReport: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let moduleName: String
    public let moduleFormat: ModuleFormat
    public let options: NoteRainVideoOptions
    public let audioFrameCount: UInt64
    public let videoFrameCount: UInt64
    public let endedNaturally: Bool
    public let audioProcessing: String
}

public enum NoteRainVideoError: Error, LocalizedError, Equatable, Sendable {
    case invalidOptions, invalidDestination, destinationExists, emptyOutput
    case encoderStalled, tooManyNotes, nonFiniteAudio
    case encodingFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidOptions: "Die Einstellungen für den Videoexport sind ungültig."
        case .invalidDestination: "Das Ziel muss eine neue MOV-Datei in einem vorhandenen Ordner sein."
        case .destinationExists: "Die Zieldatei existiert bereits. Bitte einen neuen Namen wählen."
        case .emptyOutput: "Das Modul hat keine exportierbaren Audioframes geliefert."
        case .encoderStalled: "Der Videoencoder verarbeitet keine weiteren Daten."
        case .tooManyNotes: "Die Notendarstellung überschreitet die begrenzte Ereignismenge."
        case .nonFiniteAudio: "Der Renderer hat einen ungültigen Audiopegel geliefert."
        case .encodingFailed(let detail): "Das Video konnte nicht geschrieben werden: \(detail)"
        }
    }
}

struct NoteRainVideoClock {
    let samplesPerVideoFrame: UInt64
    init(framesPerSecond: Int) throws {
        guard [24, 25, 30, 60].contains(framesPerSecond) else { throw NoteRainVideoError.invalidOptions }
        samplesPerVideoFrame = UInt64(NoteRainVideoOptions.sampleRate / framesPerSecond)
    }
    func sampleFrame(forVideoFrame frame: UInt64) throws -> UInt64 {
        let value = frame.multipliedReportingOverflow(by: samplesPerVideoFrame)
        guard !value.overflow else { throw NoteRainVideoError.invalidOptions }
        return value.partialValue
    }
    func videoFrameCount(audioFrames: UInt64) -> UInt64 {
        audioFrames / samplesPerVideoFrame + (audioFrames.isMultiple(of: samplesPerVideoFrame) ? 0 : 1)
    }
}

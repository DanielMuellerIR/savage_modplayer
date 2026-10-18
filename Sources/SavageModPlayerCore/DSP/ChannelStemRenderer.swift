import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ChannelStemExportOptions: Sendable, Codable, Equatable {
    public var sampleRate: Double
    public var maximumSeconds: Double
    public var stereoSeparation: Float
    public var useInterpolation: Bool
    public var palClock: Bool
    // nil erhält die Modul-Defaults; eine explizite Liste bildet den aktuellen
    // Playerzustand ab und kann auch zuvor stumme Headerkanäle freigeben.
    public var mutedChannels: [Int]?
    public var soloChannels: [Int]

    public init(sampleRate: Double = 44_100, maximumSeconds: Double = 300,
                stereoSeparation: Float = 0.8, useInterpolation: Bool = true,
                palClock: Bool = true, mutedChannels: [Int]? = nil, soloChannels: [Int] = []) {
        self.sampleRate = sampleRate
        self.maximumSeconds = maximumSeconds
        self.stereoSeparation = stereoSeparation
        self.useInterpolation = useInterpolation
        self.palClock = palClock
        self.mutedChannels = mutedChannels
        self.soloChannels = soloChannels
    }
}

public struct ChannelStemExportReport: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let moduleName: String
    public let moduleFormat: ModuleFormat
    public let options: ChannelStemExportOptions
    public let frameCount: UInt64
    public let endedNaturally: Bool
    public let commonGain: Float
    public let unscaledMixPeak: Float
    public let unscaledChannelPeaks: [Float]
    public let channelFiles: [String]
    public let referenceMixFile: String
    public let masterProcessing: String
}

public enum ChannelStemExportError: Error, LocalizedError, Sendable, Equatable {
    case invalidOptions, destinationExists, invalidDestination, nonFiniteAudio, inconsistentPasses

    public var errorDescription: String? {
        switch self {
        case .invalidOptions: "Die Einstellungen für den Kanalspuren-Export sind ungültig."
        case .destinationExists: "Der Zielordner existiert bereits. Bitte einen neuen Namen wählen."
        case .invalidDestination: "Das Ziel muss ein neuer Ordner in einem vorhandenen Verzeichnis sein."
        case .nonFiniteAudio: "Der Renderer hat einen ungültigen Audiopegel geliefert."
        case .inconsistentPasses: "Die beiden Renderdurchläufe haben unterschiedliche Längen geliefert."
        }
    }
}

public enum ChannelStemRenderer {
    public enum Output: String, Codable, Sendable, CaseIterable {
        case stereoMix, channelStems
    }

    // Zwei gemeinsame Durchläufe erhalten globale Effekte und IT-NNA-Stimmen.
    // Nur feste Blockpuffer bleiben im Speicher; Dateilängen wachsen auf Disk.
    public static func export(mod: Mod, to destination: URL,
                              options: ChannelStemExportOptions = .init(),
                              output: Output = .channelStems,
                              progress: @Sendable (Double) -> Void = { _ in }) throws -> ChannelStemExportReport {
        let maximumFrames = try ModuleRenderer.validatedFrameLimit(
            sampleRate: options.sampleRate, maxDurationSeconds: options.maximumSeconds)
        let channelCount = max(1, min(RenderEngine.maxChannels, mod.channelCount))
        guard options.sampleRate >= 8_000, options.sampleRate.rounded() == options.sampleRate,
              options.stereoSeparation.isFinite, (0...1).contains(options.stereoSeparation),
              ((options.mutedChannels ?? []) + options.soloChannels).allSatisfy({ (0..<channelCount).contains($0) }) else {
            throw ChannelStemExportError.invalidOptions
        }
        var options = options
        let headerMutes = mod.format == .it
            ? (0..<channelCount).filter { $0 < mod.channelDisabled.count && mod.channelDisabled[$0] }
            : []
        options.mutedChannels = Array(Set(options.mutedChannels ?? headerMutes)).sorted()
        options.soloChannels = Array(Set(options.soloChannels)).sorted()
        let destination = destination.standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard destination.isFileURL, !destination.lastPathComponent.isEmpty, !destination.path.contains("\0"),
              FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ChannelStemExportError.invalidDestination
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ChannelStemExportError.destinationExists
        }
        if output == .stereoMix {
            return try exportMix(mod: mod, to: destination, options: options,
                                 maximumFrames: maximumFrames, progress: progress)
        }
        try Task.checkCancellation()
        progress(0)
        var peaks = [Float](repeating: 0, count: channelCount)
        var mixPeak: Float = 0
        let analysis = try render(mod: mod, options: options, maximumFrames: maximumFrames) { buffers, count, rendered in
            for frame in 0..<count {
                try updatePeak(&mixPeak, buffers.capture.mixLeft[frame], buffers.capture.mixRight[frame])
                for channel in 0..<channelCount {
                    let index = channel * buffers.capture.frameCapacity + frame
                    try updatePeak(&peaks[channel], buffers.capture.left[index], buffers.capture.right[index])
                }
            }
            progress(0.5 * Double(rendered) / Double(maximumFrames))
        }
        let peak = max(mixPeak, peaks.max() ?? 0)
        let gain: Float = peak > 0.98 ? 0.98 / peak : 1
        let files = (0..<channelCount).map { String(format: "Channel-%02d.wav", $0 + 1) }
        let report = ChannelStemExportReport(schemaVersion: 1, moduleName: mod.name, moduleFormat: mod.format,
            options: options, frameCount: analysis.frames, endedNaturally: analysis.endedNaturally,
            commonGain: gain, unscaledMixPeak: mixPeak, unscaledChannelPeaks: peaks,
            channelFiles: files, referenceMixFile: "Reference-Mix.wav",
            masterProcessing: "Stereo-Float32 vor tanh; gemeinsamer Pegelfaktor für alle Dateien. Mixerlautstärke und externer LED-Ausgabefilter sind nicht enthalten.")

        try Task.checkCancellation()
        let staging = parent.appendingPathComponent(".savage-stems-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(staging.path, 0o700) == 0 else { throw posixError() }
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: staging) } }
        var writers: [StreamingFloatWAVWriter] = []
        for name in files + [report.referenceMixFile] {
            writers.append(try StreamingFloatWAVWriter(url: staging.appendingPathComponent(name), sampleRate: UInt32(options.sampleRate)))
        }
        progress(0.5)
        let written = try render(mod: mod, options: options, maximumFrames: maximumFrames) { buffers, count, rendered in
            for channel in 0..<channelCount {
                let offset = channel * buffers.capture.frameCapacity
                try writers[channel].append(left: buffers.capture.left + offset, right: buffers.capture.right + offset,
                                            frames: count, gain: gain)
            }
            try writers[channelCount].append(left: buffers.capture.mixLeft, right: buffers.capture.mixRight,
                                              frames: count, gain: gain)
            progress(0.5 + 0.5 * Double(rendered) / Double(max(1, analysis.frames)))
        }
        guard written.frames == analysis.frames, written.endedNaturally == analysis.endedNaturally else {
            throw ChannelStemExportError.inconsistentPasses
        }
        for writer in writers { try writer.finish() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: staging.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
        try Task.checkCancellation()
        try publish(staging, to: destination)
        published = true
        progress(1)
        return report
    }

    private static func exportMix(mod: Mod, to destination: URL, options: ChannelStemExportOptions,
                                  maximumFrames: UInt64, progress: @Sendable (Double) -> Void) throws
        -> ChannelStemExportReport {
        try Task.checkCancellation()
        progress(0)
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".savage-stems-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(staging.path, 0o700) == 0 else { throw posixError() }
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: staging) } }
        let writer = try StreamingFloatWAVWriter(url: staging.appendingPathComponent("Mix.wav"),
                                                sampleRate: UInt32(options.sampleRate))
        var peak: Float = 0
        let rendered = try render(mod: mod, options: options, maximumFrames: maximumFrames) { buffers, count, frames in
            for frame in 0..<count {
                try updatePeak(&peak, buffers.outputLeft[frame], buffers.outputRight[frame])
            }
            try writer.append(left: buffers.outputLeft, right: buffers.outputRight, frames: count, gain: 1)
            progress(Double(frames) / Double(maximumFrames))
        }
        try writer.finish()
        let report = ChannelStemExportReport(schemaVersion: 1, moduleName: mod.name, moduleFormat: mod.format,
            options: options, frameCount: rendered.frames, endedNaturally: rendered.endedNaturally,
            commonGain: 1, unscaledMixPeak: peak, unscaledChannelPeaks: [], channelFiles: [],
            referenceMixFile: "Mix.wav",
            masterProcessing: "Stereo-Float32 nach tanh, ohne Normalisierung. Mixerlautstärke und externer LED-Ausgabefilter sind nicht enthalten.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: staging.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
        try Task.checkCancellation()
        try publish(staging, to: destination)
        published = true
        progress(1)
        return report
    }

    private static func updatePeak(_ peak: inout Float, _ left: Float, _ right: Float) throws {
        guard left.isFinite, right.isFinite else { throw ChannelStemExportError.nonFiniteAudio }
        peak = max(peak, abs(left), abs(right))
    }

    private static func render(mod: Mod, options: ChannelStemExportOptions, maximumFrames: UInt64,
                               consume: (StemRenderBuffers, Int, UInt64) throws -> Void) throws
        -> (frames: UInt64, endedNaturally: Bool) {
        let channels = RenderEngine.makeRenderChannels(for: mod)
        let channelCount = mod.format == .it ? max(1, min(RenderEngine.maxChannels, mod.channelCount)) : channels.count
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: options.sampleRate)
        state.stereoSeparation = options.stereoSeparation
        state.useInterpolation = options.useInterpolation
        state.palClock = options.palClock
        for index in 0..<channelCount {
            if let pattern = channels.first?.itVoicePool?.patternChannels[index] {
                pattern.isMuted = options.mutedChannels?.contains(index) ?? pattern.isMuted
                pattern.isSoloed = options.soloChannels.contains(index)
            } else {
                channels[index].isMuted = options.mutedChannels?.contains(index) ?? channels[index].isMuted
                channels[index].isSoloed = options.soloChannels.contains(index)
            }
        }
        let buffers = StemRenderBuffers(channelCount: channelCount)
        let visualization = RealtimeVisualizationExchange(channelCapacity: channelCount)
        let block = RenderEngine.createRenderBlock(state: state, vuBuffer: visualization.makeVUBuffer(),
            waveBuffer: visualization.makeWaveBuffer(), dspChannels: channels, mod: mod,
            sampleRate: options.sampleRate, stereoStemCapture: buffers.capture)
        var rendered: UInt64 = 0
        while rendered < maximumFrames {
            try Task.checkCancellation()
            block(UInt32(buffers.capture.frameCapacity), buffers.outputLeft, buffers.outputRight)
            var count = min(UInt64(buffers.capture.frameCapacity), maximumFrames - rendered)
            if state.endReachedFrame != .max {
                count = min(count, state.endReachedFrame > rendered ? state.endReachedFrame - rendered : 0)
            }
            rendered += count
            try consume(buffers, Int(count), rendered)
            if state.endReached { break }
        }
        return (rendered, state.endReachedFrame <= rendered)
    }

    // Exklusives Umbenennen schützt auch ein erst während des Exports neu
    // angelegtes Ziel. Linux löst renameat2 zur Laufzeit auf, damit ältere
    // libc-Versionen einen erklärbaren Fehler statt eines Ladefehlers liefern.
    private static func publish(_ source: URL, to destination: URL) throws {
        let result: Int32
        #if canImport(Darwin)
        result = renamex_np(source.path, destination.path, UInt32(RENAME_EXCL))
        #elseif canImport(Glibc)
        typealias Rename = @convention(c) (Int32, UnsafePointer<CChar>, Int32, UnsafePointer<CChar>, UInt32) -> Int32
        guard let symbol = dlsym(nil, "renameat2") else { throw POSIXError(.ENOSYS) }
        let renameExclusive = unsafeBitCast(symbol, to: Rename.self)
        let currentDirectory: Int32 = -100 // AT_FDCWD
        let noReplace: UInt32 = 1 // RENAME_NOREPLACE
        result = source.path.withCString { from in
            destination.path.withCString { to in renameExclusive(currentDirectory, from, currentDirectory, to, noReplace) }
        }
        #else
        throw POSIXError(.ENOSYS)
        #endif
        guard result == 0 else {
            if errno == EEXIST { throw ChannelStemExportError.destinationExists }
            throw posixError()
        }
    }

    private static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

private final class StemRenderBuffers {
    let capture: StereoStemCapture
    let outputLeft: UnsafeMutablePointer<Float>
    let outputRight: UnsafeMutablePointer<Float>
    private let storage: UnsafeMutablePointer<Float>

    init(channelCount: Int) {
        let capacity = 1024
        storage = .allocate(capacity: (channelCount * 2 + 4) * capacity)
        capture = StereoStemCapture(left: storage, right: storage + channelCount * capacity,
            mixLeft: storage + channelCount * 2 * capacity, mixRight: storage + (channelCount * 2 + 1) * capacity,
            frameCapacity: capacity)
        outputLeft = storage + (channelCount * 2 + 2) * capacity
        outputRight = storage + (channelCount * 2 + 3) * capacity
    }

    deinit { storage.deallocate() }
}

final class StreamingFloatWAVWriter {
    private let handle: FileHandle
    private let sampleRate: UInt32
    private var frames: UInt64 = 0

    init(url: URL, sampleRate: UInt32) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        self.sampleRate = sampleRate
        try handle.write(contentsOf: header(frames: 0))
    }

    deinit { try? handle.close() }

    func append(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames count: Int, gain: Float) throws {
        guard count >= 0, frames + UInt64(count) <= (UInt64(UInt32.max) - 50) / 8 else {
            throw ModuleRenderer.RenderError.frameLimitExceeded
        }
        var data = Data(count: count * 8)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for frame in 0..<count {
                for side in 0..<2 {
                    let value = ((side == 0 ? left[frame] : right[frame]) * gain).bitPattern
                    let offset = frame * 8 + side * 4
                    for byte in 0..<4 { bytes[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
                }
            }
        }
        try handle.write(contentsOf: data)
        frames += UInt64(count)
    }

    func finish() throws {
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header(frames: frames))
        try handle.synchronize()
        try handle.close()
    }

    private func header(frames: UInt64) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func uint16(_ value: UInt16) { for byte in 0..<2 { data.append(UInt8(truncatingIfNeeded: value >> (byte * 8))) } }
        func uint32(_ value: UInt32) { for byte in 0..<4 { data.append(UInt8(truncatingIfNeeded: value >> (byte * 8))) } }
        let size = UInt32(frames * 8)
        text("RIFF"); uint32(50 + size); text("WAVE")
        text("fmt "); uint32(18); uint16(3); uint16(2); uint32(sampleRate)
        uint32(sampleRate * 8); uint16(8); uint16(32); uint16(0)
        text("fact"); uint32(4); uint32(UInt32(frames))
        text("data"); uint32(size)
        return data
    }
}

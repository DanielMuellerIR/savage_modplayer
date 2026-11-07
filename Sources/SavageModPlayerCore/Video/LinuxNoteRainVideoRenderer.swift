#if os(Linux)
import Foundation

public enum LinuxNoteRainVideoRenderer {
    private struct VideoNote: Codable {
        let key: Int, channel: Int
        let start: Double, end: Double
    }
    private struct Manifest: Codable {
        let options: NoteRainVideoOptions
        let title: String, format: String
        let channelCount: Int
        let audioFrameCount: UInt64
        let audioPath: String, chunksPath: String, outputPath: String, progressPath: String
    }

    public static func export(mod: Mod, to destination: URL, options: NoteRainVideoOptions,
                              renderer: URL, progress: @Sendable (Double) -> Void = { _ in }) throws -> NoteRainVideoReport {
        let maximum = try options.validate(channelCount: mod.channelCount)
        guard destination.pathExtension.lowercased() == "mov", renderer.isFileURL,
              FileManager.default.isExecutableFile(atPath: renderer.path),
              !FileManager.default.fileExists(atPath: destination.path) else { throw NoteRainVideoError.invalidDestination }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".savage-video-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        var options = options
        options.audio.mutedChannels = options.audio.mutedChannels ?? (0..<mod.channelCount).filter { $0 < mod.channelDisabled.count && mod.channelDisabled[$0] }
        let audioPath = staging.appendingPathComponent("audio.wav")
        let audio = NoteRainVideoAudio(mod: mod, options: options.audio, maximumFrames: maximum)
        let writer = try StreamingFloatWAVWriter(url: audioPath, sampleRate: 48_000)
        var samples = [Float](repeating: 0, count: NoteRainVideoAudio.capacity * 2)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: NoteRainVideoAudio.capacity)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: NoteRainVideoAudio.capacity)
        defer { left.deallocate(); right.deallocate() }
        var lastAudioReport = ProcessInfo.processInfo.systemUptime
        while true {
            let count = try samples.withUnsafeMutableBufferPointer { try audio.read(into: $0) }
            if count == 0 { break }
            for frame in 0..<count { left[frame] = samples[frame * 2]; right[frame] = samples[frame * 2 + 1] }
            try writer.append(left: left, right: right, frames: count, gain: 1)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastAudioReport >= 0.05 { progress(0.25 * Double(audio.frames) / Double(maximum)); lastAudioReport = now }
        }
        try writer.finish()
        progress(0.25)
        let frameCount = audio.frames
        guard frameCount > 0 else { throw NoteRainVideoError.invalidOptions }
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: Double(NoteRainVideoOptions.sampleRate))
        state.palClock = options.audio.palClock
        let simulation = NotePreviewSimulation(configuration: .init(mod: mod, sampleRate: Double(NoteRainVideoOptions.sampleRate), state: state))
        let chunks = staging.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: chunks, withIntermediateDirectories: false)
        let seconds = Int((frameCount + 47_999) / 48_000)
        let duration = Double(frameCount) / 48_000
        let encoder = JSONEncoder()
        let output = staging.appendingPathComponent("video.mov"), progressFile = staging.appendingPathComponent("progress")
        let manifest = Manifest(options: options, title: mod.name, format: mod.format.displayName, channelCount: mod.channelCount,
            audioFrameCount: frameCount, audioPath: audioPath.path,
            chunksPath: chunks.path, outputPath: output.path, progressPath: progressFile.path)
        let manifestURL = staging.appendingPathComponent("manifest.json")
        try encoder.encode(manifest).write(to: manifestURL, options: .withoutOverwriting)
        let process = Process()
        process.executableURL = renderer; process.arguments = ["--render-video", manifestURL.path]
        var environment = ProcessInfo.processInfo.environment; environment["QT_QPA_PLATFORM"] = "offscreen"
        process.environment = environment
        let logURL = staging.appendingPathComponent("encoder.log")
        _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL); defer { try? log.close() }
        process.standardError = log; process.standardOutput = FileHandle.nullDevice
        try process.run()
        do {
            var lastReported: Double = -1
            var lastProgress = ProcessInfo.processInfo.systemUptime
            func reportProgress() throws {
                try Task.checkCancellation()
                if let data = try? Data(contentsOf: progressFile), data.count < 100,
                   let text = String(data: data, encoding: .utf8), let value = Double(text), value != lastReported {
                    lastReported = value; lastProgress = ProcessInfo.processInfo.systemUptime
                    progress(0.25 + min(1, max(0, value)) * 0.75)
                }
                guard ProcessInfo.processInfo.systemUptime - lastProgress < 30 else { throw NoteRainVideoError.encoderStalled }
            }
            for second in 0..<seconds {
                try Task.checkCancellation()
                // Drei kleine Fenster begrenzen auch den Disk-Zwischenstand.
                // Der Qt-Konsument entfernt ein Fenster direkt nach dem Lesen.
                while try FileManager.default.contentsOfDirectory(atPath: chunks.path).count >= 3 {
                    guard process.isRunning else { throw NoteRainVideoError.encoderStalled }
                    try reportProgress(); Thread.sleep(forTimeInterval: 0.05)
                }
                let time = Double(second), target = min(frameCount, UInt64(second + options.lookaheadSeconds + 1) * 48_000)
                while simulation.frame < target {
                    try simulation.advance(to: min(target, simulation.frame + 256), commands: [], retainingFrom: max(0, time - 1))
                    guard simulation.snapshot(since: max(0, time - 1), currentTime: time).notes.count <= 60_000 else { throw NoteRainVideoError.tooManyNotes }
                }
                let notes = simulation.snapshot(since: max(0, time - 1), currentTime: time).notes.filter { $0.start < duration }
                    .map { VideoNote(key: $0.key, channel: $0.channel, start: $0.start, end: min($0.end, duration)) }
                let pending = staging.appendingPathComponent("notes-pending.json")
                try encoder.encode(notes).write(to: pending, options: .withoutOverwriting)
                try FileManager.default.moveItem(at: pending, to: chunks.appendingPathComponent("\(second).json"))
            }
            while process.isRunning {
                try reportProgress()
                Thread.sleep(forTimeInterval: 0.1)
            }
        } catch {
            process.terminate(); process.waitUntilExit(); throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = try? BoundedFileReader.read(logURL, maximumBytes: 65_536)
            let detail = data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Status \(process.terminationStatus)"
            throw NoteRainVideoError.encodingFailed("Qt/FFmpeg: \(detail)")
        }
        try Task.checkCancellation()
        try FileManager.default.linkItem(at: output, to: destination)
        progress(1)
        let clock = try NoteRainVideoClock(framesPerSecond: options.framesPerSecond)
        let videos = (frameCount + clock.samplesPerVideoFrame - 1) / clock.samplesPerVideoFrame
        return NoteRainVideoReport(schemaVersion: 1, moduleName: mod.name, moduleFormat: mod.format, options: options,
            audioFrameCount: frameCount, videoFrameCount: videos, endedNaturally: audio.endedNaturally,
            audioProcessing: "Stereo-Float32 nach tanh; Mixerlautstärke und externer LED-Ausgabefilter sind nicht enthalten.")
    }
}
#endif

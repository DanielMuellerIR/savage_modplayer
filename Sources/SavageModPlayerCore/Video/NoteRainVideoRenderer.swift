#if os(macOS) && canImport(AVFoundation)
import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import CoreGraphics
import AudioToolbox
import Darwin

public enum NoteRainVideoRenderer {
    public static func export(mod: Mod, to destination: URL, options: NoteRainVideoOptions = .init(),
                              progress: @Sendable (Double) -> Void = { _ in }) throws -> NoteRainVideoReport {
        let count = max(1, min(RenderEngine.maxChannels, mod.channelCount))
        let maximumFrames = try options.validate(channelCount: count)
        let clock = try NoteRainVideoClock(framesPerSecond: options.framesPerSecond)
        var options = options
        let headerMutes = mod.format == .it ? (0..<count).filter { $0 < mod.channelDisabled.count && mod.channelDisabled[$0] } : []
        options.audio.mutedChannels = Array(Set(options.audio.mutedChannels ?? headerMutes)).sorted()
        options.audio.soloChannels = Array(Set(options.audio.soloChannels)).sorted()
        let destination = destination.standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        var directory: ObjCBool = false
        guard destination.isFileURL, destination.query == nil, destination.fragment == nil, !destination.path.contains("\0"),
              destination.pathExtension.lowercased() == "mov", !destination.lastPathComponent.isEmpty,
              FileManager.default.fileExists(atPath: parent.path, isDirectory: &directory), directory.boolValue else {
            throw NoteRainVideoError.invalidDestination
        }
        var info = stat()
        guard lstat(destination.path, &info) != 0 else { throw NoteRainVideoError.destinationExists }
        guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try Task.checkCancellation(); progress(0)
        let staging = parent.appendingPathComponent(".savage-video-\(UUID())", isDirectory: true)
        guard mkdir(staging.path, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var stagingInfo = stat()
        guard lstat(staging.path, &stagingInfo) == 0 else { throw NoteRainVideoError.invalidDestination }
        let stagingIdentity = (stagingInfo.st_dev, stagingInfo.st_ino)
        defer {
            var current = stat()
            if lstat(staging.path, &current) == 0, current.st_dev == stagingIdentity.0, current.st_ino == stagingIdentity.1 {
                try? FileManager.default.removeItem(at: staging)
            }
        }
        let temporary = staging.appendingPathComponent("video.mov")
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mov)
        writer.movieTimeScale = Int32(NoteRainVideoOptions.sampleRate)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: options.width, AVVideoHeightKey: options.height,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false,
                                             AVVideoAverageBitRateKey: options.videoBitRate,
                                             AVVideoExpectedSourceFrameRateKey: options.framesPerSecond]])
        video.mediaTimeScale = Int32(NoteRainVideoOptions.sampleRate)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: NoteRainVideoOptions.sampleRate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        video.expectsMediaDataInRealTime = false; audioInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: options.width, kCVPixelBufferHeightKey as String: options.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard writer.canAdd(video), writer.canAdd(audioInput) else { throw NoteRainVideoError.encodingFailed("Das Ausgabeformat wird nicht unterstützt.") }
        writer.add(video); writer.add(audioInput)
        guard writer.startWriting() else { throw failure(writer) }
        writer.startSession(atSourceTime: .zero)
        let audio = NoteRainVideoAudio(mod: mod, options: options.audio, maximumFrames: maximumFrames)
        let simulation = NotePreviewSimulation(configuration: NotePreviewConfiguration(mod: mod,
            sampleRate: Double(NoteRainVideoOptions.sampleRate), state: audio.state))
        let painter = NoteRainVideoPainter(options: options, title: mod.name, format: mod.format.displayName, channelCount: count)
        let format = try audioFormat()
        var samples = [Float](repeating: 0, count: NoteRainVideoAudio.capacity * 2)
        var videoFrames: UInt64 = 0
        var audioEnded = false
        var lastProgress = ProcessInfo.processInfo.systemUptime
        var lastReport = lastProgress
        var previewEnd: Double?
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        while true {
            let frameSample = try clock.sampleFrame(forVideoFrame: videoFrames)
            if audioEnded && frameSample >= audio.frames { break }
            try Task.checkCancellation()
            guard writer.status == .writing else { throw failure(writer) }
            let progressed = try autoreleasepool { () throws -> Bool in
                var progressed = false
                let videoSample = frameSample
                if !audioEnded, audioInput.isReadyForMoreMediaData, audio.frames < videoSample + 96_000 {
                    let start = audio.frames
                    let written = try samples.withUnsafeMutableBufferPointer { try audio.read(into: $0) }
                    if written > 0 {
                        try Task.checkCancellation()
                        let sample = try audioSample(samples, count: written, start: start, format: format)
                        guard audioInput.append(sample) else { throw failure(writer) }
                    }
                    if written < NoteRainVideoAudio.capacity || audio.frames >= maximumFrames {
                        audioEnded = true; audioInput.markAsFinished()
                    }
                    progressed = true
                }
                if video.isReadyForMoreMediaData, videoSample < audio.frames {
                    guard let pool = adaptor.pixelBufferPool else { throw failure(writer) }
                    var buffer: CVPixelBuffer?
                    let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool,
                        [kCVPixelBufferPoolAllocationThresholdKey as String: 6] as CFDictionary, &buffer)
                    if status == kCVReturnSuccess, let buffer {
                        let time = Double(videoSample) / Double(NoteRainVideoOptions.sampleRate)
                        let target = videoSample + UInt64(options.lookaheadSeconds * NoteRainVideoOptions.sampleRate)
                        var snapshot = simulation.snapshot(since: max(0, time - 1), currentTime: time)
                        // Maximal 256 simulierte Frames zwischen den Prüfungen halten
                        // auch bei sehr kurzen IT-Stimmen die Ereignismenge begrenzt.
                        while simulation.frame < target, previewEnd == nil {
                            try Task.checkCancellation()
                            try simulation.advance(to: min(target, simulation.frame + 256), commands: [], retainingFrom: max(0, time - 1))
                            snapshot = simulation.snapshot(since: max(0, time - 1), currentTime: time)
                            guard snapshot.notes.count <= 60_000 else { throw NoteRainVideoError.tooManyNotes }
                            previewEnd = snapshot.nextSongEnd
                        }
                        let cutoff = min(Double(maximumFrames) / Double(NoteRainVideoOptions.sampleRate), previewEnd ?? .infinity)
                        let notes = snapshot.notes.filter { $0.start < cutoff }.map { note in
                            var note = note; note.end = min(note.end, cutoff); return note
                        }
                        try draw(buffer, options: options, painter: painter, notes: notes, sampleFrame: videoSample, colorSpace: colorSpace)
                        try Task.checkCancellation()
                        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(videoSample), timescale: Int32(NoteRainVideoOptions.sampleRate))) else { throw failure(writer) }
                        videoFrames += 1; progressed = true
                    } else if status != kCVReturnWouldExceedAllocationThreshold {
                        throw NoteRainVideoError.encodingFailed("Der Bildpuffer-Pool meldet Fehler \(status).")
                    }
                }
                return progressed
            }
            let now = ProcessInfo.processInfo.systemUptime
            if progressed { lastProgress = now }
            else {
                guard now - lastProgress < 30 else { throw NoteRainVideoError.encoderStalled }
                Thread.sleep(forTimeInterval: 0.002)
            }
            if now - lastReport >= 0.05 { progress(min(0.99, Double(audio.frames) / Double(maximumFrames))); lastReport = now }
        }
        guard audio.frames > 0, videoFrames == clock.videoFrameCount(audioFrames: audio.frames) else { throw NoteRainVideoError.emptyOutput }
        try Task.checkCancellation()
        video.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: Int64(audio.frames), timescale: Int32(NoteRainVideoOptions.sampleRate)))
        let done = DispatchSemaphore(value: 0)
        let finishingSince = ProcessInfo.processInfo.systemUptime
        writer.finishWriting { done.signal() }
        while done.wait(timeout: .now() + 0.05) == .timedOut {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime - finishingSince < 30 else { throw NoteRainVideoError.encoderStalled }
        }
        guard writer.status == .completed else { throw failure(writer) }
        try Task.checkCancellation()
        guard renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw NoteRainVideoError.destinationExists }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        progress(1)
        return NoteRainVideoReport(schemaVersion: 1, moduleName: mod.name, moduleFormat: mod.format, options: options,
            audioFrameCount: audio.frames, videoFrameCount: videoFrames, endedNaturally: audio.endedNaturally,
            audioProcessing: "Float32-Stereo nach tanh, ohne Peaknormalisierung, Mixerlautstärke und externen LED-Ausgabefilter.")
    }
    private static func draw(_ buffer: CVPixelBuffer, options: NoteRainVideoOptions, painter: NoteRainVideoPainter,
                             notes: [PreviewNote], sampleFrame: UInt64, colorSpace: CGColorSpace) throws {
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw NoteRainVideoError.encodingFailed("Der Bildpuffer konnte nicht geöffnet werden.") }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: options.width, height: options.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw NoteRainVideoError.encodingFailed("Der Bildpuffer konnte nicht angelegt werden.")
        }
        painter.draw(context, notes: notes, sampleFrame: sampleFrame)
    }
    private static func failure(_ writer: AVAssetWriter) -> NoteRainVideoError {
        .encodingFailed(writer.error?.localizedDescription ?? "Der native Medien-Writer konnte den Vorgang nicht abschließen.")
    }
    private static func audioFormat() throws -> CMAudioFormatDescription {
        var description = AudioStreamBasicDescription(mSampleRate: Double(NoteRainVideoOptions.sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
            mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0,
            layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard status == noErr, let format else { throw NoteRainVideoError.encodingFailed("Das Audioformat konnte nicht angelegt werden.") }
        return format
    }
    private static func audioSample(_ samples: [Float], count: Int, start: UInt64, format: CMAudioFormatDescription) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        let bytes = count * 8
        let created = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
        guard created == noErr, let block else { throw NoteRainVideoError.encodingFailed("Der Audiopuffer konnte nicht angelegt werden.") }
        let copied = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
        guard copied == noErr else { throw NoteRainVideoError.encodingFailed("Der Audiopuffer konnte nicht gefüllt werden.") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(NoteRainVideoOptions.sampleRate)),
            presentationTimeStamp: CMTime(value: Int64(start), timescale: Int32(NoteRainVideoOptions.sampleRate)), decodeTimeStamp: .invalid)
        var size = 8, sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw NoteRainVideoError.encodingFailed("Der Audioblock konnte nicht angelegt werden.") }
        return sample
    }
}
#endif

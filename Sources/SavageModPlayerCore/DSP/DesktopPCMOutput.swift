#if os(Linux)
import Foundation

@MainActor
final class DesktopPCMOutput {
    let sampleRate = PCMSinkFactory.preferredFormat().sampleRate
    private var sink: PCMSink?
    private var adapter: DesktopPCMAdapter?
    private var started = false

    func start(block: @escaping ModuleRenderBlock, sleepTimer: SleepTimerSignal,
               volume: Float, ledFilter: Bool, initiallyPaused: Bool) throws {
        let format = PCMFormat(sampleRate: sampleRate, channels: 2)
        let adapter = DesktopPCMAdapter(block: block, sampleRate: sampleRate, sleepTimer: sleepTimer)
        adapter.setOptions(volume: volume, ledFilter: ledFilter)
        self.adapter = adapter
        sink = PCMSinkFactory.makeDefault(format: format)
        if !initiallyPaused { try resume() }
    }

    func setOptions(volume: Float, ledFilter: Bool) { adapter?.setOptions(volume: volume, ledFilter: ledFilter) }
    func pause() throws { if started { try sink?.pause() } }
    func resume() throws {
        guard let sink, let adapter else { return }
        if started { try sink.resume() }
        else { try sink.start(render: adapter.render); started = true }
    }
    func stop() {
        sink?.stop()
        if started { _ = sink?.waitUntilFinished() }
        sink = nil
        adapter = nil
        started = false
    }
}

// Nur der Audiothread verändert Filterhistorie und Scratch-Puffer. Optionen
// wechseln atomar, und stop() wartet vor ihrer Freigabe auf den Sink.
private final class DesktopPCMAdapter: @unchecked Sendable {
    private let block: ModuleRenderBlock
    private let gain: SleepTimerGain
    private let options = LockFreeAtomicUInt64(0)
    private let capacity = 4096
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    private var l1: Float = 0, l2: Float = 0, r1: Float = 0, r2: Float = 0

    init(block: @escaping ModuleRenderBlock, sampleRate: Double, sleepTimer: SleepTimerSignal) {
        self.block = block
        gain = SleepTimerGain(signal: sleepTimer, sampleRate: sampleRate)
        left = .allocate(capacity: capacity); left.initialize(repeating: 0, count: capacity)
        right = .allocate(capacity: capacity); right.initialize(repeating: 0, count: capacity)
        let omega = 2 * Double.pi * 3200 / sampleRate
        let cosine = cos(omega), alpha = sin(omega) / sqrt(2)
        b0 = Float((1 - cosine) / 2 / (1 + alpha))
        b1 = Float((1 - cosine) / (1 + alpha)); b2 = b0
        a1 = Float(-2 * cosine / (1 + alpha)); a2 = Float((1 - alpha) / (1 + alpha))
    }
    deinit {
        left.deinitialize(count: capacity); left.deallocate()
        right.deinitialize(count: capacity); right.deallocate()
    }
    func setOptions(volume: Float, ledFilter: Bool) {
        let value = volume.isFinite ? min(1, max(0, volume)) : 0
        options.storeRelease(UInt64((value * value).bitPattern) | (ledFilter ? UInt64(1) << 32 : 0))
    }
    var render: PCMRenderBlock {
        { [self] destination, frames in
            let packed = options.loadAcquire()
            let volume = Float(bitPattern: UInt32(truncatingIfNeeded: packed))
            let filter = packed & (UInt64(1) << 32) != 0
            var written = 0
            while written < frames {
                let count = min(capacity, frames - written)
                block(UInt32(count), left, right)
                gain.process(frames: UInt32(count), left: left, right: right)
                for index in 0..<count {
                    var l = left[index], r = right[index]
                    if filter {
                        let nextL = b0 * l + l1, nextR = b0 * r + r1
                        l1 = b1 * l - a1 * nextL + l2; l2 = b2 * l - a2 * nextL
                        r1 = b1 * r - a1 * nextR + r2; r2 = b2 * r - a2 * nextR
                        l = nextL; r = nextR
                    } else { l1 = 0; l2 = 0; r1 = 0; r2 = 0 }
                    destination[(written + index) * 2] = l * volume
                    destination[(written + index) * 2 + 1] = r * volume
                }
                written += count
            }
            return frames
        }
    }
}

enum DesktopWAVWriter {
    static func export(mod: Mod, to destination: URL, stereoSeparation: Float,
                       useInterpolation: Bool, palClock: Bool, seconds: Double) throws {
        let folder = destination.deletingLastPathComponent().appendingPathComponent(".savage-wav-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = try ChannelStemRenderer.export(mod: mod, to: folder,
            options: .init(maximumSeconds: seconds, stereoSeparation: stereoSeparation,
                           useInterpolation: useInterpolation, palClock: palClock), output: .stereoMix)
        try FileManager.default.linkItem(at: folder.appendingPathComponent(report.referenceMixFile), to: destination)
    }

    static func export(sample: Sample, sampleRate: Double, to destination: URL) throws {
        let channels = sample.rightPCM == nil ? 1 : 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let byteCount = sample.pcm.count * channels * 4
        guard byteCount <= Int(UInt32.max) - 36, sampleRate.isFinite, sampleRate > 0,
              sampleRate <= Double(UInt32.max / UInt32(channels * 4)) else {
            throw ChannelStemExportError.invalidOptions
        }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(byteCount + 36))
        data.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16)); append(UInt16(3))
        append(UInt16(channels)); append(UInt32(sampleRate)); append(UInt32(sampleRate) * UInt32(channels * 4))
        append(UInt16(channels * 4)); append(UInt16(32))
        data.append(contentsOf: "data".utf8); append(UInt32(byteCount))
        for index in sample.pcm.indices {
            append(sample.pcm[index].bitPattern)
            if let right = sample.rightPCM { append((index < right.count ? right[index] : 0).bitPattern) }
        }
        try data.write(to: destination, options: .withoutOverwriting)
    }
}
#endif

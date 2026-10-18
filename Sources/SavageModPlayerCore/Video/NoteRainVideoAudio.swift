import Foundation

final class NoteRainVideoAudio {
    static let capacity = 4096
    let state: RealtimePlaybackState
    private let block: ModuleRenderBlock
    private let visualization: RealtimeVisualizationExchange
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let maximumFrames: UInt64
    private(set) var frames: UInt64 = 0
    var endedNaturally: Bool { state.endReachedFrame <= frames }

    init(mod: Mod, options: ChannelStemExportOptions, maximumFrames: UInt64) {
        self.maximumFrames = maximumFrames
        let channels = RenderEngine.makeRenderChannels(for: mod)
        let count = mod.format == .it ? max(1, min(RenderEngine.maxChannels, mod.channelCount)) : channels.count
        state = RenderEngine.makeRenderState(for: mod, sampleRate: options.sampleRate)
        state.stereoSeparation = options.stereoSeparation
        state.useInterpolation = options.useInterpolation
        state.palClock = options.palClock
        for index in 0..<count {
            if let pattern = channels.first?.itVoicePool?.patternChannels[index] {
                pattern.isMuted = options.mutedChannels?.contains(index) ?? pattern.isMuted
                pattern.isSoloed = options.soloChannels.contains(index)
            } else {
                channels[index].isMuted = options.mutedChannels?.contains(index) ?? channels[index].isMuted
                channels[index].isSoloed = options.soloChannels.contains(index)
            }
        }
        visualization = RealtimeVisualizationExchange(channelCapacity: count)
        left = .allocate(capacity: Self.capacity); right = .allocate(capacity: Self.capacity)
        left.initialize(repeating: 0, count: Self.capacity); right.initialize(repeating: 0, count: Self.capacity)
        block = RenderEngine.createRenderBlock(state: state, vuBuffer: visualization.makeVUBuffer(),
            waveBuffer: visualization.makeWaveBuffer(), dspChannels: channels, mod: mod, sampleRate: options.sampleRate)
    }
    deinit {
        left.deinitialize(count: Self.capacity); right.deinitialize(count: Self.capacity)
        left.deallocate(); right.deallocate()
    }
    func read(into samples: UnsafeMutableBufferPointer<Float>) throws -> Int {
        try Task.checkCancellation()
        let remaining = min(maximumFrames > frames ? maximumFrames - frames : 0,
                            state.endReachedFrame > frames ? state.endReachedFrame - frames : 0)
        let requested = min(Self.capacity, Int(min(UInt64(Self.capacity), remaining)), samples.count / 2)
        guard requested > 0 else { return 0 }
        block(UInt32(requested), left, right)
        let count = min(requested, Int(min(UInt64(requested), state.endReachedFrame > frames ? state.endReachedFrame - frames : 0)))
        for index in 0..<count {
            guard left[index].isFinite, right[index].isFinite else { throw NoteRainVideoError.nonFiniteAudio }
            samples[index * 2] = left[index]; samples[index * 2 + 1] = right[index]
        }
        frames += UInt64(count)
        return count
    }
}

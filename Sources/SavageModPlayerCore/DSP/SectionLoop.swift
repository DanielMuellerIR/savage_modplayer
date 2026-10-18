import Foundation

public struct SectionLoopOptions: Sendable, Equatable {
    public var stereoSeparation: Float
    public var useInterpolation: Bool
    public var palClock: Bool

    public init(stereoSeparation: Float = 0.8, useInterpolation: Bool = true, palClock: Bool = true) {
        self.stereoSeparation = stereoSeparation
        self.useInterpolation = useInterpolation
        self.palClock = palClock
    }

    func apply(to state: RealtimePlaybackState) {
        state.stereoSeparation = stereoSeparation
        state.useInterpolation = useInterpolation
        state.palClock = palClock
    }
}

public enum SectionLoopError: Error, LocalizedError, Sendable, Equatable {
    case invalidSection, unreachableStart, unreachableEnd, budgetExceeded, sampleRateChanged

    public var errorDescription: String? {
        switch self {
        case .invalidSection: "Der A/B-Bereich oder die Samplerate ist ungültig."
        case .unreachableStart: "Der Song erreicht den gewählten Anfang A nicht."
        case .unreachableEnd: "Der Song erreicht das gewählte Ende B nach A nicht."
        case .budgetExceeded: "Der A/B-Bereich wurde innerhalb der Vorbereitungsgrenze nicht erreicht."
        case .sampleRateChanged: "Die Audioausgabe hat sich geändert. Bitte A/B erneut vorbereiten."
        }
    }
}

// Die getrennte Objektstruktur wird vor dem Audiostart reserviert. Nach der
// Vorbereitung bleibt sie unveränderlich; nur die Zielinstanz wird kopiert.
final class PlaybackSnapshot: @unchecked Sendable {
    private let state: RealtimePlaybackState
    private let channels: [DSPChannel]

    init(mod: Mod, sampleRate: Double) {
        state = RenderEngine.makeRenderState(for: mod, sampleRate: sampleRate)
        channels = RenderEngine.makeRenderChannels(for: mod)
    }

    func capture(state sourceState: RealtimePlaybackState, channels sourceChannels: [DSPChannel]) {
        Self.copy(state: sourceState, channels: sourceChannels, to: state, channels: channels)
    }

    func apply(to targetState: RealtimePlaybackState, channels targetChannels: [DSPChannel]) {
        Self.copy(state: state, channels: channels, to: targetState, channels: targetChannels)
    }

    private static func copy(state: RealtimePlaybackState, channels: [DSPChannel],
                             to targetState: RealtimePlaybackState, channels targetChannels: [DSPChannel]) {
        targetState.copyPlaybackState(from: state)
        if let source = channels.first?.itVoicePool, let target = targetChannels.first?.itVoicePool {
            target.copyPlaybackState(from: source)
        }
        for index in channels.indices { targetChannels[index].copyPlaybackState(from: channels[index]) }
    }
}

public final class PreparedSectionLoop: Sendable {
    public let section: SongSection
    public let sampleRate: Double
    public let options: SectionLoopOptions
    public let startFrame: UInt64
    public let frameCount: UInt64
    let snapshot: PlaybackSnapshot

    private init(section: SongSection, sampleRate: Double, options: SectionLoopOptions,
                 startFrame: UInt64, frameCount: UInt64, snapshot: PlaybackSnapshot) {
        self.section = section
        self.sampleRate = sampleRate
        self.options = options
        self.startFrame = startFrame
        self.frameCount = frameCount
        self.snapshot = snapshot
    }

    // Diesen synchronen Worker außerhalb des MainActors und Audiothreads
    // ausführen. Speicherbedarf ist von der Songdauer unabhängig.
    public static func prepare(mod: Mod, section: SongSection, sampleRate: Double,
                               options: SectionLoopOptions = .init(), maximumSeconds: Double = 600,
                               progress: @Sendable (Double) -> Void = { _ in }) throws -> PreparedSectionLoop {
        let layout = SongPositionLayout(module: mod)
        guard layout.contains(section.start), layout.contains(section.end),
              sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
              maximumSeconds.isFinite, maximumSeconds > 0, maximumSeconds <= 3_600,
              options.stereoSeparation.isFinite, (0...1).contains(options.stereoSeparation) else {
            throw SectionLoopError.invalidSection
        }
        let maximumFrames = UInt64(sampleRate * maximumSeconds)
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: sampleRate)
        options.apply(to: state)
        let channels = RenderEngine.makeRenderChannels(for: mod)
        let snapshot = PlaybackSnapshot(mod: mod, sampleRate: sampleRate)
        let visualization = RealtimeVisualizationExchange(channelCapacity: max(1, min(64, mod.channelCount)))
        let render = RenderEngine.createRenderBlock(state: state, vuBuffer: visualization.makeVUBuffer(),
            waveBuffer: visualization.makeWaveBuffer(), dspChannels: channels, mod: mod, sampleRate: sampleRate)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
        defer { left.deallocate(); right.deallocate() }
        var firstFrame: UInt64?
        var reachedEnd = false
        var nextProgress: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let boundary = SequencerCore.willAdvanceRow(state: state)
            if boundary {
                if let firstFrame, reachedEnd {
                    progress(1)
                    return PreparedSectionLoop(section: section, sampleRate: sampleRate, options: options,
                        startFrame: firstFrame, frameCount: state.elapsedFrames - firstFrame, snapshot: snapshot)
                }
            }
            guard state.elapsedFrames < maximumFrames else { throw SectionLoopError.budgetExceeded }
            if state.elapsedFrames >= nextProgress {
                progress(Double(state.elapsedFrames) / Double(maximumFrames))
                nextProgress = state.elapsedFrames + UInt64(sampleRate)
            }
            if boundary, firstFrame == nil { snapshot.capture(state: state, channels: channels) }
            let frameBefore = state.elapsedFrames
            // Niemals eine Tick-Grenze im Chunk überfahren: Der erste Frame
            // einer neuen Zeile muss einzeln erkannt werden.
            let count = min(1024, max(1, Int(ceil(state.outputsUntilNextTick))),
                            Int(maximumFrames - state.elapsedFrames))
            render(UInt32(count), left, right)
            if boundary {
                let address = SongAddress(position: state.position, row: state.rowIndex)
                if firstFrame == nil, address == section.start { firstFrame = frameBefore }
                if firstFrame != nil, address == section.end { reachedEnd = true }
                if state.endReached { throw firstFrame == nil ? SectionLoopError.unreachableStart : SectionLoopError.unreachableEnd }
            }
        }
    }
}

// Ein unveränderlicher vorbereiteter Snapshot pro Renderinstanz. Die Lebensdauer
// deckt sämtliche Callbacks ab; es werden darin keine Swift-Objekte ersetzt oder
// freigegeben. Nur die Deaktivierung kommt als atomarer Bedienauftrag herein.
final class SectionLoopPlayback: Sendable {
    let prepared: PreparedSectionLoop
    private let enabled = LockFreeAtomicUInt64(1)
    nonisolated(unsafe) private var remainingFrames: UInt64 = 0
    nonisolated(unsafe) private var active = true

    init(_ prepared: PreparedSectionLoop) { self.prepared = prepared }
    var isEnabled: Bool { enabled.loadAcquire() != 0 }
    func disable() { enabled.storeRelease(0) }

    func beginBlock() -> Bool {
        guard active, !isEnabled else { return false }
        active = false
        return true
    }

    @discardableResult
    func beginFrame(state: RealtimePlaybackState, channels: [DSPChannel]) -> Bool {
        guard active else { return false }
        let restart = remainingFrames == 0
        if restart {
            prepared.snapshot.apply(to: state, channels: channels)
            remainingFrames = prepared.frameCount
        }
        remainingFrames -= 1
        return restart
    }
}

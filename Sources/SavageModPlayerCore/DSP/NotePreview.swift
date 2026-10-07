import Foundation

public struct PreviewNote: Sendable, Equatable, Identifiable {
    public let id: UInt64
    public let key: Int
    public let channel: Int
    public let start: Double
    public var end: Double
    public var isOpen: Bool

    public var name: String {
        Self.name(for: key)
    }

    public static func name(for key: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        guard (0..<120).contains(key) else { return "—" }
        return "\(names[key % 12])\(key / 12)"
    }
}

// Ein Produzent (Audio) und ein Konsument (UI). Ein Slot wird erst nach dem
// Release des Lesezaehlers wiederverwendet; anders als beim Dreifachpuffer
// schreiben die beiden Threads nie gleichzeitig in denselben Slot.
public final class NotePreviewExchange: @unchecked Sendable {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<NotePreviewCommand>
    private let written = LockFreeAtomicUInt64(0)
    private let read = LockFreeAtomicUInt64(0)
    private let clock = LockFreeAtomicUInt64(0)
    private let overflow = LockFreeAtomicUInt64(0)
    nonisolated(unsafe) private var renderedFrames: UInt64 = 0

    public init(capacity: Int = 128) {
        self.capacity = max(1, capacity)
        storage = .allocate(capacity: self.capacity)
        storage.initialize(repeating: NotePreviewCommand(), count: self.capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    public var frame: UInt64 { clock.loadAcquire() }
    public var hasOverflowed: Bool { overflow.loadAcquire() != 0 }

    func append(_ command: NotePreviewCommand) {
        let head = written.loadRelaxed()
        guard head - read.loadAcquire() < UInt64(capacity) else {
            overflow.storeRelease(1)
            return
        }
        var entry = command
        entry.frame = renderedFrames
        storage[Int(head % UInt64(capacity))] = entry
        written.storeRelease(head + 1)
    }

    func finishBlock(frames: Int) {
        renderedFrames += UInt64(frames)
        clock.storeRelease(renderedFrames)
    }

    public func takeCommands() -> [NotePreviewCommand] {
        let tail = read.loadRelaxed()
        let head = written.loadAcquire()
        let commands = (tail..<head).map { storage[Int($0 % UInt64(capacity))] }
        read.storeRelease(head)
        return commands
    }
}

public struct NotePreviewCommand: Sendable, Equatable {
    enum Kind: Sendable { case seek, tempo, options }
    var kind: Kind = .tempo
    var frame: UInt64 = 0
    var position = 0
    var row = 0
    var speed: Int? = nil
    var bpm: Int? = nil
    var globalVolume = 64
    var palClock = true
}

public struct NotePreviewConfiguration: Sendable {
    public let mod: Mod
    public let sampleRate: Double
    let position: Int
    let row: Int
    let speed: Int
    let bpm: Int
    let globalVolume: Int
    let palClock: Bool

    init(mod: Mod, sampleRate: Double, state: RealtimePlaybackState) {
        self.mod = mod
        self.sampleRate = sampleRate
        position = state.position
        row = state.rowIndex + 1
        speed = state.ticksPerRow
        bpm = state.bpm
        globalVolume = Int(state.globalVolume)
        palClock = state.palClock
    }
}

public final class NotePreviewSource: Sendable {
    public let id = UUID()
    public let configuration: NotePreviewConfiguration
    public let exchange: NotePreviewExchange
    @MainActor private var history: [NotePreviewCommand] = []

    init(configuration: NotePreviewConfiguration, exchange: NotePreviewExchange) {
        self.configuration = configuration
        self.exchange = exchange
    }

    @MainActor @discardableResult
    public func collectCommands() -> [NotePreviewCommand] {
        history += exchange.takeCommands()
        return history
    }
}

public struct NotePreviewSnapshot: Sendable {
    public let notes: [PreviewNote]
    public let preparedThrough: Double
    public let nextSongEnd: Double?
}

// Nur der Hintergrund-Actor besitzt diese DSP-Instanz. Die UI erhaelt Werte,
// niemals die vom Audio-Thread veraenderten DSPChannel-Referenzen.
final class NotePreviewSimulation {
    let configuration: NotePreviewConfiguration
    let state: RealtimePlaybackState
    let channels: [DSPChannel]
    var frame: UInt64 = 0
    private var notes: [PreviewNote] = []
    private var openNotes: [Int: PreviewNote] = [:]
    private var generations: [UInt64]
    private var itGenerations: [UInt64]
    private var nextID: UInt64 = 0
    private var commandIndex = 0
    private var retainedSince: Double = 0
    private var songEnds: [Double] = []

    init(configuration: NotePreviewConfiguration) {
        self.configuration = configuration
        channels = RenderEngine.makeRenderChannels(for: configuration.mod)
        generations = [UInt64](repeating: 0, count: channels.count)
        itGenerations = generations
        state = RenderEngine.makeRenderState(for: configuration.mod, sampleRate: configuration.sampleRate)
        state.position = configuration.position
        state.rowIndex = configuration.row - 1
        state.ticksPerRow = configuration.speed
        state.tick = configuration.speed - 1
        state.bpm = configuration.bpm
        state.globalVolume = Float(configuration.globalVolume)
        state.palClock = configuration.palClock
        SequencerCore.recalculateTickDuration(state: state, sampleRate: configuration.sampleRate)
    }

    func advance(to target: UInt64, commands: [NotePreviewCommand], retainingFrom: Double = 0) throws {
        retainedSince = retainingFrom
        let mod = configuration.mod
        let rate = configuration.sampleRate
        let pool = channels.first?.itVoicePool
        while frame < target {
            if frame & 1023 == 0 { try Task.checkCancellation() }
            while commandIndex < commands.count, commands[commandIndex].frame <= frame {
                apply(commands[commandIndex])
                commandIndex += 1
            }
            if state.outputsUntilNextTick <= 0 {
                SequencerCore.advanceIfNeeded(state: state, channels: channels, mod: mod, sampleRate: rate)
                if state.consumeEndTransition() != nil {
                    songEnds.append(Double(frame) / rate)
                }
                for index in channels.indices { observe(index, at: frame) }
            }
            let count = pool?.usesBackgroundVoices == true ? pool!.activeVoiceCount : channels.count
            for position in 0..<count {
                let index = pool?.usesBackgroundVoices == true ? pool!.activeVoiceIndex(at: position) : position
                _ = RenderEngine.renderChannelSample(channel: channels[index], useInterpolation: false)
                if !channels[index].playing { close(index, at: frame + 1) }
            }
            state.outputsUntilNextTick -= 1
            state.elapsedFrames += 1
            frame += 1
        }
    }

    private func apply(_ command: NotePreviewCommand) {
        switch command.kind {
        case .seek:
            for index in channels.indices { close(index, at: frame) }
            RenderEngine.applySeek(.init(
                sequence: 0, position: command.position, row: command.row,
                ticksPerRow: command.speed ?? state.ticksPerRow, bpm: command.bpm ?? state.bpm,
                globalVolume: command.globalVolume, elapsedFrames: frame),
                state: state, channels: channels, sampleRate: configuration.sampleRate)
        case .tempo:
            if let speed = command.speed { state.ticksPerRow = speed }
            if let bpm = command.bpm { state.bpm = bpm }
            SequencerCore.recalculateTickDuration(state: state, sampleRate: configuration.sampleRate)
        case .options:
            state.palClock = command.palClock
        }
    }

    private func observe(_ index: Int, at frame: UInt64) {
        let voice = channels[index]
        let isValid = voice.playing && voice.sample?.pcm.isEmpty == false
            && voice.visualNoteKey >= 0 && voice.currentVolume > 0
            && voice.xmVolumeScale > 0 && voice.itVolumeScale > 0
        if generations[index] != voice.visualNoteGeneration || itGenerations[index] != voice.itVoiceGeneration {
            close(index, at: frame)
            generations[index] = voice.visualNoteGeneration
            itGenerations[index] = voice.itVoiceGeneration
        }
        guard isValid else { close(index, at: frame); return }
        if openNotes[index] == nil {
            nextID += 1
            openNotes[index] = PreviewNote(
                id: nextID, key: voice.visualNoteKey,
                channel: voice.itPatternState?.channelIndex ?? index,
                start: Double(frame) / configuration.sampleRate,
                end: Double(frame) / configuration.sampleRate, isOpen: true)
        }
    }

    private func close(_ index: Int, at frame: UInt64) {
        guard var note = openNotes.removeValue(forKey: index) else { return }
        note.end = Double(frame) / configuration.sampleRate
        note.isOpen = false
        if note.end > note.start, note.end >= retainedSince { notes.append(note) }
    }

    func snapshot(since time: Double, currentTime: Double = 0) -> NotePreviewSnapshot {
        notes.removeAll { $0.end < time }
        songEnds.removeAll { $0 < currentTime }
        let through = Double(frame) / configuration.sampleRate
        let active = openNotes.values.map { note in
            var note = note
            note.end = through
            return note
        }
        return NotePreviewSnapshot(notes: (notes + active).sorted { $0.start < $1.start },
            preparedThrough: through, nextSongEnd: songEnds.first)
    }
}

public actor NotePreviewWorker {
    private var sourceID: UUID?
    private var simulation: NotePreviewSimulation?
    private var commandCount = 0

    public init() {}

    public func preview(source: NotePreviewSource, commands: [NotePreviewCommand],
                        currentTime: Double, horizon: Double) throws -> NotePreviewSnapshot {
        let targetFrame = (currentTime + horizon) * source.configuration.sampleRate
        guard currentTime.isFinite, currentTime >= 0, horizon.isFinite, horizon > 0,
              targetFrame.isFinite, targetFrame >= 0, targetFrame < Double(UInt64.max) else {
            return .init(notes: [], preparedThrough: 0, nextSongEnd: nil)
        }
        // Ein bereits vorhergesagter Abschnitt wird bei einer manuellen
        // Steuerung mit deren tatsaechlichem Audioframe neu durchgespielt.
        if sourceID != source.id || commandCount != commands.count {
            sourceID = source.id
            commandCount = commands.count
            simulation = NotePreviewSimulation(configuration: source.configuration)
        }
        guard let simulation else { return .init(notes: [], preparedThrough: 0, nextSongEnd: nil) }
        try simulation.advance(to: UInt64(targetFrame), commands: commands,
            retainingFrom: max(0, currentTime - 1))
        return simulation.snapshot(since: max(0, currentTime - 1), currentTime: currentTime)
    }
}

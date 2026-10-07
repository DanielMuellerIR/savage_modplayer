import Foundation

// Plattformneutraler Renderkern.
//
// Enthält alles, was Live-Wiedergabe, Offline-Render (Quick Look, WAV-Export)
// und CLI gemeinsam nutzen: die Echtzeit-Zustands- und Puffertypen sowie die
// zustandslosen Render- und Sequencer-Helfer. Bewusst frei von AVFoundation und
// Combine, damit derselbe Code unter Linux baut.
//
// Vorher lagen diese Teile in ModPlayerCoordinator.swift und hingen damit an der
// @MainActor/ObservableObject-Klasse und an AVFoundation. Es bleibt EINE Engine:
// ModPlayerCoordinator ruft dieselben Helfer, Live- und Offlinepfad können nicht
// semantisch auseinanderlaufen.

// Haelt den verbleibenden Frame-Zaehler der laufenden Instrument-Vorschau.
// Wird vom Preview-Render-Block (Audio-Thread) heruntergezaehlt — daher dieselbe
// nonisolated(unsafe)-Konvention wie RealtimePlaybackState.
public final class PreviewVoice: Sendable {
    nonisolated(unsafe) public var framesLeft: Int
    public init(framesLeft: Int) { self.framesLeft = framesLeft }
}

public final class RealtimePlaybackState: Sendable {
    nonisolated(unsafe) var notePreviewExchange: NotePreviewExchange?
    struct EndTransitionSnapshot: Sendable {
        let frame: UInt64
        let position: Int
        let row: Int
    }

    struct SeekSnapshot: Sendable {
        let sequence: UInt64
        let position: Int
        let row: Int
        let ticksPerRow: Int
        let bpm: Int
        let globalVolume: Int
        let elapsedFrames: UInt64
    }

    struct TempoSnapshot: Sendable {
        let ticksPerRow: Int?
        let ticksPerRowSequence: UInt64?
        let bpm: Int?
        let bpmSequence: UInt64?
    }

    struct RenderOptionsSnapshot: Sendable {
        let stereoSeparation: Float
        let useInterpolation: Bool
        let palClock: Bool
    }

    struct TransportSnapshot: Sendable {
        let position: Int
        let row: Int
        let ticksPerRow: Int
        let bpm: Int
        let globalVolume: Int
    }

    // Der neutrale Vorstart steht direkt vor Zeile 0 der ersten Position. Ein
    // festes rowIndex=63 funktionierte nur zufaellig mit klassischen
    // 64-Zeilen-Patterns und spielte bei OpenMPT-Patterns ab 65 Zeilen erst den
    // Pattern-Schwanz und danach dasselbe Pattern noch einmal vollstaendig.
    nonisolated(unsafe) public var position: Int = 0
    nonisolated(unsafe) public var rowIndex: Int = -1
    nonisolated(unsafe) public var tick: Int = 5
    nonisolated(unsafe) public var ticksPerRow: Int = 6
    nonisolated(unsafe) public var bpm: Int = 125
    nonisolated(unsafe) public var outputsPerTick: Double = 0.0
    nonisolated(unsafe) public var outputsUntilNextTick: Double = 0.0
    // OpenMPT kann neben dem klassischen Tracker-Timing auch alternative und
    // moderne BPM-Semantik speichern. MOD/S3M/XM bleiben beim Classic-Default.
    nonisolated(unsafe) public var tempoMode: ITTempoMode = .classic
    nonisolated(unsafe) public var rowsPerBeat: Int = 4
    nonisolated(unsafe) public var restartPosition: Int = 0
    // IT T0x/T1x verändert das Tempo auf den Folgeticks einer Zeile.
    nonisolated(unsafe) public var tempoSlide: Int = 0
    // Wxy verändert die globale IT-Lautstärke auf Folgeticks.
    nonisolated(unsafe) public var globalVolumeSlide: Int = 0
    // S6x verlängert ausschließlich die aktuelle Zeile um x Ticks.
    nonisolated(unsafe) public var rowTickDelay: Int = 0
    
    nonisolated(unsafe) public var positionJump: Int = -1
    nonisolated(unsafe) public var patternBreak: Int = -1
    nonisolated(unsafe) public var patternLoopRow: Int = -1
    nonisolated(unsafe) public var patternDelay: Int = 0
    nonisolated(unsafe) public var patternDelayCounter: Int = 0
    nonisolated(unsafe) public var patternDelaySeen: Bool = false
    
    // New parameters for user controls
    nonisolated(unsafe) public var stereoSeparation: Float = 0.8
    nonisolated(unsafe) public var useInterpolation: Bool = true
    nonisolated(unsafe) public var palClock: Bool = true

    // Globale Lautstärke: 0...64 für MOD/S3M/XM, 0...128 für IT.
    nonisolated(unsafe) public var globalVolume: Float = 64

    // S3M/IT rechnen Perioden gegen die feste ST3-Clock, XM-Amiga-Perioden
    // gegen den FastTracker-II-Takt (siehe RenderEngine.clockRateOverride(for:)).
    // 0 = kein Override (PAL/NTSC-Schalter gilt).
    nonisolated(unsafe) public var clockRateOverride: Double = 0
    
    // Elapsed frames for timing calculation
    nonisolated(unsafe) public var elapsedFrames: UInt64 = 0
    // Der Audio-Thread veröffentlicht am Ende jedes Renderblocks einen
    // atomaren Stand für UI und Sperrbildschirm. `elapsedFrames` selbst bleibt
    // im Live-Betrieb alleiniger Besitz des Renderblocks; Offline-Helfer nutzen
    // ihren jeweils privaten Zustand weiterhin synchron.
    private let publishedElapsedFramesStorage = LockFreeAtomicUInt64(0)
    public var publishedElapsedFrames: UInt64 {
        publishedElapsedFramesStorage.loadAcquire()
    }
    // Auftrag an den Renderblock, `elapsedFrames` neu zu setzen; `.max` heisst
    // "kein Auftrag". Waehrend der Wiedergabe erhoeht ausschliesslich der
    // Renderblock den Zaehler (`+= 1` pro Frame). Schriebe der Hauptthread den
    // Zaehler direkt, koennte sein Wert zwischen dem Lesen und dem
    // Zurueckschreiben des Renderblocks verlorengehen — der Reset waere dann
    // wirkungslos. Deshalb legt der Hauptthread nur diesen Wunsch ab, und der
    // Renderblock uebernimmt ihn am Frame-Anfang genau einmal.
    private let pendingElapsedFramesStorage = LockFreeAtomicUInt64(.max)
    public var pendingElapsedFrames: UInt64 {
        get { pendingElapsedFramesStorage.loadAcquire() }
        set { pendingElapsedFramesStorage.storeRelease(newValue) }
    }
    nonisolated(unsafe) public var waveWriteIndex: Int = 0
    // Eigener, ueber Callback-Grenzen rollender Index fuer das Master-Oszilloskop.
    // (Frueher mit dem Callback-lokalen frame & 127 indiziert — bei Buffern < 128
    // Frames blieb das Ende des Scopes stehen und es ruckelte zwischen Callbacks.)
    nonisolated(unsafe) public var masterWaveWriteIndex: Int = 0

    // Seek-Auftrag als lockfreier Zwei-Feld-Snapshot. `seekSequenceStorage` ist
    // waehrend des Schreibens ungerade und danach gerade. Der Audio-Thread
    // akzeptiert die Nutzdaten nur, wenn zwei Acquire-Lesevorgaenge dieselbe
    // gerade Sequenz sehen. So koennen schnelle Slider-Bewegungen alte Auftraege
    // ueberschreiben, aber nie Position aus Auftrag A mit Uhrwert aus Auftrag B
    // mischen. Alle Speicher werden beim State-Aufbau alloziert, nie im Callback.
    private let seekSequenceStorage = LockFreeAtomicUInt64(0)
    private let seekTargetStorage = LockFreeAtomicUInt64(0)
    private let seekElapsedFramesStorage = LockFreeAtomicUInt64(0)
    private let appliedSeekSequenceStorage = LockFreeAtomicUInt64(0)
    // BPM und Ticks pro Zeile besitzen getrennte Ein-Feld-Auftraege. Der
    // MainActor darf nie den gerade noch nicht bestaetigten Wert des ANDEREN
    // Steppers aus seinem UI-Snapshot mitschicken: Ein einzelner BPM-Klick
    // koennte sonst einen neueren Speed-Klick ueberschreiben. Jede Sequenz ist
    // waehrend des Schreibens ungerade und danach gerade; der Audiothread
    // bestaetigt sie erst nach dem passenden Transport-Snapshot am Blockende.
    private let ticksPerRowRequestSequenceStorage = LockFreeAtomicUInt64(0)
    private let ticksPerRowRequestValueStorage = LockFreeAtomicUInt64(0)
    private let appliedTicksPerRowSequenceStorage = LockFreeAtomicUInt64(0)
    private let invalidatedTicksPerRowSequenceStorage = LockFreeAtomicUInt64(0)
    private let bpmRequestSequenceStorage = LockFreeAtomicUInt64(0)
    private let bpmRequestValueStorage = LockFreeAtomicUInt64(0)
    private let appliedBPMSequenceStorage = LockFreeAtomicUInt64(0)
    private let invalidatedBPMSequenceStorage = LockFreeAtomicUInt64(0)
    // Vollstaendiger Snapshot der drei live bedienbaren Renderoptionen. Bit 63
    // markiert einen vorhandenen Auftrag, damit auch 0.0/false/false darstellbar
    // bleibt; die unteren 32 Bits enthalten das unveraenderte Float-Bitmuster.
    private let pendingRenderOptionsStorage = LockFreeAtomicUInt64(0)
    // Position, Zeile und Tempo werden als EIN atomarer Snapshot an MainActor
    // und Sperrbildschirm veroeffentlicht. Damit liest der Poller nie vier
    // normale Swift-Felder waehrend der Audiothread sie gerade aendert.
    private let publishedTransportStorage: LockFreeAtomicUInt64
    // Wird im Renderblock gesetzt, wenn der Song hinter die letzte Position laeuft
    // (Wrap auf 0). Der MainActor-Poller liest das Flag und meldet das Songende,
    // damit die UI den loopMode (none/track/playlist) auswerten kann.
    private let endReachedStorage = LockFreeAtomicUInt64(0)
    public var endReached: Bool { endReachedStorage.loadAcquire() != 0 }
    // Exakter Frame der ersten Endtransition. Offline-Renderer koennen damit
    // den letzten 1024er Block auf die musikalische Songlaenge kuerzen.
    private let endReachedFrameStorage = LockFreeAtomicUInt64(.max)
    public var endReachedFrame: UInt64 { endReachedFrameStorage.loadAcquire() }
    // Position und Zeile, auf denen die Wiedergabe nach der ersten
    // Endtransition tatsaechlich weiterlaeuft; -1 = noch keine Endtransition.
    // Das ist NICHT immer `restartPosition`: Ein rueckwaerts gerichteter
    // Bxx-Sprung (Subsong-Loop) gilt ebenfalls als Songende, landet aber auf
    // seinem eigenen Ziel — und ein zusaetzliches Dxx setzt dort noch eine
    // Zielzeile. Die Anzeige-Uhr muss auf genau diesen Punkt zurueckgesetzt
    // werden, sonst zeigt sie ab der zweiten Runde eine falsche Spielzeit.
    private let endReachedPositionStorage = LockFreeAtomicUInt64(UInt64.max)
    private let endReachedRowStorage = LockFreeAtomicUInt64(0)
    public var endReachedPosition: Int {
        Int(Int64(bitPattern: endReachedPositionStorage.loadAcquire()))
    }
    public var endReachedRow: Int {
        Int(Int64(bitPattern: endReachedRowStorage.loadAcquire()))
    }

    public init() {
        publishedTransportStorage = LockFreeAtomicUInt64(Self.packTransport(
            position: 0, row: -1, ticksPerRow: 6, bpm: 125, globalVolume: 64))
    }

    @inline(__always)
    private static func packTransport(
        position: Int,
        row: Int,
        ticksPerRow: Int,
        bpm: Int,
        globalVolume: Int
    ) -> UInt64 {
        let packedRow = UInt64(UInt16(bitPattern: Int16(
            max(Int(Int16.min), min(Int(Int16.max), row)))))
        return UInt64(max(0, min(Int(UInt16.max), position)))
            | (packedRow << 16)
            | (UInt64(max(1, min(Int(UInt8.max), ticksPerRow))) << 32)
            | (UInt64(max(1, min(Int(UInt16.max), bpm))) << 40)
            | (UInt64(max(0, min(Int(UInt8.max), globalVolume))) << 56)
    }

    @inline(__always)
    private static func unpackTransport(_ packed: UInt64) -> TransportSnapshot {
        TransportSnapshot(
            position: Int(packed & 0xFFFF),
            row: Int(Int16(bitPattern: UInt16((packed >> 16) & 0xFFFF))),
            ticksPerRow: Int((packed >> 32) & 0xFF),
            bpm: Int((packed >> 40) & 0xFFFF),
            globalVolume: Int((packed >> 56) & 0xFF))
    }

    var transportSnapshot: TransportSnapshot {
        Self.unpackTransport(publishedTransportStorage.loadAcquire())
    }

    // Der Audio-Callback konsumiert jeden Uhr-Auftrag mit EINEM atomaren
    // exchange. Ein gleichzeitig eintreffender Auftrag kann dadurch weder
    // zwischen getrenntem Lesen/Loeschen verloren gehen noch zweimal wirken.
    @inline(__always)
    func takePendingElapsedFrames() -> UInt64 {
        pendingElapsedFramesStorage.exchangeAcquiringAndReleasing(.max)
    }

    @discardableResult
    func requestSeek(
        position: Int,
        row: Int,
        ticksPerRow: Int,
        bpm: Int,
        globalVolume: Int,
        elapsedFrames: UInt64
    ) -> UInt64 {
        // Ein Seek enthaelt selbst einen vollstaendigen Tempo-Snapshot. Ein
        // aelterer Stepper-Auftrag darf ihn nicht im selben Audioblock wieder
        // ueberschreiben. Ein nach dem Seek abgelegter Auftrag bleibt dagegen
        // erhalten und gewinnt durch die Verarbeitungsreihenfolge im Block.
        invalidateTempoRequests()
        let packed = Self.packTransport(
            position: position,
            row: row,
            ticksPerRow: ticksPerRow,
            bpm: bpm,
            globalVolume: globalVolume)

        let current = seekSequenceStorage.loadRelaxed()
        let writingSequence = (current &+ 1) | 1
        // Das Acquire des RMW haelt die folgenden Nutzdaten-Schreibvorgaenge
        // hinter der ungeraden Sequenz. Ein zusaetzlicher seq_cst-Fence waere
        // fuer den Ein-Schreiber-Seqlock redundant; ein reiner Release-Store
        // boete diese Ordnung fuer nachfolgende Schreibvorgaenge dagegen nicht.
        _ = seekSequenceStorage.exchangeAcquiringAndReleasing(writingSequence)
        seekTargetStorage.storeRelaxed(packed)
        seekElapsedFramesStorage.storeRelaxed(elapsedFrames)
        let publishedSequence = writingSequence &+ 1
        seekSequenceStorage.storeRelease(publishedSequence)
        return publishedSequence
    }

    @discardableResult
    func requestTicksPerRow(_ ticksPerRow: Int) -> UInt64 {
        publishTempoField(
            UInt64(max(1, min(Int(UInt8.max), ticksPerRow))),
            sequenceStorage: ticksPerRowRequestSequenceStorage,
            valueStorage: ticksPerRowRequestValueStorage)
    }

    @discardableResult
    func requestBPM(_ bpm: Int) -> UInt64 {
        publishTempoField(
            UInt64(max(1, min(Int(UInt16.max), bpm))),
            sequenceStorage: bpmRequestSequenceStorage,
            valueStorage: bpmRequestValueStorage)
    }

    // Behaelt den bisherigen Core-Helfer fuer Aufrufer bei, die bewusst beide
    // Felder als einen Bedienvorgang setzen. Intern bleiben es zwei unabhaengige
    // Auftraege, damit spaetere Ein-Feld-Aenderungen nichts Altes mitschleppen.
    func requestTempo(ticksPerRow: Int, bpm: Int) {
        _ = requestTicksPerRow(ticksPerRow)
        _ = requestBPM(bpm)
    }

    @inline(__always)
    func takePendingTempo() -> TempoSnapshot? {
        let ticksPerRow = pendingTempoField(
            sequenceStorage: ticksPerRowRequestSequenceStorage,
            valueStorage: ticksPerRowRequestValueStorage,
            appliedSequenceStorage: appliedTicksPerRowSequenceStorage,
            invalidatedSequenceStorage: invalidatedTicksPerRowSequenceStorage)
        let bpm = pendingTempoField(
            sequenceStorage: bpmRequestSequenceStorage,
            valueStorage: bpmRequestValueStorage,
            appliedSequenceStorage: appliedBPMSequenceStorage,
            invalidatedSequenceStorage: invalidatedBPMSequenceStorage)
        guard ticksPerRow != nil || bpm != nil else { return nil }
        return TempoSnapshot(
            ticksPerRow: ticksPerRow.map { Int($0.value) },
            ticksPerRowSequence: ticksPerRow?.sequence,
            bpm: bpm.map { Int($0.value) },
            bpmSequence: bpm?.sequence)
    }

    func isTicksPerRowRequestApplied(_ sequence: UInt64) -> Bool {
        appliedTicksPerRowSequenceStorage.loadAcquire() == sequence
            || invalidatedTicksPerRowSequenceStorage.loadAcquire() >= sequence
    }

    func isBPMRequestApplied(_ sequence: UInt64) -> Bool {
        appliedBPMSequenceStorage.loadAcquire() == sequence
            || invalidatedBPMSequenceStorage.loadAcquire() >= sequence
    }

    @inline(__always)
    func markTempoApplied(_ tempo: TempoSnapshot) {
        if let sequence = tempo.ticksPerRowSequence {
            appliedTicksPerRowSequenceStorage.storeRelease(sequence)
        }
        if let sequence = tempo.bpmSequence {
            appliedBPMSequenceStorage.storeRelease(sequence)
        }
    }

    private func invalidateTempoRequests() {
        invalidatedTicksPerRowSequenceStorage.storeRelease(
            ticksPerRowRequestSequenceStorage.loadAcquire())
        invalidatedBPMSequenceStorage.storeRelease(
            bpmRequestSequenceStorage.loadAcquire())
    }

    @inline(__always)
    private func publishTempoField(
        _ value: UInt64,
        sequenceStorage: LockFreeAtomicUInt64,
        valueStorage: LockFreeAtomicUInt64
    ) -> UInt64 {
        let current = sequenceStorage.loadRelaxed()
        let writingSequence = (current &+ 1) | 1
        _ = sequenceStorage.exchangeAcquiringAndReleasing(writingSequence)
        valueStorage.storeRelaxed(value)
        let publishedSequence = writingSequence &+ 1
        sequenceStorage.storeRelease(publishedSequence)
        return publishedSequence
    }

    @inline(__always)
    private func pendingTempoField(
        sequenceStorage: LockFreeAtomicUInt64,
        valueStorage: LockFreeAtomicUInt64,
        appliedSequenceStorage: LockFreeAtomicUInt64,
        invalidatedSequenceStorage: LockFreeAtomicUInt64
    ) -> (sequence: UInt64, value: UInt64)? {
        let firstSequence = sequenceStorage.loadAcquire()
        guard firstSequence != 0,
              firstSequence & 1 == 0,
              firstSequence != appliedSequenceStorage.loadAcquire(),
              firstSequence > invalidatedSequenceStorage.loadAcquire() else { return nil }
        let value = valueStorage.loadRelaxed()
        LockFreeAtomicUInt64.sequentiallyConsistentFence()
        guard sequenceStorage.loadAcquire() == firstSequence else { return nil }
        return (firstSequence, value)
    }

    func requestRenderOptions(
        stereoSeparation: Float,
        useInterpolation: Bool,
        palClock: Bool
    ) {
        let packed = UInt64(stereoSeparation.bitPattern)
            | (useInterpolation ? UInt64(1) << 32 : 0)
            | (palClock ? UInt64(1) << 33 : 0)
            | (UInt64(1) << 63)
        pendingRenderOptionsStorage.storeRelease(packed)
    }

    @inline(__always)
    func takePendingRenderOptions() -> RenderOptionsSnapshot? {
        let packed = pendingRenderOptionsStorage.exchangeAcquiringAndReleasing(0)
        guard packed & (UInt64(1) << 63) != 0 else { return nil }
        return RenderOptionsSnapshot(
            stereoSeparation: Float(
                bitPattern: UInt32(truncatingIfNeeded: packed)),
            useInterpolation: packed & (UInt64(1) << 32) != 0,
            palClock: packed & (UInt64(1) << 33) != 0)
    }

    @inline(__always)
    func takePendingSeek() -> SeekSnapshot? {
        let firstSequence = seekSequenceStorage.loadAcquire()
        guard firstSequence != 0,
              firstSequence & 1 == 0,
              firstSequence != appliedSeekSequenceStorage.loadRelaxed() else { return nil }

        let packed = seekTargetStorage.loadRelaxed()
        let elapsed = seekElapsedFramesStorage.loadRelaxed()
        LockFreeAtomicUInt64.sequentiallyConsistentFence()
        let secondSequence = seekSequenceStorage.loadAcquire()
        guard firstSequence == secondSequence else { return nil }

        let transport = Self.unpackTransport(packed)

        return SeekSnapshot(
            sequence: firstSequence,
            position: transport.position,
            row: transport.row,
            ticksPerRow: transport.ticksPerRow,
            bpm: transport.bpm,
            globalVolume: transport.globalVolume,
            elapsedFrames: elapsed)
    }

    @inline(__always)
    func publishTransportSnapshot() {
        publishedTransportStorage.storeRelease(Self.packTransport(
            position: position,
            row: rowIndex,
            ticksPerRow: ticksPerRow,
            bpm: bpm,
            globalVolume: Int(globalVolume)))
    }

    @inline(__always)
    func markSeekApplied(_ sequence: UInt64) {
        appliedSeekSequenceStorage.storeRelease(sequence)
    }

    func isSeekApplied(_ sequence: UInt64) -> Bool {
        appliedSeekSequenceStorage.loadAcquire() == sequence
    }

    @inline(__always)
    func publishElapsedFrames() {
        publishedElapsedFramesStorage.storeRelease(elapsedFrames)
    }

    // Vollstaendigen Ziel-Snapshot schreiben, danach erst das Signal mit
    // Release-Semantik veroeffentlichen. Der MainActor liest das Signal mit
    // Acquire und sieht dadurch garantiert Frame, Position UND Zeile aus
    // derselben Transition.
    @inline(__always)
    func publishEndTransition(frame: UInt64, position: Int, row: Int) {
        // Solange der Empfaenger das vorige Signal noch nicht konsumiert hat,
        // bleibt dessen zusammengehoeriger Snapshot unangetastet. Mehrere
        // Pulse duerfen zusammenfallen; der Loop-Zielzustand darf es nicht.
        guard endReachedStorage.loadAcquire() == 0 else { return }
        endReachedFrameStorage.storeRelaxed(frame)
        endReachedPositionStorage.storeRelaxed(UInt64(bitPattern: Int64(position)))
        endReachedRowStorage.storeRelaxed(UInt64(bitPattern: Int64(row)))
        endReachedStorage.storeRelease(1)
    }

    @inline(__always)
    func consumeEndTransition() -> EndTransitionSnapshot? {
        // Es gibt genau einen Empfaenger (den MainActor-Poller). Solange das
        // Signal 1 bleibt, schreibt der Audio-Thread keinen neuen Snapshot.
        // Deshalb zuerst alle drei Werte lokal kopieren und erst danach den
        // Slot per exchange freigeben. Der UI-Hook kann die lokale Kopie auch
        // dann noch sicher verwenden, wenn bereits die naechste Transition
        // veroeffentlicht wurde.
        guard endReachedStorage.loadAcquire() != 0 else { return nil }
        let snapshot = EndTransitionSnapshot(
            frame: endReachedFrameStorage.loadRelaxed(),
            position: Int(Int64(bitPattern: endReachedPositionStorage.loadRelaxed())),
            row: Int(Int64(bitPattern: endReachedRowStorage.loadRelaxed())))
        // Solange das Signal noch 1 ist, darf der Producer die Snapshot-Felder
        // nicht anfassen. Deshalb neutralisieren wir sie VOR der Freigabe des
        // Slots; danach koennte bereits die naechste Transition schreiben.
        endReachedFrameStorage.storeRelaxed(.max)
        endReachedPositionStorage.storeRelaxed(.max)
        endReachedRowStorage.storeRelaxed(0)
        guard endReachedStorage.exchangeAcquiringAndReleasing(0) != 0 else {
            return nil
        }
        return snapshot
    }

    // Nur vor einem neuen Renderlauf/Seek verwenden. Die Snapshot-Felder
    // werden zuerst neutralisiert, das falsche Signal danach veroeffentlicht.
    func resetEndTransition() {
        endReachedFrameStorage.storeRelaxed(.max)
        endReachedPositionStorage.storeRelaxed(.max)
        endReachedRowStorage.storeRelaxed(0)
        endReachedStorage.storeRelease(0)
    }
}

public final class RealtimeVUBuffer: @unchecked Sendable {
    public let pointer: UnsafeMutablePointer<Float>
    let visualizationExchange: RealtimeVisualizationExchange?

    public init(pointer: UnsafeMutablePointer<Float>) {
        self.pointer = pointer
        self.visualizationExchange = nil
    }

    fileprivate init(
        pointer: UnsafeMutablePointer<Float>,
        visualizationExchange: RealtimeVisualizationExchange
    ) {
        self.pointer = pointer
        self.visualizationExchange = visualizationExchange
    }
}

public final class RealtimeWaveBuffer: @unchecked Sendable {
    public let channelWavesPointer: UnsafeMutablePointer<Float>
    public let masterWavesPointer: UnsafeMutablePointer<Float>

    public init(channelWaves: UnsafeMutablePointer<Float>, masterWaves: UnsafeMutablePointer<Float>) {
        self.channelWavesPointer = channelWaves
        self.masterWavesPointer = masterWaves
    }
}

// Dreifach gepufferte Uebergabe der VU- und Oszilloskopdaten vom Audio- an den
// MainActor. Der Renderblock behaelt eigene Arbeitspuffer und kopiert den
// fertigen Stand am Blockende in einen Slot, den weder die UI liest noch der
// vorige Snapshot belegt. Die UI beansprucht ihren Slot atomar, bevor sie ihn
// kopiert. Dadurch greifen beide Threads nie gleichzeitig auf dieselben
// Float-Zellen zu; im Echtzeitpfad entstehen weder Locks noch Allokationen.
final class RealtimeVisualizationExchange: @unchecked Sendable {
    private static let slotCount = 3
    private static let slotMask: UInt64 = 0x3

    private let channelCapacity: Int
    private let renderPeaksPointer: UnsafeMutablePointer<Float>
    private let renderChannelWavesPointer: UnsafeMutablePointer<Float>
    private let renderMasterWavesPointer: UnsafeMutablePointer<Float>
    private let snapshotPeaksPointer: UnsafeMutablePointer<Float>
    private let snapshotChannelWavesPointer: UnsafeMutablePointer<Float>
    private let snapshotMasterWavesPointer: UnsafeMutablePointer<Float>

    // Untere zwei Bits: veroeffentlichter Slot; obere Bits: Generation.
    private let publishedStorage = LockFreeAtomicUInt64(0)
    // 0 = kein Leser, sonst Slot + 1. Nur der MainActor beansprucht einen Slot.
    private let readerSlotStorage = LockFreeAtomicUInt64(0)
    private let consumedGenerationStorage = LockFreeAtomicUInt64(0)

    init(channelCapacity: Int) {
        precondition(channelCapacity > 0)
        self.channelCapacity = channelCapacity

        renderPeaksPointer = .allocate(capacity: channelCapacity)
        renderPeaksPointer.initialize(repeating: 0, count: channelCapacity)
        renderChannelWavesPointer = .allocate(capacity: channelCapacity * 32)
        renderChannelWavesPointer.initialize(repeating: 0, count: channelCapacity * 32)
        renderMasterWavesPointer = .allocate(capacity: 128)
        renderMasterWavesPointer.initialize(repeating: 0, count: 128)

        snapshotPeaksPointer = .allocate(capacity: Self.slotCount * channelCapacity)
        snapshotPeaksPointer.initialize(
            repeating: 0,
            count: Self.slotCount * channelCapacity)
        snapshotChannelWavesPointer = .allocate(
            capacity: Self.slotCount * channelCapacity * 32)
        snapshotChannelWavesPointer.initialize(
            repeating: 0,
            count: Self.slotCount * channelCapacity * 32)
        snapshotMasterWavesPointer = .allocate(capacity: Self.slotCount * 128)
        snapshotMasterWavesPointer.initialize(
            repeating: 0,
            count: Self.slotCount * 128)
    }

    deinit {
        renderPeaksPointer.deinitialize(count: channelCapacity)
        renderPeaksPointer.deallocate()
        renderChannelWavesPointer.deinitialize(count: channelCapacity * 32)
        renderChannelWavesPointer.deallocate()
        renderMasterWavesPointer.deinitialize(count: 128)
        renderMasterWavesPointer.deallocate()
        snapshotPeaksPointer.deinitialize(count: Self.slotCount * channelCapacity)
        snapshotPeaksPointer.deallocate()
        snapshotChannelWavesPointer.deinitialize(
            count: Self.slotCount * channelCapacity * 32)
        snapshotChannelWavesPointer.deallocate()
        snapshotMasterWavesPointer.deinitialize(count: Self.slotCount * 128)
        snapshotMasterWavesPointer.deallocate()
    }

    func makeVUBuffer() -> RealtimeVUBuffer {
        RealtimeVUBuffer(
            pointer: renderPeaksPointer,
            visualizationExchange: self)
    }

    func makeWaveBuffer() -> RealtimeWaveBuffer {
        RealtimeWaveBuffer(
            channelWaves: renderChannelWavesPointer,
            masterWaves: renderMasterWavesPointer)
    }

    @inline(__always)
    func beginRenderBlock(channelCount: Int) {
        let count = max(0, min(channelCapacity, channelCount))
        for channel in 0..<count {
            renderPeaksPointer[channel] = 0
        }
    }

    @inline(__always)
    func publish(channelCount: Int) {
        let count = max(0, min(channelCapacity, channelCount))
        let published = publishedStorage.loadAcquire()
        let publishedSlot = Int(published & Self.slotMask)
        let publishedGeneration = published >> 2
        // Zusammen mit dem Fence des Lesers verhindert dies den
        // Store-Buffering-Fall: Entweder sieht der Audiothread den
        // beanspruchten Slot, oder der Leser sieht bei seiner Kontrollabfrage
        // die neuere Generation. Nur Acquire/Release auf zwei verschiedenen
        // Atomikspeichern garantiert diese Alternative nicht.
        LockFreeAtomicUInt64.sequentiallyConsistentFence()
        let readerSlot = Int(readerSlotStorage.loadAcquire()) - 1

        // Von drei Slots sind hoechstens der veroeffentlichte und ein noch von
        // der UI gelesener belegt. Der dritte bleibt dem Audiothread garantiert.
        var targetSlot = (publishedSlot + 1) % Self.slotCount
        if targetSlot == readerSlot {
            targetSlot = (targetSlot + 1) % Self.slotCount
        }

        let targetPeaks = snapshotPeaksPointer.advanced(
            by: targetSlot * channelCapacity)
        let publishedPeaks = snapshotPeaksPointer.advanced(
            by: publishedSlot * channelCapacity)
        let publishedWasConsumed = consumedGenerationStorage.loadAcquire()
            >= publishedGeneration
        for channel in 0..<count {
            let blockPeak = renderPeaksPointer[channel]
            // Wenn die UI einen Block uebersprungen hat, dessen Maximum bis
            // zum naechsten konsumierten Snapshot weitertragen.
            targetPeaks[channel] = publishedWasConsumed
                ? blockPeak
                : max(blockPeak, publishedPeaks[channel])
        }

        let waveCount = count * 32
        let targetWaves = snapshotChannelWavesPointer.advanced(
            by: targetSlot * channelCapacity * 32)
        targetWaves.update(from: renderChannelWavesPointer, count: waveCount)
        let targetMaster = snapshotMasterWavesPointer.advanced(
            by: targetSlot * 128)
        targetMaster.update(from: renderMasterWavesPointer, count: 128)

        let nextGeneration = publishedGeneration &+ 1
        publishedStorage.storeRelease(
            (nextGeneration << 2) | UInt64(targetSlot))
    }

    @discardableResult
    func withLatestSnapshot(
        channelCount: Int,
        _ body: (
            UnsafePointer<Float>,
            UnsafePointer<Float>,
            UnsafePointer<Float>
        ) -> Void
    ) -> Bool {
        precondition(channelCount >= 0 && channelCount <= channelCapacity)
        while true {
            let published = publishedStorage.loadAcquire()
            let slot = Int(published & Self.slotMask)
            readerSlotStorage.storeRelease(UInt64(slot + 1))
            // Gegenstueck zum Fence in `publish`: Der Anspruch auf den Slot
            // muss global vor der folgenden Kontrollabfrage sichtbar sein.
            // Sonst koennen beide Threads jeweils noch den alten Wert des
            // anderen Atomikspeichers sehen und denselben Slot benutzen.
            LockFreeAtomicUInt64.sequentiallyConsistentFence()

            // Hat der Audiothread zwischen Auswahl und Beanspruchen einen
            // neueren Slot veroeffentlicht, noch keine Float-Zelle lesen.
            guard publishedStorage.loadAcquire() == published else {
                _ = readerSlotStorage.exchangeAcquiringAndReleasing(0)
                continue
            }

            let generation = published >> 2
            let isFresh = generation > consumedGenerationStorage.loadAcquire()
            body(
                UnsafePointer(snapshotPeaksPointer.advanced(
                    by: slot * channelCapacity)),
                UnsafePointer(snapshotChannelWavesPointer.advanced(
                    by: slot * channelCapacity * 32)),
                UnsafePointer(snapshotMasterWavesPointer.advanced(
                    by: slot * 128)))
            consumedGenerationStorage.storeRelease(generation)
            _ = readerSlotStorage.exchangeAcquiringAndReleasing(0)
            return isFresh
        }
    }
}

// Vorallozierte Capture-Pointer fuer genau EINEN Renderblock. Die Pointer
// werden vor dem Audio-Callback vom Offline-Renderer bereitgestellt und nach
// dessen Rueckkehr synchron in RenderCaptureBlock kopiert.
struct RenderCapture: @unchecked Sendable {
    let stereoLeftPointer: UnsafeMutablePointer<Float>
    let stereoRightPointer: UnsafeMutablePointer<Float>
    let stemsPointer: UnsafeMutablePointer<Float>
    let frameCapacity: Int
    let channelCount: Int
}

// Wertkopie eines fertigen Blocks fuer den Offline-Consumer. Diese Arrays
// entstehen erst nach dem Callback und sind deshalb kein Echtzeit-Arbeitsschritt.
struct RenderCaptureBlock: Sendable {
    let frameCount: Int
    let channelCount: Int
    let stereoLeft: [Float]
    let stereoRight: [Float]
    // Kanal-major: stems[channel * frameCount + frame].
    let stems: [Float]
}

// Stack-Wert eines einzelnen Voice-Frames. Mono-Voices tragen links/rechts
// denselben Wert; Stereo-IT-Samples behalten beide PCM-Seiten bis zum Mixer.
private struct RenderedVoiceFrame {
    let left: Float
    let right: Float
    let mono: Float
    let isStereo: Bool
}

// Wertkopie des Sequencer-Zustands an einer festen Frame-Grenze. Sie enthaelt
// bewusst keine Referenz auf den laufenden Zustand und kein endReached: Die
// Probe setzt dieses Live-/Offline-Abbruchsignal heute nicht.
struct SequencerTraceSnapshot: Sendable, Equatable {
    let frame: Int
    let position: Int
    let pattern: Int
    let row: Int
    let tick: Int
    let speed: Int
    let tempo: Int
    let globalVolume: Float
    let positionJump: Int
    let patternBreak: Int
    let patternLoopRow: Int
    let patternDelay: Int
    let patternDelayCounter: Int
    let tempoSlide: Int
    let globalVolumeSlide: Int
    let rowTickDelay: Int
    let patternDelaySeen: Bool

    init(frame: Int, state: RealtimePlaybackState, mod: Mod) {
        self.frame = frame
        self.position = state.position
        if mod.patternTable.isEmpty {
            self.pattern = -1
        } else {
            let positionIndex = max(0, min(mod.patternTable.count - 1, state.position))
            self.pattern = mod.patternTable[positionIndex]
        }
        self.row = state.rowIndex
        self.tick = state.tick
        self.speed = state.ticksPerRow
        self.tempo = state.bpm
        self.globalVolume = state.globalVolume
        self.positionJump = state.positionJump
        self.patternBreak = state.patternBreak
        self.patternLoopRow = state.patternLoopRow
        self.patternDelay = state.patternDelay
        self.patternDelayCounter = state.patternDelayCounter
        self.tempoSlide = state.tempoSlide
        self.globalVolumeSlide = state.globalVolumeSlide
        self.rowTickDelay = state.rowTickDelay
        self.patternDelaySeen = state.patternDelaySeen
    }
}

struct RenderProbeSample: Sendable {
    let frame: Int
    let position: Int
    let row: Int
    let channelOutputs: [Float]
    let trace: SequencerTraceSnapshot

    init(frame: Int, position: Int, row: Int, channelOutputs: [Float], trace: SequencerTraceSnapshot) {
        self.frame = frame
        self.position = position
        self.row = row
        self.channelOutputs = channelOutputs
        self.trace = trace
    }
}

public enum RenderEngine {
    // Obergrenze der unterstützten Kanäle — bestimmt die Größe der
    // vorallozierten VU-/Waveform-Puffer (S3M erlaubt bis zu 32 Kanäle).
    // IT-Patterns besitzen bis zu 64 logische Kanäle. Die zugehörigen
    // VU-/Scope-Puffer werden wie zuvor einmalig vor dem Audiostart reserviert.
    nonisolated public static let maxChannels = 64

    nonisolated public static let itVoiceCapacity = ITPlaybackVoicePool.voiceCapacity

    // OpenMPT-Timingparameter aus dem Modulkopf. Live-Start, Seek,
    // Loop-Uhr und Offline-Zustand muessen dieselben Defaults verwenden.
    nonisolated static func timingParameters(for mod: Mod)
        -> (tempoMode: ITTempoMode, rowsPerBeat: Int) {
        let tempoMode = mod.itProperties?.openMPTExtensions?.tempoMode ?? .classic
        let headerRowsPerBeat = mod.itProperties.map { $0.patternHighlight & 0xFF } ?? 4
        let rowsPerBeat = max(
            1,
            mod.itProperties?.openMPTExtensions?.rowsPerBeat
                ?? (headerRowsPerBeat > 0 ? headerRowsPerBeat : 4))
        return (tempoMode, rowsPerBeat)
    }

    // Fester Format-Takt für die Periodenformel `hz = clock / periode`:
    // - S3M/IT: ST3-Clock 14.317056 MHz.
    // - XM mit Amiga-Perioden: FastTracker-II-Takt 8363 × 1712 (C-4 hat in der
    //   FT2-Amiga-Tabelle die Periode 1712 und muss laut XM-Spezifikation mit
    //   8363 Hz spielen; gegen die Paula-Clock gerechnet läge C-4 rund zwei
    //   Oktaven zu tief). XM-linear ignoriert den Takt ohnehin (Exponentialformel).
    // - MOD-Varianten: 0 = kein Override, der PAL/NTSC-Schalter gilt.
    nonisolated static func clockRateOverride(for mod: Mod) -> Double {
        switch mod.format {
        case .s3m, .it: return 14_317_056.0
        case .xm: return 8363.0 * 1712.0
        default: return 0
        }
    }

    // Format-abhängige Kanal-Konfiguration: Panning aus dem Modul, bei S3M
    // zusätzlich das ScreamTracker-Periodenmodell (feinere Perioden, weitere
    // Klemmgrenzen, Effekt-Memory). Muss nach jedem DSPChannel.reset() erneut
    // angewandt werden (reset() stellt die MOD-Defaults wieder her).
    nonisolated static func configure(channels: [DSPChannel], for mod: Mod) {
        if mod.format == .it {
            ITPlaybackVoicePool(mod: mod).configure(voices: channels)
            return
        }
        for (i, ch) in channels.enumerated() {
            if i < mod.channelPannings.count {
                ch.panning = mod.channelPannings[i]
            }
            if mod.format == .s3m {
                ch.s3mMode = true
                ch.periodScale = 4
                ch.periodMin = 64
                ch.periodMax = 32767
            } else if mod.format == .xm {
                // XM-Formatverhalten gilt in beiden Frequenzmodi. Das Header-Flag
                // wählt strikt zwischen FT2s linearer und Amiga-Periodentabelle.
                ch.xmMode = true
                ch.xmLinearMode = mod.linearFrequency
                ch.periodMin = 1
                ch.periodMax = mod.linearFrequency ? 7680 : 32768
            }
        }
        // Statische Periodentabellen JETZT anfassen, nicht erst im Renderblock:
        // ein Swift `static let`-Array initialisiert lazy beim ersten Zugriff
        // (swift_once + Heap-Allokation). Der erste Zugriff passiert sonst beim
        // ersten Notenereignis im Echtzeit-Audiothread und verletzt die
        // Renderblock-Invariante (keine Allokationen/Locks).
        if mod.format == .s3m {
            _ = DSPChannel.s3mPeriod(key: 48, c2spd: 8363)
        } else if mod.format == .xm, !mod.linearFrequency {
            _ = DSPChannel.xmAmigaPeriod(realNote: 48, finetune: 0)
        }
    }

    // Ermittelt Speed/Tempo/Global-Volume an einem Sprungziel (position,row): wendet
    // alle Set-Speed/Tempo/Global-Volume-Befehle vom Songanfang bis dorthin der
    // Reihe nach an. Damit klingt ein Sprung mitten in den Song im RICHTIGEN Tempo
    // (z.B. Starfish: Speed 8 wird in Pattern-Pos 0, Zeile 0 gesetzt). Folgt bewusst
    // KEINEN Pattern-Spruengen (Bxx/Dxx) und rekonstruiert KEINE Per-Kanal-Slides —
    // fuer den linearen Normalfall und Test-Spruenge gedacht.
    nonisolated static func reconstructGlobalParams(_ mod: Mod, toPosition: Int, row: Int)
        -> (speed: Int, bpm: Int, globalVolume: Int) {
        var speed = mod.initialSpeed
        var bpm = mod.initialTempo
        var gvol = mod.initialGlobalVolume
        func scan(_ r: Row) {
            for n in r.notes where n.hasEffect {
                if n.effectId > ModuleEffect.impulseTrackerCommandBase,
                   n.effectId <= ModuleEffect.impulseTrackerCommandBase + 26 {
                    switch n.effectId - ModuleEffect.impulseTrackerCommandBase {
                    case 1:
                        if n.effectData > 0 { speed = n.effectData }
                    case 20:
                        if n.effectData >= 0x20 { bpm = n.effectData }
                    case 22:
                        if n.effectData <= 128 { gvol = n.effectData }
                    default:
                        break
                    }
                } else if n.effectId == 0x0F {
                    if n.effectData >= 1 && n.effectData <= 31 { speed = n.effectData }
                    else if n.effectData >= 32 { bpm = n.effectData }
                } else if n.effectId == ModuleEffect.setSpeed {
                    if n.effectData > 0 { speed = n.effectData }
                } else if n.effectId == ModuleEffect.setTempo {
                    if n.effectData >= 32 { bpm = n.effectData }
                } else if n.effectId == ModuleEffect.globalVolume {
                    gvol = min(64, max(0, n.effectData))
                }
            }
        }
        // Wie in SequencerCore.patternRowCount: ohne Playlist gibt es keine
        // Position, die sich rekonstruieren liesse — und patternTable[0] waere
        // ein Zugriff ausserhalb der Grenzen.
        guard !mod.patternTable.isEmpty else { return (speed, bpm, gvol) }
        let lastPos = max(0, min(mod.length - 1, toPosition))
        for p in 0...lastPos {
            let posIndex = max(0, min(mod.patternTable.count - 1, p))
            let patternIndex = mod.patternTable[posIndex]
            guard patternIndex >= 0 && patternIndex < mod.patterns.count else { continue }
            let rows = mod.patterns[patternIndex].rows
            let maxRow = (p == lastPos) ? min(row, rows.count - 1) : rows.count - 1
            guard maxRow >= 0 else { continue }
            for r in 0...maxRow { scan(rows[r]) }
        }
        return (speed, bpm, gvol)
    }

    // internal statt private: ModuleRenderer (WAV-Offline-Render für Export
    // und Quick-Look) nutzt denselben Render-Block wie die Live-Wiedergabe.
    nonisolated static func createRenderBlock(
        state: RealtimePlaybackState,
        vuBuffer: RealtimeVUBuffer,
        waveBuffer: RealtimeWaveBuffer,
        dspChannels: [DSPChannel],
        mod: Mod,
        sampleRate: Double,
        capture: RenderCapture? = nil
    ) -> ModuleRenderBlock {
        // Kanalzahl und Mix-Gain einmalig ableiten: Mehr als 4 Kanäle laufen
        // sonst deutlich heißer in den tanh-Limiter als das klassische
        // 4-Kanal-Bild. Equal-Power-Skalierung sqrt(4/N) statt linearem 4/N:
        // unkorrelierte Kanäle addieren sich in Leistung, nicht in Amplitude —
        // lineares 4/N machte 16-Kanal-S3Ms ~12 dB zu leise (praktisch stumm).
        // Rest-Spitzen fängt der tanh-Limiter weich ab.
        let voiceCount = dspChannels.count
        let logicalChannelCount = mod.format == .it
            ? max(1, min(Self.maxChannels, mod.channelCount))
            : voiceCount
        let itVoicePool = mod.format == .it ? dspChannels.first?.itVoicePool : nil
        let mixGain: Float
        if mod.format == .it {
            // ITs reservieren stets 64 logische Kanäle; deren Zahl darf den Mix
            // nicht pauschal absenken. Stattdessen ist das Headerfeld Mixing
            // Volume (0...128, 64 = neutral) der vorgesehene Masterfaktor.
            let samplePreamp = mod.itProperties?.openMPTExtensions?.samplePreamp
                ?? mod.itProperties?.mixVolume
                ?? 64
            mixGain = Float(samplePreamp) / 64.0
        } else {
            mixGain = voiceCount > 4 ? (4.0 / Float(voiceCount)).squareRoot() : 1.0
        }
        let globalVolumeScale = Float(mod.globalVolumeScale.rawValue)
        let visualizationExchange = vuBuffer.visualizationExchange

        return { (frameCount, left, right) in
            let safeFrameCount = Int(frameCount)
            var appliedSeekSequence: UInt64?

            if safeFrameCount > 0 {
                visualizationExchange?.beginRenderBlock(
                    channelCount: logicalChannelCount)
            }

            // UI-Auftraege hoechstens einmal pro Audioblock pruefen. Eine
            // Blockgrenze ist fuer Seek/Uhr genau genug und spart im Normalfall
            // zwei C11-Atomikaufrufe pro Audioframe.
            if safeFrameCount > 0, let request = state.takePendingSeek() {
                state.notePreviewExchange?.append(.init(
                    kind: .seek, position: request.position, row: request.row,
                    speed: request.ticksPerRow, bpm: request.bpm,
                    globalVolume: request.globalVolume))
                Self.applySeek(
                    request,
                    state: state,
                    channels: dspChannels,
                    sampleRate: sampleRate)
                appliedSeekSequence = request.sequence
            }
            var appliedTempo: RealtimePlaybackState.TempoSnapshot?
            if safeFrameCount > 0, let tempo = state.takePendingTempo() {
                state.notePreviewExchange?.append(.init(
                    kind: .tempo, speed: tempo.ticksPerRow, bpm: tempo.bpm))
                if let ticksPerRow = tempo.ticksPerRow {
                    state.ticksPerRow = ticksPerRow
                }
                if let bpm = tempo.bpm {
                    state.bpm = bpm
                }
                SequencerCore.recalculateTickDuration(
                    state: state,
                    sampleRate: sampleRate)
                appliedTempo = tempo
            }
            if safeFrameCount > 0,
               let options = state.takePendingRenderOptions() {
                state.notePreviewExchange?.append(.init(kind: .options, palClock: options.palClock))
                state.stereoSeparation = options.stereoSeparation
                state.useInterpolation = options.useInterpolation
                state.palClock = options.palClock
            }
            if safeFrameCount > 0 {
                let requestedElapsedFrames = state.takePendingElapsedFrames()
                if requestedElapsedFrames != .max {
                    state.elapsedFrames = requestedElapsedFrames
                }
            }

            for frame in 0..<safeFrameCount {
                SequencerCore.advanceIfNeeded(
                    state: state,
                    channels: dspChannels,
                    mod: mod,
                    sampleRate: sampleRate
                )

                state.outputsUntilNextTick -= 1.0
                state.elapsedFrames += 1

                // Mischen der Kanäle
                var outL: Float = 0.0
                var outR: Float = 0.0

                var hasSolo = false
                if let itVoicePool {
                    for channel in 0..<itVoicePool.logicalChannelCount {
                        if itVoicePool.patternChannels[channel].isSoloed {
                            hasSolo = true
                            break
                        }
                    }
                } else {
                    for channel in 0..<logicalChannelCount where dspChannels[channel].isSoloed {
                        hasSolo = true
                        break
                    }
                }
                // Globale Lautstärke (S3M Vxx) wirkt auf alle Kanäle gleich.
                let globalGain = state.globalVolume / globalVolumeScale
                let captureStems = capture?.stemsPointer
                let captureFrameCapacity = capture?.frameCapacity ?? 0

                // Roll the wave sample write index
                state.waveWriteIndex = (state.waveWriteIndex + 1) % 32
                let wIdx = state.waveWriteIndex

                // Der sichtbare Kanalpuffer und die Capture-Stems gehören den
                // logischen Kanälen, nicht den bis zu 256 physischen Stimmen.
                for channel in 0..<logicalChannelCount {
                    waveBuffer.channelWavesPointer[channel * 32 + wIdx] = 0.0
                    if let captureStems {
                        captureStems[channel * captureFrameCapacity + frame] = 0.0
                    }
                }

                let renderedVoiceCount = itVoicePool?.usesBackgroundVoices == true
                    ? itVoicePool!.activeVoiceCount
                    : voiceCount
                for renderPosition in 0..<renderedVoiceCount {
                    let voiceIndex = itVoicePool?.usesBackgroundVoices == true
                        ? itVoicePool!.activeVoiceIndex(at: renderPosition)
                        : renderPosition
                    let ch = dspChannels[voiceIndex]
                    let ownerIndex = itVoicePool == nil
                        ? voiceIndex
                        : (ch.itPatternState?.channelIndex ?? -1)
                    guard ownerIndex >= 0, ownerIndex < logicalChannelCount else { continue }
                    let voiceFrame = Self.renderChannelFrame(
                        channel: ch,
                        useInterpolation: state.useInterpolation
                    )
                    let outputSample = voiceFrame.mono * globalGain

                    // Roh-Stem vor Panning, Mix-Gain und Limiter. Bei Capture=nil
                    // bleibt dies nur ein einfacher optionaler Pointer-Check.
                    if let captureStems {
                        captureStems[ownerIndex * captureFrameCapacity + frame] += outputSample
                    }

                    // Mute / Solo logic
                    let ownerState = ch.itPatternState
                    var isChannelMuted = ownerState?.isMuted ?? ch.isMuted
                    if hasSolo && !(ownerState?.isSoloed ?? ch.isSoloed) {
                        isChannelMuted = true
                    }

                    if isChannelMuted {
                        continue
                    }

                    // Alle Vorder-/Hintergrundstimmen eines Besitzers addieren.
                    waveBuffer.channelWavesPointer[ownerIndex * 32 + wIdx] += outputSample

                    // Panning LRRL mit Separation (XM: inkl. Panning-Hüllkurve)
                    let p = ch.effectivePanning
                    let separation = state.stereoSeparation
                    let pEffective = max(0.0, min(1.0, 0.5 + (p - 0.5) * separation))
                    let lGain = 1.0 - pEffective
                    let rGain = pEffective

                    if ch.itSurround {
                        let surround = voiceFrame.isStereo
                            ? (voiceFrame.left + voiceFrame.right) * 0.25 * globalGain
                            : outputSample * 0.5
                        outL += surround * mixGain
                        outR -= surround * mixGain
                    } else {
                        outL += voiceFrame.left * globalGain * lGain * mixGain
                        outR += voiceFrame.right * globalGain * rGain * mixGain
                    }

                }

                for channel in 0..<logicalChannelCount {
                    let absVal = abs(waveBuffer.channelWavesPointer[channel * 32 + wIdx])
                    if absVal > vuBuffer.pointer[channel] {
                        vuBuffer.pointer[channel] = absVal
                    }
                }

                // Float-Stereo unmittelbar vor dem tanh-Limiter sichern.
                if let capture {
                    capture.stereoLeftPointer[frame] = outL
                    capture.stereoRightPointer[frame] = outR
                }
                
                // Soft Limiter (Hyperbolic Tangent) gegen Clipping
                let limitedL = tanh(outL)
                let limitedR = tanh(outR)
                left[frame] = limitedL
                right[frame] = limitedR
                // Master-Scope als echter, ueber Callbacks rollender Ringpuffer
                // (wie waveWriteIndex oben), damit alle 128 Slots stetig gefuellt
                // werden — kein stehender/ruckelnder Tail bei kleinen Buffern.
                state.masterWaveWriteIndex = (state.masterWaveWriteIndex + 1) & 127
                waveBuffer.masterWavesPointer[state.masterWaveWriteIndex] = (limitedL + limitedR) * 0.5
            }
            if safeFrameCount > 0 {
                visualizationExchange?.publish(
                    channelCount: logicalChannelCount)
            }
            state.publishElapsedFrames()
            state.notePreviewExchange?.finishBlock(frames: safeFrameCount)
            state.publishTransportSnapshot()
            if let appliedTempo {
                // Erst der veroeffentlichte Transport-Snapshot bestaetigt dem
                // MainActor, dass er seinen noch sichtbaren Stepper-Wert wieder
                // aus dem Audiostand spiegeln darf.
                state.markTempoApplied(appliedTempo)
            }
            if let appliedSeekSequence {
                // Erst nach dem vollstaendigen Zielblock freigeben: Der
                // MainActor sieht durch Acquire danach den passenden atomaren
                // Transport-Snapshot und nie den Vor-Seek-Stand.
                state.markSeekApplied(appliedSeekSequence)
            }
        }
    }

    // Wendet den kompletten Seek dort an, wo alle betroffenen Felder ohnehin
    // leben: am Anfang eines Audioframes im Renderblock. Kein Lock, keine
    // Allokation und kein Zugriff des Oberflaechen-Threads auf halb geaenderten
    // Sequencer- oder Kanalzustand.
    @inline(__always)
    nonisolated static func applySeek(
        _ request: RealtimePlaybackState.SeekSnapshot,
        state: RealtimePlaybackState,
        channels: [DSPChannel],
        sampleRate: Double
    ) {
        state.position = request.position
        state.rowIndex = request.row - 1
        state.ticksPerRow = request.ticksPerRow
        state.bpm = request.bpm
        state.tick = request.ticksPerRow - 1
        state.globalVolume = Float(request.globalVolume)

        state.positionJump = -1
        state.patternBreak = -1
        state.patternLoopRow = -1
        state.patternDelay = 0
        state.patternDelayCounter = 0
        state.patternDelaySeen = false
        state.tempoSlide = 0
        state.globalVolumeSlide = 0
        state.rowTickDelay = 0

        for channel in channels {
            channel.patternLoopCount = -1
            channel.patternLoopStartRow = 0
            channel.playing = false
        }
        if let patternStates = channels.first?.itVoicePool?.patternChannels {
            for patternState in patternStates {
                patternState.patternLoopCount = -1
                patternState.patternLoopStartRow = 0
                patternState.channelVolumeSlide = 0
                patternState.panningSlide = 0
            }
        }

        state.resetEndTransition()
        _ = state.takePendingElapsedFrames()
        SequencerCore.recalculateTickDuration(state: state, sampleRate: sampleRate)
        state.outputsUntilNextTick = 0.0
        state.elapsedFrames = request.elapsedFrames
    }

    // IT-Samplevorschau in derselben Stimmung wie die Song-Engine. C-5 spielt
    // genau mit C5Speed; jede Oktave verdoppelt beziehungsweise halbiert die
    // Abspielrate. Der getrennte Helfer macht diese Regression hardwarefrei
    // testbar, obwohl previewInstrument selbst eine AVAudioEngine startet.
    nonisolated static func itPreviewSampleSpeed(
        sample: Sample,
        targetNote: Int,
        linearFrequency: Bool,
        sampleRate: Double
    ) -> Double {
        guard sampleRate > 0 else { return 0 }
        let c5Speed = sample.itProperties?.c5Speed ?? sample.c2spd
        guard c5Speed > 0 else { return 0 }
        if linearFrequency {
            return Double(c5Speed) * pow(2.0, Double(targetNote - 60) / 12.0) / sampleRate
        }
        let period = DSPChannel.itAmigaPeriod(key: targetNote, c5Speed: c5Speed)
        return period > 0 ? 14_317_056.0 / Double(period) / sampleRate : 0
    }

    // XM-Vorschauperiode in derselben Rechnung wie die Song-Engine
    // (`DSPChannel.playNote`): gespielte Note plus Sample-`relativeNote`, dazu
    // der signed Finetune; das Header-Flag waehlt lineare oder Amiga-Perioden.
    // Der Halbtonbereich wird wie in den Periodentabellen auf 0...119 begrenzt,
    // damit ein extremer `relativeNote` keine unsinnige Periode liefert.
    nonisolated static func xmPreviewPeriod(
        sample: Sample,
        targetNote: Int,
        linearFrequency: Bool
    ) -> Float {
        DSPChannel.xmPeriod(
            key: targetNote,
            relativeNote: sample.relativeNote,
            finetune: sample.finetune,
            linearFrequency: linearFrequency)
    }

    // XM-Samplevorschau in derselben Stimmung wie die Song-Engine. Frueher lief
    // XM im MOD-Zweig der Vorschau (Periode 214 - Finetune gegen die
    // Paula-Clock) und klang gegenueber derselben Note im Modul deutlich
    // verstimmt. Wie bei IT macht der getrennte Helfer das hardwarefrei
    // testbar, obwohl `previewInstrument` selbst eine AVAudioEngine startet.
    nonisolated static func xmPreviewSampleSpeed(
        sample: Sample,
        targetNote: Int,
        linearFrequency: Bool,
        sampleRate: Double
    ) -> Double {
        guard sampleRate > 0 else { return 0 }
        let period = xmPreviewPeriod(
            sample: sample, targetNote: targetNote, linearFrequency: linearFrequency)
        if linearFrequency {
            // Dieselbe Exponentialformel wie im Renderblock: C-4 (Periode 4608)
            // spielt mit 8363 Hz.
            return 8363.0 * pow(2.0, (4608.0 - Double(period)) / 768.0) / sampleRate
        }
        // Amiga-Perioden gegen den FastTracker-II-Takt, nicht gegen Paula.
        guard period > 0 else { return 0 }
        return 8363.0 * 1712.0 / Double(period) / sampleRate
    }

    // Minimaler Render-Block der Vorschau: genau EIN Kanal, mittig gepannt, ohne
    // Sequencer/Effekte. Nach Ablauf des Frame-Budgets gibt er Stille aus.
    nonisolated static func createPreviewRenderBlock(
        channel ch: DSPChannel,
        voice: PreviewVoice,
        useInterpolation: Bool
    ) -> ModuleRenderBlock {
        return { (frameCount, left, right) in
            for frame in 0..<Int(frameCount) {
                var rendered = RenderedVoiceFrame(
                    left: 0, right: 0, mono: 0, isStereo: false
                )
                if voice.framesLeft > 0 {
                    rendered = Self.renderChannelFrame(
                        channel: ch,
                        useInterpolation: useInterpolation
                    )
                    voice.framesLeft -= 1
                }
                // Stereo-Samples bleiben in der Instrumentvorschau räumlich
                // erhalten; tanh schützt wie zuvor weich gegen Clipping.
                left[frame] = tanh(rendered.left)
                right[frame] = tanh(rendered.right)
            }
        }
    }

    // Frisch konfigurierte Offline-Render-Kanäle für ein Modul (Panning +
    // Format-Modell), z.B. für WAV-Export, Render-Probe und Quick-Look.
    nonisolated static func makeRenderChannels(for mod: Mod) -> [DSPChannel] {
        let logicalCount = max(1, min(Self.maxChannels, mod.channelCount))
        let count = mod.format == .it && mod.itProperties?.usesInstruments == true
            ? Self.itVoiceCapacity
            : logicalCount
        let renderChannels = (1...count).map { DSPChannel(index: $0) }
        configure(channels: renderChannels, for: mod)
        return renderChannels
    }

    // Startzustand des Sequencers für ein Modul (Header-Tempo, Global Volume,
    // S3M-Clock). Position 0 / Zeile -1 funktioniert fuer jede Pattern-Laenge;
    // der erste Frame laedt sofort Zeile 0.
    nonisolated static func makeRenderState(for mod: Mod, sampleRate: Double) -> RealtimePlaybackState {
        let state = RealtimePlaybackState()
        state.position = 0
        state.rowIndex = -1
        state.tick = mod.initialSpeed - 1
        state.ticksPerRow = mod.initialSpeed
        state.bpm = mod.initialTempo
        let timing = timingParameters(for: mod)
        state.tempoMode = timing.tempoMode
        state.rowsPerBeat = timing.rowsPerBeat
        state.restartPosition = max(
            0,
            min(mod.length - 1, mod.itProperties?.openMPTExtensions?.restartPosition ?? 0)
        )
        SequencerCore.recalculateTickDuration(state: state, sampleRate: sampleRate)
        state.outputsUntilNextTick = 0.0
        state.globalVolume = Float(mod.initialGlobalVolume)
        state.clockRateOverride = clockRateOverride(for: mod)
        state.publishTransportSnapshot()
        return state
    }

    // Berechnet die musikalische Dauer ueber echte Row-/Tick-Uebergaenge, ohne
    // Samples zu mischen. Statt Millionen einzelner Audioframes werden nur die
    // Tick-Grenzen besucht; der gerundete Frame-Schritt bildet denselben
    // Restwert-Akkumulator wie der Live-/Offline-Renderblock nach.
    //
    // Oeffentlich, weil ein Aufrufer die Probe vorziehen koennen muss: Sie ist
    // bei einem grossen IT der teuerste Teil des Ladens, und `setMod` laeuft
    // auf dem MainActor. Wer im Hintergrund laedt, rechnet sie dort aus und
    // reicht das Ergebnis als `precomputedDuration` an `setMod` weiter.
    public nonisolated static func sequencedDuration(
        of mod: Mod,
        sampleRate: Double = 44_100,
        maximumSeconds: Double = 600
    ) -> Double {
        guard mod.length > 0, sampleRate > 0, maximumSeconds > 0 else { return 0 }
        let channels = makeRenderChannels(for: mod)
        let state = makeRenderState(for: mod, sampleRate: sampleRate)
        let maximumFrames = UInt64(sampleRate * maximumSeconds)

        while state.elapsedFrames < maximumFrames {
            SequencerCore.advanceIfNeeded(
                state: state,
                channels: channels,
                mod: mod,
                sampleRate: sampleRate
            )
            if state.endReached { break }

            let remaining = maximumFrames - state.elapsedFrames
            let frameStep = min(
                remaining,
                UInt64(max(1, Int(ceil(state.outputsUntilNextTick))))
            )
            state.outputsUntilNextTick -= Double(frameStep)
            state.elapsedFrames += frameStep
        }
        return Double(state.elapsedFrames) / sampleRate
    }

    // Reihenzahl des Patterns an der gegebenen Song-Position. XM-Patterns haben
    // variable Länge (1..256 Reihen); MOD/S3M sind immer 64. Wird beim Row-Wrap
    // gebraucht, damit ein kurzes Pattern nach seiner letzten echten Reihe
    // umbricht — nicht erst bei fixen 64 (sonst 34 leere Reihen bei 30-Reihen-
    // Patterns → Timing-Drift + weiterlaufende Volume-Slides). Allokationsfrei
    // (nur Array-Index-Zugriffe), damit im Echtzeit-Render-Block nutzbar.
    nonisolated static func patternRowCount(_ mod: Mod, at position: Int) -> Int {
        SequencerCore.patternRowCount(mod, at: position)
    }

    // Anzeige-Uhr (elapsedFrames) fuer einen Positions-/Zeilenpunkt: dieselbe
    // Naeherung wie beim Seek — globale Zeilenzahl mal aktueller Tick-Dauer.
    // Bei Tempo-Wechseln im Song ist das bewusst nur eine Naeherung.
    nonisolated static func elapsedFrames(
        for mod: Mod,
        position: Int,
        row: Int = 0,
        ticksPerRow: Int,
        outputsPerTick: Double
    ) -> UInt64 {
        let frames = Double(cumulativeRows(mod, upTo: position, row: row) * max(1, ticksPerRow))
            * max(0, outputsPerTick)
        return frames.isFinite && frames > 0 ? UInt64(frames) : 0
    }

    // Ein Endsignal entsteht exakt an `transitionFrame`; bis der MainActor es
    // beim naechsten 30-/5-Hz-Poll verarbeitet, hat der Renderblock bereits
    // weitere Frames am Loop-Ziel gespielt. Diese Strecke gehoert auf den
    // statischen Loop-Start, sonst hinkt die sichtbare Uhr bei jedem Durchlauf
    // um ein Poll-Intervall hinterher.
    nonisolated static func elapsedFramesAfterLoopTransition(
        loopStartFrames: UInt64,
        transitionFrame: UInt64,
        renderedFrame: UInt64
    ) -> UInt64 {
        let distance = renderedFrame >= transitionFrame
            ? renderedFrame - transitionFrame
            : 0
        let (result, overflow) = loopStartFrames.addingReportingOverflow(distance)
        return overflow ? .max : result
    }

    // Globaler Zeilen-Index: Summe der ECHTEN Pattern-Reihen aller Positionen vor
    // `position`, plus `row`. Ersetzt die frühere (position*64 + row)-Annahme, die
    // bei XM mit variablen Pattern-Längen die Elapsed-/Gesamtzeit und die
    // Positionsanzeige verfälschte (z.B. Starfish: 212s statt 178s angezeigt).
    // Nicht im Audio-Thread aufrufen (O(Positionen)); nur bei Seek/Zeitanzeige.
    nonisolated static func cumulativeRows(_ mod: Mod, upTo position: Int, row: Int = 0) -> Int {
        let clamped = max(0, min(mod.length, position))
        var total = 0
        for p in 0..<clamped { total += patternRowCount(mod, at: p) }
        return total + max(0, row)
    }

    // Umkehrung von `cumulativeRows`: globaler Zeilen-Index -> (Position, Zeile)
    // entlang der echten Pattern-Längen. Für den relativen Zeitsprung (+/- s).
    nonisolated static func positionAndRow(_ mod: Mod, forGlobalRow globalRow: Int) -> (position: Int, row: Int) {
        var remaining = max(0, globalRow)
        for p in 0..<max(0, mod.length) {
            let rows = patternRowCount(mod, at: p)
            if remaining < rows { return (p, remaining) }
            remaining -= rows
        }
        let last = max(0, mod.length - 1)
        return (last, max(0, patternRowCount(mod, at: last) - 1))
    }

    @inline(__always)
    nonisolated private static func renderChannelFrame(
        channel ch: DSPChannel,
        useInterpolation: Bool
    ) -> RenderedVoiceFrame {
        // Note-Cut, Key-Off und Stop setzen dieses Flag. Besonders geloopte
        // Samples wuerden ohne den Guard trotz gestoppter Stimme weiterklingen.
        guard ch.playing else { return RenderedVoiceFrame(left: 0, right: 0, mono: 0, isStereo: false) }
        guard let smp = ch.sample, smp.pcm.count > 0, ch.currentPeriod > 0 else {
            return RenderedVoiceFrame(left: 0, right: 0, mono: 0, isStereo: false)
        }
        guard ch.sampleIndex.isFinite, !ch.sampleIndex.isNaN else {
            return RenderedVoiceFrame(left: 0, right: 0, mono: 0, isStereo: false)
        }

        let loop = activeSampleLoop(channel: ch, sample: smp)
        if let loop {
            wrapLoopedSampleIndexIfNeeded(channel: ch, sample: smp, loop: loop)
        }

        let idx = Int(ch.sampleIndex)
        guard idx >= 0, idx < smp.pcm.count else {
            // Ein beendetes One-Shot bleibt beendet. Das ist insbesondere für
            // IT Qxy wichtig: sehr kurze Samples werden nicht später aus dem
            // Nichts erneut gestartet.
            if loop == nil { ch.playing = false }
            return RenderedVoiceFrame(
                left: 0,
                right: 0,
                mono: 0,
                isStereo: smp.rightPCM != nil
            )
        }

        let leftSample = readVoiceSample(
            pcm: smp.pcm,
            channel: ch,
            loop: loop,
            useInterpolation: useInterpolation
        )
        let rightSample: Float
        if let rightPCM = smp.rightPCM {
            rightSample = readVoiceSample(
                pcm: rightPCM,
                channel: ch,
                loop: loop,
                useInterpolation: useInterpolation
            )
        } else {
            rightSample = leftSample
        }

        // sampleDirection ist bei MOD/S3M immer +1 (unverändert); nur XM-Ping-Pong
        // dreht sie auf -1. xmVolumeScale ist bei MOD/S3M 1.0 (Envelope/Fadeout aus).
        ch.sampleIndex += ch.sampleSpeed * ch.sampleDirection
        if let loop {
            wrapLoopedSampleIndexIfNeeded(channel: ch, sample: smp, loop: loop)
        }

        let gain = ch.currentVolume / 64.0 * ch.xmVolumeScale * ch.itVolumeScale
        let filtered = ch.applyITFilter(left: leftSample * gain, right: rightSample * gain)
        return RenderedVoiceFrame(
            left: filtered.0,
            right: filtered.1,
            mono: (filtered.0 + filtered.1) * 0.5,
            isStereo: smp.rightPCM != nil
        )
    }

    @inline(__always)
    // internal statt private: renderProbe im ModPlayerCoordinator liegt seit dem
    // Split in einer anderen Datei, nutzt aber weiterhin denselben Sample-Renderer.
    nonisolated static func renderChannelSample(
        channel ch: DSPChannel,
        useInterpolation: Bool
    ) -> Float {
        renderChannelFrame(channel: ch, useInterpolation: useInterpolation).mono
    }

    // Schmale interne Testnaht für Loop-, Stereo- und Filterdetails. Der
    // Produktionsmixer verwendet weiterhin direkt den privaten Stack-Wert.
    nonisolated static func renderChannelStereoSampleForTesting(
        channel ch: DSPChannel,
        useInterpolation: Bool
    ) -> (left: Float, right: Float) {
        let frame = renderChannelFrame(channel: ch, useInterpolation: useInterpolation)
        return (frame.left, frame.right)
    }

    @inline(__always)
    nonisolated private static func readVoiceSample(
        pcm: [Float],
        channel ch: DSPChannel,
        loop: SampleLoop?,
        useInterpolation: Bool
    ) -> Float {
        if let loop, useInterpolation {
            if loop.type == .pingpong {
                let end = min(pcm.count, loop.start + loop.length)
                if ch.sampleIndex >= Double(end - 1), end > 0 {
                    return pcm[end - 1]
                }
                return ch.getInterpolatedSample(from: pcm, index: ch.sampleIndex)
            }
            return ch.getInterpolatedSampleLooped(
                from: pcm,
                index: ch.sampleIndex,
                repeatOffset: loop.start,
                repeatLength: loop.length
            )
        }
        if useInterpolation {
            return ch.getInterpolatedSample(from: pcm, index: ch.sampleIndex)
        }
        return ch.getNearestSample(from: pcm, index: ch.sampleIndex)
    }

    @inline(__always)
    nonisolated private static func activeSampleLoop(
        channel ch: DSPChannel,
        sample smp: Sample
    ) -> SampleLoop? {
        if ch.itMode, !ch.keyReleased,
           let sustain = smp.sustainLoop,
           sustain.type != .none,
           sustain.length > 0 {
            return sustain
        }
        // IT kennt auch absichtlich sehr kurze Loops. Die historische >2-
        // Schwelle des neutralen Modells bleibt für MOD/S3M-Sentinel-Loops
        // erhalten, wird für echte IT-Loopflags aber nicht übernommen.
        if ch.itMode, smp.loopType != .none, smp.loopLength > 0 {
            return SampleLoop(
                start: smp.loopStart,
                length: smp.loopLength,
                type: smp.loopType
            )
        }
        guard smp.isLooped else { return nil }
        return SampleLoop(start: smp.loopStart, length: smp.loopLength, type: smp.loopType)
    }

    nonisolated private static func wrapLoopedSampleIndexIfNeeded(
        channel ch: DSPChannel,
        sample smp: Sample,
        loop: SampleLoop
    ) {
        let frameCount = smp.pcm.count
        let loopStart = max(0, min(loop.start, frameCount - 1))
        let declaredLoopEnd = loop.start + loop.length
        let loopEnd = max(loopStart + 1, min(declaredLoopEnd, frameCount))
        guard loopEnd > loopStart else { return }

        let start = Double(loopStart)
        let end = Double(loopEnd)
        let length = end - start

        if loop.type == .pingpong {
            let crossedEnd = ch.sampleDirection > 0 && ch.sampleIndex >= end
            let crossedStart = ch.sampleDirection < 0 && ch.sampleIndex < start
            guard crossedEnd || crossedStart else { return }
            // Zwei Spannen erhalten auch bei grossen Schritten die Richtung.
            // Das obere Ende ist exklusiv: exakt dort darf kein PCM-Zugriff landen.
            let cycle = 2 * length
            let offset = ch.sampleIndex - start
            let unfolded = ch.sampleDirection > 0 ? offset : cycle - offset
            var phase = unfolded.truncatingRemainder(dividingBy: cycle)
            if phase < 0 { phase += cycle }
            if phase < length {
                ch.sampleIndex = start + phase
                ch.sampleDirection = 1
            } else {
                ch.sampleIndex = min(end.nextDown, end - (phase - length))
                ch.sampleDirection = -1
            }
        } else if ch.sampleIndex >= end {
            // Vorwärts-Loop: in den Repeat-Bereich zurückfalten. Der alte Swift-
            // Code setzte hart auf repeatOffset und konnte bei genauem Loop-Ende
            // kurzzeitig ausserhalb der gültigen Sampledaten landen.
            ch.sampleIndex = start + (ch.sampleIndex - start).truncatingRemainder(dividingBy: length)
        }
    }
}

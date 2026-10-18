import Foundation

// Live-Wiedergabe für macOS/iOS: AVAudioEngine-Anbindung, UI-Zustand und die
// Instrument-Vorschau. Der plattformneutrale Renderkern liegt in
// RenderEngine.swift — CLI und Offline-Render (Quick Look, WAV) laufen ohne diese
// Klasse und bauen deshalb auch unter Linux, wo weder AVFoundation noch Combine
// existieren.
#if canImport(AVFoundation) && canImport(Combine)
import AVFoundation
import Combine

// Gemeinsamer Nenner der beiden Traeger von Mute und Solo: bei IT der logische
// Pattern-Kanal, sonst die Stimme selbst. Beide sind Klassen, deshalb genuegt
// eine Referenz, um den Schalter zu lesen und zu setzen. Die Auswahl trifft
// `ModPlayerCoordinator.muteState(at:)` — der Echtzeit-Renderblock liest die
// Felder weiterhin direkt am konkreten Typ und bekommt hiervon nichts mit.
protocol ChannelMuteState: AnyObject, Sendable {
    var isMuted: Bool { get set }
    var isSoloed: Bool { get set }
}

extension DSPChannel: ChannelMuteState {}
extension ITPatternChannelState: ChannelMuteState {}

@MainActor
public final class ModPlayerCoordinator: ObservableObject {
    public let sleepTimer = SleepTimerController()
    public var onSleepTimerExpired: (@MainActor () -> Void)?
    @Published public var isPlaying = false
    // Pausiert: Engine steht, aber der komplette Wiedergabezustand (Position,
    // Kanäle, Effekt-Memory) bleibt erhalten — resume() spielt nahtlos weiter.
    // isPlaying bleibt dabei true (die Engine ist weiterhin alloziert).
    @Published public var isPaused = false
    // Song-Position + aktuelle Zeile leben in einem EIGENEN ObservableObject
    // (row-rate), damit die ~20-Hz-Zeilenwechsel NICHT die ganze MainView.body neu
    // evaluieren — nur die positionsabhängigen Subviews beobachten `transport`.
    // War die eigentliche CPU-Grundlast (2026-07-09). Convenience-Accessoren unten
    // halten bestehende Aufrufer (seek etc.) unverändert.
    public let transport = TransportState()
    public var currentPosition: Int {
        get { transport.currentPosition }
        set { transport.currentPosition = newValue }
    }
    public var currentRow: Int {
        get { transport.currentRow }
        set { transport.currentRow = newValue }
    }
    // Die BPM-/Speed-Stepper in der UI schreiben in diese beiden Properties.
    // Damit eine Aenderung auch wirklich die laufende Wiedergabe beeinflusst,
    // legt der MainActor einen atomaren Auftrag fuer den Renderblock ab. Nur der
    // Audiothread schreibt danach `state.bpm` und `state.ticksPerRow`; ein
    // Stepper kann deshalb nicht mehr parallel in den Sequencer-Zustand greifen.
    // Beim Veröffentlichen eines Seek-Ziels werden die UI-Werte sofort
    // nachgezogen. Dieser Schalter verhindert, dass ihre didSet-Hooks dabei
    // denselben Zustand doch wieder ausserhalb des Audiothreads verändern.
    private var suppressRealtimeParameterWriteback = false
    private var pendingBPMSequence: UInt64?
    private var pendingSpeedSequence: UInt64?
    @Published public private(set) var sectionLoopIsPreparing = false
    @Published public private(set) var sectionLoopIsActive = false
    @Published public private(set) var sectionLoopProgress: Double = 0
    @Published public private(set) var sectionLoopError: SectionLoopError?
    @Published public private(set) var sectionLoopTarget: SongSection?
    private var sectionLoopPreparation: Task<Void, Never>?
    private var sectionLoopGeneration = UUID()
    private var pendingSectionLoop: PreparedSectionLoop?
    private var sectionLoopPlayback: SectionLoopPlayback?

    @Published public var bpm = 125 {
        didSet {
            guard !suppressRealtimeParameterWriteback, bpm > 0 else { return }
            cancelSectionLoop()
            guard let state = playbackState else { return }
            pendingBPMSequence = state.requestBPM(bpm)
        }
    }
    @Published public var speed = 6 {
        didSet {
            guard !suppressRealtimeParameterWriteback, speed > 0 else { return }
            cancelSectionLoop()
            guard let state = playbackState else { return }
            pendingSpeedSequence = state.requestTicksPerRow(speed)
        }
    }
    @Published public var trackName = "Kein Song geladen"

    // Kanalzahl des aktiven Moduls (4 bei klassischem MOD, bis 32 bei S3M).
    // Die UI leitet daraus Grid-Spalten, VU-Meter und Scopes ab.
    @Published public var channelCount = 4

    // Hochfrequenter (30 Hz) Visualisierungs-Zustand (VU, Oszilloskope, Spielzeit)
    // in EIGENEM ObservableObject — damit die 30-Hz-Updates NICHT die ganze
    // MainView.body neu evaluieren, sondern nur die beobachtenden Scope-/VU-/Zeit-
    // Subviews. War die Haupt-CPU-Last (2026-07-09). `let`: stabile Referenz.
    public let visualizerState = VisualizerState()
    @Published public private(set) var notePreviewSource: NotePreviewSource?

    // Sind die schweren Visualisierungen (Kanal-Oszis + Master-Oszi) gerade
    // sichtbar? Setzt die View im responsiven Kompaktmodus: bei kleinem Fenster
    // werden Grid/Oszis aus der Hierarchie entfernt. Der EIGENTLICHE CPU-Hebel ist
    // dann NICHT das Weglassen der Views (SwiftUI-Rendering ist billig), sondern
    // das Herunterschalten der Update-FREQUENZ: der 30-Hz-Tick schiebt sonst 30×/s
    // @Published-Werte durch SwiftUI — DAS war die Hauptlast (gemessen ~9 % von
    // ~15 %; Audio-DSP nur ~3-4 %). Ohne sichtbare Oszis reicht ~5 Hz für Uhr/VU.
    public var visualizersVisible = true {
        didSet {
            if !visualizersVisible {
                visualizerState.releaseWaveformBuffers()
            }
            // Läuft der VU-Timer, bei einem Sichtbarkeitswechsel mit der passenden
            // Frequenz neu aufsetzen (30 Hz sichtbar ↔ 5 Hz kompakt).
            guard oldValue != visualizersVisible, vuUpdateTimer != nil else { return }
            startVUUpdates()
        }
    }

    // Bildrate der Visualisierungen im Vollmodus, in Hz. 30 ist die Vorgabe und
    // damit die volle Optik; wer lieber CPU spart, stellt sie herunter.
    //
    // Der Hebel ist gross: gemessen am 2026-08-23 auf einem Mac mit M5-Chip, mit demselben
    // 4-Kanal-MOD, gleicher Fenstergroesse und stummer Ausgabe (verbrauchte
    // CPU-Zeit ueber je 30 s) — 30 Hz: 22 %, 24 Hz: 20 %, 15 Hz: 18 %,
    // 10 Hz: 14 % eines Kerns. Nicht der Audio-DSP, sondern das Durchreichen
    // der Werte durch SwiftUI macht den Unterschied.
    //
    // Geklemmt auf 1…60 Hz: 0 wuerde einen Timer mit Intervall unendlich
    // ergeben, ein sehr grosser Wert einen Timer, der den MainActor flutet.
    @Published public var visualizerFrameRate: Double = 30 {
        didSet {
            guard oldValue != visualizerFrameRate, vuUpdateTimer != nil else { return }
            startVUUpdates()
        }
    }

    // Update-Frequenz des VU-/Oszi-/Zeit-Ticks: im Vollmodus die eingestellte
    // Bildrate, im Kompaktmodus fest ~5 Hz (kein Oszi sichtbar) — das senkt die
    // SwiftUI-Last stark und ist dort auch nicht sichtbar.
    private var vuUpdateInterval: TimeInterval {
        Self.visualizerUpdateInterval(
            frameRate: visualizerFrameRate, visualizersVisible: visualizersVisible)
    }

    // Als eigene Funktion, damit sich die Klemmung ohne laufende Audio-Engine
    // pruefen laesst.
    nonisolated static func visualizerUpdateInterval(
        frameRate: Double, visualizersVisible: Bool
    ) -> TimeInterval {
        guard visualizersVisible else { return 0.2 }
        return 1.0 / min(60.0, max(1.0, frameRate))
    }

    // New parameters for user controls
    @Published public var stereoSeparation: Float = 0.8 {
        didSet {
            requestRenderOptions()
        }
    }
    @Published public var useInterpolation: Bool = true {
        didSet {
            requestRenderOptions()
        }
    }
    @Published public var palClock: Bool = true {
        didSet {
            requestRenderOptions()
        }
    }

    private func requestRenderOptions() {
        cancelSectionLoop()
        playbackState?.requestRenderOptions(
            stereoSeparation: stereoSeparation,
            useInterpolation: useInterpolation,
            palClock: palClock)
    }
    

    // Zaehlt bei jedem erreichten Songende hoch. Die UI beobachtet das per
    // onChange und wertet dort den loopMode aus (stop / Song wiederholen / naechster).
    @Published public var songEndPulse: Int = 0
    // Der MainActor kopiert das Loop-Ziel beim Konsumieren des atomaren Signals.
    // Der SwiftUI-onChange-Hook laeuft erst danach; bis dahin kann der
    // Audio-Thread schon die naechste Transition veroeffentlicht haben.
    private var consumedEndPosition = -1
    private var consumedEndRow = 0
    private var consumedEndFrame = UInt64.max
    // Der UI-Snapshot bleibt auf dem angeforderten Ziel, bis der Audioblock
    // genau diese Seek-Sequenz angewandt und atomar veroeffentlicht hat.
    private var pendingSeekSequence: UInt64?
    private var pendingSeekTransport: RealtimePlaybackState.TransportSnapshot?
    
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var lowPassFilterNode: AVAudioUnitEQ?

    // Getrennte Engine nur fuer die Instrument-Vorschau (previewInstrument).
    private var previewEngine: AVAudioEngine?
    private var previewSourceNode: AVAudioSourceNode?
    
    @Published public var ledFilterActive: Bool = false {
        didSet {
            if oldValue != ledFilterActive { cancelSectionLoop() }
            lowPassFilterNode?.bypass = !ledFilterActive
        }
    }
    

    // Vorallozierte DSP-Kanäle. Wird in setMod() passend zur Kanalzahl des
    // Moduls neu aufgebaut (der Render-Block captured das Array bei play()).
    private var channels = [DSPChannel(index: 1), DSPChannel(index: 2), DSPChannel(index: 3), DSPChannel(index: 4)]
    public var activeMod: Mod?
    
    // ARC-managed state captured by the AVAudioSourceNode closure
    private var playbackState: RealtimePlaybackState?
    private var playbackSampleRate: Double?
    
    // Vorallozierte Dreifachpuffer trennen den schreibenden Audiothread vom
    // lesenden MainActor. Der Renderblock waehlt den freien Slot lockfrei.
    private let visualizationExchange = RealtimeVisualizationExchange(
        channelCapacity: RenderEngine.maxChannels)
    
    // Timer for VU meter visual updates
    private var vuUpdateTimer: Timer?
    
    public init() {
        sleepTimer.onExpired = { [weak self] in
            guard let self else { return }
            self.stop()
            self.onSleepTimerExpired?()
        }
    }

    public func cancelSectionLoop() {
        sectionLoopGeneration = UUID()
        sectionLoopPreparation?.cancel()
        sectionLoopPreparation = nil
        sectionLoopPlayback?.disable()
        pendingSectionLoop = nil
        sectionLoopIsPreparing = false
        sectionLoopIsActive = false
        sectionLoopProgress = 0
        sectionLoopTarget = nil
        sectionLoopError = nil
    }

    public func startSectionLoop(_ section: SongSection, beforeActivation: @escaping @MainActor () -> Void = {}) {
        guard sleepTimer.allowsPlayback() else { return }
        cancelSectionLoop()
        guard let mod = activeMod else { return }
        // Die Quellrate wurde vor dem Verbinden der Engine festgelegt. Danach
        // kann der Mixer bereits die abweichende Geräterate melden.
        let engine = audioEngine ?? AVAudioEngine()
        let outputRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = playbackSampleRate ?? (outputRate.isFinite && outputRate > 0 ? outputRate : 44_100)
        let options = SectionLoopOptions(stereoSeparation: stereoSeparation,
            useInterpolation: useInterpolation, palClock: palClock)
        let generation = sectionLoopGeneration
        sectionLoopIsPreparing = true
        sectionLoopTarget = section
        let coordinator = self
        let worker = Task.detached(priority: .userInitiated) {
            try PreparedSectionLoop.prepare(mod: mod, section: section, sampleRate: sampleRate, options: options) { value in
                Task { @MainActor in
                    guard coordinator.sectionLoopGeneration == generation,
                          coordinator.sectionLoopIsPreparing else { return }
                    coordinator.sectionLoopProgress = value
                }
            }
        }
        sectionLoopPreparation = Task { [weak self] in
            do {
                let prepared = try await withTaskCancellationHandler(operation: { try await worker.value },
                    onCancel: { worker.cancel() })
                guard let self, !Task.isCancelled, self.sectionLoopGeneration == generation else { return }
                guard self.sleepTimer.allowsPlayback() else { return }
                let paused = self.isPaused
                let muteStates = (0..<self.channelCount).map { index in
                    let mute = self.muteState(at: index)
                    return (mute?.isMuted ?? false, mute?.isSoloed ?? false)
                }
                // Aktivierung ist ein ausdrücklicher Sprung nach A. Der neue
                // Callback besitzt seinen Snapshot schon vor dem Audiostart.
                self.sectionLoopPreparation = nil
                self.stop()
                self.pendingSectionLoop = prepared
                self.sectionLoopTarget = section
                self.sectionLoopIsActive = true
                beforeActivation()
                self.play(initiallyPaused: paused, muteStates: muteStates)
                if self.sectionLoopIsActive {
                    self.currentPosition = section.start.position
                    self.currentRow = section.start.row
                    self.visualizerState.elapsedTime = Double(prepared.startFrame) / prepared.sampleRate
                }
            } catch {
                guard let self, self.sectionLoopGeneration == generation else { return }
                self.sectionLoopPreparation = nil
                self.sectionLoopIsPreparing = false
                if !(error is CancellationError) { self.sectionLoopError = error as? SectionLoopError ?? .invalidSection }
            }
        }
    }
    
    // fallbackName: Anzeigename (i. d. R. der Dateiname), der genutzt wird, wenn
    // das Modul selbst keinen brauchbaren Titel im Header traegt. Viele Module —
    // gerade aus der Demoscene — haben ein leeres Titelfeld; frueher stand dann
    // stumpf "Unbekannter Track" oben. Der Dateiname ist fuer den Nutzer weit
    // aussagekraeftiger.
    //
    // precomputedDuration: Die Spieldauer, falls der Aufrufer sie schon kennt.
    // Sie zu ermitteln heisst, den Sequencer einmal ohne Audio bis zum
    // Songende durchzutakten — bei einem grossen IT der teuerste Teil des
    // Ladens. Weil dieser Coordinator auf dem MainActor lebt, wuerde die Probe
    // hier die Oberflaeche blockieren. Wer im Hintergrund laedt, rechnet sie
    // deshalb dort aus und reicht sie herein (so macht es die iPhone-App).
    // Ohne Angabe wird sie wie bisher hier berechnet.
    public func setMod(_ mod: Mod, fallbackName: String? = nil, precomputedDuration: Double? = nil) {
        stop()
        consumedEndPosition = -1
        consumedEndRow = 0
        consumedEndFrame = .max
        pendingSeekSequence = nil
        pendingSeekTransport = nil
        self.activeMod = mod
        // Header-Titel um Leerraum bereinigen; nur ein echter, nicht-leerer Titel
        // gewinnt, sonst der Dateiname-Fallback (und erst zuletzt der Default).
        let headerTitle = mod.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trackName = !headerTitle.isEmpty ? headerTitle
            : (fallbackName?.isEmpty == false ? fallbackName! : "Unbekannter Track")

        // Kanal-Setup passend zum Modul neu aufbauen (4 bei MOD, N bei S3M).
        let count = max(1, min(RenderEngine.maxChannels, mod.channelCount))
        // Nur der IT-Instrument-Modus braucht NNA-Hintergrundstimmen. Im
        // Sample-Modus bleibt die direkte 64-Kanal-Zuordnung deutlich billiger.
        let voiceCount = mod.format == .it && mod.itProperties?.usesInstruments == true
            ? RenderEngine.itVoiceCapacity
            : count
        self.channels = (1...voiceCount).map { DSPChannel(index: $0) }
        RenderEngine.configure(channels: self.channels, for: mod)
        self.channelCount = count
        self.visualizerState.resize(
            channelCount: count,
            includeWaveforms: visualizersVisible)
        // Einmal pro Song denselben Sequencer ohne Audio bis zum Endsignal
        // vortakten. Die fruehere Rows*Speed/BPM-Schaetzung ignorierte Bxx,
        // Pattern-Loops, Delays und Tempoaenderungen (Referenz-IT: 01:24 statt
        // korrekt 00:46). Die schnelle Tick-Probe ist von Blockgroessen frei.
        self.visualizerState.totalDuration = precomputedDuration ?? RenderEngine.sequencedDuration(of: mod)

        self.currentPosition = 0
        self.currentRow = 0
        // Eine fuer den alten Song vorgemerkte Startposition/-zeile gilt nicht mehr.
        self.pendingStartPosition = nil
        self.pendingStartRow = nil
        self.pendingGlobalVolume = nil
        // codereview-ok: by-design — neuer Song startet auf seinem Header-Tempo
        // (MOD: ProTracker-Default 125/6, S3M: Initial Speed/Tempo) und setzt
        // sein Tempo per Effekt selbst; mit dem didSet-Fix benigne, kein
        // Datenverlust an laufender Wiedergabe (2026-07-01)
        self.bpm = mod.initialTempo
        self.speed = mod.initialSpeed
    }

    
    public func play() { play(initiallyPaused: false) }

    private func play(initiallyPaused: Bool, muteStates: [(Bool, Bool)] = []) {
        guard sleepTimer.allowsPlayback() else { return }
        // Eine evtl. laufende Instrument-Vorschau weicht der Song-Wiedergabe.
        stopPreview()
        guard let mod = activeMod, mod.length > 0 else { return }
        if isPlaying { return }
        
        // Ensure channels are fresh
        for ch in channels {
            ch.reset()
        }
        // reset() stellt MOD-Defaults her -> Format-Konfiguration neu anwenden.
        RenderEngine.configure(channels: channels, for: mod)
        for index in muteStates.indices {
            if let mute = muteState(at: index) {
                mute.isMuted = muteStates[index].0
                mute.isSoloed = muteStates[index].1
            }
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let mixer = engine.mainMixerNode
        var sampleRate = mixer.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0.0 || sampleRate.isNaN || sampleRate.isInfinite {
            sampleRate = 44100.0
        }
        if let prepared = pendingSectionLoop, prepared.sampleRate != sampleRate {
            pendingSectionLoop = nil
            sectionLoopIsActive = false
            sectionLoopError = .sampleRateChanged
            audioEngine = nil
            return
        }
        let sectionLoop = pendingSectionLoop.map(SectionLoopPlayback.init)
        sectionLoopPlayback = sectionLoop
        pendingSectionLoop = nil
        
        // Define a guaranteed standard stereo format for our sourceNode
        guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            print("Fehler: Konnte standard stereo format nicht erstellen.")
            return
        }
        
        // Instantiate ARC-managed playback state
        let state = RealtimePlaybackState()
        state.position = 0
        state.rowIndex = -1
        // Start-Tempo aus den aktuellen Coordinator-Werten (self.bpm/self.speed)
        // statt stur aus dem Modul-Header: setMod() setzt beide beim Songwechsel
        // ohnehin auf die Header-Werte, aber eine im gestoppten Zustand per
        // Stepper gewaehlte Aenderung bleibt so erhalten und wird beim Play nicht
        // sofort wieder ueberschrieben. Song-eigene Tempo-Effekte (Fxx) greifen
        // waehrend der Wiedergabe weiterhin.
        state.tick = self.speed - 1
        state.ticksPerRow = self.speed
        state.bpm = self.bpm
        let timing = RenderEngine.timingParameters(for: mod)
        state.tempoMode = timing.tempoMode
        state.rowsPerBeat = timing.rowsPerBeat
        state.restartPosition = max(
            0,
            min(mod.length - 1, mod.itProperties?.openMPTExtensions?.restartPosition ?? 0)
        )
        SequencerCore.recalculateTickDuration(state: state, sampleRate: sampleRate)
        state.outputsUntilNextTick = 0.0
        state.positionJump = -1
        state.patternBreak = -1
        state.patternLoopRow = -1
        state.patternDelay = 0
        state.patternDelayCounter = 0
        state.patternDelaySeen = false
        state.tempoSlide = 0
        state.globalVolumeSlide = 0
        state.rowTickDelay = 0
        state.resetEndTransition()
        state.pendingElapsedFrames = .max
        if let states = channels.first?.itVoicePool?.patternChannels {
            for patternState in states {
                patternState.patternLoopCount = -1
                patternState.patternLoopStartRow = 0
                patternState.channelVolumeSlide = 0
                patternState.panningSlide = 0
            }
        }
        state.stereoSeparation = self.stereoSeparation
        state.useInterpolation = self.useInterpolation
        state.palClock = self.palClock
        state.globalVolume = Float(mod.initialGlobalVolume)
        state.clockRateOverride = RenderEngine.clockRateOverride(for: mod)
        state.elapsedFrames = 0

        // Wurde im gestoppten Zustand per Slider eine Startposition gewaehlt,
        // dort direkt vor Zeile 0 stehen. Das ist unabhaengig von der variablen
        // Zeilenzahl des vorherigen OpenMPT-Patterns.
        if let startPos = pendingStartPosition, startPos >= 0, startPos < mod.length {
            if let startRow = pendingStartRow, startRow > 0 {
                // Zeilen-genauer Start (Grid-Klick): direkt auf (startPos, startRow)
                // setzen — eine Zeile davor auf dem letzten Tick, damit der erste
                // Tick-Boundary die Zielzeile frisch laedt und triggert.
                state.position = startPos
                state.rowIndex = startRow - 1
                state.tick = state.ticksPerRow - 1
                state.elapsedFrames = UInt64(Double(RenderEngine.cumulativeRows(mod, upTo: startPos, row: startRow) * state.ticksPerRow) * state.outputsPerTick)
            } else {
                state.position = startPos
                state.rowIndex = -1
                state.elapsedFrames = UInt64(Double(RenderEngine.cumulativeRows(mod, upTo: startPos) * mod.initialSpeed) * state.outputsPerTick)
            }
        }
        // Rekonstruiertes Global-Volume (Zeilen-Sprung) uebernehmen.
        if let gv = pendingGlobalVolume { state.globalVolume = Float(gv) }
        // Auch eine zunächst pausierte Aktivierung besitzt schon den Zustand
        // vor A. Ausschalten vor dem ersten Callback darf ihn nicht verlieren.
        sectionLoop?.prepared.snapshot.apply(to: state, channels: channels)
        state.publishTransportSnapshot()
        pendingStartPosition = nil
        pendingStartRow = nil
        pendingGlobalVolume = nil

        self.playbackState = state
        self.playbackSampleRate = sampleRate
        #if os(macOS)
        let noteExchange = NotePreviewExchange()
        state.notePreviewExchange = noteExchange
        notePreviewSource = NotePreviewSource(
            configuration: .init(mod: mod, sampleRate: sampleRate, state: state, sectionLoop: sectionLoop?.prepared),
            exchange: noteExchange)
        #endif
        
        let dspChannels = channels
        let vuBuffer = visualizationExchange.makeVUBuffer()
        let waveBuffer = visualizationExchange.makeWaveBuffer()
        
        let renderBlock = RenderEngine.createRenderBlock(
            state: state,
            vuBuffer: vuBuffer,
            waveBuffer: waveBuffer,
            dspChannels: dspChannels,
            mod: mod,
            sampleRate: sampleRate,
            sectionLoop: sectionLoop
        )
        
        let sourceNode = AVAudioSourceNode(renderBlock: Self.makeSourceNodeRenderBlock(
            renderBlock, sleepTimer: sleepTimer.signal, sampleRate: sampleRate))

        self.sourceNode = sourceNode
        engine.attach(sourceNode)
        
        let lowPass = AVAudioUnitEQ(numberOfBands: 1)
        let band = lowPass.bands[0]
        band.filterType = .lowPass
        band.frequency = 3200.0
        lowPass.bypass = !ledFilterActive
        self.lowPassFilterNode = lowPass
        
        engine.attach(lowPass)
        
        engine.connect(sourceNode, to: lowPass, format: stereoFormat)
        engine.connect(lowPass, to: mixer, format: stereoFormat)
        
        // Die AVAudioSession wird hier bewusst NICHT angefasst. Sie ist ein
        // globaler Systemzustand und gehoert der App, nicht dem Replayer: Auf
        // iOS setzt und aktiviert `AudioSessionController` sie, samt
        // Puffergroesse, Unterbrechungen und Routenwechseln. Frueher stand hier
        // ein zweiter setCategory/setActive-Aufruf, dessen einzige
        // Fehlerbehandlung ein `print` war — zwei Stellen, die denselben
        // Systemzustand setzen, und keine davon zustaendig.
        do {
            guard sleepTimer.allowsPlayback() else { return }
            if initiallyPaused { engine.prepare() } else { try engine.start() }
            // Gespeicherte Lautstaerke auf den neuen Mixer anwenden, damit die
            // Ausgabe sofort zum UI-Slider passt (nicht erst nach Slider-Bewegung).
            mixer.outputVolume = lastVolume * lastVolume
            isPlaying = true
            isPaused = initiallyPaused
            if !initiallyPaused { startVUUpdates() }
        } catch {
            print("Fehler beim Starten der AVAudioEngine: \(error)")
            // Startet die Engine nicht, muessen die eben erzeugten Ressourcen
            // wieder abgebaut werden. Sonst bleiben audioEngine/sourceNode/
            // playbackState gesetzt, waehrend isPlaying==false ist — ein erneuter
            // play()-Aufruf liefe dann am `if isPlaying { return }`-Guard vorbei
            // und wuerde eine zweite, konkurrierende Engine erzeugen (Ressourcen-
            // Leak). stop() raeumt alles konsistent auf.
            stop()
        }
    }

    public func stop() {
        cancelSectionLoop()
        sectionLoopPlayback = nil
        pendingSectionLoop = nil
        stopPreview()
        if let engine = audioEngine {
            engine.stop()
        }
        audioEngine = nil
        sourceNode = nil
        isPlaying = false
        isPaused = false
        stopVUUpdates()

        self.playbackState = nil
        self.playbackSampleRate = nil
        notePreviewSource = nil
        pendingSeekSequence = nil
        pendingSeekTransport = nil
        pendingBPMSequence = nil
        pendingSpeedSequence = nil

        for ch in channels {
            ch.reset()
        }
    }

    // Wiedergabe anhalten, ohne den Zustand zu verwerfen. Gegenstück: resume().
    public func pause() {
        guard isPlaying, !isPaused, let engine = audioEngine else { return }
        engine.pause()
        isPaused = true
        // VU-Timer anhalten — die Meter fallen auf 0, elapsedTime friert ein.
        stopVUUpdates()
    }

    // Pausierte Wiedergabe nahtlos fortsetzen.
    public func resume() {
        guard sleepTimer.allowsPlayback() else { return }
        guard isPaused, let engine = audioEngine else { return }
        do {
            try engine.start()
            isPaused = false
            startVUUpdates()
        } catch {
            print("Fehler beim Fortsetzen der AVAudioEngine: \(error)")
            // Engine nicht wiederbelebbar -> sauber aufraeumen statt in einem
            // halb-pausierten Zustand haengen zu bleiben.
            stop()
        }
    }
    
    // Zuletzt gesetzte Lautstaerke (0..1). Wird beim naechsten play() auf den
    // frisch erzeugten Mixer angewandt, damit die tatsaechliche Ausgabe von Anfang
    // an zum Slider passt (vorher lief die erste Wiedergabe auf Default 1.0).
    private var lastVolume: Float = 0.6

    public func setVolume(_ v: Float) {
        lastVolume = v
        audioEngine?.mainMixerNode.outputVolume = v * v // Psychoacoustic scaling
        previewEngine?.mainMixerNode.outputVolume = v * v
    }
    
    // Merkt die per Slider gewaehlte Startposition, wenn gerade nichts spielt.
    // Der naechste play()-Aufruf startet dann dort statt am Songanfang.
    private var pendingStartPosition: Int?
    // Zusaetzlich zur Position eine Zeile (Zeilen-genauer Sprung per Grid-Klick im
    // gestoppten Zustand) und das rekonstruierte Start-Global-Volume.
    private var pendingStartRow: Int?
    private var pendingGlobalVolume: Int?


    // Zeilen-genauer Sprung: Grid-Klick auf eine Zeile. Rekonstruiert Speed/Tempo/
    // Global-Volume, damit die Wiedergabe ab dort im richtigen Tempo laeuft.
    public func seek(toPosition pos: Int, row: Int) {
        cancelSectionLoop()
        guard let mod = activeMod else { return }
        let p = max(0, min(mod.length - 1, pos))
        let r = max(0, min(RenderEngine.patternRowCount(mod, at: p) - 1, row))
        let params = RenderEngine.reconstructGlobalParams(mod, toPosition: p, row: r)
        publishSeekParameters(speed: params.speed, bpm: params.bpm)
        guard let state = playbackState else {
            // Gestoppt: Ziel vormerken; play() startet dort mit dem rekonstruierten Tempo.
            pendingStartPosition = p
            pendingStartRow = r
            pendingGlobalVolume = params.globalVolume
            currentPosition = p
            currentRow = r
            return
        }
        requestSeek(
            state: state,
            mod: mod,
            position: p,
            row: r,
            speed: params.speed,
            bpm: params.bpm,
            globalVolume: params.globalVolume)
    }

    public func seek(toPosition: Int) {
        cancelSectionLoop()
        guard let mod = activeMod else { return }
        let pos = max(0, min(mod.length - 1, toPosition))
        // Der Positionsslider veraendert nur die Position. Manuell gesetzte
        // BPM/Speed und die aktuelle globale Lautstaerke bleiben wie vor der
        // zeilengenauen Seek-Erweiterung erhalten.
        let currentGlobalVolume = playbackState.map { seekTransport(for: $0).globalVolume }
            ?? pendingGlobalVolume
            ?? mod.initialGlobalVolume
        let params = (speed: speed, bpm: bpm, globalVolume: currentGlobalVolume)
        guard let state = playbackState else {
            // Gestoppt: Position nur vormerken und in der UI anzeigen —
            // play() greift sie auf und beginnt an dieser Stelle.
            pendingStartPosition = pos
            pendingStartRow = 0
            pendingGlobalVolume = params.globalVolume
            currentPosition = pos
            currentRow = 0
            return
        }
        requestSeek(
            state: state,
            mod: mod,
            position: pos,
            row: 0,
            speed: params.speed,
            bpm: params.bpm,
            globalVolume: params.globalVolume)
    }

    // Relativer Zeitsprung (z.B. +30s/-15s). Rechnet die gewuenschten Sekunden
    // ueber die aktuelle Zeilendauer (Speed/BPM) in Pattern-Zeilen um und
    // springt zeilengenau — bei Tempo-Wechseln im Song eine Naeherung.
    public func seek(bySeconds delta: Double) {
        guard let state = playbackState, let mod = activeMod else { return }
        let transport = seekTransport(for: state)
        let effectiveBPM = Double(transport.bpm > 0 ? transport.bpm : 125)
        let rowDuration = Double(max(1, transport.ticksPerRow))
            * 60.0 / (effectiveBPM * 24.0)
        guard rowDuration > 0 else { return }

        let currentRows = RenderEngine.cumulativeRows(
            mod,
            upTo: transport.position,
            row: max(0, transport.row))
        var targetRows = currentRows + Int((delta / rowDuration).rounded())
        let totalRows = RenderEngine.cumulativeRows(mod, upTo: mod.length)
        targetRows = max(0, min(totalRows - 1, targetRows))
        let target = RenderEngine.positionAndRow(mod, forGlobalRow: targetRows)
        seek(toPosition: target.position, row: target.row)
    }

    func requestSeek(
        state: RealtimePlaybackState,
        mod: Mod,
        position: Int,
        row: Int,
        speed: Int,
        bpm: Int,
        globalVolume: Int
    ) {
        let sampleRate = self.audioEngine?.mainMixerNode.outputFormat(forBus: 0).sampleRate ?? 44100.0
        let timing = RenderEngine.timingParameters(for: mod)
        let outputsPerTick = SequencerCore.outputsPerTick(
            tempoMode: timing.tempoMode,
            bpm: bpm,
            ticksPerRow: speed,
            rowsPerBeat: timing.rowsPerBeat,
            sampleRate: sampleRate)
        let elapsedFrames = RenderEngine.elapsedFrames(
            for: mod, position: position, row: row,
            ticksPerRow: speed, outputsPerTick: outputsPerTick)
        // Ein Endsignal aus der alten Position darf weder den Seek stoppen noch
        // den Playlist-Titel wechseln. Eine Transition, die der Audiothread
        // genau jetzt noch veroeffentlicht, bleibt bis applySeek liegen; der
        // Poller konsumiert waehrend `pendingSeekSequence` nichts.
        _ = state.consumeEndTransition()
        let sequence = state.requestSeek(
            position: position,
            row: row,
            ticksPerRow: speed,
            bpm: bpm,
            globalVolume: globalVolume,
            elapsedFrames: elapsedFrames)
        pendingSeekSequence = sequence
        pendingSeekTransport = RealtimePlaybackState.TransportSnapshot(
            position: position,
            row: row,
            ticksPerRow: min(Int(UInt8.max), max(1, speed)),
            bpm: min(Int(UInt16.max), max(1, bpm)),
            globalVolume: min(Int(UInt8.max), max(0, globalVolume)))

        consumedEndPosition = -1
        consumedEndRow = 0
        consumedEndFrame = .max
        self.currentPosition = position
        self.currentRow = max(0, row)
    }

    // Fuer einen zweiten relativen Sprung im selben Audiopuffer gilt bereits
    // das erste Seek-Ziel; danach der letzte vollstaendig veroeffentlichte
    // Renderstand. Die 30-/5-Hz-UI-Spiegel sind dafuer zu alt.
    func seekTransport(for state: RealtimePlaybackState)
        -> RealtimePlaybackState.TransportSnapshot {
        if let sequence = pendingSeekSequence,
           !state.isSeekApplied(sequence),
           let pendingSeekTransport {
            return pendingSeekTransport
        }
        return state.transportSnapshot
    }

    private func publishSeekParameters(speed: Int, bpm: Int) {
        suppressRealtimeParameterWriteback = true
        self.speed = speed
        self.bpm = bpm
        suppressRealtimeParameterWriteback = false
    }

    // Setzt NUR die Anzeige-/Sperrbildschirm-Uhr auf den Loop-Neustartpunkt
    // zurueck, ohne die laufende Wiedergabe anzufassen. Gedacht fuer den
    // Track-Loop: Der Renderblock springt am Songende von selbst zum
    // restartPosition, `elapsedFrames` zaehlte aber weiter — UI- und
    // Sperrbildschirm-Spielzeit ueberholten ab der zweiten Runde die
    // Titeldauer.
    public func resetElapsedToLoopStart() {
        guard let state = playbackState, let mod = activeMod else { return }
        // Ziel der Endtransition bevorzugen: Ein rueckwaerts gerichteter
        // Bxx-Sprung landet nicht auf `restartPosition`, und ein zusaetzliches
        // Dxx setzt dort noch eine Zielzeile. Nur wenn (noch) kein Ziel erfasst
        // wurde, gilt der Neustartpunkt aus dem Modulkopf.
        let position: Int
        let row: Int
        if consumedEndPosition >= 0 {
            position = max(0, min(mod.length - 1, consumedEndPosition))
            row = max(0, consumedEndRow)
        } else if state.endReachedPosition >= 0 {
            // Fallback fuer direkte Core-Aufrufer, die keinen VU-Poll fahren.
            position = max(0, min(mod.length - 1, state.endReachedPosition))
            row = max(0, state.endReachedRow)
        } else {
            position = max(0, min(mod.length - 1, state.restartPosition))
            row = 0
        }
        let sampleRate = self.audioEngine?.mainMixerNode.outputFormat(forBus: 0).sampleRate ?? 44100.0
        let timing = RenderEngine.timingParameters(for: mod)
        let outputsPerTick = SequencerCore.outputsPerTick(
            tempoMode: timing.tempoMode,
            bpm: bpm,
            ticksPerRow: speed,
            rowsPerBeat: timing.rowsPerBeat,
            sampleRate: sampleRate)
        let loopStartFrames = RenderEngine.elapsedFrames(
            for: mod, position: position, row: row,
            ticksPerRow: speed, outputsPerTick: outputsPerTick)
        let transitionFrame = consumedEndFrame != .max
            ? consumedEndFrame
            : state.endReachedFrame
        let frames = transitionFrame != .max
            ? RenderEngine.elapsedFramesAfterLoopTransition(
                loopStartFrames: loopStartFrames,
                transitionFrame: transitionFrame,
                renderedFrame: state.publishedElapsedFrames)
            : loopStartFrames
        // Den Zaehler NICHT selbst schreiben: Er gehoert dem Renderblock, der
        // ihn pro Frame erhoeht. Ein direkter Schreibzugriff von hier koennte
        // zwischen dessen Lesen und Zurueckschreiben verlorengehen.
        state.pendingElapsedFrames = frames
        // Die veroeffentlichte Spielzeit sofort mitziehen. Der Aufrufer
        // aktualisiert direkt danach Sperrbildschirm und Oberflaeche aus
        // `visualizerState.elapsedTime`; ohne diese Zeile zeigte er dort noch
        // einmal die alte, zu lange Zeit und korrigierte sich erst beim
        // naechsten VU-Takt.
        visualizerState.elapsedTime = Double(frames) / sampleRate
    }
    
    // Wer traegt Mute und Solo fuer diesen sichtbaren Kanal?
    //
    // IT fuehrt beide Schalter am logischen Pattern-Kanal, weil eine Note dort
    // ueber NNA mehrere Stimmen gleichzeitig belegen kann; alle anderen Formate
    // fuehren sie direkt an der einen Stimme des Kanals. Lesen und Schreiben
    // muessen zwingend denselben Traeger treffen — sonst schaltet die
    // Oberflaeche den einen stumm und liest den anderen aus, und der
    // M/S-Schalter zeigt etwas anderes an, als zu hoeren ist. Deshalb steht die
    // Auswahl hier einmal statt viermal.
    private func muteState(at channelIndex: Int) -> ChannelMuteState? {
        guard channelIndex >= 0, channelIndex < channelCount else { return nil }
        if activeMod?.format == .it,
           let states = channels.first?.itVoicePool?.patternChannels,
           channelIndex < states.count {
            return states[channelIndex]
        }
        // channelCount ist in setMod auf die Stimmenzahl begrenzt, der Zugriff
        // liegt damit immer innerhalb von `channels`.
        return channels[channelIndex]
    }

    public func toggleMute(channelIndex: Int) {
        guard let state = muteState(at: channelIndex) else { return }
        state.isMuted.toggle()
        objectWillChange.send()
        // Die Kanal-Streifen beobachten den visualizerState (nicht den Coordinator).
        // Ohne diesen Anstoß aktualisierte sich die M/S-Optik im gestoppten Zustand
        // erst beim nächsten Play (dann tickt der VU-Timer wieder).
        visualizerState.nudge()
    }

    public func toggleSolo(channelIndex: Int) {
        guard let state = muteState(at: channelIndex) else { return }
        state.isSoloed.toggle()
        objectWillChange.send()
        visualizerState.nudge()
    }

    public func isMuted(channelIndex: Int) -> Bool {
        muteState(at: channelIndex)?.isMuted ?? false
    }

    public func isSoloed(channelIndex: Int) -> Bool {
        muteState(at: channelIndex)?.isSoloed ?? false
    }

    @MainActor
    private func updateVULevelsTick() {
        // Steuerungsbefehle auch bei geschlossenem Notenfenster behalten. Ein
        // spaeter geoeffneter Visualizer kann die laufende Wiedergabe nachbilden.
        notePreviewSource?.collectCommands()
        // Hochfrequente Puffer landen im getrennten visualizerState (nicht mehr auf
        // self), damit dieser 30-Hz-Tick nur die Scope-/VU-/Zeit-Subviews neu rendert.
        let vis = self.visualizerState
        let count = min(channelCount, RenderEngine.maxChannels)
        var rawPeaks = [Float](repeating: 0, count: count)
        var newWaves = visualizersVisible
            ? (0..<count).map { _ in [Float](repeating: 0.0, count: 32) }
            : []
        var newMasterOsc = visualizersVisible
            ? [Float](repeating: 0.0, count: 128)
            : []
        let hasFreshSnapshot = visualizationExchange.withLatestSnapshot(channelCount: count) {
            peaks, waves, master in
            for channel in 0..<count {
                rawPeaks[channel] = peaks[channel]
            }
            if visualizersVisible {
                for channel in 0..<count {
                    for sample in 0..<32 {
                        newWaves[channel][sample] = waves[channel * 32 + sample]
                    }
                }
                for sample in 0..<128 {
                    newMasterOsc[sample] = master[sample]
                }
            }
        }
        // Wellenformen duerfen bis zum naechsten Audioblock stehenbleiben. Ein
        // Peak ist dagegen ein Ereignis dieses Blocks: Den gleichen Snapshot
        // mehrfach als neue Attacke anzuwenden verfälscht den VU-Ausschlag.
        if !hasFreshSnapshot {
            rawPeaks = [Float](repeating: 0, count: count)
        }

        var newLevels = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let rawPeak = rawPeaks[i]
            let prev = i < vis.vuLevels.count ? vis.vuLevels[i] : 0
            let attack: Float = 0.35
            let release: Float = 0.08

            let factor = rawPeak > prev ? attack : release
            newLevels[i] = prev + (rawPeak - prev) * factor
        }
        vis.vuLevels = newLevels

        // Level-2-Sparen (Kompaktmodus): Die teure Wellen-/Master-Oszi-Berechnung
        // (count×32 + 128 Kopien pro Tick, je eine Allokation) NUR ausführen, wenn
        // die Oszilloskope überhaupt sichtbar sind. Bei kleinem Fenster sind sie aus
        // der View-Hierarchie entfernt — dann sparen wir diesen CPU-Posten komplett.
        // VU-Pegel (oben, billig), Spielzeit und Songende laufen weiter.
        if visualizersVisible {
            vis.channelWaveforms = newWaves
            vis.masterSamples = newMasterOsc
        }

        // Read progress directly from shared state (100% lock-free, allocation-free)
        if let state = self.playbackState {
            synchronizePlaybackState(state)
            
            let sampleRate = self.audioEngine?.mainMixerNode.outputFormat(forBus: 0).sampleRate ?? 44100.0
            // Liegt ein Uhr-Auftrag an (Track-Loop), zaehlt bereits dieser Wert.
            // Sonst zeigte die Anzeige bis zum naechsten Audio-Callback noch
            // einmal die alte, zu lange Spielzeit.
            let pendingElapsed = state.pendingElapsedFrames
            let elapsed = pendingElapsed != .max
                ? pendingElapsed
                : state.publishedElapsedFrames
            vis.elapsedTime = Double(elapsed) / sampleRate

        }
    }

    // MainActor-Seite des Seek-Handshakes. Solange der Audioblock das Ziel noch
    // nicht bestaetigt hat, bleiben UI-Ziel und altes Endsignal unangetastet.
    // Nach der Bestaetigung stammt Position/Zeile/Tempo aus EINEM atomaren Wort.
    func synchronizePlaybackState(_ state: RealtimePlaybackState) {
        let seekIsPending = pendingSeekSequence.map { !state.isSeekApplied($0) } ?? false
        guard !seekIsPending else { return }

        if pendingSeekSequence != nil {
            pendingSeekSequence = nil
            pendingSeekTransport = nil
        }
        if let transition = state.consumeEndTransition() {
            consumedEndFrame = transition.frame
            consumedEndPosition = transition.position
            consumedEndRow = transition.row
            self.songEndPulse &+= 1
        }

        if let sequence = pendingBPMSequence,
           state.isBPMRequestApplied(sequence) {
            pendingBPMSequence = nil
        }
        if let sequence = pendingSpeedSequence,
           state.isTicksPerRowRequestApplied(sequence) {
            pendingSpeedSequence = nil
        }
        // Die Ack-Acquire-Lesevorgaenge oben stehen bewusst VOR dem Transport:
        // Der Audiothread veroeffentlicht erst diesen Snapshot und danach die
        // Bestaetigung. So kann ein bestaetigter Auftrag nie mit dem alten
        // Transportstand in die UI zurueckgespiegelt werden.
        let transport = state.transportSnapshot
        suppressRealtimeParameterWriteback = true
        defer { suppressRealtimeParameterWriteback = false }
        if self.currentPosition != transport.position {
            self.currentPosition = transport.position
        }
        if self.currentRow != transport.row { self.currentRow = transport.row }
        if pendingBPMSequence == nil, self.bpm != transport.bpm {
            self.bpm = transport.bpm
        }
        if pendingSpeedSequence == nil, self.speed != transport.ticksPerRow {
            self.speed = transport.ticksPerRow
        }
    }
    
    private func startVUUpdates() {
        // Evtl. laufenden Timer ersetzen (z. B. bei Frequenzwechsel Full↔Compact).
        vuUpdateTimer?.invalidate()
        // 30 Hz für flüssige Oszilloskope; im Kompaktmodus 5 Hz (vuUpdateInterval).
        // Jeder Tick schiebt @Published-Werte durch SwiftUI — die Frequenz ist der
        // dominante UI-CPU-Faktor (nicht das Zeichnen), darum im Compact gedrosselt.
        let timer = Timer(timeInterval: vuUpdateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateVULevelsTick()
            }
        }
        // .common statt Default-Mode: der Default-RunLoop-Mode pausiert
        // waehrend Maus-Drags (Slider, Fenster-Resize) — VU, Scopes und die
        // Tracker-Ansicht froren dann ein, obwohl der Ton weiterlief.
        RunLoop.main.add(timer, forMode: .common)
        vuUpdateTimer = timer
    }
    
    private func stopVUUpdates() {
        vuUpdateTimer?.invalidate()
        vuUpdateTimer = nil
        self.visualizerState.vuLevels = [Float](repeating: 0, count: channelCount)
    }
    
    // MARK: - Safe Real-Time Audio Block Construction

    // Einziger Übergang vom plattformneutralen Renderblock zu CoreAudio. Nur
    // AVAudioSourceNode braucht die Darwin-Signatur; alles dahinter (Sequencer,
    // Mixing, Limiter) bleibt plattformneutral und damit unter Linux baubar.
    //
    // Echtzeit-sicher: UnsafeMutableAudioBufferListPointer ist ein reiner
    // Pointer-Wrapper, der aufgerufene Block ist ein bereits erzeugter Closure.
    // Keine Allokation, kein Lock, kein dynamischer Objective-C-Aufruf.
    nonisolated static func makeSourceNodeRenderBlock(
        _ block: @escaping ModuleRenderBlock,
        sleepTimer: SleepTimerSignal? = nil,
        sampleRate: Double = 44_100
    ) -> AVAudioSourceNodeRenderBlock {
        let render: ModuleRenderBlock
        if let sleepTimer {
            let gain = SleepTimerGain(signal: sleepTimer, sampleRate: sampleRate)
            render = { frames, left, right in
                block(frames, left, right)
                gain.process(frames: frames, left: left, right: right)
            }
        } else {
            render = block
        }
        return { _, _, frameCount, outputData -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard buffers.count >= 2,
                  let leftPtr = buffers[0].mData,
                  let rightPtr = buffers[1].mData else {
                return noErr
            }
            render(
                frameCount,
                leftPtr.assumingMemoryBound(to: Float.self),
                rightPtr.assumingMemoryBound(to: Float.self)
            )
            return noErr
        }
    }

    
    // Spielt eine einzelne Instrument-Grundnote in einer EIGENEN, vom Song
    // voellig getrennten Audio-Engine ab. Dadurch klingt die Vorschau auch im
    // gestoppten Zustand (die Song-Engine existiert dann gar nicht) und kapert
    // niemals einen Song-Kanal (frueher wurde channels.last uebernommen und dabei
    // dessen Mute/Solo geloescht).
    public func previewInstrument(index: Int) {
        guard sleepTimer.allowsPlayback() else { return }
        guard let mod = activeMod, index >= 1 && index < mod.instruments.count,
              let inst = mod.instruments[index],
              let selection = mod.previewSelection(instrumentIndex: index) else { return }
        let smp = selection.sample

        // Laufende Vorschau zuerst abbauen — erneuter Klick startet frisch.
        stopPreview()

        // Eigener Kanal, nur fuer die Vorschau. Kein configure()/performTick noetig:
        // renderChannelSample braucht bloss Sample, Periode, sampleSpeed und
        // Lautstaerke — es gibt keinen Sequencer und keine Effekte in der Vorschau.
        let ch = DSPChannel(index: 1)
        ch.instrument = inst
        ch.sample = smp
        ch.volume = Float(smp.volume)
        ch.currentVolume = Float(smp.volume)
        if mod.format == .s3m {
            // C-4 im ST3-Periodenmodell (Key 48) mit Instrument-C2Spd.
            ch.period = DSPChannel.s3mPeriod(key: 48, c2spd: smp.c2spd)
        } else if mod.format == .it {
            // IT stimmt Samples ueber C5Speed. Instrument-Mode kann die
            // Vorschau-Note zusaetzlich per 120er Notemap transponieren.
            ch.period = mod.linearFrequency
                ? DSPChannel.itLinearPeriod(key: selection.targetNote)
                : DSPChannel.itAmigaPeriod(
                    key: selection.targetNote,
                    c5Speed: smp.itProperties?.c5Speed ?? smp.c2spd
                )
        } else if mod.format == .xm {
            // XM stimmt ueber (Note + relativeNote) und Finetune; das
            // Header-Flag waehlt lineare oder Amiga-Perioden. Frueher lief XM
            // im MOD-Zweig darunter und war gegenueber derselben Note im Modul
            // deutlich verstimmt.
            ch.period = RenderEngine.xmPreviewPeriod(
                sample: smp,
                targetNote: selection.targetNote,
                linearFrequency: mod.linearFrequency
            )
        } else {
            // C-3 note period = 214
            ch.period = 214.0 - Float(smp.finetune)
        }
        ch.currentPeriod = ch.period
        ch.sampleIndex = 0.0
        ch.playing = true

        let engine = AVAudioEngine()
        let mixer = engine.mainMixerNode
        var sampleRate = mixer.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0.0 || sampleRate.isNaN || sampleRate.isInfinite { sampleRate = 44100.0 }
        guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }

        // sampleSpeed aus der Periode ableiten — dieselbe Formel wie in
        // performTick (Paula-Frequenz / Ausgabe-Rate). clockRate wie im Song-Pfad:
        // S3M nutzt den festen ST3-Takt, MOD den PAL/NTSC-Amiga-Takt.
        let clockRate = (mod.format == .s3m || mod.format == .it)
            ? 14317056.0
            : (self.palClock ? 3546894.6 : 3579545.25)
        if mod.format == .it {
            ch.sampleSpeed = RenderEngine.itPreviewSampleSpeed(
                sample: smp,
                targetNote: selection.targetNote,
                linearFrequency: mod.linearFrequency,
                sampleRate: sampleRate
            )
        } else if mod.format == .xm {
            // XM-linear rechnet exponentiell, XM-Amiga gegen den
            // FastTracker-II-Takt — beides nicht die Paula-Clock von oben.
            ch.sampleSpeed = RenderEngine.xmPreviewSampleSpeed(
                sample: smp,
                targetNote: selection.targetNote,
                linearFrequency: mod.linearFrequency,
                sampleRate: sampleRate
            )
        } else {
            ch.sampleSpeed = ch.currentPeriod > 0 ? (clockRate / Double(ch.currentPeriod)) / sampleRate : 0.0
        }

        // Frame-Budget: geloopte Samples nach ~1,6 s ausklingen lassen (sonst
        // droehnen sie endlos); nicht-geloopte enden ohnehin von selbst, weil
        // renderChannelSample hinter dem Sample-Ende 0 liefert.
        let voice = PreviewVoice(framesLeft: Int(sampleRate * 1.6))
        let renderBlock = RenderEngine.createPreviewRenderBlock(channel: ch, voice: voice, useInterpolation: self.useInterpolation)

        let sourceNode = AVAudioSourceNode(renderBlock: Self.makeSourceNodeRenderBlock(
            renderBlock, sleepTimer: sleepTimer.signal, sampleRate: sampleRate))
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mixer, format: stereoFormat)
        do {
            guard sleepTimer.allowsPlayback() else { return }
            try engine.start()
            mixer.outputVolume = lastVolume * lastVolume
            self.previewEngine = engine
            self.previewSourceNode = sourceNode
        } catch {
            print("Fehler beim Starten der Preview-Engine: \(error)")
        }
    }


    // Vorschau-Engine abbauen (idempotent). Wird bei erneutem Preview-Klick sowie
    // beim Start/Stopp der Song-Wiedergabe und beim Songwechsel gerufen, damit nie
    // zwei Engines nebeneinander laufen.
    public func stopPreview() {
        if let engine = previewEngine { engine.stop() }
        previewEngine = nil
        previewSourceNode = nil
    }


    nonisolated public func exportActiveModToWav(
        mod: Mod,
        stereoSeparation: Float,
        useInterpolation: Bool,
        palClock: Bool,
        destinationURL: URL,
        durationSeconds: Double = 180.0
    ) throws {
        let sampleRate = 44100.0
        guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw NSError(domain: "ModPlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Konnte Audio-Format nicht erstellen"])
        }
        
        // Ziel-Datei ggf. entfernen, damit AVAudioFile sauber neu schreiben kann.
        // "Datei nicht vorhanden" ist der Normalfall (frischer Save-Panel-Pfad) und
        // wird ignoriert; andere Fehler (z.B. Sandbox-Permissions) werden geloggt,
        // statt sie wie zuvor per try? stillschweigend zu verschlucken.
        do {
            try FileManager.default.removeItem(at: destinationURL)
        } catch CocoaError.fileNoSuchFile {
            // erwartet — Zielpfad war frei
        } catch {
            print("WAV-Export: konnte bestehende Datei nicht entfernen: \(error.localizedDescription)")
        }
        let audioFile = try AVAudioFile(forWriting: destinationURL, settings: stereoFormat.settings)

        let renderChannels = RenderEngine.makeRenderChannels(for: mod)
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: sampleRate)
        state.stereoSeparation = stereoSeparation
        state.useInterpolation = useInterpolation
        state.palClock = palClock

        let channelCount = mod.format == .it
            ? max(1, min(RenderEngine.maxChannels, mod.channelCount))
            : renderChannels.count
        let dummyPeaks = UnsafeMutablePointer<Float>.allocate(capacity: channelCount)
        defer { dummyPeaks.deallocate() }
        for j in 0..<channelCount { dummyPeaks[j] = 0.0 }
        let vuBuffer = RealtimeVUBuffer(pointer: dummyPeaks)

        let dummyWaves = UnsafeMutablePointer<Float>.allocate(capacity: channelCount * 32)
        defer { dummyWaves.deallocate() }
        for j in 0..<(channelCount * 32) { dummyWaves[j] = 0.0 }
        let dummyMasterWaves = UnsafeMutablePointer<Float>.allocate(capacity: 128)
        defer { dummyMasterWaves.deallocate() }
        for j in 0..<128 { dummyMasterWaves[j] = 0.0 }
        let waveBuffer = RealtimeWaveBuffer(channelWaves: dummyWaves, masterWaves: dummyMasterWaves)
        
        let block = RenderEngine.createRenderBlock(
            state: state,
            vuBuffer: vuBuffer,
            waveBuffer: waveBuffer,
            dspChannels: renderChannels,
            mod: mod,
            sampleRate: sampleRate
        )
        
        let blockFrames = UInt32(1024)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: blockFrames) else {
            throw NSError(domain: "ModPlayer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Konnte Buffer nicht erstellen"])
        }
        // stereoFormat ist non-interleaved Float32, floatChannelData liefert also
        // je einen eigenen Puffer für links und rechts — genau das, was der
        // plattformneutrale Renderblock erwartet.
        guard let floatData = pcmBuffer.floatChannelData else {
            throw NSError(domain: "ModPlayer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Kein Float-Puffer verfügbar"])
        }

        let totalFramesToRender = UInt64(sampleRate * durationSeconds)
        var renderedFrames: UInt64 = 0

        while renderedFrames < totalFramesToRender {
            pcmBuffer.frameLength = blockFrames
            block(blockFrames, floatData[0], floatData[1])

            var validFrames = UInt64(blockFrames)
            validFrames = min(validFrames, totalFramesToRender - renderedFrames)
            if state.endReachedFrame != .max {
                validFrames = min(
                    validFrames,
                    state.endReachedFrame > renderedFrames
                        ? state.endReachedFrame - renderedFrames
                        : 0
                )
            }
            pcmBuffer.frameLength = AVAudioFrameCount(validFrames)
            if validFrames > 0 { try audioFile.write(from: pcmBuffer) }
            renderedFrames += validFrames
            
            // Songende: der Render-Block setzt endReached beim Wrap über
            // mod.length (unabhängig von der Pattern-Reihenzahl — die ist bei XM
            // variabel, ein fixes rowIndex>=63 hätte bei kurzen End-Patterns nie
            // ausgelöst). Für den einmaligen Offline-Render (Quick Look / A/B)
            // ist das das saubere Abbruchsignal.
            if state.endReached {
                break
            }
        }
    }

    nonisolated func renderProbe(
        mod: Mod,
        durationSeconds: Double,
        sampleRate: Double = 44100.0
    ) -> [RenderProbeSample] {
        let renderChannels = RenderEngine.makeRenderChannels(for: mod)
        let channelCount = mod.format == .it
            ? max(1, min(RenderEngine.maxChannels, mod.channelCount))
            : renderChannels.count
        let state = RenderEngine.makeRenderState(for: mod, sampleRate: sampleRate)
        state.stereoSeparation = 0.8
        state.useInterpolation = true
        state.palClock = true

        let totalFrames = Int(sampleRate * durationSeconds)
        var samples: [RenderProbeSample] = []
        samples.reserveCapacity(totalFrames / 256)

        for frame in 0..<totalFrames {
            SequencerCore.advanceIfNeeded(
                state: state,
                channels: renderChannels,
                mod: mod,
                sampleRate: sampleRate
            )

            state.outputsUntilNextTick -= 1.0
            state.elapsedFrames += 1

            var channelOutputs = [Float](repeating: 0, count: channelCount)
            let pool = renderChannels.first?.itVoicePool
            let renderedVoiceCount = pool?.usesBackgroundVoices == true
                ? pool!.activeVoiceCount
                : renderChannels.count
            for renderPosition in 0..<renderedVoiceCount {
                let voice = pool?.usesBackgroundVoices == true
                    ? renderChannels[pool!.activeVoiceIndex(at: renderPosition)]
                    : renderChannels[renderPosition]
                let owner = mod.format == .it ? (voice.itPatternState?.channelIndex ?? -1) : voice.channelIndex - 1
                if owner >= 0, owner < channelCount {
                    channelOutputs[owner] += RenderEngine.renderChannelSample(
                        channel: voice,
                        useInterpolation: state.useInterpolation
                    )
                }
            }

            if frame % 256 == 0 {
                let trace = SequencerTraceSnapshot(frame: frame, state: state, mod: mod)
                samples.append(RenderProbeSample(
                    frame: frame,
                    position: state.position,
                    row: state.rowIndex,
                    channelOutputs: channelOutputs,
                    trace: trace
                ))
            }
        }

        return samples
    }


    
    public func exportInstrumentToWav(index: Int, destinationURL: URL) throws {
        guard let mod = activeMod else {
            throw NSError(domain: "ModPlayer", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Kein Modul geladen"])
        }
        try exportInstrumentToWav(mod: mod, index: index, destinationURL: destinationURL)
    }

    public func exportInstrumentToWav(mod: Mod, index: Int, destinationURL: URL) throws {
        guard index >= 1 && index < mod.instruments.count,
              let selection = mod.previewSelection(instrumentIndex: index) else {
            throw NSError(domain: "ModPlayer", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Kein exportierbares Sample ausgewählt"])
        }
        let smp = selection.sample
        let pcm = smp.pcm

        // IT-Samples mit ihrer C5-Bezugsrate exportieren; die bestehenden
        // MOD-/S3M-/XM-Exportregeln bleiben unveraendert.
        let sampleRate = mod.format == .it
            ? Double(smp.itProperties?.c5Speed ?? smp.c2spd)
            : 22050.0
        let channelCount: AVAudioChannelCount = smp.rightPCM == nil ? 1 : 2
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount) else {
            throw NSError(domain: "ModPlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Konnte Sample-Format nicht erstellen"])
        }
        
        // Ziel-Datei ggf. entfernen, damit AVAudioFile sauber neu schreiben kann.
        // "Datei nicht vorhanden" ist der Normalfall (frischer Save-Panel-Pfad) und
        // wird ignoriert; andere Fehler (z.B. Sandbox-Permissions) werden geloggt,
        // statt sie wie zuvor per try? stillschweigend zu verschlucken.
        do {
            try FileManager.default.removeItem(at: destinationURL)
        } catch CocoaError.fileNoSuchFile {
            // erwartet — Zielpfad war frei
        } catch {
            print("WAV-Export: konnte bestehende Datei nicht entfernen: \(error.localizedDescription)")
        }
        let audioFile = try AVAudioFile(forWriting: destinationURL, settings: format.settings)
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(pcm.count)) else {
            throw NSError(domain: "ModPlayer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Konnte Buffer nicht erstellen"])
        }

        pcmBuffer.frameLength = UInt32(pcm.count)
        if let channelData = pcmBuffer.floatChannelData {
            for i in 0..<pcm.count {
                channelData[0][i] = pcm[i]
                if let right = smp.rightPCM {
                    channelData[1][i] = i < right.count ? right[i] : 0
                }
            }
        }
        
        try audioFile.write(from: pcmBuffer)
    }
}

#endif

import Combine
import Foundation
import SavageModPlayerCore

// Die Wiedergabe der iPhone-App. Sie haelt genau einen ModPlayerCoordinator aus
// dem Core (der die eigentliche Audio-Engine und den DSP betreibt) und ergaenzt
// alles, was es nur auf einem Telefon gibt:
//
//  - die AVAudioSession (Ton bei gesperrtem Bildschirm, Anruf, Kopfhoerer),
//  - den Sperrbildschirm mit Titelanzeige und Fernbedienung,
//  - die Abspielreihenfolge samt Loop-Modus und Zufallswiedergabe,
//  - das Merken und Wiederherstellen der letzten Sitzung.
//
// Die Oberflaeche redet ausschliesslich mit dieser Klasse. Sie greift nur fuer
// die Visualisierungen direkt auf `coordinator.visualizerState` und
// `coordinator.transport` zu — das sind bewusst getrennte, hochfrequente
// Zustandsobjekte, damit deren Aktualisierungen nicht die ganze Oberflaeche
// neu zeichnen. Die Begruendung dazu steht ausfuehrlich in VisualizerState.swift.
@MainActor
final class PlaybackEngine: ObservableObject {

    // MARK: - Oeffentlicher Zustand

    // Der Renderkern aus dem Core. Oeffentlich, weil die Visualisierungs-Views
    // seine beiden Unterzustaende direkt beobachten.
    let coordinator = ModPlayerCoordinator()
    let playbackSettings: TrackPlaybackSettingsModel

    @Published private(set) var currentTrack: TrackRef?
    @Published private(set) var loadedModuleID = UUID()

    // "Die Engine laeuft" — auch im pausierten Zustand true. Erst stop() setzt
    // sie zurueck. Dieselbe Bedeutung wie im Core, damit nichts auseinanderlaeuft.
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false

    @Published private(set) var queue: [TrackRef] = []
    @Published private(set) var pendingQueue = TrackQueue()

    // -1 = es ist nichts aus der Liste gewaehlt.
    @Published private(set) var currentIndex = -1

    // Lesbarer Fehlertext fuer einen Hinweis in der Oberflaeche. Die Oberflaeche
    // darf ihn nach dem Anzeigen wieder auf nil setzen, deshalb nicht private(set).
    @Published var errorMessage: String?

    var channelCount: Int { coordinator.channelCount }
    var totalDuration: Double { coordinator.visualizerState.totalDuration }

    // MARK: - Innereien

    private let settings: PlayerSettings
    private let library: LibraryStore
    private let catalog: LibraryCatalogModel?
    private let session = AudioSessionController()
    private let nowPlaying = NowPlayingController()

    private var cancellables = Set<AnyCancellable>()

    // Schreibt einmal pro Sekunde den Sperrbildschirm fort und sichert die
    // Songposition fuer die naechste Sitzung.
    private var heartbeat: Timer?

    // Format des geladenen Moduls — nur fuer die Anzeige (Kuerzel, Titelbild).
    private var activeFormat: ModuleFormat?

    // Haben WIR wegen einer Unterbrechung pausiert? Nur dann darf nach dem Ende
    // der Unterbrechung automatisch weitergespielt werden. Hat der Nutzer selbst
    // pausiert, bleibt die Wiedergabe stehen.
    private var pausedByInterruption = false

    // Der Core kennt keine Abfrage der zuletzt gesetzten Lautstaerke, also
    // spiegeln wir sie hier, um unnoetige Aufrufe zu vermeiden.
    private var appliedVolume: Float = -1

    // Der schnelle Visualizer-Takt braucht zwei gleichzeitig wahre Bedingungen:
    // Die App ist vorn UND der Visualizer-Abschnitt schneidet den sichtbaren
    // Scrollbereich. Die View meldet die zweite Bedingung direkt.
    private var sceneIsActive = true
    private var visualizerSectionIsVisible = false

    // Eigene Schlange fuer Lesen, Parsen und Dauerprobe eines Moduls. Diese
    // drei Schritte dauern bei einem grossen IT oder einer Datei aus der Cloud
    // spuerbar lange; auf dem MainActor friert dabei die Oberflaeche ein und im
    // schlimmsten Fall greift der Watchdog des Systems ein. `userInitiated`,
    // weil am anderen Ende meistens ein Fingertipp auf einen Titel steht.
    private let loader = DispatchQueue(label: "com.viben.SavageModPlayer.moduleLoad", qos: .userInitiated)
    private let readModule: @Sendable (URL) throws -> Data

    // Der laufende Ladeauftrag und sein Abbruchschalter. Ein neuer Auftrag
    // ueberholt den alten: Der alte darf danach weder etwas anzeigen noch
    // abspielen. Wichtig beim Durchtippen von "weiter" — sonst arbeitete die
    // Schlange zehn Ladeauftraege nacheinander ab, bevor der zuletzt gewaehlte
    // Titel klingt.
    private var loadTask: Task<Void, Never>?
    private(set) var requestRevision: UInt64 = 0
    private var loadCancellation: CancellationFlag?
    private var explicitQueuePaths: [String]?
    private var resumeTrackPath: String?
    private var isPlayingQueuedTrack = false

    // MARK: - Aufbau

    init(settings: PlayerSettings, library: LibraryStore, catalog: LibraryCatalogModel? = nil,
         playbackSettings: TrackPlaybackSettingsModel? = nil,
         readModule: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }) {
        self.settings = settings
        self.library = library
        self.catalog = catalog
        self.readModule = readModule
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.playbackSettings = playbackSettings ?? TrackPlaybackSettingsModel(
            fileURL: support.appendingPathComponent("SavageModPlayer/track-playback-settings.json"),
            defaults: settings.playbackOptions, saveDefaults: { [weak settings] in settings?.setPlaybackOptions($0) })
        self.playbackSettings.onResolvedChange = { [weak self] options in self?.applyPlaybackOptions(options) }
        coordinator.onSleepTimerExpired = { [weak self] in self?.stopPlayback() }

        configureSession()
        configureRemoteControl()
        observeCoordinator()
        observeSettings()
        library.favoritesDidChange
            .sink { [weak self] in self?.refreshQueueFromLibrary() }
            .store(in: &cancellables)
        applySettings()
    }

    private func configureSession() {
        session.onEvent = { [weak self] event in
            self?.handleAudioSessionEvent(event)
        }
        // Kategorie und Puffergroesse jetzt setzen, die Session aber erst beim
        // ersten Play aktivieren — sonst wuerde schon der App-Start die Musik
        // einer anderen App abwuergen.
        session.prepare()
    }

    func handleAudioSessionEvent(_ event: AudioSessionController.Event) {
        switch event {
        case .interruptionBegan:
            handleInterruptionBegan()
        case .interruptionEnded(let shouldResume):
            handleInterruptionEnded(shouldResume: shouldResume)
        case .outputDeviceLost:
            handleOutputDeviceLost()
        case .mediaServicesWereReset:
            rebuildAfterMediaServicesReset()
        }
    }

    private func configureRemoteControl() {
        nowPlaying.onCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .play:
                self.play()
            case .pause:
                self.pause()
            case .togglePlayPause:
                self.togglePlayPause()
            case .nextTrack:
                self.next()
            case .previousTrack:
                self.previous()
            case .seek(let seconds):
                self.seek(toSeconds: seconds)
            case .skip(let delta):
                self.skip(bySeconds: delta)
            }
        }
        nowPlaying.activate()
    }

    private func observeCoordinator() {
        // Songende: der Renderblock meldet es ueber einen hochzaehlenden Impuls,
        // den der Core-Timer auf den Hauptthread hebt. dropFirst() ueberspringt
        // den Startwert, den jeder @Published-Datenstrom beim Abonnieren liefert.
        coordinator.$songEndPulse
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.handleSongEnd() }
            }
            .store(in: &cancellables)

        // Der Core kann seinen Wiedergabezustand auch von sich aus aendern (etwa
        // wenn die Audio-Engine nicht startet und er aufraeumt). Damit unsere
        // eigenen Anzeigen und der Sperrbildschirm nicht auseinanderlaufen,
        // spiegeln wir ihn statt ihn nur bei eigenen Aufrufen zu setzen.
        Publishers.Merge(coordinator.$isPlaying, coordinator.$isPaused)
            .sink { [weak self] _ in
                Task { @MainActor in self?.syncTransportState() }
            }
            .store(in: &cancellables)
    }

    private func observeSettings() {
        // PlayerSettings speichert alles per @AppStorage, also direkt in den
        // UserDefaults. Ein solcher Wert meldet KEINE Aenderung an das umgebende
        // Objekt — ein Schalter im Einstellungs-Tab bliebe sonst unhoerbar, bis
        // der naechste Titel geladen wird. Die UserDefaults selbst melden jede
        // Aenderung aber systemweit, und genau darauf hoeren wir hier.
        //
        // `.receive(on: DispatchQueue.main)` ist hier NICHT kosmetisch: die
        // UserDefaults melden ihre Aenderung auf dem Thread, der geschrieben hat
        // — das kann jeder beliebige sein. Diese Klasse ist @MainActor-isoliert,
        // also ist es auch der Sink-Block. Laeuft er auf einem fremden Thread,
        // stellt die Swift-Laufzeit den Isolationsbruch fest und beendet den
        // Prozess mit SIGTRAP, noch bevor das `Task` ueberhaupt startet.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySettings()
            }
            .store(in: &cancellables)
    }

    // MARK: - Einstellungen

    // Klangwerte aus den Einstellungen in den laufenden DSP durchreichen.
    // Jeder Wert wird nur bei echter Aenderung gesetzt: die Eigenschaften des
    // Coordinators sind @Published, ein blindes Zuweisen wuerde also bei jedem
    // beliebigen UserDefaults-Schreibvorgang die Oberflaeche neu zeichnen.
    func applySettings() {
        playbackSettings.updateDefaults(settings.playbackOptions, persist: false)
        applyPlaybackOptions(playbackSettings.effective)
        let volume = Float(settings.volume)
        if appliedVolume != volume {
            appliedVolume = volume
            coordinator.setVolume(volume)
        }
        applyVisualizerState()
    }

    private func applyPlaybackOptions(_ options: PlaybackOptions) {
        let separation = Float(options.stereoSeparation)
        if coordinator.stereoSeparation != separation {
            coordinator.stereoSeparation = separation
        }
        if coordinator.useInterpolation != options.useInterpolation {
            coordinator.useInterpolation = options.useInterpolation
        }
        if coordinator.palClock != options.palClock {
            coordinator.palClock = options.palClock
        }
        if coordinator.ledFilterActive != options.ledFilterActive {
            coordinator.ledFilterActive = options.ledFilterActive
        }
    }

    // MARK: - Abspielliste

    // Aus welcher Auswahl die aktuelle Liste stammt. Wird gebraucht, wenn sich
    // die Bibliothek aendert: Die Liste wird dann aus derselben Auswahl neu
    // gebildet, statt durch den Gesamtbestand ersetzt zu werden.
    private(set) var queueFilter = QueueFilter()

    func setQueue(_ tracks: [TrackRef], filter: QueueFilter = QueueFilter()) {
        explicitQueuePaths = nil
        applyQueue(tracks, filter: filter)
    }

    func setExplicitQueue(_ tracks: [TrackRef]) {
        explicitQueuePaths = tracks.map(\.relativePath)
        applyQueue(tracks, filter: QueueFilter())
    }

    private func applyQueue(_ tracks: [TrackRef], filter: QueueFilter) {
        queueFilter = filter
        queue = tracks
        // Laeuft gerade etwas, das auch in der neuen Liste steht, behaelt es
        // seinen Platz — sonst spraenge "weiter" unerwartet an den Anfang.
        // Andernfalls ist nichts aus der Liste gewaehlt (-1); ein bereits
        // geladener Titel spielt trotzdem zu Ende.
        let path = isPlayingQueuedTrack ? resumeTrackPath : currentTrack?.relativePath
        if let index = tracks.firstIndex(where: { $0.relativePath == path }) {
            currentIndex = index
        } else {
            currentIndex = -1
        }
    }

    // Die Bibliothek hat sich geaendert: Liste aus derselben Auswahl neu bilden.
    //
    // Vorher setzte die Oberflaeche hier stumpf den Gesamtbestand ein. Wer die
    // Wiedergabe aus einer Suche oder aus den Favoriten gestartet hatte, spielte
    // danach durch die ganze Sammlung weiter — schon ein einzelner neuer
    // Favorit reichte dafuer.
    func refreshQueueFromLibrary() {
        if let paths = explicitQueuePaths {
            applyQueue(paths.compactMap { library.track(forRelativePath: $0) }, filter: queueFilter)
            return
        }
        applyQueue(
            library.filteredTracks(
                search: queueFilter.search,
                favoritesOnly: queueFilter.favoritesOnly),
            filter: queueFilter)
    }

    func enqueue(_ track: TrackRef, next: Bool = false) {
        guard let reference = track.playlistReference else { return }
        pendingQueue.enqueue(reference, next: next)
    }

    func removeQueued(id: UUID) { pendingQueue.remove(id: id) }
    func moveQueued(id: UUID, by offset: Int) { pendingQueue.move(id: id, by: offset) }
    func clearQueued() { pendingQueue.removeAll() }

    // MARK: - Titel waehlen

    // Laden und sofort abspielen.
    func play(_ track: TrackRef) {
        coordinator.sleepTimer.prepareForManualPlayback()
        replaceLoadTask { engine, cancellation in
            await engine.start(track, autoPlay: true, cancellation: cancellation)
        }
    }

    // Nur laden, nicht abspielen (z. B. Antippen in der Bibliothek im
    // pausierten Zustand oder das Wiederherstellen der letzten Sitzung).
    func select(_ track: TrackRef) {
        replaceLoadTask { engine, cancellation in
            await engine.start(track, autoPlay: false, cancellation: cancellation)
        }
    }

    // Startet einen Ladevorgang und macht damit jeden vorherigen ungueltig.
    // Alle Einstiege ins Laden gehen hier durch, damit es nie zwei gleichzeitig
    // gueltige Auftraege gibt.
    private func replaceLoadTask(
        _ work: @escaping @MainActor (PlaybackEngine, CancellationFlag) async -> Void
    ) {
        cancelPendingLoad()
        let cancellation = CancellationFlag()
        loadCancellation = cancellation
        loadTask = Task { [weak self] in
            guard let self else { return }
            await work(self, cancellation)
        }
    }

    // Macht einen noch wartenden oder auf der Ladeschlange laufenden Auftrag
    // ungueltig. `Task.cancel()` allein reicht nicht: Die DispatchQueue-Arbeit
    // ist kein Kind-Task und liest deshalb den threadsicheren Schalter.
    private func cancelPendingLoad() {
        requestRevision &+= 1
        loadCancellation?.set()
        loadCancellation = nil
        loadTask?.cancel()
        loadTask = nil
    }

    private func start(_ track: TrackRef, autoPlay: Bool, cancellation: CancellationFlag) async {
        isPlayingQueuedTrack = false
        resumeTrackPath = nil
        if let index = queue.firstIndex(of: track) {
            await activateTrack(at: index, autoPlay: autoPlay, cancellation: cancellation)
            return
        }
        // Der Titel gehoert nicht zur aktuellen Liste (z. B. per "Oeffnen mit"
        // hereingereicht). Dann gibt es kein Weiter/Zurueck, aber abspielen laesst
        // er sich trotzdem.
        switch await loadModule(track, cancellation: cancellation) {
        case .cancelled:
            return
        case .failed(let message):
            errorMessage = message
        case .loaded:
            currentIndex = -1
            if autoPlay { continuePlayback() }
        }
    }

    // Einen Titel aus der Liste laden. Laesst er sich nicht laden (kaputte Datei,
    // fremdes Format), wird er UEBERSPRUNGEN statt die Wiedergabe zu beenden —
    // eine einzelne faule Datei darf einen Abend Musik nicht stoppen. Nach einer
    // vollen Runde durch die Liste wird abgebrochen, damit eine komplett
    // unlesbare Sammlung nicht in einer Endlosschleife landet.
    //
    // `direction` ist die Suchrichtung fuer das Ueberspringen: Bei "Zurueck"
    // (-1) wird absteigend weitergesucht — sonst spraenge die Rueckwaerts-
    // Navigation ueber eine defekte Datei wieder VORWAERTS zum aktuellen Titel.
    private func activateTrack(
        at index: Int,
        direction: Int = 1,
        autoPlay: Bool,
        cancellation: CancellationFlag
    ) async {
        guard !queue.isEmpty else { return }
        let step = direction < 0 ? -1 : 1
        var position = index
        var skipped: [String] = []

        for _ in 0..<queue.count {
            // Zwischen zwei Ladeversuchen liegt ein `await`, und die Liste kann
            // sich in dieser Zeit geaendert haben (die Bibliothek meldet
            // laufend neue Staende). Deshalb wird die Position bei jedem
            // Durchgang neu gegen die aktuelle Laenge gefaltet, statt einmal am
            // Anfang.
            guard !queue.isEmpty else { return }
            let count = queue.count
            position = ((position % count) + count) % count
            let track = queue[position]
            switch await loadModule(track, cancellation: cancellation) {
            case .cancelled:
                // Ein neuerer Auftrag hat uebernommen. Dieser hier darf weder
                // eine Meldung setzen noch etwas abspielen.
                return
            case .loaded:
                isPlayingQueuedTrack = false
                resumeTrackPath = nil
                currentIndex = queue.firstIndex(where: { $0.relativePath == track.relativePath }) ?? -1
                errorMessage = Self.skipMessage(for: skipped)
                if autoPlay { continuePlayback() }
                return
            case .failed:
                skipped.append(track.displayName)
                position += step
            }
        }

        // Kein einziger Titel liess sich laden.
        coordinator.stop()
        currentTrack = nil
        loadedModuleID = UUID()
        currentIndex = -1
        activeFormat = nil
        playbackSettings.setContext(sourceID: nil, format: nil)
        errorMessage = "Kein Titel der Liste liess sich laden."
        updateNowPlaying(force: true)
    }

    private static func skipMessage(for skipped: [String]) -> String? {
        guard !skipped.isEmpty else { return nil }
        if skipped.count == 1 {
            return "„\(skipped[0])“ liess sich nicht laden und wurde übersprungen."
        }
        return "\(skipped.count) Titel liessen sich nicht laden und wurden übersprungen."
    }

    // Wie ein Ladeversuch ausging.
    private enum LoadOutcome {
        case loaded
        case failed(String)
        // Ein neuerer Ladeauftrag hat uebernommen. Kein Fehler — und vor allem
        // kein Grund, irgendetwas anzuzeigen oder abzuspielen.
        case cancelled
    }

    // Das Ergebnis der Hintergrundarbeit. `Sendable`, weil es die Schlange
    // verlaesst; `Mod` ist ein Wertetyp aus dem Core und selbst `Sendable`.
    private enum PreparedModule: Sendable {
        case ready(mod: Mod, duration: Double)
        case failed(String)
        case cancelled
    }

    // Modul einlesen und dem Core uebergeben.
    //
    // Lesen, Parsen und Dauerprobe laufen auf der Ladeschlange; nur die
    // Uebergabe an den Coordinator und die Zustandspflege bleiben auf dem
    // MainActor. Was der abgebrochene Auftrag dort schon angefangen hatte,
    // laesst sich nicht mitten im Lesen stoppen — sein Ergebnis wird aber
    // verworfen, und der naechste Schritt beginnt gar nicht erst.
    private func loadModule(_ track: TrackRef, cancellation: CancellationFlag) async -> LoadOutcome {
        let url = track.url
        let readModule = self.readModule
        let prepared = await onLoader {
            Self.prepare(url, readModule: readModule, isCancelled: { cancellation.isSet })
        }
        coordinator.sleepTimer.refresh()
        // Zwischen Schlange und MainActor kann der Auftrag ueberholt worden
        // sein. Ab hier wird Zustand veraendert — also noch einmal pruefen.
        guard !cancellation.isSet else { return .cancelled }

        switch prepared {
        case .cancelled:
            return .cancelled
        case .failed(let reason):
            return .failed("„\(track.displayName)“ konnte nicht geladen werden: \(reason)")
        case .ready(let mod, let duration):
            let fallbackName = (track.displayName as NSString).deletingPathExtension
            // Die Dauer ist schon gemessen; setMod muss den Sequencer dafuer
            // nicht noch einmal auf dem MainActor durchtakten.
            coordinator.setMod(mod, fallbackName: fallbackName, precomputedDuration: duration)
            loadedModuleID = UUID()

            activeFormat = mod.format
            currentTrack = track
            playbackSettings.setContext(sourceID: track.relativePath, format: mod.format, sourceDescription: track.relativePath)
            // Klangeinstellungen gelten auch fuer den frisch geladenen Song.
            applySettings()

            // Sitzung fortschreiben: dieser Titel ist jetzt der zuletzt gespielte.
            settings.lastPlayedRelativePath = track.relativePath
            settings.lastPlayedPosition = 0

            updateNowPlaying(force: true)
            return .loaded
        }
    }

    // Der teure Teil, ausserhalb des MainActor: Datei lesen, parsen, Spieldauer
    // ermitteln. Zwischen den Schritten wird jeweils geprueft, ob der Auftrag
    // noch gilt — vor allem vor der Dauerprobe, die den Sequencer einmal
    // komplett durchtaktet.
    private nonisolated static func prepare(
        _ url: URL,
        readModule: (URL) throws -> Data,
        isCancelled: () -> Bool
    ) -> PreparedModule {
        guard !isCancelled() else { return .cancelled }
        // Dateien aus der Dateien-App oder von einem Cloud-Anbieter liegen
        // ausserhalb des App-Containers; ohne dieses Paar bleibt der Zugriff
        // verwehrt. Bei Dateien aus der eigenen Bibliothek liefert der Aufruf
        // schlicht false und das defer tut nichts.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try readModule(url)
            guard !isCancelled() else { return .cancelled }
            // ModuleLoader erkennt MOD, S3M, XM und IT am Inhalt, nicht an der
            // Dateiendung — auf Modulsammlungen ist die Endung oft falsch.
            let mod = try ModuleLoader.parse(data: data)
            guard !isCancelled() else { return .cancelled }
            return .ready(mod: mod, duration: RenderEngine.sequencedDuration(of: mod))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // Fuehrt einen Block auf der Ladeschlange aus und wartet auf sein Ergebnis,
    // ohne den MainActor zu blockieren — dasselbe Muster wie `onWorker` im
    // Bibliotheks-Teil.
    private func onLoader<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
            loader.async {
                continuation.resume(returning: work())
            }
        }
    }

    // MARK: - Transport

    func togglePlayPause() {
        guard coordinator.activeMod != nil else { return }
        if coordinator.isPlaying && !coordinator.isPaused {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard coordinator.activeMod != nil else { return }
        coordinator.sleepTimer.prepareForManualPlayback()
        continuePlayback()
    }

    private func continuePlayback() {
        guard coordinator.activeMod != nil, coordinator.sleepTimer.allowsPlayback() else { return }
        // Erst jetzt die Session anmelden — ab hier gehoert die Tonausgabe uns.
        session.activate()
        pausedByInterruption = false
        if coordinator.isPaused {
            coordinator.resume()
        } else if !coordinator.isPlaying {
            coordinator.play()
        }
        if coordinator.isPlaying && !coordinator.isPaused, let track = currentTrack {
            catalog?.markHeard(track.relativePath)
        }
        updateNowPlaying(force: true)
    }

    func startSectionLoop(_ section: SongSection) {
        guard coordinator.activeMod != nil else { return }
        coordinator.sleepTimer.prepareForManualPlayback()
        cancelPendingLoad()
        coordinator.startSectionLoop(section) { [weak self] in
            guard let self, self.coordinator.sleepTimer.allowsPlayback() else { return }
            self.session.activate()
            self.pausedByInterruption = false
        }
    }

    func pause() {
        cancelPendingLoad()
        pausedByInterruption = false
        coordinator.pause()
        persistPlaybackPosition()
        updateNowPlaying(force: true)
    }

    func stop() {
        coordinator.sleepTimer.cancel()
        stopPlayback()
    }

    // Auch natürliches Songende und Timerablauf stoppen die Ausgabe, ohne die
    // Deadline zu quittieren. Nur der ausdrückliche Stop-Button löscht den Timer.
    private func stopPlayback() {
        // Stop bedeutet auch: Ein eben angetippter, noch ladender Titel darf
        // nicht nach diesem Aufruf verspaetet die Wiedergabe starten.
        cancelPendingLoad()
        pausedByInterruption = false
        coordinator.stop()
        persistPlaybackPosition()
        // Session freigeben und andere Apps informieren, dass sie ihre eigene
        // Wiedergabe fortsetzen duerfen.
        session.deactivate()
        syncTransportState()
    }

    func next() {
        advance(step: 1, automatic: false)
    }

    func previous() {
        advance(step: -1, automatic: false)
    }

    // Ein Schritt vor oder zurueck. `automatic` unterscheidet den Songwechsel am
    // Songende vom bewussten Antippen: manuell wird immer gespielt, wenn vorher
    // gespielt wurde, und am Listenrand wird umgebrochen.
    private func advance(step: Int, automatic: Bool) {
        if automatic && !coordinator.sleepTimer.allowsPlayback() { return }
        guard !queue.isEmpty || !pendingQueue.items.isEmpty else { return }
        // setMod() im Ladepfad ruft stop(), also VOR dem Wechsel merken, ob
        // gerade wirklich gespielt wurde (pausiert zaehlt nicht als spielend).
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        let shouldPlay = wasPlaying || automatic

        // Die Warteschlange laedt zuerst. Danach wird die aktuelle Liste am
        // gemerkten Anker fortgesetzt, auch nach einem Bibliotheksabgleich.
        replaceLoadTask { engine, cancellation in
            var skipped: String?
            if step > 0 {
                let outcome = await engine.activateQueued(autoPlay: shouldPlay, cancellation: cancellation)
                if outcome.handled { return }
                skipped = outcome.message
            }
            guard !cancellation.isSet else { return }
            guard !engine.queue.isEmpty else {
                if automatic { engine.stopPlayback() }
                if let skipped { engine.errorMessage = skipped }
                return
            }
            let target: Int
            let direction: Int
            if engine.settings.shuffleEnabled {
                target = engine.randomIndex(excluding: engine.currentIndex)
                direction = 1
            } else {
                let next = engine.currentIndex + step
                target = (next >= 0 && next < engine.queue.count) ? next : (next < 0 ? engine.queue.count - 1 : 0)
                direction = step
            }
            await engine.activateTrack(
                at: target, direction: direction, autoPlay: shouldPlay, cancellation: cancellation)
            if !cancellation.isSet, engine.errorMessage == nil { engine.errorMessage = skipped }
        }
    }

    private func activateQueued(autoPlay: Bool, cancellation: CancellationFlag) async
        -> (handled: Bool, message: String?) {
        let anchor = isPlayingQueuedTrack ? resumeTrackPath
            : (queue.indices.contains(currentIndex) ? queue[currentIndex].relativePath : nil)
        var skipped: [String] = []
        while let item = pendingQueue.items.first {
            guard !cancellation.isSet else { return (true, nil) }
            guard let path = item.track.source.libraryRelativePath,
                  let track = library.track(forRelativePath: path) else {
                pendingQueue.remove(id: item.id)
                skipped.append(item.track.displayName)
                continue
            }
            switch await loadModule(track, cancellation: cancellation) {
            case .cancelled: return (true, nil)
            case .failed:
                pendingQueue.remove(id: item.id)
                skipped.append(track.displayName)
            case .loaded:
                pendingQueue.remove(id: item.id)
                isPlayingQueuedTrack = true
                resumeTrackPath = anchor
                currentIndex = queue.firstIndex { $0.relativePath == anchor } ?? -1
                errorMessage = Self.queuedSkipMessage(skipped)
                if autoPlay { continuePlayback() }
                return (true, nil)
            }
        }
        return (false, Self.queuedSkipMessage(skipped))
    }

    private static func queuedSkipMessage(_ skipped: [String]) -> String? {
        guard !skipped.isEmpty else { return nil }
        return String(localized: "queue.skipped") + " " + skipped.joined(separator: ", ")
    }

    // Zufaelliger Titel, aber nie derselbe zweimal hintereinander — solange die
    // Liste mehr als einen Eintrag hat. Sonst faende ein Nutzer die
    // Zufallswiedergabe schlicht kaputt.
    private func randomIndex(excluding current: Int) -> Int {
        guard queue.count > 1 else { return 0 }
        var index = current
        while index == current {
            index = Int.random(in: 0..<queue.count)
        }
        return index
    }

    // Wird ausgeloest, wenn der Renderblock das Songende erreicht hat.
    private func handleSongEnd() {
        guard coordinator.isPlaying, !coordinator.isPaused, coordinator.sleepTimer.allowsPlayback() else { return }
        if !pendingQueue.items.isEmpty || isPlayingQueuedTrack {
            if queue.isEmpty && pendingQueue.items.isEmpty { stopPlayback(); return }
            advance(step: 1, automatic: true)
            return
        }
        switch settings.loopMode {
        case .track:
            // Der Renderblock springt am Songende von selbst zurueck zum
            // Neustartpunkt. Nur die Anzeige-Uhr muss mit: elapsedFrames
            // zaehlte sonst weiter, und UI-/Sperrbildschirm-Spielzeit
            // ueberholten ab der zweiten Runde die Titeldauer.
            coordinator.resetElapsedToLoopStart()
        case .playlist:
            advance(step: 1, automatic: true)
        case LoopMode.none:
            coordinator.stop()
            session.deactivate()
        }
        updateNowPlaying(force: true)
    }

    // MARK: - Springen

    func seek(toPosition position: Int) {
        coordinator.seek(toPosition: position)
        persistPlaybackPosition()
        updateNowPlaying(force: true)
    }

    func seek(to address: SongAddress) {
        coordinator.seek(toPosition: address.position, row: address.row)
        persistPlaybackPosition()
        updateNowPlaying(force: true)
    }

    // Relativ springen (die −15 s / +30 s der Fernbedienung).
    func skip(bySeconds delta: Double) {
        coordinator.seek(bySeconds: delta)
        persistPlaybackPosition()
        updateNowPlaying(force: true)
    }

    // Absolut springen. Der Core kennt nur relative Zeitspruenge, deshalb wird
    // aus der Zielzeit die Differenz zur aktuellen Spielzeit gebildet.
    private func seek(toSeconds seconds: Double) {
        let elapsed = coordinator.visualizerState.elapsedTime
        skip(bySeconds: seconds - elapsed)
    }

    // MARK: - Kanaele

    func toggleMute(channelIndex: Int) {
        coordinator.toggleMute(channelIndex: channelIndex)
    }

    func toggleSolo(channelIndex: Int) {
        coordinator.toggleSolo(channelIndex: channelIndex)
    }

    // MARK: - Sichtbarkeit der Visualisierungen

    // false = App im Hintergrund oder Bildschirm gesperrt.
    //
    // Der Ton laeuft weiter (dafuer sorgen UIBackgroundModes und die
    // .playback-Kategorie), aber der Core drosselt seinen Aktualisierungs-Takt
    // von 30 Hz auf ~5 Hz und laesst die teure Wellenform-Berechnung ganz weg.
    // Das ist der eigentliche Hebel: nicht das Weglassen der Zeichnungen kostet,
    // sondern die 30 Zustandsaenderungen pro Sekunde, die durch die Oberflaeche
    // laufen. Die ausfuehrliche Begruendung steht bei `visualizersVisible` in
    // ModPlayerCoordinator.swift.
    func setSceneActive(_ active: Bool) {
        if !active { playbackSettings.flush() }
        coordinator.sleepTimer.refresh()
        guard sceneIsActive != active else { return }
        sceneIsActive = active
        applyVisualizerState()
    }

    // Kommt direkt von der Geometrie des Wiedergabe-Tabs. Beim Herausscrollen
    // verschwinden Timeline-/Canvas-Views und die Wellenform-Caches werden im
    // Core freigegeben; beim Hineinscrollen beginnt der naechste Tick sofort
    // wieder mit echten Samples.
    func setVisualizerSectionVisible(_ visible: Bool) {
        guard visualizerSectionIsVisible != visible else { return }
        visualizerSectionIsVisible = visible
        applyVisualizerState()
    }

    // Sichtbare App UND sichtbarer Scrollabschnitt — nur dann laeuft der
    // schnelle Takt des Cores.
    private func applyVisualizerState() {
        let active = sceneIsActive && visualizerSectionIsVisible
        guard coordinator.visualizersVisible != active else { return }
        coordinator.visualizersVisible = active
    }

    // MARK: - Sitzung

    // Den zuletzt gespielten Titel wieder auswaehlen — ohne ihn abzuspielen.
    // Die Liste muss vorher ueber setQueue(_:) gesetzt worden sein.
    func restoreSession() {
        let path = settings.lastPlayedRelativePath
        guard !path.isEmpty,
              let index = queue.firstIndex(where: { $0.relativePath == path }) else { return }

        // Position VOR dem Laden merken: loadModule setzt sie fuer einen frisch
        // gewaehlten Titel auf 0 zurueck.
        let savedPosition = settings.lastPlayedPosition
        replaceLoadTask { engine, cancellation in
            await engine.activateTrack(at: index, autoPlay: false, cancellation: cancellation)
            // Nur weitermachen, wenn genau dieser Titel geladen wurde. Ein
            // abgebrochener oder uebersprungener Auftrag darf die gespeicherte
            // Position nicht auf einen anderen Song anwenden.
            guard !cancellation.isSet, engine.currentTrack?.relativePath == path else { return }
            if savedPosition > 0 {
                engine.coordinator.seek(toPosition: savedPosition)
            }
            engine.persistPlaybackPosition()
            engine.updateNowPlaying(force: true)
        }
    }

    private func persistPlaybackPosition() {
        let position = coordinator.currentPosition
        if settings.lastPlayedPosition != position {
            settings.lastPlayedPosition = position
        }
    }

    // MARK: - Sperrbildschirm

    private func updateNowPlaying(force: Bool) {
        guard let track = currentTrack, coordinator.activeMod != nil else {
            nowPlaying.clear()
            updateHeartbeat()
            return
        }
        let info = NowPlayingController.TrackInfo(
            title: coordinator.trackName,
            formatLabel: Self.formatLabel(activeFormat),
            formatDescription: activeFormat?.displayName ?? "Tracker-Modul",
            folderPath: track.folderPath.joined(separator: " › "),
            duration: coordinator.visualizerState.totalDuration
        )
        nowPlaying.update(
            info: info,
            isPlaying: coordinator.isPlaying,
            isPaused: coordinator.isPaused,
            elapsed: coordinator.visualizerState.elapsedTime,
            force: force
        )
        updateHeartbeat()
    }

    // Kurzes Kuerzel fuers Titelbild. Die MOD-Spielarten (ProTracker,
    // Soundtracker, Multichannel) sind fuer den Nutzer alle "MOD".
    private static func formatLabel(_ format: ModuleFormat?) -> String {
        switch format {
        case .protracker, .soundtracker, .multichannel: return "MOD"
        case .s3m: return "S3M"
        case .xm: return "XM"
        case .it: return "IT"
        case nil: return "MOD"
        }
    }

    private func syncTransportState() {
        let playing = coordinator.isPlaying
        let paused = coordinator.isPaused
        if isPlaying != playing { isPlaying = playing }
        if isPaused != paused { isPaused = paused }
        if coordinator.sectionLoopIsActive, playing, !paused, let track = currentTrack {
            catalog?.markHeard(track.relativePath)
        }
        updateNowPlaying(force: true)
    }

    // Ein Takt pro Sekunde, solange wirklich gespielt wird. Er haelt die
    // verstrichene Zeit im Sperrbildschirm nach und sichert die Songposition
    // fuer die naechste Sitzung. Bewusst nicht schneller: haeufigere Schreib-
    // vorgaenge waeren unsichtbar und wuerden nur Akku kosten.
    private func updateHeartbeat() {
        let shouldRun = coordinator.isPlaying && !coordinator.isPaused
        if shouldRun {
            guard heartbeat == nil else { return }
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.heartbeatTick() }
            }
            // .common statt Standardmodus: waehrend der Nutzer einen Regler
            // zieht, pausiert der Standardmodus — die Anzeige wuerde einfrieren.
            RunLoop.main.add(timer, forMode: .common)
            heartbeat = timer
        } else {
            heartbeat?.invalidate()
            heartbeat = nil
        }
    }

    private func heartbeatTick() {
        updateNowPlaying(force: false)
        persistPlaybackPosition()
    }

    // MARK: - Systemereignisse

    private func handleInterruptionBegan() {
        cancelPendingLoad()
        if coordinator.sectionLoopIsPreparing { coordinator.cancelSectionLoop() }
        // Anruf, Wecker, Siri: iOS hat die Engine bereits angehalten. Wir ziehen
        // den eigenen Zustand nach und merken uns, dass WIR nicht schuld sind —
        // nur dann darf spaeter automatisch fortgesetzt werden.
        guard coordinator.isPlaying, !coordinator.isPaused else { return }
        coordinator.pause()
        pausedByInterruption = true
        persistPlaybackPosition()
        updateNowPlaying(force: true)
    }

    private func handleInterruptionEnded(shouldResume: Bool) {
        guard coordinator.sleepTimer.allowsPlayback() else { return }
        guard pausedByInterruption else { return }
        pausedByInterruption = false
        // Ohne die Empfehlung des Systems bleibt die Wiedergabe stehen. Der
        // Nutzer telefoniert vielleicht noch oder hoert inzwischen etwas anderes.
        guard shouldResume else {
            updateNowPlaying(force: true)
            return
        }
        session.activate()
        coordinator.resume()
        updateNowPlaying(force: true)
    }

    private func handleOutputDeviceLost() {
        cancelPendingLoad()
        if coordinator.sectionLoopIsPreparing { coordinator.cancelSectionLoop() }
        pausedByInterruption = false
        // Kopfhoerer abgezogen. Hier wird bewusst NICHT gemerkt, dass wir
        // pausiert haben: die Musik darf spaeter nicht von selbst wieder
        // losbrechen, schon gar nicht ueber den Lautsprecher.
        guard coordinator.isPlaying, !coordinator.isPaused else { return }
        coordinator.pause()
        persistPlaybackPosition()
        updateNowPlaying(force: true)
    }

    // iOS hat den Audio-Dienst neu gestartet. Danach sind AVAudioEngine, der
    // Quellknoten und der Tiefpass-Knoten des LED-Filters allesamt tot — sie
    // lassen sich nicht reparieren, nur neu bauen. Genau das passiert hier:
    // Titel neu laden, an die alte Stelle springen, den Zustand play/pause
    // beibehalten. Stehenbleiben waere fuer den Nutzer nicht erklaerbar.
    private func rebuildAfterMediaServicesReset() {
        let allowsPlayback = coordinator.sleepTimer.allowsPlayback()
        let wasPlaying = allowsPlayback && coordinator.isPlaying && !coordinator.isPaused
        let wasPaused = allowsPlayback && coordinator.isPaused
        let position = coordinator.currentPosition
        let row = max(0, coordinator.currentRow)
        let track = currentTrack

        coordinator.stop()
        heartbeat?.invalidate()
        heartbeat = nil

        // Session komplett neu konfigurieren und die Fernbedienung neu anmelden.
        session.invalidateConfiguration()
        session.prepare()
        nowPlaying.activate()

        guard allowsPlayback, let track else {
            updateNowPlaying(force: true)
            return
        }
        replaceLoadTask { engine, cancellation in
            switch await engine.loadModule(track, cancellation: cancellation) {
            case .cancelled:
                return
            case .failed(let message):
                engine.errorMessage = message
                return
            case .loaded:
                break
            }
            // seek(toPosition:row:) merkt sich im gestoppten Zustand das Ziel; der
            // naechste play()-Aufruf baut die Engine samt Tiefpass dort neu auf.
            engine.coordinator.seek(toPosition: position, row: row)
            // Die rekonstruierte Position sofort sichern: loadModule hat sie eben
            // auf 0 gesetzt, und im pausierten Zustand laeuft kein Heartbeat —
            // ein App-Neustart nach dem Reset starte sonst faelschlich bei 0.
            engine.persistPlaybackPosition()

            if wasPlaying || wasPaused {
                engine.continuePlayback()
                if wasPaused { engine.coordinator.pause() }
            }
            engine.updateNowPlaying(force: true)
        }
    }
}

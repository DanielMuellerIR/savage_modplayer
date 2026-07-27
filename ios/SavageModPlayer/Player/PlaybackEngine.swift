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

    @Published private(set) var currentTrack: TrackRef?

    // "Die Engine laeuft" — auch im pausierten Zustand true. Erst stop() setzt
    // sie zurueck. Dieselbe Bedeutung wie im Core, damit nichts auseinanderlaeuft.
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false

    @Published private(set) var queue: [TrackRef] = []

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

    // MARK: - Aufbau

    init(settings: PlayerSettings, library: LibraryStore) {
        self.settings = settings
        self.library = library

        configureSession()
        configureRemoteControl()
        observeCoordinator()
        observeSettings()
        applySettings()
    }

    private func configureSession() {
        session.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .interruptionBegan:
                self.handleInterruptionBegan()
            case .interruptionEnded(let shouldResume):
                self.handleInterruptionEnded(shouldResume: shouldResume)
            case .outputDeviceLost:
                self.handleOutputDeviceLost()
            case .mediaServicesWereReset:
                self.rebuildAfterMediaServicesReset()
            }
        }
        // Kategorie und Puffergroesse jetzt setzen, die Session aber erst beim
        // ersten Play aktivieren — sonst wuerde schon der App-Start die Musik
        // einer anderen App abwuergen.
        session.prepare()
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
        let separation = Float(settings.stereoSeparation)
        if coordinator.stereoSeparation != separation {
            coordinator.stereoSeparation = separation
        }
        if coordinator.useInterpolation != settings.useInterpolation {
            coordinator.useInterpolation = settings.useInterpolation
        }
        if coordinator.palClock != settings.palClock {
            coordinator.palClock = settings.palClock
        }
        if coordinator.ledFilterActive != settings.ledFilterActive {
            coordinator.ledFilterActive = settings.ledFilterActive
        }
        let volume = Float(settings.volume)
        if appliedVolume != volume {
            appliedVolume = volume
            coordinator.setVolume(volume)
        }
        applyVisualizerState()
    }

    // MARK: - Abspielliste

    func setQueue(_ tracks: [TrackRef]) {
        queue = tracks
        // Laeuft gerade etwas, das auch in der neuen Liste steht, behaelt es
        // seinen Platz — sonst spraenge "weiter" unerwartet an den Anfang.
        // Andernfalls ist nichts aus der Liste gewaehlt (-1); ein bereits
        // geladener Titel spielt trotzdem zu Ende.
        if let track = currentTrack, let index = tracks.firstIndex(of: track) {
            currentIndex = index
        } else {
            currentIndex = -1
        }
    }

    // MARK: - Titel waehlen

    // Laden und sofort abspielen.
    func play(_ track: TrackRef) {
        start(track, autoPlay: true)
    }

    // Nur laden, nicht abspielen (z. B. Antippen in der Bibliothek im
    // pausierten Zustand oder das Wiederherstellen der letzten Sitzung).
    func select(_ track: TrackRef) {
        start(track, autoPlay: false)
    }

    private func start(_ track: TrackRef, autoPlay: Bool) {
        if let index = queue.firstIndex(of: track) {
            activateTrack(at: index, autoPlay: autoPlay)
            return
        }
        // Der Titel gehoert nicht zur aktuellen Liste (z. B. per "Oeffnen mit"
        // hereingereicht). Dann gibt es kein Weiter/Zurueck, aber abspielen laesst
        // er sich trotzdem.
        if let message = loadModule(track) {
            errorMessage = message
            return
        }
        currentIndex = -1
        if autoPlay { play() }
    }

    // Einen Titel aus der Liste laden. Laesst er sich nicht laden (kaputte Datei,
    // fremdes Format), wird er UEBERSPRUNGEN statt die Wiedergabe zu beenden —
    // eine einzelne faule Datei darf einen Abend Musik nicht stoppen. Nach einer
    // vollen Runde durch die Liste wird abgebrochen, damit eine komplett
    // unlesbare Sammlung nicht in einer Endlosschleife landet.
    private func activateTrack(at index: Int, autoPlay: Bool) {
        guard !queue.isEmpty else { return }
        var position = ((index % queue.count) + queue.count) % queue.count
        var skipped: [String] = []

        for _ in 0..<queue.count {
            let track = queue[position]
            if loadModule(track) == nil {
                currentIndex = position
                errorMessage = Self.skipMessage(for: skipped)
                if autoPlay { play() }
                return
            }
            skipped.append(track.displayName)
            position = (position + 1) % queue.count
        }

        // Kein einziger Titel liess sich laden.
        coordinator.stop()
        currentTrack = nil
        currentIndex = -1
        activeFormat = nil
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

    // Modul einlesen und dem Core uebergeben. Rueckgabe: nil bei Erfolg, sonst
    // ein lesbarer Fehlertext.
    private func loadModule(_ track: TrackRef) -> String? {
        let url = track.url
        // Dateien aus der Dateien-App oder von einem Cloud-Anbieter liegen
        // ausserhalb des App-Containers; ohne dieses Paar bleibt der Zugriff
        // verwehrt. Bei Dateien aus der eigenen Bibliothek liefert der Aufruf
        // schlicht false und das defer tut nichts.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            // ModuleLoader erkennt MOD, S3M, XM und IT am Inhalt, nicht an der
            // Dateiendung — auf Modulsammlungen ist die Endung oft falsch.
            let mod = try ModuleLoader.parse(data: data)
            let fallbackName = (track.displayName as NSString).deletingPathExtension
            coordinator.setMod(mod, fallbackName: fallbackName)

            activeFormat = mod.format
            currentTrack = track
            // Klangeinstellungen gelten auch fuer den frisch geladenen Song.
            applySettings()

            // Sitzung fortschreiben: dieser Titel ist jetzt der zuletzt gespielte.
            settings.lastPlayedRelativePath = track.relativePath
            settings.lastPlayedPosition = 0

            updateNowPlaying(force: true)
            return nil
        } catch {
            return "„\(track.displayName)“ konnte nicht geladen werden: \(error.localizedDescription)"
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
        // Erst jetzt die Session anmelden — ab hier gehoert die Tonausgabe uns.
        session.activate()
        pausedByInterruption = false
        if coordinator.isPaused {
            coordinator.resume()
        } else if !coordinator.isPlaying {
            coordinator.play()
        }
        updateNowPlaying(force: true)
    }

    func pause() {
        pausedByInterruption = false
        coordinator.pause()
        persistPlaybackPosition()
        updateNowPlaying(force: true)
    }

    func stop() {
        pausedByInterruption = false
        coordinator.stop()
        persistPlaybackPosition()
        // Session freigeben und andere Apps informieren, dass sie ihre eigene
        // Wiedergabe fortsetzen duerfen.
        session.deactivate()
        updateNowPlaying(force: true)
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
        guard !queue.isEmpty else { return }
        // setMod() im Ladepfad ruft stop(), also VOR dem Wechsel merken, ob
        // gerade wirklich gespielt wurde (pausiert zaehlt nicht als spielend).
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        let shouldPlay = wasPlaying || automatic

        if settings.shuffleEnabled {
            activateTrack(at: randomIndex(excluding: currentIndex), autoPlay: shouldPlay)
            return
        }

        let target = currentIndex + step
        if target >= 0 && target < queue.count {
            activateTrack(at: target, autoPlay: shouldPlay)
            return
        }
        // Am Rand der Liste von der anderen Seite weitermachen.
        activateTrack(at: target < 0 ? queue.count - 1 : 0, autoPlay: shouldPlay)
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
        switch settings.loopMode {
        case .track:
            // Nichts zu tun: der Renderblock springt am Songende von selbst
            // zurueck auf Position 0 und spielt denselben Titel weiter.
            break
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
        activateTrack(at: index, autoPlay: false)
        guard currentIndex == index else { return }
        if savedPosition > 0 {
            coordinator.seek(toPosition: savedPosition)
        }
        persistPlaybackPosition()
        updateNowPlaying(force: true)
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
        // Kopfhoerer abgezogen. Hier wird bewusst NICHT gemerkt, dass wir
        // pausiert haben: die Musik darf spaeter nicht von selbst wieder
        // losbrechen, schon gar nicht ueber den Lautsprecher.
        guard coordinator.isPlaying, !coordinator.isPaused else { return }
        coordinator.pause()
        pausedByInterruption = false
        persistPlaybackPosition()
        updateNowPlaying(force: true)
    }

    // iOS hat den Audio-Dienst neu gestartet. Danach sind AVAudioEngine, der
    // Quellknoten und der Tiefpass-Knoten des LED-Filters allesamt tot — sie
    // lassen sich nicht reparieren, nur neu bauen. Genau das passiert hier:
    // Titel neu laden, an die alte Stelle springen, den Zustand play/pause
    // beibehalten. Stehenbleiben waere fuer den Nutzer nicht erklaerbar.
    private func rebuildAfterMediaServicesReset() {
        let wasPlaying = coordinator.isPlaying && !coordinator.isPaused
        let wasPaused = coordinator.isPaused
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

        guard let track else {
            updateNowPlaying(force: true)
            return
        }
        if let message = loadModule(track) {
            errorMessage = message
            return
        }
        // seek(toPosition:row:) merkt sich im gestoppten Zustand das Ziel; der
        // naechste play()-Aufruf baut die Engine samt Tiefpass dort neu auf.
        coordinator.seek(toPosition: position, row: row)

        if wasPlaying || wasPaused {
            play()
            if wasPaused { coordinator.pause() }
        }
        updateNowPlaying(force: true)
    }
}

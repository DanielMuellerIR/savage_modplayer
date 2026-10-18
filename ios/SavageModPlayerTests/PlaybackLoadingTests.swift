import XCTest
@testable import SavageModPlayerCore
@testable import SavageModPlayer

/// Der Ladepfad der Wiedergabe — headless im Simulator.
///
/// Hintergrund (2026-08-23): Lesen, Parsen und Dauerprobe liefen synchron auf
/// dem MainActor. Ein grosses IT oder eine Datei aus der Cloud fror damit die
/// Oberflaeche ein. Seither laeuft der teure Teil auf einer eigenen Schlange,
/// und nur das Ergebnis des juengsten Auftrags wird uebernommen.
///
/// Die Tests pruefen genau diesen Vertrag, und zwar ohne Zeitmessung:
/// * Laden kehrt sofort zurueck und wirkt erst spaeter.
/// * Ein neuer Auftrag ueberholt den alten.
/// * Ein kaputter Titel wird uebersprungen, nicht zum Abbruch.
///
/// Die Fixtures enthalten nur stumme Samples, auch beim Test der Audio-Unterbrechung.
@MainActor
final class PlaybackLoadingTests: XCTestCase {

    private var workDir: URL!
    private var settings: PlayerSettings!
    private var engine: PlaybackEngine!

    override func setUp() async throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlaybackLoading-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        settings = PlayerSettings()
        engine = PlaybackEngine(settings: settings, library: LibraryStore())
    }

    override func tearDown() async throws {
        engine = nil
        settings = nil
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - Testmaterial

    /// Minimal gueltiges M.K.-MOD. Das Sample besteht aus Nullbytes, der Titel
    /// steht im Header — damit laesst sich nachweisen, WELCHES Modul geladen
    /// wurde, ohne echte Musikdateien ins Repo zu holen.
    private func writeModule(named name: String, title: String) throws -> TrackRef {
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        let titleBytes = Array(title.utf8.prefix(20))
        data.replaceSubrange(0..<titleBytes.count, with: titleBytes)
        data[20 + 23] = 0x02        // Instrument 1: Laenge 2 Words
        data[20 + 25] = 64          // Lautstaerke
        data[950] = 1               // Songlaenge 1 Position
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        let period = 428            // C-3
        data[1084] = UInt8((period >> 8) & 0x0F)
        data[1085] = UInt8(period & 0xFF)
        data[1086] = 0x10           // Instrument 1
        let url = workDir.appendingPathComponent(name)
        try data.write(to: url)
        return TrackRef(relativePath: name, displayName: name, folderPath: [], url: url)
    }

    /// Bytes, die kein Parser akzeptiert.
    private func writeBrokenModule(named name: String) throws -> TrackRef {
        let url = workDir.appendingPathComponent(name)
        try Data(repeating: 0, count: 2048).write(to: url)
        return TrackRef(relativePath: name, displayName: name, folderPath: [], url: url)
    }

    /// Wartet, bis die Bedingung zutrifft — oder bricht den Test ab.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 10,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            // Kurz den MainActor abgeben, damit der Ladeauftrag ueberhaupt
            // drankommt. Genau das koennte er nicht, wenn er synchron liefe.
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Zeitueberschreitung: \(description)")
    }

    // MARK: - Laden blockiert den MainActor nicht mehr

    /// `select` kehrt sofort zurueck; der Titel ist erst danach gesetzt.
    ///
    /// Das ist kein Zeittest: Ein neu erzeugter Task kann nicht laufen, solange
    /// diese Testmethode den MainActor synchron haelt. Waere das Laden noch
    /// synchron, staende `currentTrack` unmittelbar nach dem Aufruf.
    func testSelectReturnsBeforeTheModuleIsLoaded() async throws {
        let track = try writeModule(named: "eins.mod", title: "EINS")

        engine.select(track)
        XCTAssertNil(engine.currentTrack, "Laden darf den Aufrufer nicht blockieren")

        await waitUntil("Titel wird geladen") { self.engine.currentTrack == track }
        XCTAssertEqual(engine.coordinator.trackName, "EINS")
        XCTAssertFalse(engine.isPlaying, "select() laedt nur, es spielt nicht ab")
    }

    /// Die Spieldauer wird im Hintergrund ermittelt und ans Ziel gereicht —
    /// sie muss danach genauso dastehen wie bei der Berechnung im Coordinator.
    func testDurationSurvivesTheBackgroundLoad() async throws {
        let track = try writeModule(named: "dauer.mod", title: "DAUER")
        let expected = try RenderEngine.sequencedDuration(of: ModuleLoader.parse(data: Data(contentsOf: track.url)))

        engine.select(track)
        await waitUntil("Titel wird geladen") { self.engine.currentTrack == track }

        XCTAssertEqual(engine.coordinator.visualizerState.totalDuration, expected, accuracy: 0.0001)
        XCTAssertGreaterThan(expected, 0, "Ein Modul mit einer Position hat eine messbare Dauer")
    }

    // MARK: - Der juengste Auftrag gewinnt

    /// Zwei Anforderungen direkt hintereinander: Die zweite gewinnt, und die
    /// erste darf danach nichts mehr setzen.
    func testNewerRequestOverridesTheOlderOne() async throws {
        let first = try writeModule(named: "erster.mod", title: "ERSTER")
        let second = try writeModule(named: "zweiter.mod", title: "ZWEITER")

        engine.select(first)
        engine.select(second)

        await waitUntil("zweiter Titel wird geladen") { self.engine.currentTrack == second }
        XCTAssertEqual(engine.coordinator.trackName, "ZWEITER")

        // Nachlauf: Der ueberholte Auftrag darf auch verspaetet nichts mehr
        // uebernehmen.
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(engine.currentTrack, second)
        XCTAssertEqual(engine.coordinator.trackName, "ZWEITER")
    }

    /// Stoppen gilt auch fuer einen Ladeauftrag, der noch gar nicht auf der
    /// Hintergrundschlange begonnen hat. Sonst startet der Auftrag nach dem
    /// Stoppen verspaetet doch noch die Wiedergabe.
    func testStopCancelsAPendingAutoplayLoad() async throws {
        let track = try writeModule(named: "stop.mod", title: "STOP")

        engine.play(track)
        // Der neu erzeugte Task kann erst laufen, wenn diese MainActor-Methode
        // aussetzt. `stop()` trifft ihn deshalb sicher noch im wartenden Zustand.
        engine.stop()

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(engine.currentTrack)
        XCTAssertFalse(engine.coordinator.isPlaying)
        XCTAssertFalse(engine.isPlaying)
    }

    func testPauseCancelsAPendingAutoplayLoad() async throws {
        let track = try writeModule(named: "pause.mod", title: "PAUSE")
        engine.play(track)
        engine.pause()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(engine.currentTrack)
        XCTAssertFalse(engine.coordinator.isPlaying)
    }

    func testOutputLossAndInterruptionCancelPendingAutoplay() async throws {
        let track = try writeModule(named: "route.mod", title: "ROUTE")
        for event in [AudioSessionController.Event.outputDeviceLost, .interruptionBegan] {
            engine.play(track)
            engine.handleAudioSessionEvent(event)
            try? await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertNil(engine.currentTrack)
            XCTAssertFalse(engine.coordinator.isPlaying)
        }
    }

    func testLoadedTrackUsesItsIndexInTheUpdatedQueue() async throws {
        let first = try writeModule(named: "a.mod", title: "A")
        let selected = try writeModule(named: "b.mod", title: "B")
        let last = try writeModule(named: "c.mod", title: "C")
        let started = CancellationFlag()
        let release = DispatchSemaphore(value: 0)
        engine = PlaybackEngine(settings: settings, library: LibraryStore(), readModule: { url in
            started.set()
            guard release.wait(timeout: .now() + 5) == .success else {
                throw CocoaError(.fileReadUnknown)
            }
            return try Data(contentsOf: url)
        })
        defer { release.signal() }
        engine.setQueue([selected, last])
        engine.select(selected)
        await waitUntil("Leser hat begonnen") { started.isSet }
        engine.setQueue([first, selected, last])
        release.signal()
        await waitUntil("Titel ist geladen") { self.engine.currentTrack == selected }
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.queue[engine.currentIndex + 1], last)
    }

    func testHeadphoneRemovalDuringInterruptionPreventsAutomaticResume() async throws {
        let track = try writeModule(named: "interrupted.mod", title: "INTERRUPTED")
        engine.setQueue([track])
        engine.select(track)
        await waitUntil("Titel ist geladen") { self.engine.currentTrack == track }
        engine.coordinator.play()
        engine.handleAudioSessionEvent(.interruptionBegan)
        XCTAssertTrue(engine.coordinator.isPaused)
        engine.handleAudioSessionEvent(.outputDeviceLost)
        engine.handleAudioSessionEvent(.interruptionEnded(shouldResume: true))
        XCTAssertTrue(engine.coordinator.isPaused)
    }

    func testSleepTimerCancelsPendingLoadAndPreservesQueueAndVolume() async throws {
        let track = try writeModule(named: "sleep-pending.mod", title: "SLEEP PENDING")
        let started = CancellationFlag()
        let release = DispatchSemaphore(value: 0)
        engine = PlaybackEngine(settings: settings, library: LibraryStore(), readModule: { url in
            started.set()
            guard release.wait(timeout: .now() + 5) == .success else { throw CocoaError(.fileReadUnknown) }
            return try Data(contentsOf: url)
        })
        let originalVolume = settings.volume
        defer { release.signal(); engine.stop(); settings.volume = originalVolume }
        settings.volume = 0.37
        engine.applySettings()
        engine.enqueue(track)
        let queuedIDs = engine.pendingQueue.items.map(\.id)
        XCTAssertEqual(queuedIDs.count, 1)
        engine.play(track)
        await waitUntil("Leser wartet") { started.isSet }
        engine.coordinator.sleepTimer.start(minutes: 1)
        engine.coordinator.sleepTimer.signal.start(seconds: 0.001, now: SleepTimerClock.now())
        try await Task.sleep(for: .milliseconds(20))
        engine.coordinator.sleepTimer.refresh()
        release.signal()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(engine.currentTrack)
        XCTAssertFalse(engine.coordinator.isPlaying)
        XCTAssertEqual(engine.coordinator.sleepTimer.snapshot.phase, .expired)
        XCTAssertEqual(engine.pendingQueue.items.map(\.id), queuedIDs)
        XCTAssertEqual(settings.volume, 0.37, accuracy: 0.000001)
    }

    func testExpiredSleepTimerBlocksInterruptionResumeUntilManualPlay() async throws {
        let track = try writeModule(named: "sleep-interrupted.mod", title: "SLEEP INT")
        engine.select(track)
        await waitUntil("Titel geladen") { self.engine.currentTrack == track }
        let originalVolume = settings.volume
        defer { engine.stop(); settings.volume = originalVolume }
        engine.play()
        engine.coordinator.sleepTimer.start(minutes: 1)
        engine.coordinator.sleepTimer.signal.start(seconds: 0.001, now: SleepTimerClock.now())
        engine.handleAudioSessionEvent(.interruptionBegan)
        settings.volume = 0.41
        engine.applySettings()
        try await Task.sleep(for: .milliseconds(20))
        engine.handleAudioSessionEvent(.interruptionEnded(shouldResume: true))
        XCTAssertFalse(engine.coordinator.isPlaying)
        XCTAssertEqual(engine.coordinator.sleepTimer.snapshot.phase, .expired)
        XCTAssertEqual(settings.volume, 0.41, accuracy: 0.000001)
        engine.play()
        XCTAssertTrue(engine.coordinator.isPlaying)
        XCTAssertEqual(engine.coordinator.sleepTimer.snapshot.phase, .inactive)
        XCTAssertEqual(settings.volume, 0.41, accuracy: 0.000001)
    }

    func testSleepTimerContinuesAcrossPauseAndTitleChangeAndExplicitStopCancelsIt() async throws {
        let first = try writeModule(named: "sleep-first.mod", title: "SLEEP FIRST")
        let second = try writeModule(named: "sleep-second.mod", title: "SLEEP SECOND")
        engine.select(first)
        await waitUntil("Erster Titel geladen") { self.engine.currentTrack == first }
        defer { engine.stop() }
        engine.play()
        engine.coordinator.sleepTimer.start(minutes: 1)
        let deadline = engine.coordinator.sleepTimer.signal.deadline
        engine.pause()
        XCTAssertEqual(engine.coordinator.sleepTimer.signal.deadline, deadline)
        engine.select(second)
        await waitUntil("Zweiter Titel geladen") { self.engine.currentTrack == second }
        engine.play()
        XCTAssertEqual(engine.coordinator.sleepTimer.signal.deadline, deadline)
        engine.stop()
        XCTAssertEqual(engine.coordinator.sleepTimer.snapshot.phase, .inactive)
        XCTAssertEqual(engine.coordinator.sleepTimer.signal.deadline, 0)
    }

    func testSceneReturnExpiresTimerAndLateSongEndCannotRestartAfterReset() async throws {
        let first = try writeModule(named: "sleep-scene-first.mod", title: "SLEEP SCENE")
        let second = try writeModule(named: "sleep-scene-second.mod", title: "SLEEP NEXT")
        let originalLoopMode = settings.loopMode
        settings.loopMode = .playlist
        engine.setQueue([first, second])
        engine.select(first)
        await waitUntil("Titel geladen") { self.engine.currentTrack == first }
        defer { engine.stop(); settings.loopMode = originalLoopMode }
        engine.play()
        engine.coordinator.sleepTimer.start(minutes: 1)
        engine.setSceneActive(false)
        engine.coordinator.sleepTimer.signal.start(seconds: 0.001, now: SleepTimerClock.now())
        try await Task.sleep(for: .milliseconds(20))
        engine.setSceneActive(true)
        XCTAssertFalse(engine.coordinator.isPlaying)
        XCTAssertEqual(engine.coordinator.sleepTimer.snapshot.phase, .expired)
        engine.coordinator.sleepTimer.cancel()
        engine.coordinator.songEndPulse += 1
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(engine.currentTrack, first)
        XCTAssertFalse(engine.coordinator.isPlaying)
    }

    // MARK: - Kaputte Titel

    /// Ein Titel aus der Liste, der sich nicht parsen laesst, wird
    /// uebersprungen — mit Hinweis, aber ohne die Wiedergabe zu beenden.
    func testBrokenTrackInTheQueueIsSkipped() async throws {
        let broken = try writeBrokenModule(named: "kaputt.mod")
        let good = try writeModule(named: "heil.mod", title: "HEIL")
        engine.setQueue([broken, good])

        engine.select(broken)
        await waitUntil("heiler Titel wird geladen") { self.engine.currentTrack == good }

        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertNotNil(engine.errorMessage, "Der uebersprungene Titel gehoert gemeldet")
        XCTAssertEqual(engine.coordinator.trackName, "HEIL")
    }

    // MARK: - Sitzung wiederherstellen

    /// Der zuletzt gespielte Titel ist nach dem Start wieder ausgewaehlt.
    ///
    /// Der Weg fuehrt seit 1.6.10 durch den asynchronen Ladepfad. Ein Test
    /// dafuer fehlte — aufgefallen ist die Luecke, als der Titel im
    /// iPad-Simulator nach dem Start nicht wieder dastand und sich nicht
    /// unterscheiden liess, ob das an der Wiederherstellung oder am
    /// Simulator-Aufbau lag.
    func testRestoreSessionSelectsTheLastPlayedTrack() async throws {
        let first = try writeModule(named: "erster.mod", title: "ERSTER")
        let second = try writeModule(named: "zweiter.mod", title: "ZWEITER")
        engine.setQueue([first, second])

        let previous = settings.lastPlayedRelativePath
        defer { settings.lastPlayedRelativePath = previous }
        settings.lastPlayedRelativePath = second.relativePath

        engine.restoreSession()

        await waitUntil("zuletzt gespielter Titel steht wieder da") {
            self.engine.currentTrack == second
        }
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.coordinator.trackName, "ZWEITER")
        XCTAssertFalse(engine.isPlaying, "Wiederherstellen waehlt aus, es spielt nicht ab")
    }

    /// Steht der gemerkte Pfad nicht mehr in der Liste, passiert nichts —
    /// insbesondere wird nicht einfach der erste Titel geladen.
    func testRestoreSessionIgnoresATrackThatIsGone() async throws {
        let present = try writeModule(named: "da.mod", title: "DA")
        engine.setQueue([present])

        let previous = settings.lastPlayedRelativePath
        defer { settings.lastPlayedRelativePath = previous }
        settings.lastPlayedRelativePath = "verschwunden.mod"

        engine.restoreSession()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(engine.currentTrack)
    }

    // MARK: - Audio-Session

    /// Die Wiedergabe startet wirklich — und damit auch die AVAudioSession.
    ///
    /// Hintergrund (Code-Review 2026-08-02): Der Core setzte und aktivierte die
    /// Session in `play()` ein zweites Mal, zusaetzlich zum
    /// `AudioSessionController` der App, mit `print` als einziger
    /// Fehlerbehandlung. Der Block ist raus; zustaendig ist jetzt allein die
    /// App. Ohne brauchbare Session startet `AVAudioEngine` nicht — dass
    /// `isPlaying` hier wahr wird, ist also der Beleg, dass die verbliebene
    /// Seite ihre Arbeit tut.
    ///
    /// Das Modul ist stumm (Sample aus Nullbytes), der Simulator bleibt still.
    func testPlaybackStartsWithTheAppOwningTheAudioSession() async throws {
        let track = try writeModule(named: "session.mod", title: "SESSION")
        engine.select(track)
        await waitUntil("Titel wird geladen") { self.engine.currentTrack == track }

        engine.play()
        // Der Core setzt seinen Zustand sofort; die Spiegelung in der
        // PlaybackEngine laeuft ueber einen Combine-Sink und kommt erst danach.
        XCTAssertTrue(
            engine.coordinator.isPlaying,
            "Ohne aktive Audio-Session startet AVAudioEngine nicht")
        XCTAssertFalse(engine.coordinator.isPaused)

        await waitUntil("Zustand ist gespiegelt") { self.engine.isPlaying }

        engine.stop()
        XCTAssertFalse(engine.coordinator.isPlaying)
    }

    /// Ein einzelner Titel ausserhalb der Liste, der sich nicht laden laesst,
    /// meldet den Fehler und aendert den laufenden Titel nicht.
    func testBrokenSingleTrackReportsAnError() async throws {
        let broken = try writeBrokenModule(named: "einzeln-kaputt.mod")

        engine.select(broken)
        await waitUntil("Fehler wird gemeldet") { self.engine.errorMessage != nil }

        XCTAssertNil(engine.currentTrack)
    }
}

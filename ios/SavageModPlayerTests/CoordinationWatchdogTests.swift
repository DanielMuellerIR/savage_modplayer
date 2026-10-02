import XCTest
@testable import SavageModPlayer

/// Der Wächter über einem koordinierten Lesevorgang.
///
/// Hintergrund (Code-Review 2026-08-02): `NSFileCoordinator.coordinate` hat
/// kein Zeitlimit und liest zwischendurch kein Abbruchflag. Ein hängender
/// fremder File Provider blockierte damit den Bibliotheks-Worker dauerhaft.
///
/// **Was diese Tests belegen und was nicht.** Geprüft wird die Entscheidung des
/// Wächters — abbrechen bei Nutzerabbruch, abbrechen bei Stillstand, laufen
/// lassen bei Fortschritt. Dass ein realer, hängender File Provider daraufhin
/// wirklich loslässt, lässt sich nur mit einem solchen Anbieter zeigen; das
/// bleibt Sache eines Gerätetests. Die Zeitwerte sind hier absichtlich winzig,
/// damit die Suite schnell bleibt.
final class CoordinationWatchdogTests: XCTestCase {

    /// Zählt die Abbrüche threadsicher mit.
    private final class AbortCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func increment() {
            lock.lock(); value += 1; lock.unlock()
        }
    }

    /// Ein von aussen setzbarer Fortschrittswert.
    private final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64 = 0
        var current: Int64 {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    private final class CancellationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func cancel() {
            lock.lock(); value = true; lock.unlock()
        }
    }

    /// Ein Lesevorgang, der von selbst durchläuft, wird nicht angefasst.
    func testFinishingInTimeAbortsNothing() {
        let aborts = AbortCounter()
        let watchdog = CoordinationWatchdog(
            stallTimeout: 5,
            pollInterval: 0.01,
            isCancelled: { false },
            progress: { 0 },
            abort: { aborts.increment() })

        watchdog.start()
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(watchdog.finish(), .none)
        XCTAssertEqual(aborts.count, 0)
    }

    /// Bricht der Nutzer ab, greift der Wächter mitten im Lesevorgang ein —
    /// vorher war das Abbruchflag ab dem Start der Koordination wirkungslos.
    func testUserCancellationAbortsTheCoordination() {
        let aborts = AbortCounter()
        let watchdog = CoordinationWatchdog(
            stallTimeout: 5,
            pollInterval: 0.01,
            isCancelled: { true },
            progress: { 0 },
            abort: { aborts.increment() })

        watchdog.start()
        waitUntil("Abbruch wird ausgelöst") { aborts.count > 0 }
        XCTAssertEqual(watchdog.finish(), .cancelled)
    }

    /// Ohne Fortschritt läuft das Zeitlimit ab.
    func testStandstillAbortsAfterTheStallTimeout() {
        let aborts = AbortCounter()
        let watchdog = CoordinationWatchdog(
            stallTimeout: 0.05,
            pollInterval: 0.01,
            isCancelled: { false },
            progress: { 0 },
            abort: { aborts.increment() })

        watchdog.start()
        waitUntil("Zeitlimit greift") { aborts.count > 0 }
        XCTAssertEqual(watchdog.finish(), .stalled)
    }

    /// Fortschritt verlängert die Frist: Ein langsamer Anbieter darf
    /// durchlaufen, nur ein steckengebliebener wird abgebrochen.
    func testProgressKeepsTheCoordinationAlive() {
        let aborts = AbortCounter()
        let progress = ProgressBox()
        let watchdog = CoordinationWatchdog(
            stallTimeout: 0.1,
            pollInterval: 0.01,
            isCancelled: { false },
            progress: { progress.current },
            abort: { aborts.increment() })

        watchdog.start()
        // Deutlich länger als das Zeitlimit, aber es geht ständig voran.
        for step in 1...15 {
            Thread.sleep(forTimeInterval: 0.02)
            progress.current = Int64(step) * 1024
        }
        XCTAssertEqual(aborts.count, 0, "Fortschritt darf nicht abgebrochen werden")
        XCTAssertEqual(watchdog.finish(), .none)

        // Und jetzt bleibt der Fortschritt stehen — dann greift das Zeitlimit.
        let stalling = CoordinationWatchdog(
            stallTimeout: 0.05,
            pollInterval: 0.01,
            isCancelled: { false },
            progress: { progress.current },
            abort: { aborts.increment() })
        stalling.start()
        waitUntil("Zeitlimit greift nach dem Stillstand") { aborts.count > 0 }
        XCTAssertEqual(stalling.finish(), .stalled)
    }

    /// Nach `finish()` läuft kein Wächter-Thread mehr.
    ///
    /// Das ist keine Kosmetik: Ein noch laufender Wächter benutzte die
    /// übergebenen Blöcke weiter, nachdem der Aufrufer sie längst als erledigt
    /// betrachtet. Genau daran ist die erste Fassung im Simulator gescheitert
    /// (`closure argument was escaped in withoutActuallyEscaping block`).
    func testFinishWaitsUntilTheWatchdogIsReallyOut() {
        let aborts = AbortCounter()
        // Zeitlimit weit unter der Wartezeit unten: Ein weiterlaufender
        // Waechter wuerde also ganz sicher noch abbrechen.
        let watchdog = CoordinationWatchdog(
            stallTimeout: 0.02,
            pollInterval: 0.01,
            isCancelled: { false },
            progress: { 0 },
            abort: { aborts.increment() })

        watchdog.start()
        XCTAssertEqual(watchdog.finish(), .none)
        let afterFinish = aborts.count

        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(aborts.count, afterFinish,
                       "Nach finish() darf kein Waechter mehr eingreifen")
    }

    /// Mehrfaches `finish()` ist harmlos — und blockiert nicht.
    func testRepeatedFinishIsHarmless() {
        let watchdog = CoordinationWatchdog(
            stallTimeout: 5,
            pollInterval: 0.01,
            isCancelled: { false },
            progress: { 0 },
            abort: { })
        watchdog.start()
        XCTAssertEqual(watchdog.finish(), .none)
        XCTAssertEqual(watchdog.finish(), .none)
    }

    /// Sobald der Koordinator den Zugriff gewaehrt hat, ist ein unveraenderter
    /// Download-Fortschritt kein Stillstand mehr. Der eigentliche Leseblock
    /// darf laenger als die Koordinationsfrist brauchen, etwa beim Hashen oder
    /// Auspacken einer grossen lokalen Datei.
    func testReadStopsTheCoordinationWatchdogBeforeRunningTheAccessBody() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Watchdog-\(UUID().uuidString).mod")
        try Data([0x01]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        var bodyRan = false
        XCTAssertNoThrow(try FileProviderReader.read(
            file,
            isCancelled: { false },
            coordinationStallTimeout: 0.03,
            coordinationPollInterval: 0.005
        ) { readable in
            bodyRan = true
            XCTAssertEqual(readable.path, file.path)
            Thread.sleep(forTimeInterval: 0.1)
        })
        XCTAssertTrue(bodyRan)
    }

    /// Der Koordinationswaechter endet vor dem langen Leseblock. Ein Abbruch in
    /// genau diesem Zeitfenster muss nach dem Block typisiert zum Importer
    /// gelangen; sonst meldet die Oberflaeche den abgebrochenen Import als
    /// erfolgreich.
    func testReadReportsCancellationRaisedInsideTheAccessBody() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Watchdog-Cancel-\(UUID().uuidString).mod")
        try Data([0x01]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let cancellation = CancellationBox()

        XCTAssertThrowsError(try FileProviderReader.read(
            file,
            isCancelled: { cancellation.isSet }
        ) { _ in
            cancellation.cancel()
        }) { error in
            XCTAssertTrue(error is FileProviderReader.ReadCancelled)
        }
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.005)
        }
        XCTFail("Zeitueberschreitung: \(description)")
    }
}

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
/// bleibt Sache eines Gerätetests. Entscheidungen verwenden eine feste Uhr;
/// Start und Ende des echten Workers werden getrennt asynchron beobachtet.
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
    func testFinishingAStartedWorkerAbortsNothing() async {
        let aborts = AbortCounter()
        let started = WorkerStartSignal()
        let watchdog = CoordinationWatchdog(
            stallTimeout: 60,
            pollInterval: 0.01,
            isCancelled: { false },
            progress: { started.signalOnce(); return 0 },
            abort: { aborts.increment() })

        watchdog.start()
        defer { watchdog.finish() }
        guard await XCTWaiter.fulfillment(of: [started.expectation], timeout: 5) == .completed else {
            XCTFail("Watchdog-Worker wurde nicht eingeplant")
            return
        }
        XCTAssertEqual(watchdog.finish(), .none)
        XCTAssertEqual(aborts.count, 0)
    }

    func testUserCancellationTakesPrecedenceOverStallAndProgress() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        var state = CoordinationWatchdog.PollState(now: now, stallTimeout: 5, progress: 0)
        XCTAssertEqual(state.poll(now: now.addingTimeInterval(10), isCancelled: true,
                                  progress: { XCTFail("Abbruch darf keinen Fortschritt abfragen"); return 1024 }),
                       .cancelled)
    }

    func testStandstillAbortsAtTheDeadline() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        var state = CoordinationWatchdog.PollState(now: now, stallTimeout: 5, progress: 0)
        XCTAssertEqual(state.poll(now: now.addingTimeInterval(4.99), isCancelled: false,
                                  progress: { 0 }), .none)
        XCTAssertEqual(state.poll(now: now.addingTimeInterval(5), isCancelled: false,
                                  progress: { 0 }), .stalled)
    }

    func testProgressExtendsTheDeadlineOnlyWhenItIncreases() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        var state = CoordinationWatchdog.PollState(now: now, stallTimeout: 5, progress: 0)
        XCTAssertEqual(state.poll(now: now.addingTimeInterval(4), isCancelled: false,
                                  progress: { 1024 }), .none)
        XCTAssertEqual(state.poll(now: now.addingTimeInterval(8), isCancelled: false,
                                  progress: { 512 }), .none)
        XCTAssertEqual(state.poll(now: now.addingTimeInterval(9), isCancelled: false,
                                  progress: { 1024 }), .stalled)
    }

    func testProgressDeadlineUsesTheTimeAfterReadingProgress() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        var observedAt = start.addingTimeInterval(4)
        var state = CoordinationWatchdog.PollState(now: start, stallTimeout: 5, progress: 0)
        XCTAssertEqual(state.poll(now: observedAt, isCancelled: false, progress: {
            observedAt = start.addingTimeInterval(10)
            return 1024
        }), .none)
        XCTAssertEqual(state.poll(now: start.addingTimeInterval(14), isCancelled: false,
                                  progress: { 1024 }), .none)
        XCTAssertEqual(state.poll(now: start.addingTimeInterval(15), isCancelled: false,
                                  progress: { 1024 }), .stalled)
    }

    func testStartedWorkerAbortsOnUserCancellation() async {
        let started = WorkerStartSignal()
        let cancelled = CancellationBox()
        let aborted = XCTestExpectation(description: "Gestarteter Worker bricht ab")
        let watchdog = CoordinationWatchdog(
            stallTimeout: 60,
            pollInterval: 0.01,
            isCancelled: { cancelled.isSet },
            progress: { started.signalOnce(); return 0 },
            abort: { aborted.fulfill() })
        watchdog.start()
        defer { watchdog.finish() }
        guard await XCTWaiter.fulfillment(of: [started.expectation], timeout: 5) == .completed else {
            XCTFail("Watchdog-Worker wurde nicht eingeplant")
            return
        }
        cancelled.cancel()
        guard await XCTWaiter.fulfillment(of: [aborted], timeout: 5) == .completed else {
            XCTFail("Gestarteter Watchdog hat den Nutzerabbruch nicht gemeldet")
            return
        }
        XCTAssertEqual(watchdog.finish(), .cancelled)
    }

    private final class WorkerStartSignal: @unchecked Sendable {
        let expectation = XCTestExpectation(description: "Watchdog-Worker hat begonnen")
        private let lock = NSLock()
        private var signalled = false

        func signalOnce() {
            lock.lock()
            let shouldSignal = !signalled
            signalled = true
            lock.unlock()
            if shouldSignal { expectation.fulfill() }
        }
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

}

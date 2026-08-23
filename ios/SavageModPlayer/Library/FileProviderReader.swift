import Foundation
import SavageModPlayerCore

// Liest eine Quelldatei so, wie iOS es verlangt — auch wenn sie noch gar nicht
// auf dem Geraet liegt.
//
// Das Problem: die Dateien-App zeigt nicht nur den eigenen Speicher, sondern
// auch Cloud-Ordner fremder Anbieter (File Provider). Was dort wie eine Datei
// aussieht, ist oft nur ein Platzhalter — ein Eintrag mit Namen und Groesse,
// aber ohne Inhalt. Ein schlichtes `copyItem` wuerde daran scheitern oder eine
// leere Huelle kopieren.
//
// Der Weg dorthin ist dreistufig:
//
// 1. **Nachsehen, ob der Inhalt schon da ist.** `ubiquitousItemDownloadingStatus`
//    beantwortet das fuer iCloud-Ablagen. Meldet der Wert `.notDownloaded`, fehlt
//    der Inhalt wirklich.
// 2. **Laden anstossen und warten.** `startDownloadingUbiquitousItem` tritt das
//    Laden los; danach wird im Sekundentakt nachgesehen. Gewartet wird mit
//    Zeitlimit UND Abbruchmoeglichkeit — sonst haengt die App an einem
//    100-MB-Archiv ueber eine lahme Leitung fest. Das Zeitlimit greift nur,
//    solange nichts vorangeht: waechst die Datei, wird die Frist verlaengert.
//    Ein langsamer Download laeuft also durch, ein steckengebliebener nicht.
// 3. **Koordiniert lesen.** `NSFileCoordinator` klammert den eigentlichen
//    Lesevorgang. Fremde File Provider melden ihre Dateien haeufig gar nicht als
//    iCloud-Objekte — bei ihnen ist genau diese Klammer der Ausloeser, der den
//    Inhalt herbeischafft. Deshalb wird immer koordiniert gelesen, auch wenn
//    Schritt 1 und 2 nichts zu tun hatten.
//
// Scheitert eine Datei, wirft der Leser. Der `LibraryImporter` macht daraus
// einen `ImportFailure` und laeuft mit der naechsten Datei weiter — eine
// unerreichbare Datei darf einen Import ueber tausende nicht beenden.
//
// Alles hier laeuft auf der Arbeitsschlange des `LibraryStore`, nie auf dem
// MainActor: das Warten blockiert seinen Thread bewusst, und genau deshalb darf
// es nicht der Haupt-Thread sein.
struct FileProviderReader: Sendable {

    // Wie lange ohne jeden Fortschritt gewartet wird, bevor eine Datei als
    // haengend gilt.
    static let stallTimeout: TimeInterval = 60
    // Wie oft nachgesehen wird. Kurz genug, dass "Abbrechen" sich sofort
    // anfuehlt, lang genug, dass das Warten selbst nichts kostet.
    static let pollInterval: TimeInterval = 0.25

    // Wortlaut, mit dem ein Abbruch gemeldet wird (nur noch Anzeige-Text —
    // erkannt wird der Abbruch typisiert ueber das Markerprotokoll unten).
    static let cancellationReason = "Der Vorgang wurde abgebrochen."

    let isCancelled: @Sendable () -> Bool

    // Fertig verdrahteter Haken fuer `LibraryImporter(library:coordinatedRead:)`.
    var hook: LibraryImporter.CoordinatedRead {
        let isCancelled = self.isCancelled
        return { url, body in
            try FileProviderReader.read(url, isCancelled: isCancelled, body: body)
        }
    }

    // MARK: - Fehler

    // Der Abbruch ist bewusst ein EIGENER Typ mit dem Markerprotokoll des
    // Core-Importers: `LibraryImporter` erkennt ihn typisiert, setzt
    // `wasCancelled` und erzeugt keinen Fehlschlag-Eintrag. Frueher war er
    // ein ReadError-Fall und musste im Store per String-Vergleich aus dem
    // Bericht gefiltert werden.
    struct ReadCancelled: ImportCancellationError, LocalizedError {
        var errorDescription: String? { FileProviderReader.cancellationReason }
    }

    enum ReadError: Error, LocalizedError {
        case stalled
        case coordinationFailed(String)

        var errorDescription: String? {
            switch self {
            case .stalled:
                return "Die Datei wurde nicht aus der Cloud geladen (Zeitlimit erreicht)."
            case .coordinationFailed(let description):
                return "Die Datei liess sich nicht oeffnen: \(description)"
            }
        }
    }

    // MARK: - Lesen

    // `isCancelled` ist ausdruecklich `@escaping`: Der Waechter unten laeuft
    // auf einem eigenen Thread und muss die Abfrage waehrend der Koordination
    // in der Hand halten. (Er ist beendet, bevor dieser Aufruf zurueckkehrt —
    // siehe `CoordinationWatchdog.finish()`.)
    static func read(
        _ url: URL,
        isCancelled: @escaping @Sendable () -> Bool,
        body: (URL) throws -> Void
    ) throws {
        try awaitLocalCopy(of: url, isCancelled: isCancelled)
        if isCancelled() { throw ReadCancelled() }

        var coordinationError: NSError?
        var thrownInside: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        // Die Koordination selbst hat kein Zeitlimit. Bei einem fremden File
        // Provider ist genau sie der Ausloeser, der den Inhalt herbeischafft —
        // haengt der Anbieter, blockiert sie den Bibliotheks-Worker fuer immer,
        // und auch "Abbrechen" wirkt nicht mehr, weil das Abbruchflag zuletzt
        // vor diesem Aufruf geprueft wurde. Der Waechter sieht deshalb WAEHREND
        // der Koordination nach und ruft `cancel()`, wenn der Nutzer abbricht
        // oder nichts mehr vorangeht. `cancel()` darf laut Dokumentation von
        // jedem Thread kommen und laesst `coordinate` mit einem Fehler enden.
        //
        let cancellable = CancellableCoordinator(coordinator: coordinator)
        let watchdog = CoordinationWatchdog(
            stallTimeout: stallTimeout,
            pollInterval: pollInterval,
            isCancelled: isCancelled,
            progress: { downloadedSize(of: url) },
            abort: { cancellable.cancel() }
        )
        watchdog.start()

        // `withoutActuallyEscaping` nur deshalb, weil `body` hier
        // nicht-entweichend hereinkommt, der Zugriffs-Block des Koordinators
        // aber ein eigener Closure-Wert ist. Gespeichert wird nichts: der Block
        // laeuft synchron, bevor `coordinate` zurueckkehrt.
        withoutActuallyEscaping(body) { escapableBody in
            coordinator.coordinate(
                readingItemAt: url,
                options: [.withoutChanges],
                error: &coordinationError
            ) { readableURL in
                do {
                    try escapableBody(readableURL)
                } catch {
                    thrownInside = error
                }
            }
        }
        let watchdogOutcome = watchdog.finish()

        // Ein Fehler aus dem Leseblock selbst zaehlt zuerst: Er sagt mehr als
        // "abgebrochen".
        if let thrownInside { throw thrownInside }
        switch watchdogOutcome {
        case .cancelled:
            throw ReadCancelled()
        case .stalled:
            throw ReadError.stalled
        case .none:
            break
        }
        if let coordinationError {
            throw ReadError.coordinationFailed(coordinationError.localizedDescription)
        }
    }

    // MARK: - Auf den Inhalt warten

    private static func awaitLocalCopy(of url: URL, isCancelled: @Sendable () -> Bool) throws {
        guard isPlaceholder(url) else { return }
        // Klappt das Anstossen nicht, ist die Datei kein iCloud-Objekt. Dann
        // uebernimmt die Koordinations-Klammer weiter unten — dort haengt sich
        // ein fremder File Provider ein.
        guard (try? FileManager.default.startDownloadingUbiquitousItem(at: url)) != nil else { return }

        var deadline = Date().addingTimeInterval(stallTimeout)
        var lastSize = downloadedSize(of: url)

        while isPlaceholder(url) {
            if isCancelled() { throw ReadCancelled() }
            if Date() >= deadline { throw ReadError.stalled }
            Thread.sleep(forTimeInterval: pollInterval)

            // Fortschritt verlaengert die Frist. Ohne diese Regel waere jede
            // grosse Datei ueber eine langsame Leitung ein Fehlschlag.
            let size = downloadedSize(of: url)
            if size > lastSize {
                lastSize = size
                deadline = Date().addingTimeInterval(stallTimeout)
            }
        }
    }

    // Fehlt der Inhalt noch? Nur `.notDownloaded` heisst wirklich "nichts da";
    // alle anderen Zustaende sind lesbar. Ist der Wert gar nicht vorhanden,
    // gehoert die Datei keiner iCloud-Ablage an — dann gibt es hier nichts zu
    // warten.
    private static func isPlaceholder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              let status = values.ubiquitousItemDownloadingStatus
        else { return false }
        return status == .notDownloaded
    }

    // Belegter Platz auf der Platte. Waehrend des Ladens waechst dieser Wert,
    // waehrend die gemeldete Dateigroesse von Anfang an die volle Groesse zeigt.
    // Deshalb ist er der brauchbare Fortschritts-Anhaltspunkt.
    private static func downloadedSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        if let total = values?.totalFileAllocatedSize { return Int64(total) }
        if let allocated = values?.fileAllocatedSize { return Int64(allocated) }
        return 0
    }
}

// MARK: - Abbrechbarer Koordinator

// `NSFileCoordinator` ist nicht als `Sendable` deklariert, und das zu Recht:
// Die meisten seiner Methoden gehoeren auf den Thread, der die Koordination
// startet. `cancel()` ist die dokumentierte Ausnahme — es darf ausdruecklich
// von jedem Thread kommen. Diese Huelle laesst genau das durch und nichts
// sonst; deshalb ist ihr `@unchecked Sendable` gedeckt.
private struct CancellableCoordinator: @unchecked Sendable {
    let coordinator: NSFileCoordinator
    func cancel() { coordinator.cancel() }
}

// MARK: - Waechter fuer eine laufende Koordination

// Sieht waehrend eines koordinierten Lesevorgangs regelmaessig nach und bricht
// ihn ab, wenn der Nutzer abbricht oder nichts mehr vorangeht.
//
// Warum ueberhaupt: `NSFileCoordinator.coordinate(readingItemAt:…)` kehrt erst
// zurueck, wenn der zustaendige File Provider den Inhalt bereitgestellt hat. Es
// gibt weder ein Zeitlimit noch eine Stelle, an der zwischendurch das
// Abbruchflag gelesen wuerde. Ein haengender Anbieter blockierte damit den
// Bibliotheks-Worker dauerhaft.
//
// Fortschritt verlaengert die Frist — dieselbe Regel wie beim Warten auf den
// iCloud-Download: Ein langsamer Anbieter darf durchlaufen, ein
// steckengebliebener nicht.
//
// `@unchecked Sendable` ist gedeckt: `outcome` liegt hinter dem Lock, alles
// andere sind unveraenderliche Werte und `@Sendable`-Bloecke.
final class CoordinationWatchdog: @unchecked Sendable {

    enum Outcome: Equatable {
        /// Der Lesevorgang lief von selbst durch.
        case none
        /// Der Nutzer hat abgebrochen.
        case cancelled
        /// Es ging zu lange nichts mehr voran.
        case stalled
    }

    private let stallTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let isCancelled: @Sendable () -> Bool
    private let progress: @Sendable () -> Int64
    private let abort: @Sendable () -> Void

    private let queue = DispatchQueue(label: "com.viben.SavageModPlayer.coordinationWatchdog",
                                      qos: .utility)
    // Signalisiert dem Waechter, dass die Koordination durch ist.
    private let finished = DispatchSemaphore(value: 0)
    // Der Waechter meldet zurueck, dass er wirklich aus ist. `finish()` wartet
    // darauf: Danach laeuft garantiert kein Waechter-Thread mehr, der noch
    // `abort()` rufen oder die Datei abfragen koennte. Das Warten kostet nur
    // die Aufweckzeit, nicht den ganzen Poll-Abstand — die Poll-Pause bricht
    // beim Signal sofort ab.
    private let stopped = DispatchSemaphore(value: 0)
    private var isRunning = false
    private let lock = NSLock()
    private var outcome: Outcome = .none

    init(
        stallTimeout: TimeInterval,
        pollInterval: TimeInterval,
        isCancelled: @escaping @Sendable () -> Bool,
        progress: @escaping @Sendable () -> Int64,
        abort: @escaping @Sendable () -> Void
    ) {
        self.stallTimeout = stallTimeout
        self.pollInterval = pollInterval
        self.isCancelled = isCancelled
        self.progress = progress
        self.abort = abort
    }

    func start() {
        lock.lock()
        isRunning = true
        lock.unlock()

        queue.async { [self] in
            defer { stopped.signal() }
            var deadline = Date().addingTimeInterval(stallTimeout)
            var lastProgress = progress()

            while true {
                // Wartet hoechstens einen Poll-Abstand — oder kehrt sofort
                // zurueck, sobald die Koordination durch ist.
                if finished.wait(timeout: .now() + pollInterval) == .success { return }

                if isCancelled() {
                    record(.cancelled)
                    abort()
                    return
                }
                let current = progress()
                if current > lastProgress {
                    lastProgress = current
                    deadline = Date().addingTimeInterval(stallTimeout)
                }
                if Date() >= deadline {
                    record(.stalled)
                    abort()
                    return
                }
            }
        }
    }

    /// Beendet die Beobachtung und sagt, ob und warum abgebrochen wurde.
    ///
    /// Kehrt erst zurueck, wenn der Waechter-Thread wirklich aus ist. Ohne
    /// dieses Abwarten koennte er die uebergebenen Bloecke noch benutzen,
    /// nachdem der Aufrufer sie laengst als erledigt betrachtet.
    @discardableResult
    func finish() -> Outcome {
        lock.lock()
        let wasRunning = isRunning
        isRunning = false
        lock.unlock()

        if wasRunning {
            finished.signal()
            stopped.wait()
        }
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }

    private func record(_ value: Outcome) {
        lock.lock()
        outcome = value
        lock.unlock()
    }
}

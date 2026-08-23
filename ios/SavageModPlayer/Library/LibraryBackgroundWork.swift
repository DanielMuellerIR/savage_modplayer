import Foundation
import SavageModPlayerCore

// Drei kleine Helfer, die sich Haupt-Thread und Arbeitsschlange teilen.
//
// Warum eigene Typen und nicht einfach `Task.isCancelled` und `await`: der Core
// (`MusicLibrary`, `LibraryImporter`, `LibraryReset`) ist bewusst synchron und
// plattformneutral. Er fragt Abbruch ueber `() -> Bool` ab und meldet Fortschritt
// ueber `(ImportProgress) -> Void`. Beides wird auf der Arbeitsschlange
// aufgerufen, waehrend der Rest der App auf dem MainActor sitzt — also braucht
// es ein paar Bausteine, die beide Seiten gefahrlos anfassen duerfen.

// MARK: - Schalter fuer zwei Threads

// Ein Ja/Nein-Schalter, den der Haupt-Thread setzt und eine Arbeitsschlange
// liest. Genau dafuer sind die Abbruch-Haken des Core gedacht: der Nutzer tippt
// auf "Abbrechen", der laufende Import sieht das beim naechsten Datei-Schritt.
// Die Wiedergabe nutzt denselben Schalter, um einen ueberholten Ladeauftrag
// abzubrechen — deshalb steht "Cancellation" im Namen und nicht "Library".
//
// `@unchecked Sendable` ist hier ehrlich verdient: der Zugriff ist mit einem
// Lock geschuetzt, mehr Zustand als ein Bool gibt es nicht.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }

    func set() {
        lock.lock()
        raised = true
        lock.unlock()
    }

    func clear() {
        lock.lock()
        raised = false
        lock.unlock()
    }
}

// MARK: - Fortschritt drosseln

// Der Importer meldet Fortschritt fuer JEDE Datei. Bei einer Sammlung mit
// tausenden Modulen waeren das tausende Sprunge auf den MainActor pro Sekunde —
// die Oberflaeche wuerde nur noch Fortschrittsbalken zeichnen. Deshalb laesst
// dieser Relais-Baustein hoechstens alle `interval` Sekunden eine Meldung durch.
// Der letzte Stand geht dabei nie verloren: nach dem Vorgang setzt der Store den
// Fortschritt ohnehin auf nil und zeigt den Bericht.
final class LibraryProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var lastDelivery = Date.distantPast
    private let interval: TimeInterval
    private let deliver: @Sendable (ImportProgress) -> Void

    init(interval: TimeInterval = 0.1, deliver: @escaping @Sendable (ImportProgress) -> Void) {
        self.interval = interval
        self.deliver = deliver
    }

    func send(_ progress: ImportProgress) {
        lock.lock()
        let now = Date()
        let due = now.timeIntervalSince(lastDelivery) >= interval
        if due { lastDelivery = now }
        lock.unlock()
        guard due else { return }
        deliver(progress)
    }
}

// MARK: - Zugriff auf ausgewaehlte Ordner

// Ordner, die der Nutzer im Dateiauswahl-Blatt bestimmt, liegen ausserhalb des
// App-Containers. iOS gibt sie nur frei, solange der Zugriff ausdruecklich
// geoeffnet ist — und jedes `start…` braucht sein `stop…`, sonst laeuft die App
// in ein Limit offener Zugriffe.
//
// Dieser Typ macht das Paar sichtbar: einmal oeffnen, bevor der Vorgang
// startet, einmal schliessen, wenn er fertig ist — auch bei Abbruch und Fehler.
// Gemerkt werden nur die URLs, deren Oeffnen wirklich geklappt hat; alles andere
// wuerde beim Schliessen einen Zaehler ins Minus treiben.
struct LibraryScopedAccess: Sendable {
    private let opened: [URL]

    static func open(_ urls: [URL]) -> LibraryScopedAccess {
        LibraryScopedAccess(opened: urls.filter { $0.startAccessingSecurityScopedResource() })
    }

    func close() {
        for url in opened {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

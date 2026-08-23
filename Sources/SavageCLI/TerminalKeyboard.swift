import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// ============================================================================
// TerminalKeyboard — einzelne Tastendruecke waehrend der Wiedergabe lesen.
//
// Normalerweise sammelt das Terminal eine ganze Zeile und gibt sie erst bei
// Enter an das Programm weiter ("kanonischer Modus"), und es zeigt jedes
// getippte Zeichen an ("Echo"). Fuer einen Player ist beides falsch: `p` soll
// sofort pausieren, ohne dass ein `p` im Bild steht. Deshalb schaltet diese
// Klasse das Terminal in den Rohmodus und stellt den alten Zustand danach
// wieder her.
//
// Die Wiederherstellung ist der heikle Teil: Wer den Rohmodus stehen laesst,
// hinterlaesst dem Nutzer eine Shell ohne Echo. Sie passiert deshalb dreifach
// abgesichert — beim regulaeren `restore()`, ueber `atexit` (die CLI beendet
// sich an vielen Stellen mit `exit()`) und in den Signalhandlern fuer Ctrl-C
// und `kill`. `tcsetattr` ist laut POSIX aus einem Signalhandler heraus
// erlaubt.
//
// Ohne Terminal (Pipe, CI, `< /dev/null`) gibt es nichts zu steuern: dann
// liefert `makeIfInteractive()` nil und die Wiedergabe laeuft wie bisher
// einfach durch.
// ============================================================================

/// Der gesicherte Terminalzustand. Global, weil `atexit`- und Signalhandler
/// C-Funktionszeiger sind und nichts einfangen duerfen.
private nonisolated(unsafe) var savedTerminalAttributes = termios()
private nonisolated(unsafe) var terminalIsRaw = false

/// Von einem Signalhandler gesetzt: Ctrl-C oder `kill` kam an. `sig_atomic_t`
/// ist der einzige Typ, dessen Zuweisung aus einem Handler heraus garantiert
/// unteilbar ist.
private nonisolated(unsafe) var interruptRequested: sig_atomic_t = 0

private func restoreTerminalAttributes() {
    guard terminalIsRaw else { return }
    terminalIsRaw = false
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTerminalAttributes)
}

private func handleInterruptSignal(_ signalNumber: Int32) {
    interruptRequested = 1
}

/// Merkt sich, dass Ctrl-C oder `kill` angekommen ist, statt den Prozess sofort
/// zu beenden — die Wiedergabe soll die Audio-Ausgabe noch sauber schliessen.
///
/// Warum das noetig ist: Waehrend `--play` verschwand ein SIGINT wirkungslos.
/// Belegt am 2026-08-23 mit dem Stand vor dieser Aenderung: `--stdout` endete
/// auf `kill -INT` sofort, `--play` spielte die ganze Playlist zu Ende. Die
/// Audio-Ausgabe der Plattform bringt offenbar eine eigene Behandlung mit. Ein
/// eigener Handler stellt das Verhalten wieder her, das die Meldung schon
/// immer versprochen hat.
enum InterruptWatch {
    /// Nur einmal je Prozess installieren.
    private nonisolated(unsafe) static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        signal(SIGINT, handleInterruptSignal)
        signal(SIGTERM, handleInterruptSignal)
    }

    /// Kam seit dem Start ein Ctrl-C oder `kill`?
    static var wasRequested: Bool { interruptRequested != 0 }
}

/// Was der Nutzer waehrend der Wiedergabe angefordert hat.
enum PlaybackKeyCommand: Equatable {
    case togglePause
    case nextTrack
    case previousTrack
    case quit
}

/// Liest einzelne Tasten von einem echten Terminal.
final class TerminalKeyboard {

    /// Liefert eine Steuerung, wenn stdin an einem Terminal haengt — sonst nil.
    static func makeIfInteractive() -> TerminalKeyboard? {
        guard isatty(STDIN_FILENO) == 1 else { return nil }
        return TerminalKeyboard()
    }

    private init() {
        tcgetattr(STDIN_FILENO, &savedTerminalAttributes)
        var raw = savedTerminalAttributes
        // ICANON aus: Zeichen kommen sofort statt erst bei Enter.
        // ECHO aus: getippte Zeichen erscheinen nicht im Bild.
        // ISIG bleibt AN, damit Ctrl-C weiterhin ein echtes SIGINT ausloest —
        // die Wiedergabe soll darauf sauber aufraeumen, nicht `^C` als Taste
        // sehen.
        raw.c_lflag &= ~(tcflag_t(ICANON) | tcflag_t(ECHO))
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        terminalIsRaw = true

        // Die CLI beendet sich an vielen Stellen mit `exit()`; ohne diesen
        // Eintrag bliebe dann ein Terminal ohne Echo zurueck.
        atexit(restoreTerminalAttributes)
    }

    /// Stellt das Terminal wieder her. Mehrfacher Aufruf ist harmlos.
    func restore() {
        restoreTerminalAttributes()
    }

    /// Wartet hoechstens `timeoutMilliseconds` auf einen Tastendruck.
    ///
    /// - Returns: Der Befehl, oder nil bei Zeitablauf, unbekannter Taste oder
    ///   einem Signal (dann pruefen Aufrufer `wasInterrupted`).
    func waitForCommand(timeoutMilliseconds: Int32) -> PlaybackKeyCommand? {
        guard let key = readByte(timeoutMilliseconds: timeoutMilliseconds) else { return nil }
        switch key {
        case UInt8(ascii: " "), UInt8(ascii: "p"), UInt8(ascii: "P"):
            return .togglePause
        case UInt8(ascii: "n"), UInt8(ascii: "N"):
            return .nextTrack
        case UInt8(ascii: "b"), UInt8(ascii: "B"):
            return .previousTrack
        case UInt8(ascii: "q"), UInt8(ascii: "Q"):
            return .quit
        case 0x1B:
            // Escape-Sequenz: Pfeiltasten senden ESC [ C bzw. ESC [ D. Die
            // Folgebytes muessen in jedem Fall weggelesen werden, sonst
            // erschiene das `[` als naechster "Tastendruck".
            return readEscapeSequence()
        default:
            return nil
        }
    }

    // MARK: - Intern

    /// Pfeil rechts/links als naechster/vorheriger Titel; alles andere
    /// verwerfen. Kurzes Zeitfenster, weil die Folgebytes einer echten
    /// Pfeiltaste unmittelbar anliegen — ein allein gedruecktes Escape soll
    /// nicht 20 ms haengen bleiben und schon gar nichts ausloesen.
    private func readEscapeSequence() -> PlaybackKeyCommand? {
        guard readByte(timeoutMilliseconds: 20) == UInt8(ascii: "[") else { return nil }
        switch readByte(timeoutMilliseconds: 20) {
        case UInt8(ascii: "C"): return .nextTrack
        case UInt8(ascii: "D"): return .previousTrack
        default: return nil
        }
    }

    private func readByte(timeoutMilliseconds: Int32) -> UInt8? {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, timeoutMilliseconds) > 0 else { return nil }
        var byte: UInt8 = 0
        // `read` liefert 0 bei geschlossenem stdin und -1 bei einem Signal.
        guard read(STDIN_FILENO, &byte, 1) == 1 else { return nil }
        return byte
    }
}

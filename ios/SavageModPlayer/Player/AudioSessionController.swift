import AVFoundation
import Foundation

// Fuehrt die AVAudioSession der App — also den Vertrag zwischen dieser App und
// dem Rest des Systems darueber, wann und wie sie Ton ausgeben darf.
//
// Warum das eine eigene Klasse ist: auf einem Telefon kann der Ton jederzeit von
// aussen unterbrochen werden (Anruf, Wecker, Siri), das Ausgabegeraet kann
// verschwinden (Kopfhoerer abgezogen) und im Extremfall startet iOS den ganzen
// Audio-Dienst neu. Jeder dieser Faelle braucht eine andere Reaktion. Die
// PlaybackEngine soll sich um Titel und DSP kuemmern, nicht um Systemzustaende,
// deshalb uebersetzt dieser Controller die rohen Benachrichtigungen in eine
// Handvoll klar benannter Ereignisse.
@MainActor
final class AudioSessionController {

    // Was dem Aufrufer gemeldet wird. Bewusst wenige, eindeutige Faelle —
    // die Wiedergabe soll nicht selbst Notification-Codes auswerten muessen.
    enum Event: Sendable {
        // Etwas anderes hat den Ton uebernommen (typisch: eingehender Anruf).
        // Sofort pausieren; iOS hat die Engine ohnehin schon angehalten.
        case interruptionBegan
        // Die Unterbrechung ist vorbei. `shouldResume` ist die Empfehlung des
        // Systems: true = weiterspielen, false = pausiert bleiben (z. B. weil
        // der Nutzer inzwischen eine andere App laufen hat).
        case interruptionEnded(shouldResume: Bool)
        // Das bisherige Ausgabegeraet ist weg — praktisch immer "Kopfhoerer
        // abgezogen". Dann muss pausiert werden, sonst schallt die Musik
        // ploetzlich ueber den Lautsprecher.
        case outputDeviceLost
        // iOS hat den Audio-Server neu gestartet. Alle AVAudioEngine-Objekte,
        // Knoten und Puffer sind danach tot und muessen neu gebaut werden.
        case mediaServicesWereReset
    }

    // Startwert fuer die Laenge eines Audio-Puffers: 10 Millisekunden.
    //
    // WICHTIG — dieser Wert ist eine begruendete Vermutung, kein Messergebnis.
    // Er bestimmt, wie viel Zeit der Renderblock pro Aufruf hat: bei 10 ms und
    // 44,1 kHz sind das rund 441 Frames, die berechnet sein muessen, bevor die
    // Hardware sie abholt. Ein klassisches 4-Kanal-MOD schafft das mit grossem
    // Abstand. Ein IT-Modul mit 64 Pattern-Kanaelen und bis zu 256 gleichzeitig
    // klingenden Stimmen ist ein Vielfaches teurer — dort kann derselbe Wert zu
    // knapp sein und in hoerbaren Aussetzern enden.
    //
    // Zu tun: auf echter Hardware mit einem anspruchsvollen IT-Modul messen
    // (Dauerlauf, auch bei gesperrtem Bildschirm) und den Wert danach anpassen.
    // Groesser = mehr Sicherheitsabstand, aber traegere Reaktion; kleiner =
    // reaktionsschneller, aber weniger Luft. iOS akzeptiert den Wunsch nur als
    // Vorschlag, der tatsaechlich gewaehrte Wert steht in `ioBufferDuration`.
    static let preferredIOBufferDuration: TimeInterval = 0.010

    // Wird bei jedem Systemereignis aufgerufen. Setzt die PlaybackEngine.
    var onEvent: ((Event) -> Void)?

    // Die angemeldeten Benachrichtigungen liegen in einem eigenen kleinen
    // Behaelter (siehe unten), damit sie sicher wieder abgemeldet werden.
    private let observers = ObserverTokens()

    // Kategorie/Modus nur einmal setzen, nicht bei jedem Play erneut.
    private var isConfigured = false

    // Ist die Session gerade beim System angemeldet?
    private(set) var isActive = false

    // Tatsaechlich gewaehrte Pufferlaenge in Sekunden. Zum Nachmessen auf dem
    // Geraet gedacht: der Wunschwert oben und dieser Wert koennen abweichen.
    var ioBufferDuration: TimeInterval {
        AVAudioSession.sharedInstance().ioBufferDuration
    }

    // Abtastrate, die das System der App zuteilt (auf iPhones meist 48 kHz).
    var sampleRate: Double {
        AVAudioSession.sharedInstance().sampleRate
    }

    // MARK: - Einrichten und Aktivieren

    // Kategorie setzen und auf Systemereignisse hoeren — aber die Session NOCH
    // NICHT aktivieren. Das ist die Trennung, auf die es ankommt: schon das
    // Aktivieren einer `.playback`-Session unterbricht laufende Musik anderer
    // Apps. Beim App-Start waere das eine Unverschaemtheit, also passiert es
    // erst, wenn der Nutzer wirklich auf Play drueckt.
    func prepare() {
        installObservers()
        guard !isConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback ist die Kategorie fuer einen Musikplayer: der Ton laeuft
            // bei gesperrtem Bildschirm weiter und ignoriert den Stummschalter.
            // (Zusammen mit UIBackgroundModes = audio in der Info.plist.)
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(Self.preferredIOBufferDuration)
            isConfigured = true
        } catch {
            print("AudioSession: Konfiguration fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // Session beim System anmelden. Ab hier gehoert die Tonausgabe dieser App.
    func activate() {
        prepare()
        guard !isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            isActive = true
        } catch {
            print("AudioSession: Aktivieren fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // Session freigeben. `notifyOthersOnDeactivation` sagt anderen Apps
    // Bescheid, dass sie ihre pausierte Wiedergabe fortsetzen duerfen — ohne
    // das bleibt z. B. eine unterbrochene Podcast-App stumm stehen.
    func deactivate() {
        guard isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            isActive = false
        } catch {
            print("AudioSession: Deaktivieren fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // Nach einem Neustart des Audio-Dienstes ist die alte Konfiguration wertlos.
    // Diesen Merker zuruecksetzen, damit prepare() wirklich neu konfiguriert.
    func invalidateConfiguration() {
        isConfigured = false
        isActive = false
    }

    // Alle Benachrichtigungen abmelden. Wird ausserdem automatisch erledigt,
    // wenn dieses Objekt stirbt (siehe ObserverTokens.deinit).
    func stopObserving() {
        observers.removeAll()
    }

    // MARK: - Systemereignisse

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        // Anruf, Wecker, Siri: iOS meldet Beginn und Ende getrennt.
        observers.add(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            // Die rohen Zahlen NOCH IM Benachrichtigungs-Aufruf auslesen. Die
            // Notification selbst darf nicht auf den Hauptthread weitergereicht
            // werden — reine Zahlen duerfen das problemlos.
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(typeRaw: typeRaw, optionRaw: optionRaw)
            }
        })

        // Ausgabeweg gewechselt: Kopfhoerer rein/raus, Bluetooth verbunden …
        observers.add(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self?.handleRouteChange(reasonRaw: reasonRaw)
            }
        })

        // Der seltene, aber harte Fall: der Audio-Dienst des Systems wurde neu
        // gestartet. Danach ist jede bestehende Audio-Engine unbrauchbar.
        observers.add(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMediaServicesReset()
            }
        })
    }

    private func handleInterruption(typeRaw: UInt?, optionRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            // iOS hat die Engine bereits angehalten. Wir ziehen unseren eigenen
            // Zustand nach, damit Oberflaeche und Sperrbildschirm stimmen.
            isActive = false
            onEvent?(.interruptionBegan)
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionRaw ?? 0)
            onEvent?(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        // Nur dieser eine Grund ist gefaehrlich: das bisherige Ausgabegeraet ist
        // verschwunden. Alle anderen Wechsel (neues Geraet dazu, Kategorie
        // geaendert) duerfen die Wiedergabe ungestoert lassen.
        if reason == .oldDeviceUnavailable {
            onEvent?(.outputDeviceLost)
        }
    }

    private func handleMediaServicesReset() {
        invalidateConfiguration()
        onEvent?(.mediaServicesWereReset)
    }
}

// Kleiner Behaelter fuer die Rueckgabewerte von NotificationCenter.addObserver.
//
// Warum eine eigene Klasse statt eines Arrays direkt im Controller: der
// Controller ist an den Hauptthread gebunden (@MainActor), sein deinit aber
// nicht. Aus einem solchen deinit heraus kommt man an isolierte Eigenschaften
// nicht sauber heran. Dieser Behaelter ist an keinen Thread gebunden — stirbt
// der Controller, stirbt der Behaelter mit, und sein eigenes deinit meldet die
// Benachrichtigungen ab. So bleibt garantiert kein Beobachter haengen.
private final class ObserverTokens {
    private var tokens: [NSObjectProtocol] = []

    var isEmpty: Bool { tokens.isEmpty }

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    func removeAll() {
        let center = NotificationCenter.default
        for token in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }

    deinit {
        let center = NotificationCenter.default
        for token in tokens { center.removeObserver(token) }
    }
}

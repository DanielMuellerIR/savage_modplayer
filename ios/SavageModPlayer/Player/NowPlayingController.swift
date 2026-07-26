import Foundation
import MediaPlayer
import UIKit

// Alles, was ausserhalb der App-Oberflaeche ueber die Wiedergabe sichtbar oder
// bedienbar ist: der Sperrbildschirm, das Kontrollzentrum, die AirPods, die
// Anzeige im Auto (CarPlay) und auf der Apple Watch.
//
// Zwei Systemdienste stecken dahinter:
//  - MPRemoteCommandCenter nimmt Befehle ENTGEGEN (Play, Pause, weiter, …).
//  - MPNowPlayingInfoCenter zeigt an, WAS gerade laeuft (Titel, Dauer, Position).
//
// Beide sind global und gehoeren dem System, nicht der App. Deshalb gibt es
// genau eine Instanz dieser Klasse, und sie ist die einzige Stelle im Projekt,
// die diese beiden Dienste anfasst.
@MainActor
final class NowPlayingController {

    // Was der Nutzer von aussen ausgeloest hat. Die PlaybackEngine setzt
    // `onCommand` und uebersetzt diese Faelle in echte Wiedergabe-Aufrufe.
    enum Command: Sendable {
        case play
        case pause
        case togglePlayPause
        case nextTrack
        case previousTrack
        case seek(toSeconds: Double)   // absoluter Sprung (Scrubber im Sperrbildschirm)
        case skip(bySeconds: Double)   // relativer Sprung (+30 s / −15 s)
    }

    // Die Angaben, die auf dem Sperrbildschirm landen. Bewusst ein einfacher
    // Wert-Typ: so kann die PlaybackEngine ihn zusammenbauen, ohne dass diese
    // Klasse den Core oder die Bibliothek kennen muss.
    struct TrackInfo: Equatable {
        var title: String            // Songtitel (Header oder Dateiname)
        var formatLabel: String      // Kuerzel fuers Bild: "MOD", "S3M", "XM", "IT"
        var formatDescription: String // ausgeschrieben, z. B. "Impulse Tracker (IT)"
        var folderPath: String       // Ordner in der Bibliothek, z. B. "Demos › 1994"
        var duration: Double         // Gesamtdauer in Sekunden
    }

    // Sprungweiten der beiden Pfeiltasten im Sperrbildschirm. Bewusst
    // unsymmetrisch: zurueck kurz (man hat etwas verpasst), vorwaerts lang
    // (man will etwas ueberspringen) — dieselbe Aufteilung nutzen Podcast-Apps.
    // `nonisolated`, weil die Fernsteuerungs-Bloecke unten an keinen Actor
    // gebunden sind (siehe `bind`) und diese beiden Werte trotzdem lesen muessen.
    nonisolated static let skipForwardInterval: Double = 30
    nonisolated static let skipBackwardInterval: Double = 15

    // Wird bei jedem Fernsteuerungs-Befehl aufgerufen. Setzt die PlaybackEngine.
    var onCommand: ((Command) -> Void)?

    // Angemeldete Befehls-Empfaenger, damit sie wieder abgemeldet werden koennen.
    private var commandTokens: [(command: MPRemoteCommand, token: Any)] = []

    // Fertig gezeichnete Titelbilder je Formatkuerzel. Das Zeichnen kostet
    // spuerbar Zeit; bei einem Ordner mit hunderten Titeln waere es Verschwendung,
    // fuer jeden Titelwechsel dasselbe "MOD"-Bild neu zu malen. Es gibt genau
    // vier moegliche Bilder, also passt der Zwischenspeicher problemlos.
    private var artworkCache: [String: MPMediaItemArtwork] = [:]

    // Der zuletzt geschriebene Stand, um unnoetige Schreibvorgaenge zu erkennen.
    private var lastInfo: TrackInfo?
    private var lastRate: Double = -1
    private var lastElapsedWriteTime: TimeInterval = 0

    // MPNowPlayingInfoCenter ist teuer: jeder Schreibvorgang wandert ueber die
    // Prozessgrenze zum System. Die Spielzeit im Sperrbildschirm laeuft ohnehin
    // von selbst weiter (das System rechnet sie aus Position und Rate hoch),
    // deshalb genuegt ein Abgleich pro Sekunde. 30 Aktualisierungen pro Sekunde
    // waeren unsichtbar und wuerden nur Akku kosten.
    private static let minimumElapsedWriteInterval: TimeInterval = 1.0

    // MARK: - Fernsteuerung

    // Alle Befehle beim System anmelden. Mehrfachaufrufe sind harmlos: es wird
    // zuerst sauber abgemeldet, damit kein Empfaenger doppelt haengt.
    func activate() {
        deactivate()
        let center = MPRemoteCommandCenter.shared()

        bind(center.playCommand) { _ in .play }
        bind(center.pauseCommand) { _ in .pause }
        bind(center.togglePlayPauseCommand) { _ in .togglePlayPause }
        bind(center.nextTrackCommand) { _ in .nextTrack }
        bind(center.previousTrackCommand) { _ in .previousTrack }

        // Der Positions-Regler im Sperrbildschirm liefert eine absolute Zeit.
        bind(center.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return nil }
            return .seek(toSeconds: event.positionTime)
        }

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForwardInterval)]
        bind(center.skipForwardCommand) { _ in .skip(bySeconds: Self.skipForwardInterval) }

        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBackwardInterval)]
        bind(center.skipBackwardCommand) { _ in .skip(bySeconds: -Self.skipBackwardInterval) }

        disableUnsupportedCommands(center)
    }

    // Alle Befehls-Empfaenger wieder abmelden.
    func deactivate() {
        for entry in commandTokens {
            entry.command.removeTarget(entry.token)
        }
        commandTokens.removeAll()
    }

    // Ein Befehl, den diese App nicht bedient, muss ausdruecklich abgeschaltet
    // werden. Sonst zeigt iOS ihn im Sperrbildschirm als Knopf an, der beim
    // Druecken nichts tut — das wirkt kaputt.
    private func disableUnsupportedCommands(_ center: MPRemoteCommandCenter) {
        let unsupported: [MPRemoteCommand] = [
            center.stopCommand,
            center.seekForwardCommand,      // Dauerdruck-Spulen; wir haben feste Spruenge
            center.seekBackwardCommand,
            center.changePlaybackRateCommand,
            center.changeRepeatModeCommand, // Loop-Modus wird in der App gesetzt
            center.changeShuffleModeCommand,
            center.ratingCommand,
            center.likeCommand,
            center.dislikeCommand,
            center.bookmarkCommand,
            center.enableLanguageOptionCommand,
            center.disableLanguageOptionCommand
        ]
        for command in unsupported {
            command.isEnabled = false
        }
    }

    // Verbindet einen Systembefehl mit einem eigenen Command-Wert.
    //
    // Der Handler kann von iOS auf einem beliebigen Thread aufgerufen werden.
    // Deshalb wird der ausgewertete Befehl ueber einen Sprung auf den
    // Hauptthread zugestellt; die Rueckmeldung an das System erfolgt sofort.
    //
    // Der Handler wird bewusst ueber eine ausdruecklich als `@Sendable`
    // getypte Zwischenvariable uebergeben. Grund: diese Klasse ist
    // @MainActor-isoliert, und ein hier gebildeter Block erbt diese Isolation.
    // Ruft iOS ihn dann von einem anderen Thread auf, stellt die Swift-Laufzeit
    // den Bruch fest und beendet den Prozess mit SIGTRAP — ausgerechnet beim
    // Druck auf den Sperrbildschirm-Knopf, also dort, wo es niemand im
    // Simulator bemerkt. Ein `@Sendable`-Block ist dagegen an keinen Actor
    // gebunden; er darf ueberall laufen und springt selbst auf den Hauptthread.
    private func bind(
        _ command: MPRemoteCommand,
        translate: @escaping @Sendable (MPRemoteCommandEvent) -> Command?
    ) {
        command.isEnabled = true
        let handler: @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] event in
            guard let translated = translate(event) else { return .commandFailed }
            Task { @MainActor in
                self?.onCommand?(translated)
            }
            return .success
        }
        let token = command.addTarget(handler: handler)
        commandTokens.append((command, token))
    }

    // MARK: - Anzeige

    // Den Sperrbildschirm auf Stand bringen.
    //
    // `force` erzwingt einen sofortigen Schreibvorgang. Das ist bei jedem
    // Ereignis noetig, das der Nutzer unmittelbar sieht — Pause, Fortsetzen,
    // Titelwechsel, Sprung. Ohne das haengt die Anzeige bis zu einer Sekunde
    // hinterher und fuehlt sich traege an. Der regelmaessige Sekundentakt
    // laeuft dagegen mit `force = false` und darf uebersprungen werden.
    func update(info: TrackInfo, isPlaying: Bool, isPaused: Bool, elapsed: Double, force: Bool) {
        let rate: Double = (isPlaying && !isPaused) ? 1.0 : 0.0
        let now = Date.timeIntervalSinceReferenceDate
        let contentChanged = (info != lastInfo) || (rate != lastRate)
        let dueForUpdate = (now - lastElapsedWriteTime) >= Self.minimumElapsedWriteInterval

        guard force || contentChanged || dueForUpdate else { return }

        var payload: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            // Das Format steht in der Kuenstlerzeile: bei Tracker-Modulen ist das
            // die Angabe, die am ehesten interessiert.
            MPMediaItemPropertyArtist: info.formatDescription,
            MPMediaItemPropertyPlaybackDuration: max(0, info.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        // Der Ordnerpfad steht als "Album" — so bleibt in gemischten Sammlungen
        // erkennbar, aus welcher Ecke der Bibliothek der Titel stammt.
        if !info.folderPath.isEmpty {
            payload[MPMediaItemPropertyAlbumTitle] = info.folderPath
        }
        payload[MPMediaItemPropertyArtwork] = artwork(for: info.formatLabel)

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = payload
        center.playbackState = isPlaying ? (isPaused ? .paused : .playing) : .stopped

        lastInfo = info
        lastRate = rate
        lastElapsedWriteTime = now
    }

    // Nichts geladen: Anzeige leeren, sonst behauptet der Sperrbildschirm
    // weiterhin, diese App spiele etwas.
    func clear() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        lastInfo = nil
        lastRate = -1
        lastElapsedWriteTime = 0
    }

    // MARK: - Titelbild

    // Es gibt (noch) kein App-Icon-Asset, also wird das Titelbild gezeichnet:
    // dunkler Hintergrund in der Hausfarbe, angedeutete Wellenform, darueber das
    // Formatkuerzel. Ergebnis wird je Kuerzel behalten (siehe artworkCache).
    private func artwork(for label: String) -> MPMediaItemArtwork {
        if let cached = artworkCache[label] { return cached }

        // 512 Punkte reichen fuer Sperrbildschirm und Kontrollzentrum bequem aus.
        let size = CGSize(width: 512, height: 512)
        let image = Self.drawArtwork(label: label, size: size)
        // Der Anforderungs-Block darf von iOS in beliebiger Groesse aufgerufen
        // werden. Wir liefern immer dasselbe fertige Bild; das System skaliert.
        //
        // Das `@Sendable` ist Pflicht, nicht Kosmetik: diese Klasse ist
        // @MainActor-isoliert, und ein hier gebildeter Block erbt diese
        // Isolation. MediaPlayer ruft ihn aber auf einer eigenen Warteschlange
        // auf — die Swift-Laufzeit stellt den Bruch fest und beendet den Prozess
        // mit SIGTRAP, sobald ein Titel geladen wird. Ein `@Sendable`-Block ist
        // an keinen Actor gebunden und darf ueberall laufen.
        let artwork = MPMediaItemArtwork(boundsSize: size) { @Sendable _ in image }
        artworkCache[label] = artwork
        return artwork
    }

    private static func drawArtwork(label: String, size: CGSize) -> UIImage {
        let accent = UIColor(red: 0.24, green: 0.90, blue: 0.71, alpha: 1.0)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext

            // Hintergrund: senkrechter Verlauf von fast schwarz zu tiefem Gruen.
            let colors = [
                UIColor(red: 0.04, green: 0.10, blue: 0.09, alpha: 1.0).cgColor,
                UIColor(red: 0.01, green: 0.03, blue: 0.04, alpha: 1.0).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.0, 1.0]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }

            // Angedeutete Wellenform im unteren Drittel — rein dekorativ, aber
            // sie macht das Bild auf den ersten Blick als Musik erkennbar.
            cg.setStrokeColor(accent.withAlphaComponent(0.45).cgColor)
            cg.setLineWidth(max(1, size.height / 80))
            cg.setLineJoin(.round)
            let baseline = size.height * 0.74
            let steps = 24
            let stepWidth = size.width / CGFloat(steps)
            cg.move(to: CGPoint(x: 0, y: baseline))
            for step in 1...steps {
                // Feste, sich wiederholende Auslenkungen statt Zufall: so sieht
                // das Bild bei jedem Start identisch aus.
                let pattern: [CGFloat] = [0.10, 0.04, 0.16, 0.06, 0.12, 0.03]
                let amplitude = size.height * pattern[step % pattern.count]
                let direction: CGFloat = step % 2 == 0 ? -1 : 1
                cg.addLine(to: CGPoint(
                    x: stepWidth * CGFloat(step),
                    y: baseline + direction * amplitude
                ))
            }
            cg.strokePath()

            // Formatkuerzel gross und mittig im oberen Bereich.
            let font = UIFont.monospacedSystemFont(ofSize: size.height * 0.26, weight: .heavy)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: accent
            ]
            let text = label as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: size.height * 0.36 - textSize.height / 2
                ),
                withAttributes: attributes
            )
        }
    }
}

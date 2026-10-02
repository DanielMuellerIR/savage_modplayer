import Combine
import Foundation
import SwiftUI

// Klammer um die drei Bereiche der App. Es gibt genau eine Instanz, erzeugt in
// SavageModPlayerApp; alle Views holen sie sich per @EnvironmentObject.
//
// AppModel selbst enthaelt absichtlich fast keine Logik. Es besitzt die drei
// Bausteine, verdrahtet sie einmal miteinander und reicht den Szenen-Zustand
// weiter. Alles Fachliche liegt in Player/, Library/ und UI/.
@MainActor
final class AppModel: ObservableObject {

    // Klang- und Wiedergabe-Einstellungen (PAL/NTSC, LED-Filter, Interpolation,
    // Stereo-Separation, Lautstaerke, Loop-Modus, Shuffle, Theme).
    let settings: PlayerSettings

    // Bibliothek: Index, Ordnerbaum, Import, Zuruecksetzen, Favoriten.
    let library: LibraryStore

    // Wiedergabe: Core-Coordinator, Titelwechsel, AudioSession, Now Playing.
    let player: PlaybackEngine

    // Ist die App gerade im Vordergrund und sichtbar? Zusammen mit dem
    // Scroll-Viewport entscheidet dieser Zustand, ob Visualisierungen laufen.
    // Bei gesperrtem Bildschirm laeuft der Ton weiter, die Scope-Arbeit stoppt.
    @Published private(set) var isSceneActive = true

    // Ist gerade das Suchfeld der Bibliothek aktiv?
    //
    // Das Kuerzel fuer Abspielen/Pause liegt auf der Leertaste, ohne Zusatz.
    // Waehrend jemand einen Titel sucht, muss die Leertaste aber ein
    // Leerzeichen tippen. Darauf zu hoffen, dass iOS richtig entscheidet, waere
    // geraten: Ein Menuebefehl der Szene wird vor dem Texteingabefeld gefragt.
    // Deshalb schaltet PlaybackCommands das Kuerzel hier ausdruecklich ab —
    // ein abgeschalteter Befehl greift die Taste nicht, und sie erreicht das
    // Feld.
    @Published var isSearchFieldActive = false

    // Von aussen hereingereichte Dateien, die noch auf den Import warten. Sie
    // treffen typischerweise beim Kaltstart ein — genau dann, wenn die
    // Bibliothek noch mit dem Startabgleich beschaeftigt ist und keinen Import
    // annimmt.
    //
    // `playFirst` unterscheidet die beiden Wege: "Oeffnen mit" reicht genau eine
    // Datei herein und der Nutzer will sie hoeren; ein Fallenlassen aus der
    // Dateien-App kann ein ganzer Ordner sein und soll die laufende Wiedergabe
    // nicht unterbrechen.
    private struct PendingSource {
        let url: URL
        let playFirst: Bool
    }
    private var pendingOpenURLs: [PendingSource] = []
    private var cancellables = Set<AnyCancellable>()

    // Die Vorgaben sind der Normalfall der App. Tests reichen eine Bibliothek
    // mit eigener Wurzel herein, damit sie nicht im echten `Documents/` des
    // Simulators arbeiten.
    init(settings: PlayerSettings = PlayerSettings(), library: LibraryStore = LibraryStore()) {
        self.settings = settings
        self.library = library
        self.player = PlaybackEngine(settings: settings, library: library)

        // Sobald die Bibliothek wieder frei ist, kommt eine wartende Datei dran.
        library.$isBusy
            .removeDuplicates()
            .sink { [weak self] busy in
                guard !busy else { return }
                // Der Sink laeuft im Zweifel nicht auf dem MainActor, diese
                // Klasse ist aber @MainActor-isoliert. Der Sprung ist deshalb
                // Pflicht, nicht Kosmetik (siehe AGENTS: Swift-6-Isolation).
                Task { @MainActor in self?.openPendingFiles() }
            }
            .store(in: &cancellables)
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        let active = (phase == .active)
        guard active != isSceneActive else { return }
        isSceneActive = active
        player.setSceneActive(active)
    }

    // MARK: - "Oeffnen mit"

    // Eine von aussen hereingereichte Datei: aus der Dateien-App, aus Mail, aus
    // der Finder-Dateifreigabe oder von einer anderen App.
    //
    // Sie wird nicht bloss abgespielt, sondern zuerst in die Bibliothek
    // uebernommen. Das ist der ehrliche Weg: Die Wahrheit der Bibliothek ist
    // `Documents/`, und eine nur weitergereichte URL waere beim naechsten Start
    // wertlos — iOS raeumt den Uebergabeordner wieder auf. Ein Archiv wird dabei
    // wie jede andere Quelle behandelt und unterwegs ausgepackt.
    func open(_ url: URL) {
        pendingOpenURLs.append(PendingSource(url: url, playFirst: true))
        openPendingFiles()
    }

    // MARK: - Fallenlassen aus der Dateien-App

    // Auf breiten Bildschirmen zieht man Dateien direkt aus der Dateien-App in
    // die Bibliothek. Der Weg ist derselbe wie bei "Oeffnen mit" — Uebernahme
    // nach `Documents/`, Archive unterwegs ausgepackt —, nur ohne anschliessend
    // etwas abzuspielen: Wer waehrend eines laufenden Titels zehn Module
    // ablegt, will sie sortiert wissen und nicht mitten im Stueck unterbrochen
    // werden.
    func importDropped(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pendingOpenURLs.append(contentsOf: urls.map { PendingSource(url: $0, playFirst: false) })
        openPendingFiles()
    }

    private func openPendingFiles() {
        guard let first = pendingOpenURLs.first, !library.isBusy else { return }
        // Immer nur einen Stapel gleicher Art auf einmal: Sonst muesste der
        // Bericht rueckwaerts einzelnen Quellen zugeordnet werden, und dafuer
        // gibt es keine verlaessliche Zuordnung. Der Rest kommt beim naechsten
        // Durchlauf dran — dafuer sorgt der Sink auf `isBusy`.
        let playFirst = first.playFirst
        let batchEnd = pendingOpenURLs.firstIndex { $0.playFirst != playFirst }
            ?? pendingOpenURLs.endIndex
        let batch = pendingOpenURLs[..<batchEnd]
        pendingOpenURLs.removeSubrange(..<batchEnd)

        library.importSources(batch.map(\.url)) { [weak self] report in
            guard let self else { return }
            // Wartet noch ein Stapel der anderen Art, kommt er jetzt dran.
            defer { self.openPendingFiles() }
            guard playFirst, let report else { return }
            // Ein bereits vorhandener Titel ist kein Fehlschlag: Dann spielt
            // eben der, der schon in der Bibliothek steht.
            guard let path = report.imported.first ?? report.duplicates.first,
                  let track = self.library.tracks.first(where: { $0.relativePath == path })
            else { return }
            self.player.play(track)
        }
    }
}

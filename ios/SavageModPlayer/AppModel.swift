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

    // Per "Oeffnen mit" hereingereichte Dateien, die noch auf den Import
    // warten. Sie treffen typischerweise beim Kaltstart ein — genau dann, wenn
    // die Bibliothek noch mit dem Startabgleich beschaeftigt ist und keinen
    // Import annimmt.
    private var pendingOpenURLs: [URL] = []
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
        pendingOpenURLs.append(url)
        openPendingFiles()
    }

    private func openPendingFiles() {
        guard !pendingOpenURLs.isEmpty, !library.isBusy else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs = []
        library.importSources(urls) { [weak self] report in
            guard let self, let report else { return }
            // Ein bereits vorhandener Titel ist kein Fehlschlag: Dann spielt
            // eben der, der schon in der Bibliothek steht.
            guard let path = report.imported.first ?? report.duplicates.first,
                  let track = self.library.tracks.first(where: { $0.relativePath == path })
            else { return }
            self.player.play(track)
        }
    }
}

import Combine
import Foundation
import SwiftUI
import SavageModPlayerCore

// Klammer um die drei Bereiche der App. Es gibt genau eine Instanz, erzeugt in
// SavageModPlayerApp; alle Views holen sie sich per @EnvironmentObject.
//
// AppModel selbst enthaelt absichtlich fast keine Logik. Es besitzt die
// fachlichen Bausteine, verdrahtet sie einmal miteinander und reicht den Szenen-Zustand
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

    let playlists: PlaylistCollectionStore
    let catalog: LibraryCatalogModel
    let markers: SongMarkersModel

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
    @Published var isLibraryPanelOpen = false {
        didSet { if !isLibraryPanelOpen { Task { [weak self] in self?.openPendingFiles(); self?.openPendingCollection() } } }
    }
    @Published var collectionContext: CollectionExchangeContext? {
        didSet {
            collectionSync?.setPaused(collectionContext != nil)
            isLibraryPanelOpen = collectionContext != nil
        }
    }
    @Published private(set) var collectionSync: CollectionSyncModel?
    @Published var collectionSyncContext: CollectionSyncContext? {
        didSet {
            if collectionSyncContext == nil {
                if isSceneActive { collectionSync?.activate() }
                Task { [weak self] in self?.openPendingFiles(); self?.openPendingCollection() }
            }
        }
    }
    private var pendingCollectionURLs: [URL] = []
    private let collectionPersistence: CollectionExchangePersistence?
    private let collectionPreferences: CollectionExchangePreferences?
    private let syncPersistence: CollectionExchangePersistence?
    private let syncService: CollectionSyncService?
    private let collectionRecoveryFailure: @MainActor (Error) -> Void
    var isTextEntryActive: Bool { isSearchFieldActive || isLibraryPanelOpen || collectionSyncContext != nil }

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
        var deferredPlaybackRevision: UInt64? = nil
    }
    private var pendingOpenURLs: [PendingSource] = []
    private var cancellables = Set<AnyCancellable>()

    // Die Vorgaben sind der Normalfall der App. Tests reichen eine Bibliothek
    // mit eigener Wurzel herein, damit sie nicht im echten `Documents/` des
    // Simulators arbeiten.
    init(settings: PlayerSettings = PlayerSettings(), library: LibraryStore = LibraryStore(),
         playlists: PlaylistCollectionStore = PlaylistCollectionStore(), catalog: LibraryCatalogModel? = nil,
         markers: SongMarkersModel? = nil, playbackSettings: TrackPlaybackSettingsModel? = nil,
         collectionPersistence: CollectionExchangePersistence? = nil, collectionPreferences: CollectionExchangePreferences? = nil,
         syncPersistence: CollectionExchangePersistence? = nil,
         syncService: CollectionSyncService? = CollectionSyncConfiguration.service(),
         collectionRecoveryFailure: @escaping @MainActor (Error) -> Void = { _ in }) {
        self.collectionPersistence = collectionPersistence; self.collectionPreferences = collectionPreferences
        self.collectionRecoveryFailure = collectionRecoveryFailure
        self.syncPersistence = syncPersistence; self.syncService = syncService
        self.settings = settings
        self.library = library
        self.catalog = catalog ?? Self.makeCatalog()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.markers = markers ?? SongMarkersModel(fileURL: support.appendingPathComponent("SavageModPlayer/song-markers.json"))
        self.player = PlaybackEngine(settings: settings, library: library, catalog: self.catalog, playbackSettings: playbackSettings)
        self.playlists = playlists

        // Sobald die Bibliothek wieder frei ist, kommt eine wartende Datei dran.
        library.$isBusy
            .removeDuplicates()
            .sink { [weak self] busy in
                guard !busy else { return }
                // Der Sink laeuft im Zweifel nicht auf dem MainActor, diese
                // Klasse ist aber @MainActor-isoliert. Der Sprung ist deshalb
                // Pflicht, nicht Kosmetik (siehe AGENTS: Swift-6-Isolation).
                Task { @MainActor in
                    self?.openPendingFiles(); self?.openPendingCollection()
                    if self?.isSceneActive == true { self?.collectionSync?.activate() }
                }
            }
            .store(in: &cancellables)

        library.tracksDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in self?.refreshCatalog(tracks) }
            .store(in: &cancellables)
        library.favoritesDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.catalog.setFavorites(self.library.favorites)
                self.collectionSync?.metadataDidChange()
            }
            .store(in: &cancellables)
        playlists.metadataDidChange.merge(with: self.markers.metadataDidChange, player.playbackSettings.metadataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.collectionSync?.metadataDidChange() }
            .store(in: &cancellables)
        refreshCatalog(library.tracks)
    }

    private static func makeCatalog() -> LibraryCatalogModel {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SavageModPlayer")
        return LibraryCatalogModel(metadataURL: support.appendingPathComponent("metadata.json"),
                                   preferencesURL: support.appendingPathComponent("library-preferences.json"))
    }

    private func refreshCatalog(_ tracks: [TrackRef]) {
        catalog.setFavorites(library.favorites)
        catalog.setSources(tracks.map {
            LibraryCatalogSource(id: $0.relativePath, url: $0.url, displayName: $0.displayName,
                                 folderPath: $0.folderPath.joined(separator: "/"), addedAt: $0.addedAt)
        })
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        let active = (phase == .active)
        guard active != isSceneActive else { return }
        isSceneActive = active
        player.setSceneActive(active)
        if active { collectionSync?.activate() } else { collectionSync?.deactivate() }
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
        if url.pathExtension.lowercased() == CollectionExchangeCodec.fileExtension {
            pendingCollectionURLs.append(url); openPendingCollection(); return
        }
        pendingOpenURLs.append(PendingSource(url: url, playFirst: true,
            deferredPlaybackRevision: collectionContext == nil && collectionSyncContext == nil ? nil : player.requestRevision))
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
        pendingCollectionURLs.append(contentsOf: urls.filter { $0.pathExtension.lowercased() == CollectionExchangeCodec.fileExtension })
        pendingOpenURLs.append(contentsOf: urls.filter { $0.pathExtension.lowercased() != CollectionExchangeCodec.fileExtension }.map { PendingSource(url: $0, playFirst: false) })
        openPendingFiles()
        openPendingCollection()
    }

    private func openPendingFiles() {
        guard let first = pendingOpenURLs.first, !library.isBusy, collectionContext == nil, collectionSyncContext == nil else { return }
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
            defer { self.openPendingFiles(); self.openPendingCollection() }
            guard playFirst, let report else { return }
            if let revision = first.deferredPlaybackRevision, revision != self.player.requestRevision { return }
            // Ein bereits vorhandener Titel ist kein Fehlschlag: Dann spielt
            // eben der, der schon in der Bibliothek steht.
            guard let path = report.imported.first ?? report.duplicates.first,
                  let track = self.library.tracks.first(where: { $0.relativePath == path })
            else { return }
            self.player.play(track)
            if let revision = first.deferredPlaybackRevision {
                for index in self.pendingOpenURLs.indices where self.pendingOpenURLs[index].deferredPlaybackRevision == revision {
                    self.pendingOpenURLs[index].deferredPlaybackRevision = self.player.requestRevision
                }
            }
        }
    }

    func showCollectionExchange(fileURL: URL? = nil) {
        guard collectionContext == nil, collectionSyncContext == nil, !isLibraryPanelOpen, !library.isBusy else {
            if let fileURL { pendingCollectionURLs.append(fileURL) }
            return
        }
        do {
            let preferences = collectionPreferences ?? CollectionExchangeSupport.preferences()
            do {
                let recovery = try syncPersistence ?? collectionPersistence ?? CollectionExchangeSupport.persistence()
                _ = try recovery.recover { try preferences.replace(expected: $0, replacement: $1) }
            } catch { player.stop(); collectionRecoveryFailure(error); throw error }
            let binding = CollectionExchangeSupport.binding(library: library, playlists: playlists, markers: markers, player: player,
                settings: settings, persistence: try collectionPersistence ?? CollectionExchangeSupport.persistence(includeSync: false),
                preferences: collectionPreferences ?? CollectionExchangeSupport.preferences(), recoveryFailed: collectionRecoveryFailure)
            collectionContext = .init(model: binding.makeModel(read: { url, cancelled in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var document: CollectionExchangeDocument?
                try FileProviderReader.read(url, isCancelled: cancelled) { local in
                    document = try CollectionExchangeCodec.load(from: local, isCancelled: cancelled)
                }
                guard let document else { throw CollectionExchangeError.unreadable }
                return document
            }), fileURL: fileURL)
        } catch {
            collectionContext = .init(model: .init(capture: { throw error }, apply: { _ in throw error }), fileURL: fileURL)
        }
    }
    func prepareCollectionSync() {
        guard collectionSync == nil else { return }
        do {
            let binding = CollectionExchangeSupport.binding(library: library, playlists: playlists, markers: markers, player: player,
                settings: settings, persistence: try syncPersistence ?? collectionPersistence ?? CollectionExchangeSupport.persistence(),
                preferences: collectionPreferences ?? CollectionExchangeSupport.preferences(), recoveryFailed: collectionRecoveryFailure)
            collectionSync = .init(binding: binding, service: syncService)
            if !library.isBusy && isSceneActive { collectionSync?.activate() }
        } catch { collectionRecoveryFailure(error) }
    }

    func showCollectionSync() {
        guard collectionContext == nil, collectionSyncContext == nil, !library.isBusy else { return }
        prepareCollectionSync()
        if let collectionSync { collectionSyncContext = .init(model: collectionSync) }
    }

    private func openPendingCollection() {
        guard !pendingCollectionURLs.isEmpty, !library.isBusy, collectionContext == nil, collectionSyncContext == nil, !isLibraryPanelOpen,
              pendingOpenURLs.isEmpty else { return }
        let url = pendingCollectionURLs.removeFirst(); showCollectionExchange(fileURL: url)
    }
}

import Combine
import Foundation
import SavageModPlayerCore

// Die Bibliothek, wie die Oberflaeche sie sieht: ein Ordnerbaum, eine flache
// Abspielreihenfolge, Favoriten — und die vier Vorgaenge, die daran etwas
// aendern (Abgleich, Import, Archive auspacken, Zuruecksetzen).
//
// Die Arbeitsteilung: der Core erledigt die Dateiarbeit und weiss nichts von
// SwiftUI (`MusicLibrary`, `LibraryImporter`, `LibraryReset`). Dieser Store
// macht daraus beobachtbaren Zustand und uebernimmt die drei Dinge, die der
// Core bewusst offen laesst:
//
// 1. **Immer nur ein Vorgang.** `MusicLibrary` und `LibraryImporter` sind
//    `@unchecked Sendable`, also ausdruecklich nicht gegen gleichzeitige
//    Schreibzugriffe abgesichert. Deshalb laeuft jede Dateiarbeit auf genau
//    einer seriellen Schlange (`worker`), und `isBusy` weist jeden weiteren
//    Vorgang ab, solange einer laeuft.
// 2. **Nichts Schweres auf dem Haupt-Thread.** Ein Import kopiert und entpackt
//    womoeglich Gigabytes. Auf den MainActor kommen nur fertige, kleine
//    Ergebnisse zurueck: Fortschritt (gedrosselt), Bericht, Baum.
// 3. **Abbruch ohne halben Zustand.** Der Abbruch-Haken des Core wird zwischen
//    den Dateien geprueft; danach steht im Index genau das, was wirklich auf der
//    Platte liegt. Nach jedem Vorgang wird der Baum neu aus dem Index gebaut.
//
// Die Bibliothek liegt in `Documents`, ist also ueber die Finder-Dateifreigabe
// und die Dateien-App sichtbar. Der Nutzer legt dort Dateien ab und loescht sie
// wieder — deshalb ist `start()` nicht nur "laden", sondern immer auch
// "abgleichen".
@MainActor
final class LibraryStore: ObservableObject {

    // MARK: - Zustand fuer die Oberflaeche

    // Anzeigebaum und flache Abspielreihenfolge. Beide gehoeren zusammen und
    // werden immer gemeinsam gesetzt: `tracks` ist exakt die Tiefensuche durch
    // `tree`, damit Weiter/Zurueck der Anzeige folgt.
    @Published private(set) var tree: PlaylistScanner.FolderNode?
    @Published private(set) var tracks: [TrackRef] = []

    // Laeuft gerade ein Vorgang? Solange das gilt, wird kein zweiter gestartet.
    @Published private(set) var isBusy = false
    // Welcher Vorgang das ist — fuer die Beschriftung waehrend der Arbeit.
    @Published private(set) var activity: LibraryActivity?
    // Zwischenstand waehrend Import und Auspacken; nil, wenn es (noch) nichts
    // zu zeigen gibt.
    @Published private(set) var progress: ImportProgress?
    // Abschlussbericht des letzten Import- oder Auspack-Vorgangs.
    @Published private(set) var lastReport: ImportReport?
    // Archive, die per Finder oder Dateien-App in der Bibliothek gelandet sind
    // und beim automatischen Auspacken uebrig blieben. Im Normalfall ist diese
    // Liste leer: der Abgleich behandelt ZIPs wie die Mac-App als Ordner und
    // packt sie direkt aus. Sichtbar bleiben nur Abbruch- und Fehlerfaelle, damit
    // der Nutzer sie nach Beseitigung der Ursache erneut versuchen kann.
    @Published private(set) var pendingArchives: [String] = []
    // Fehlermeldung fuer einen Hinweis-Dialog. Die Texte kommen teils aus dem
    // Core und sind dort deutsch formuliert.
    @Published var errorMessage: String?

    // Favoriten. Schluessel ist der relative Pfad aus dem Index — die einzige
    // ID, die eine Neuinstallation ueberlebt (der Container-Pfad wechselt).
    @Published private(set) var favorites: Set<String> = []

    // MARK: - Innereien

    static let favoritesDefaultsKey = "savage.ios.favorites"

    private let defaults: UserDefaults
    // Die serielle Schlange ist die eigentliche Absicherung gegen parallele
    // Zugriffe auf `MusicLibrary`: dort laeuft immer nur ein Block.
    private let worker = DispatchQueue(label: "com.viben.SavageModPlayer.library", qos: .utility)
    private let cancellation = LibraryFlag()

    private var library: MusicLibrary?
    private var currentTask: Task<Void, Never>?
    private var hasStarted = false

    // Schneller Zugriff auf einen Titel ueber seinen relativen Pfad.
    private var trackIndex: [String: TrackRef] = [:]
    // Klein geschriebene, diakritikfreie Fassung von `tracks[i].displayName` —
    // einmal auf der Arbeitsschlange gebaut, damit die Suche bei jedem
    // Tastendruck nur noch vergleichen muss.
    private var searchNames: [String] = []
    // Zaehler, der sich bei jeder Aenderung an Titeln oder Favoriten erhoeht.
    // Er macht den Filter-Zwischenspeicher unten ungueltig.
    private var generation = 0
    private var filterCache: (key: FilterKey, tracks: [TrackRef], tree: PlaylistScanner.FolderNode?)?

    init(defaults: UserDefaults = .standard, library: MusicLibrary? = nil) {
        self.defaults = defaults
        self.library = library
        let stored = defaults.stringArray(forKey: Self.favoritesDefaultsKey) ?? []
        favorites = Set(stored)
    }

    // MARK: - Start

    // Beim App-Start: gespeicherten Index laden, sofort anzeigen, danach im
    // Hintergrund mit dem Dateisystem abgleichen und die Anzeige nachziehen.
    // Der Abgleich haelt die App nicht auf — er beginnt erst, wenn schon etwas
    // zu sehen ist.
    func start() {
        guard !hasStarted, !isBusy else { return }
        hasStarted = true
        runScan(loadCachedFirst: true)
    }

    // Erneuter Abgleich waehrend des Betriebs — sinnvoll, wenn die App aus dem
    // Hintergrund zurueckkommt: was inzwischen ueber die Dateien-App abgelegt
    // oder geloescht wurde, steht danach richtig im Index. Laeuft gerade ein
    // Vorgang, passiert nichts.
    func refresh() {
        guard hasStarted, !isBusy else { return }
        runScan(loadCachedFirst: false)
    }

    private func runScan(loadCachedFirst: Bool) {
        beginOperation(.scanning)

        currentTask = Task { [weak self] in
            guard let self else { return }
            guard let library = await self.resolveLibrary() else {
                self.endOperation()
                return
            }

            // Schritt 1: der gespeicherte Stand, ohne eine einzige Datei zu lesen.
            if loadCachedFirst {
                let cached = await self.onWorker { LibrarySnapshot.make(from: library) }
                self.apply(cached)
            }

            // Schritt 2: Fremdablagen und Fremdloeschungen einsammeln.
            let flag = self.cancellation
            let outcome: ScanOutcome = await self.onWorker {
                do {
                    let report = try library.rescan(isCancelled: { flag.isSet })
                    return ScanOutcome(
                        archives: report.archivesFound,
                        // Ein abgebrochener Durchlauf hat nur einen Teil des
                        // Ordners gesehen — seine Archivliste ist unvollstaendig
                        // und darf die bisherige nicht ersetzen.
                        archivesComplete: !report.wasCancelled,
                        snapshot: LibrarySnapshot.make(from: library),
                        errorMessage: nil)
                } catch {
                    return ScanOutcome(
                        archives: [],
                        archivesComplete: false,
                        snapshot: nil,
                        errorMessage: LibraryStore.describe(error))
                }
            }

            if let snapshot = outcome.snapshot { self.apply(snapshot) }
            if outcome.archivesComplete { self.pendingArchives = outcome.archives }
            self.errorMessage = outcome.errorMessage ?? self.errorMessage

            // ZIPs aus Finder-Dateifreigabe oder Dateien-App verhalten sich wie
            // importierte Ordner: finden, automatisch streamend auspacken und
            // den resultierenden Baum anzeigen. Der Sicherheitsfilter und der
            // konstante Speicherbedarf bleiben im Core identisch zum manuellen
            // Weg. Nach Abbruch wird nicht heimlich weitergearbeitet.
            if outcome.archivesComplete,
               !outcome.archives.isEmpty,
               !flag.isSet {
                await self.unpackArchives(in: library)
            }
            self.endOperation()
        }
    }

    // MARK: - Weg A: Ordner-Import

    // Importiert die im Dateiauswahl-Blatt gewaehlten Ordner. Laeuft komplett im
    // Hintergrund; die Oberflaeche sieht nur Fortschritt und Bericht.
    func importFolders(_ urls: [URL]) {
        guard !urls.isEmpty, !isBusy else { return }

        // Der Zugriff auf ausgewaehlte Ordner wird EINMAL geoeffnet und erst
        // geschlossen, wenn der Vorgang vorbei ist — auch bei Abbruch oder
        // Fehler (`defer` unten). Ohne diese Klammer bleibt alles ausserhalb des
        // App-Containers unlesbar.
        let access = LibraryScopedAccess.open(urls)
        beginOperation(.importing)
        lastReport = nil

        currentTask = Task { [weak self] in
            guard let self else {
                access.close()
                return
            }
            defer { access.close() }

            guard let library = await self.resolveLibrary() else {
                self.endOperation()
                return
            }
            let flag = self.cancellation
            let relay = self.makeProgressRelay()

            let outcome: ImportOutcome = await self.onWorker {
                let reader = FileProviderReader(isCancelled: { flag.isSet })
                let importer = LibraryImporter(library: library, coordinatedRead: reader.hook)
                do {
                    let report = try importer.importContents(
                        of: urls,
                        progress: { relay.send($0) },
                        isCancelled: { flag.isSet })
                    return ImportOutcome(
                        report: report,
                        snapshot: LibrarySnapshot.make(from: library),
                        errorMessage: nil)
                } catch {
                    return ImportOutcome(
                        report: nil,
                        snapshot: LibrarySnapshot.make(from: library),
                        errorMessage: LibraryStore.describe(error))
                }
            }

            self.apply(outcome.snapshot)
            self.lastReport = outcome.report.map(LibraryStore.sanitized)
            self.errorMessage = outcome.errorMessage ?? self.errorMessage
            self.endOperation()
        }
    }

    // MARK: - Weg B: per Finder abgelegte Archive

    // Packt die beim Abgleich gefundenen Archive aus. Danach wird erneut
    // abgeglichen: was durchlief, steht im Index, was liegen blieb, meldet der
    // Abgleich wieder als offenes Archiv.
    func unpackPendingArchives() {
        guard !pendingArchives.isEmpty, !isBusy else { return }
        beginOperation(.unpacking)

        currentTask = Task { [weak self] in
            guard let self else { return }
            guard let library = await self.resolveLibrary() else {
                self.endOperation()
                return
            }
            await self.unpackArchives(in: library)
            self.endOperation()
        }
    }

    // Gemeinsamer Auspackpfad fuer den automatischen Abgleich und den
    // Wiederholen-Knopf nach einem Fehler. Der Aufrufer besitzt bereits den
    // exklusiven Bibliotheksvorgang; hier wird deshalb kein zweiter Task
    // gestartet und `isBusy` bleibt lueckenlos wahr.
    private func unpackArchives(in library: MusicLibrary) async {
        activity = .unpacking
        lastReport = nil

        let flag = cancellation
        let relay = makeProgressRelay()
        let outcome: UnpackOutcome = await onWorker {
            let reader = FileProviderReader(isCancelled: { flag.isSet })
            let importer = LibraryImporter(library: library, coordinatedRead: reader.hook)
            do {
                let report = try importer.unpackPendingArchives(
                    progress: { relay.send($0) },
                    isCancelled: { flag.isSet })
                // Der Abgleich danach sagt, was uebrig blieb: ausgepackte
                // Archive sind weg, gescheiterte liegen noch da. Nach einem
                // Abbruch liefert er nur einen Teil und wird ignoriert.
                let rescan = try? library.rescan(isCancelled: { flag.isSet })
                return UnpackOutcome(
                    report: report,
                    archives: rescan?.archivesFound ?? [],
                    archivesComplete: rescan.map { !$0.wasCancelled } ?? false,
                    snapshot: LibrarySnapshot.make(from: library),
                    errorMessage: nil)
            } catch {
                return UnpackOutcome(
                    report: nil,
                    archives: [],
                    archivesComplete: false,
                    snapshot: LibrarySnapshot.make(from: library),
                    errorMessage: LibraryStore.describe(error))
            }
        }

        apply(outcome.snapshot)
        lastReport = outcome.report.map(LibraryStore.sanitized)
        if outcome.archivesComplete { pendingArchives = outcome.archives }
        errorMessage = outcome.errorMessage ?? errorMessage
    }

    // MARK: - Abbrechen

    // Setzt nur den Schalter. Der laufende Vorgang sieht ihn beim naechsten
    // Datei-Schritt, raeumt sauber ab und liefert seinen Bericht — abgebrochen,
    // aber vollstaendig.
    func cancelCurrentOperation() {
        guard isBusy else { return }
        cancellation.set()
    }

    // MARK: - Zuruecksetzen

    // Loescht Bibliotheksinhalt, Index, Temp-Extrakte und Caches. Favoriten nur
    // auf Wunsch — der Core kennt sie nicht und ruft dafuer bloss einen Haken
    // auf.
    func resetLibrary(clearFavorites: Bool) {
        guard !isBusy else { return }
        beginOperation(.resetting)
        lastReport = nil

        // Der Haken wird auf der Arbeitsschlange aufgerufen; `UserDefaults`
        // wird deshalb nicht dort angefasst, sondern hier auf dem MainActor,
        // sobald feststeht, dass der Core den Haken wirklich gezogen hat.
        let favoritesCleared = LibraryFlag()

        currentTask = Task { [weak self] in
            guard let self else { return }
            guard let library = await self.resolveLibrary() else {
                self.endOperation()
                return
            }

            let outcome: ResetOutcome = await self.onWorker {
                do {
                    let report = try LibraryReset.reset(
                        library: library,
                        temporaryDirectories: LibraryStore.scratchDirectories(),
                        options: LibraryReset.Options(removeIndex: true, clearFavorites: clearFavorites),
                        favoritesCleaner: { favoritesCleared.set() })
                    return ResetOutcome(
                        failures: report.failures,
                        snapshot: LibrarySnapshot.make(from: library),
                        errorMessage: nil)
                } catch {
                    return ResetOutcome(
                        failures: [],
                        snapshot: LibrarySnapshot.make(from: library),
                        errorMessage: LibraryStore.describe(error))
                }
            }

            self.apply(outcome.snapshot)
            self.pendingArchives = []
            if favoritesCleared.isSet { self.clearFavorites() }
            if let first = outcome.failures.first {
                self.errorMessage = first.reason
            } else {
                self.errorMessage = outcome.errorMessage ?? self.errorMessage
            }
            self.endOperation()
        }
    }

    func clearLastReport() {
        lastReport = nil
    }

    // MARK: - Zugriff auf Titel

    func track(forRelativePath path: String) -> TrackRef? {
        trackIndex[path]
    }

    // MARK: - Favoriten

    func isFavorite(_ path: String) -> Bool {
        favorites.contains(path)
    }

    func toggleFavorite(_ path: String) {
        if favorites.contains(path) {
            favorites.remove(path)
        } else {
            favorites.insert(path)
        }
        persistFavorites()
        invalidateFilters()
    }

    private func clearFavorites() {
        guard !favorites.isEmpty else { return }
        favorites = []
        persistFavorites()
        invalidateFilters()
    }

    private func persistFavorites() {
        // Sortiert gespeichert, damit die Datei zwischen zwei Starts stabil
        // bleibt und sich leichter ansehen laesst.
        defaults.set(favorites.sorted(), forKey: Self.favoritesDefaultsKey)
    }

    // MARK: - Suche und Filter

    // Gefilterter Anzeigebaum. Gesucht wird in den Dateinamen, ohne Ruecksicht
    // auf Gross-/Kleinschreibung und Akzente; Ordner ohne Treffer verschwinden.
    // nil bedeutet: nichts zu zeigen (leere Bibliothek oder kein Treffer).
    func filteredTree(search: String, favoritesOnly: Bool) -> PlaylistScanner.FolderNode? {
        filtered(search: search, favoritesOnly: favoritesOnly).tree
    }

    // Dieselbe Auswahl als flache Abspielreihenfolge. Sie ist immer die
    // Tiefensuche durch `filteredTree` — Weiter/Zurueck bleibt also genau die
    // Reihenfolge, die auf dem Bildschirm steht.
    func filteredTracks(search: String, favoritesOnly: Bool) -> [TrackRef] {
        filtered(search: search, favoritesOnly: favoritesOnly).tracks
    }

    private func filtered(
        search: String,
        favoritesOnly: Bool
    ) -> (tracks: [TrackRef], tree: PlaylistScanner.FolderNode?) {
        let needle = Self.normalized(search).trimmingCharacters(in: .whitespacesAndNewlines)
        let key = FilterKey(needle: needle, favoritesOnly: favoritesOnly, generation: generation)
        // Suchfeld und Baumansicht fragen im selben Bilddurchlauf beides ab;
        // ein einziger gemerkter Eintrag spart damit die halbe Arbeit.
        if let cache = filterCache, cache.key == key { return (cache.tracks, cache.tree) }

        let result: (tracks: [TrackRef], tree: PlaylistScanner.FolderNode?)
        if needle.isEmpty && !favoritesOnly {
            result = (tracks, tree)
        } else {
            var matching: [TrackRef] = []
            matching.reserveCapacity(tracks.count)
            for (offset, track) in tracks.enumerated() {
                if favoritesOnly && !favorites.contains(track.relativePath) { continue }
                if !needle.isEmpty && !searchNames[offset].contains(needle) { continue }
                matching.append(track)
            }
            if matching.isEmpty {
                result = ([], nil)
            } else {
                // Der Baum wird aus den Treffern neu gebaut. `buildTree` sortiert
                // wie beim Original (Ordner vor Dateien, jeweils alphabetisch),
                // die Reihenfolge bleibt also dieselbe — nur ohne die leeren
                // Ordner.
                let entries = matching.map {
                    PlaylistScanner.Entry(url: $0.url, displayName: $0.displayName, folderPath: $0.folderPath)
                }
                result = (matching, PlaylistScanner.buildTree(entries))
            }
        }

        filterCache = (key, result.tracks, result.tree)
        return result
    }

    private func invalidateFilters() {
        generation &+= 1
        filterCache = nil
    }

    // MARK: - Zustand uebernehmen

    private func apply(_ snapshot: LibrarySnapshot) {
        tree = snapshot.tree
        tracks = snapshot.tracks
        searchNames = snapshot.searchNames
        trackIndex = Dictionary(
            snapshot.tracks.map { ($0.relativePath, $0) },
            uniquingKeysWith: { first, _ in first })
        invalidateFilters()
    }

    private func beginOperation(_ kind: LibraryActivity) {
        cancellation.clear()
        isBusy = true
        activity = kind
        progress = nil
    }

    private func endOperation() {
        isBusy = false
        activity = nil
        progress = nil
        currentTask = nil
        cancellation.clear()
    }

    // MARK: - Arbeitsschlange

    // Fuehrt einen Block auf der seriellen Arbeitsschlange aus und wartet auf
    // sein Ergebnis, ohne den MainActor zu blockieren. Genau hier passiert der
    // Uebergang zwischen "langsam und synchron" (Core) und "asynchron"
    // (Oberflaeche).
    private func onWorker<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
            worker.async {
                continuation.resume(returning: work())
            }
        }
    }

    // Legt die Bibliothek an, falls das noch nicht geschehen ist. Das Laden des
    // Index liest eine Datei und gehoert deshalb ebenfalls auf die
    // Arbeitsschlange.
    private func resolveLibrary() async -> MusicLibrary? {
        if let library { return library }
        let outcome: LibraryOutcome = await onWorker {
            do {
                return LibraryOutcome(library: try MusicLibrary.onDevice(), errorMessage: nil)
            } catch {
                return LibraryOutcome(library: nil, errorMessage: LibraryStore.describe(error))
            }
        }
        if let created = outcome.library {
            library = created
            return created
        }
        errorMessage = outcome.errorMessage
        return nil
    }

    private func makeProgressRelay() -> LibraryProgressRelay {
        LibraryProgressRelay { [weak self] snapshot in
            Task { @MainActor in
                // Nach dem Ende eines Vorgangs kann noch eine Meldung
                // eintrudeln; die wird verworfen.
                guard let self, self.isBusy else { return }
                self.progress = snapshot
            }
        }
    }

    // MARK: - Statische Helfer (laufen auch auf der Arbeitsschlange)

    // Verzeichnisse, die beim Zuruecksetzen mitgeleert werden: das
    // Zwischenlager des Importers und der App-Cache.
    nonisolated static func scratchDirectories() -> [URL] {
        let fileManager = FileManager.default
        var directories = [fileManager.temporaryDirectory]
        if let caches = try? fileManager.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            directories.append(caches)
        }
        return directories
    }

    nonisolated static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return (error as NSError).localizedDescription
    }

    // Ein Abbruch waehrend des Wartens auf eine Cloud-Datei erzeugt im Core
    // einen Fehleintrag. Fuer den Nutzer ist das kein Fehlschlag, sondern
    // schlicht das, worum er gebeten hat — deshalb fliegen diese Eintraege aus
    // dem Bericht.
    nonisolated static func sanitized(_ report: ImportReport) -> ImportReport {
        guard report.wasCancelled else { return report }
        let failures = report.failures.filter {
            !$0.reason.hasSuffix(FileProviderReader.cancellationReason)
        }
        guard failures.count != report.failures.count else { return report }
        return ImportReport(
            imported: report.imported,
            duplicates: report.duplicates,
            failures: failures,
            wasCancelled: report.wasCancelled)
    }

    nonisolated static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    // MARK: - Kleine Typen

    private struct FilterKey: Hashable {
        let needle: String
        let favoritesOnly: Bool
        let generation: Int
    }

    private struct LibraryOutcome: Sendable {
        let library: MusicLibrary?
        let errorMessage: String?
    }

    private struct ScanOutcome: Sendable {
        let archives: [String]
        let archivesComplete: Bool
        let snapshot: LibrarySnapshot?
        let errorMessage: String?
    }

    private struct ImportOutcome: Sendable {
        let report: ImportReport?
        let snapshot: LibrarySnapshot
        let errorMessage: String?
    }

    private struct UnpackOutcome: Sendable {
        let report: ImportReport?
        let archives: [String]
        let archivesComplete: Bool
        let snapshot: LibrarySnapshot
        let errorMessage: String?
    }

    private struct ResetOutcome: Sendable {
        let failures: [ImportFailure]
        let snapshot: LibrarySnapshot
        let errorMessage: String?
    }
}

// MARK: - Vorgangsarten

// Welcher Vorgang gerade laeuft. Nur fuer die Beschriftung — fachlich
// unterscheiden sich die vier nur darin, was sie mit den Dateien tun.
enum LibraryActivity: Sendable {
    case scanning       // Abgleich mit dem Dateisystem
    case importing      // Ordner-Import
    case unpacking      // per Finder abgelegte Archive auspacken
    case resetting      // Bibliothek zuruecksetzen
}

// MARK: - Momentaufnahme

// Alles, was die Oberflaeche ueber den Bestand wissen muss — gebaut auf der
// Arbeitsschlange, damit auf dem MainActor nur noch zugewiesen wird. Bei
// zehntausend Titeln ist das Bauen des Baums und der Suchnamen sonst ein
// spuerbarer Ruckler.
struct LibrarySnapshot: Sendable {
    let tree: PlaylistScanner.FolderNode?
    let tracks: [TrackRef]
    let searchNames: [String]

    static func make(from library: MusicLibrary) -> LibrarySnapshot {
        let root = library.folderTree()
        let entries = PlaylistScanner.flattenedFiles(root)
        let tracks = entries.map { entry in
            TrackRef(
                // Der relative Pfad ist die stabile ID des Index und setzt sich
                // genau so zusammen: Ordnerkette plus Dateiname.
                relativePath: (entry.folderPath + [entry.displayName]).joined(separator: "/"),
                displayName: entry.displayName,
                folderPath: entry.folderPath,
                url: entry.url)
        }
        let searchNames = tracks.map { LibraryStore.normalized($0.displayName) }
        return LibrarySnapshot(
            tree: tracks.isEmpty ? nil : root,
            tracks: tracks,
            searchNames: searchNames)
    }
}

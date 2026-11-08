import Foundation
import SavageModPlayerCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

// JSON-Nachrichten werden nach dem Einlesen nicht mehr verändert und nur auf
// dem MainActor ausgewertet. Der Audiothread berührt diesen Kanal niemals.
private struct DesktopRequest: @unchecked Sendable {
    let values: [String: Any]
}

@main
struct DesktopMain {
    static func main() async {
        // Diagnoseausgaben des gemeinsam genutzten Cores dürfen keine JSON-Zeile beschädigen.
        let descriptor = dup(STDOUT_FILENO)
        guard descriptor >= 0, dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else { exit(2) }
        let engine = DesktopEngine(output: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
        await engine.start()
        await Task.detached {
            while let line = readLine() {
                guard line.utf8.count <= 32 * 1024 * 1024,
                      let data = line.data(using: .utf8),
                      let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let request = DesktopRequest(values: values)
                Task { await engine.handle(request) }
            }
        }.value
        await engine.shutdown()
    }
}

@MainActor
private final class DesktopEngine {
    let player = ModPlayerCoordinator()
    private let output: FileHandle
    private let directory: URL
    private let temporary: URL
    private var entries: [PlaylistScanner.Entry] = []
    private var knownEntries: [String: PlaylistScanner.Entry] = [:]
    private var saved = SavedPlaylistDocument()
    private var committedSaved = SavedPlaylistDocument()
    private var overrides = TrackPlaybackSettingsDocument()
    private var markerDocument = SongMarkerDocument()
    private var markerStore: SongMarkerStore
    private var markerRevision: UInt64 = 0
    private var markerWritesInFlight = 0
    private var preferences: [String: Any] = [:]
    private var metadata: [String: ModuleMetadataRecord] = [:]
    private var inspectionModule: Mod?
    private var sampleExport: (token: UUID, mod: Mod, index: Int)?
    private var metadataIndex: ModuleMetadataIndex?
    private var indexTask: Task<Void, Never>?
    private var query = LibraryQuery()
    private var queue = TrackQueue()
    private var selection: [String]?
    private var resumeSource: String?
    private var currentID: String?
    private var recent: [PlaylistTrackReference] = []
    private var played = Set<String>()
    private var currentGeneration = UUID()
    private var scanGeneration = UUID()
    private var startupSuperseded = false
    private var isScanning = false
    private var moduleRevision = UUID()
    private var endPulse = 0
    private var lastPlaybackError: String?
    private var lastPattern = -1
    private var lastPosition = -1
    private var lastVisualizerRevision: UUID?
    private var visualizerWasAnimating = false
    private var nextStateUpdate = ContinuousClock.now
    private var ticker: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var exportModule: Mod?
    private var exportOptions = ChannelStemExportOptions()
    private var noteCommandCount = 0
    private var noteRevision = UUID()
    private var noteTask: Task<Void, Never>?
    private var notes = [[String: Any]]()
    private var noteWorker = NotePreviewWorker()
    private var noteSource: UUID?
    private var preparedThrough: Double = 0
    private var nextNoteSongEnd: Double?
    private var noteRainVisible = false
    private var writable = true
    private var libraryPreferences: LibraryPreferencesStore
    private var libraryDocument = LibraryPreferencesDocument()
    private var exchangeDocument: CollectionExchangeDocument?
    private var exchangeMapping: [UUID: PlaylistTrackReference] = [:]
    private var exchangeSkipped = Set<UUID>()
    private var exchangeResolutions: [CollectionExchangeConflictID: CollectionExchangeResolution] = [:]
    private var exchangeConflictIDs: [String: CollectionExchangeConflictID] = [:]
    private var exchangePreview: CollectionExchangeImportPreview?
    private var pendingCollections: [String] = []
    private var pendingAudio: (paths: [String], autoPlay: Bool)?

    init(output: FileHandle) {
        self.output = output
        let base = ProcessInfo.processInfo.environment["SAVAGE_DESKTOP_DATA"]
            ?? ((ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
                 ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share").path)
                + "/savage-mod-player")
        directory = URL(fileURLWithPath: base, isDirectory: true)
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("savage-desktop-\(UUID())", isDirectory: true)
        markerStore = SongMarkerStore(fileURL: directory.appendingPathComponent("song-markers.json"))
        libraryPreferences = LibraryPreferencesStore(fileURL: directory.appendingPathComponent("library-preferences.json"))
    }

    func start() async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            _ = try persistence().recover { before, after in try self.replacePreferences(before, after) }
            saved = try SavedPlaylistStore(fileURL: directory.appendingPathComponent("playlists.json")).load()
            committedSaved = saved
            overrides = try TrackPlaybackSettingsStore(fileURL: directory.appendingPathComponent("track-settings.json")).load()
            let snapshot = try await markerStore.snapshot()
            markerDocument = snapshot.document; markerRevision = snapshot.revision
            libraryDocument = try await libraryPreferences.snapshot().document
            played = libraryDocument.heardIDs
            let file = directory.appendingPathComponent("preferences.json")
            if FileManager.default.fileExists(atPath: file.path) {
                guard let loaded = try JSONSerialization.jsonObject(with: BoundedFileReader.read(file, maximumBytes: 1_048_576)) as? [String: Any] else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                preferences = loaded
                if let data = loaded["recent"] {
                    recent = try JSONDecoder().decode([PlaylistTrackReference].self, from: JSONSerialization.data(withJSONObject: data))
                }
            }
            metadataIndex = try ModuleMetadataIndex(cacheURL: directory.appendingPathComponent("metadata.json"))
            if let data = preferences["query"] as? [String: Any] {
                query = try JSONDecoder().decode(LibraryQuery.self, from: JSONSerialization.data(withJSONObject: data))
            }
            player.setVolume(Float(number("volume", default: 0.6)))
            player.visualizerFrameRate = number("visualizerHz", default: 60)
            applySound()
        } catch { writable = false; emit("error", ["message": "Gespeicherte Daten sind geschützt: \(error.localizedDescription)"]) }
        emit("ready", ["preferences": preferences, "writable": writable, "protocolVersion": 2])
        sendLibrary()
        ticker = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled {
                guard let self else { return }
                tick()
                let animated = player.isPlaying && !player.isPaused
                    && (player.visualizersVisible || noteRainVisible)
                let rate = min(60, max(1, player.visualizerFrameRate))
                let interval = animated ? 1 / rate : 0.2
                deadline += .seconds(interval)
                if deadline < clock.now { deadline = clock.now + .seconds(interval) }
                do { try await clock.sleep(until: deadline) } catch { return }
            }
        }
        if let folder = preferences["autoplayFolder"] as? String, !folder.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !startupSuperseded else { return }
                await open([folder], autoPlay: true, restoreLast: true)
            }
        }
    }

    func shutdown() async {
        ticker?.cancel(); noteTask?.cancel(); indexTask?.cancel(); exportTask?.cancel()
        await exportTask?.value
        player.stop()
        try? FileManager.default.removeItem(at: temporary)
    }

    func handle(_ request: DesktopRequest) async {
        let v = request.values
        let command = v["command"] as? String ?? ""
        let index = v["index"] as? Int ?? 0
        let value = v["value"] as? Double ?? 0
        let text = v["text"] as? String ?? ""
        do {
            switch command {
            case "open": startupSuperseded = true; await open(v["paths"] as? [String] ?? [], autoPlay: v["autoPlay"] as? Bool ?? true)
            case "load": cancelPendingLoads(); try await load(id: text, play: true)
            case "recentLoad":
                cancelPendingLoads()
                if let reference = recent.first(where: { $0.id == text }) {
                    if knownEntries[text] == nil {
                        let folder = temporary.appendingPathComponent(UUID().uuidString)
                        let result = await Task.detached { SavedPlaylistResolver.resolve([reference], tempDir: folder) }.value
                        remember(result.entries)
                    }
                    try await load(id: text, play: true)
                }
            case "play":
                cancelPendingLoads()
                player.sleepTimer.prepareForManualPlayback()
                if player.isPaused { player.resume() }
                else if player.isPlaying { player.pause() }
                else { player.play() }
                await markHeardIfPlaying(); sendLibrary()
            case "stop": cancelPendingLoads(); player.sleepTimer.cancel(); player.stop(); player.seek(toPosition: 0)
            case "resume":
                cancelPendingLoads()
                player.sleepTimer.prepareForManualPlayback()
                if player.isPaused { player.resume() } else if !player.isPlaying { player.play() }
                await markHeardIfPlaying(); sendLibrary()
            case "pause": cancelPendingLoads(); if player.isPlaying && !player.isPaused { player.pause() }
            case "next": cancelPendingLoads(); try await adjacent(backwards: false)
            case "previous": cancelPendingLoads(); try await adjacent(backwards: true)
            case "seek":
                if let row = v["row"] as? Int { player.seek(toPosition: index, row: row) }
                else { player.seek(toPosition: index) }
            case "seekSeconds": player.seek(bySeconds: value)
            case "bpm": player.bpm = max(32, min(300, index))
            case "speed": player.speed = max(1, min(31, index))
            case "mute": player.toggleMute(channelIndex: index)
            case "solo": player.toggleSolo(channelIndex: index)
            case "volume": preferences["volume"] = min(1, max(0, value)); player.setVolume(Float(value)); try savePreferences(); emit("preferences", preferences)
            case "defaultOption":
                guard ["palClock", "stereoSeparation", "useInterpolation", "ledFilterActive"].contains(text) else { return }
                try requireWritable(); preferences[text] = v["setting"]
                applySound(); try savePreferences(); emit("preferences", preferences)
            case "option":
                guard ["theme", "loop", "shuffle", "palClock", "stereoSeparation", "useInterpolation", "ledFilterActive", "visualizerHz", "autoplayFolder", "zoom", "sidebarWidth", "recentHeight", "sleepTimerMinutes", "noteRainHorizon", "noteRainZoomToSong"].contains(text) else { return }
                if ["palClock", "stereoSeparation", "useInterpolation", "ledFilterActive"].contains(text),
                   let currentID, var settings = overrides.tracks[currentID],
                   let encoded = json(settings) as? [String: Any], encoded[text] != nil {
                    var changed = encoded; changed[text] = v["setting"]
                    settings = try JSONDecoder().decode(TrackPlaybackOverrides.self, from: JSONSerialization.data(withJSONObject: changed))
                    var next = overrides; next.tracks[currentID] = settings
                    try requireWritable()
                    try TrackPlaybackSettingsStore(fileURL: directory.appendingPathComponent("track-settings.json")).save(next)
                    overrides = next; sendDetails()
                } else { preferences[text] = v["setting"] }
                player.visualizerFrameRate = number("visualizerHz", default: 60)
                applySound(); try savePreferences()
                emit("preferences", preferences)
            case "compact":
                player.visualizersVisible = !(v["enabled"] as? Bool ?? false)
                if !player.visualizersVisible { emit("visualizer", ["vu": [], "waves": [], "master": []]) }
            case "indexCancel": indexTask?.cancel()
            case "indexRefresh": refreshIndex(generation: scanGeneration)
            case "favorite":
                try requireWritable()
                if saved.favoriteIDs.contains(text) { saved.favoriteIDs.remove(text) } else { saved.favoriteIDs.insert(text) }
                try savePlaylists(); sendLibrary()
            case "markUnheard":
                try requireWritable()
                libraryDocument = try await libraryPreferences.markHeard(text, heard: false).document
                played.remove(text); sendLibrary()
            case "query":
                query = try JSONDecoder().decode(LibraryQuery.self, from: JSONSerialization.data(withJSONObject: v["query"] ?? [:]))
                preferences["query"] = json(query); try savePreferences(); sendLibrary()
            case "selection":
                selection = v["ids"] as? [String]; sendLibrary()
                if let first = selection?.first { try await load(id: first, play: true) }
            case "clear": cancelPendingLoads(); player.stop(); entries = []; selection = nil; resumeSource = nil; sendLibrary()
            case "demo":
                player.sleepTimer.prepareForManualPlayback(); player.setMod(ModParser.generateDemoMod())
                currentID = nil; moduleRevision = UUID(); lastPattern = -1; lastPosition = -1
                applySound(); player.play(); sendDetails(); sendLibrary()
            case "enqueue":
                if let entry = entries.first(where: { $0.source.id == text }) { queue.enqueue(entry.reference, next: v["next"] as? Bool ?? false) }
                sendLibrary()
            case "queueRemove": if let id = UUID(uuidString: text) { queue.remove(id: id) }; sendLibrary()
            case "queueMove": if let id = UUID(uuidString: text) { queue.move(id: id, by: index) }; sendLibrary()
            case "queueClear": queue.removeAll(); sendLibrary()
            case "playlistSave":
                try requireWritable()
                let ids = v["ids"] as? [String] ?? visibleIDs()
                let tracks = ids.compactMap { id in entries.first { $0.source.id == id }?.reference }
                saved.playlists.append(SavedPlaylist(name: text, tracks: tracks)); try savePlaylists(); sendLibrary()
            case "playlistRename":
                try requireWritable()
                if let id = v["playlist"] as? String, let i = saved.playlists.firstIndex(where: { $0.id.uuidString == id }) {
                    saved.playlists[i].name = text; try savePlaylists(); sendLibrary()
                }
            case "playlistDelete":
                try requireWritable(); saved.playlists.removeAll { $0.id.uuidString == text }; try savePlaylists(); sendLibrary()
            case "playlistMove":
                try requireWritable()
                if let i = saved.playlists.firstIndex(where: { $0.id.uuidString == text }), saved.playlists.indices.contains(i + index) {
                    saved.playlists.swapAt(i, i + index); try savePlaylists(); sendLibrary()
                }
            case "playlistTrackRemove", "playlistTrackMove":
                try requireWritable()
                if let id = v["playlist"] as? String, let i = saved.playlists.firstIndex(where: { $0.id.uuidString == id }),
                   let j = saved.playlists[i].tracks.firstIndex(where: { $0.id == text }) {
                    if command == "playlistTrackRemove" { saved.playlists[i].tracks.remove(at: j) }
                    else if saved.playlists[i].tracks.indices.contains(j + index) { saved.playlists[i].tracks.swapAt(j, j + index) }
                    try savePlaylists(); sendLibrary()
                }
            case "playlistAdd":
                try requireWritable()
                if let id = v["playlist"] as? String, let i = saved.playlists.firstIndex(where: { $0.id.uuidString == id }),
                   let entry = entries.first(where: { $0.source.id == text }) {
                    if !saved.playlists[i].tracks.contains(where: { $0.id == entry.source.id }) { saved.playlists[i].tracks.append(entry.reference) }
                    try savePlaylists(); sendLibrary()
                }
            case "playlistOpen":
                cancelPendingLoads()
                if let playlist = saved.playlists.first(where: { $0.id.uuidString == text }) {
                    let generation = UUID(); scanGeneration = generation; isScanning = true
                    emit("loading", ["active": true])
                    let folder = temporary.appendingPathComponent(UUID().uuidString)
                    let result = await Task.detached { SavedPlaylistResolver.resolve(playlist.tracks, tempDir: folder) }.value
                    guard scanGeneration == generation else { return }
                    isScanning = false; emit("loading", ["active": false])
                    entries = result.entries; selection = nil
                    remember(result.entries)
                    sendLibrary()
                    refreshIndex(generation: generation)
                    if !result.missing.isEmpty || !result.limited.isEmpty {
                        emit("notice", ["message": "\(result.missing.count) fehlende und \(result.limited.count) begrenzte Quellen."])
                    }
                }
            case "preview":
                player.sleepTimer.prepareForManualPlayback()
                if v["snapshot"] as? Bool == true, let mod = inspectionModule { player.previewInstrument(mod: mod, index: index) }
                else { player.previewInstrument(index: index) }
            case "stopPreview": player.stopPreview()
            case "inspect": inspectionModule = player.activeMod; try sendInspection()
            case "instrument": sendInstrument(index)
            case "sample": try sendSample(id: text, zoom: max(1, index), position: value, focus: v["focus"] as? String)
            case "prepareSampleExport":
                guard let mod = player.activeMod, v["revision"] as? String == moduleRevision.uuidString,
                      let selection = mod.previewSelection(instrumentIndex: index) else { throw CocoaError(.fileReadNoSuchFile) }
                let token = UUID(); sampleExport = (token, mod, index)
                emit("sampleExportPrepared", ["token": token.uuidString, "name": selection.sample.name.isEmpty ? "sample_\(index)" : selection.sample.name])
            case "sampleExportCancel": sampleExport = nil
            case "sampleExport":
                if let path = v["path"] as? String {
                    let captured: (Mod, Int)
                    if let token = v["token"] as? String {
                        guard let snapshot = sampleExport, snapshot.token.uuidString == token else { throw CocoaError(.fileReadNoSuchFile) }
                        captured = (snapshot.mod, snapshot.index)
                    } else if let mod = player.activeMod { captured = (mod, index) }
                    else { return }
                    defer { sampleExport = nil }
                    let destination = URL(fileURLWithPath: path)
                    let expected = try Self.wavStamp(destination, overwrite: v["overwrite"] as? Bool ?? false)
                    let staging = destination.deletingLastPathComponent().appendingPathComponent(".savage-sample-\(UUID()).wav")
                    defer { try? FileManager.default.removeItem(at: staging) }
                    try player.exportInstrumentToWav(mod: captured.0, index: captured.1, destinationURL: staging)
                    try Self.publishWAV(staging, to: destination, replacing: expected)
                    emit("complete", ["path": path])
                }
            case "timer":
                if index > 0 {
                    if player.sleepTimer.start(minutes: index), writable {
                        preferences["sleepTimerMinutes"] = index
                        try savePreferences(); emit("preferences", preferences)
                    }
                } else { player.sleepTimer.cancel() }
            case "timerExtend": player.sleepTimer.extend()
            case "markerAdd", "markerRename", "markerDelete": try await editMarker(command, v)
            case "section":
                if let a = v["start"] as? [String: Any], let b = v["end"] as? [String: Any] {
                    let start = SongAddress(position: a["position"] as? Int ?? 0, row: a["row"] as? Int ?? 0)
                    let end = SongAddress(position: b["position"] as? Int ?? 0, row: b["row"] as? Int ?? 0)
                    if let section = SongSection(start: start, end: end) {
                        player.sleepTimer.prepareForManualPlayback(); player.startSectionLoop(section)
                    }
                }
            case "sectionCancel": player.cancelSectionLoop()
            case "trackSettings":
                try requireWritable()
                if let currentID {
                    let data = try JSONSerialization.data(withJSONObject: v["settings"] ?? [:])
                    let settings = try JSONDecoder().decode(TrackPlaybackOverrides.self, from: data)
                    var next = overrides
                    next.tracks[currentID] = settings.isEmpty ? nil : settings
                    try TrackPlaybackSettingsStore(fileURL: directory.appendingPathComponent("track-settings.json")).save(next)
                    overrides = next
                    applySound(); sendDetails()
                }
            case "notes": noteRainVisible = v["enabled"] as? Bool ?? false
            case "prepareExport":
                exportModule = player.activeMod
                exportOptions = .init(stereoSeparation: player.stereoSeparation, useInterpolation: player.useInterpolation,
                    palClock: player.palClock, mutedChannels: (0..<player.channelCount).filter { player.isMuted(channelIndex: $0) },
                    soloChannels: (0..<player.channelCount).filter { player.isSoloed(channelIndex: $0) })
                emit("exportPrepared", ["title": player.trackName])
                if v["video"] as? Bool == true { beginVideoExport([:], preview: true) }
            case "export": beginExport(v)
            case "videoExport": beginVideoExport(v)
            case "videoPreview": beginVideoExport(v, preview: true)
            case "batchExport": beginBatchExport(v)
            case "collectionExport":
                if let path = v["path"] as? String {
                    let snapshot = collectionSnapshot()
                    let sources = try collectionSources(snapshot)
                    let document = try CollectionExchangeExporter.makeDocument(from: snapshot, sources: sources)
                    try CollectionExchangeCodec.encode(document).write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
                    emit("complete", ["path": path])
                }
            case "collectionImport":
                if let path = v["path"] as? String {
                    if exchangeDocument != nil { pendingCollections.append(path); return }
                    exchangeDocument = try CollectionExchangeCodec.load(from: URL(fileURLWithPath: path))
                    exchangeMapping = [:]; exchangeSkipped = []; exchangeResolutions = [:]
                    if let document = exchangeDocument {
                        let sources = try collectionSources(collectionSnapshot())
                        for (id, match) in try CollectionExchangeMatcher.match(document, against: sources) {
                            if case .matched(let sourceID) = match { exchangeMapping[id] = sources.first { $0.reference.id == sourceID }?.reference }
                        }
                    }
                    try sendExchangePreview()
                }
            case "collectionMap":
                if let id = (v["track"] as? String).flatMap(UUID.init(uuidString:)) {
                    exchangeMapping[id] = entries.first { $0.source.id == text }?.reference
                    if text == "__skip__" { exchangeSkipped.insert(id) } else { exchangeSkipped.remove(id) }
                    try sendExchangePreview()
                }
            case "collectionResolve":
                if let id = exchangeConflictIDs[text], let choice = v["choice"] as? String,
                   let resolution = CollectionExchangeResolution(rawValue: choice) {
                    exchangeResolutions[id] = resolution; try sendExchangePreview()
                }
            case "collectionApply": try await applyExchange(); await advancePendingCollection()
            case "collectionCancel": exchangeDocument = nil; exchangePreview = nil; await advancePendingCollection()
            case "filterSave":
                try requireWritable()
                let current = query
                let snapshot = try await libraryPreferences.update { document in
                    document.savedFilters.append(SavedLibraryFilter(name: text, query: current))
                }
                libraryDocument = snapshot.document; sendLibrary()
            case "filterDelete":
                try requireWritable()
                let snapshot = try await libraryPreferences.update { $0.savedFilters.removeAll { $0.id.uuidString == text } }
                libraryDocument = snapshot.document; sendLibrary()
            case "filterOpen":
                if let filter = libraryDocument.savedFilters.first(where: { $0.id.uuidString == text }) {
                    query = filter.query; preferences["query"] = json(query); try savePreferences(); sendLibrary()
                }
            case "exportCancel": exportTask?.cancel()
            case "quit": await shutdown(); exit(0)
            default: emit("error", ["message": "Unbekannter Desktop-Auftrag: \(command)"])
            }
        } catch { emit("error", ["message": error.localizedDescription, "command": command]) }
    }

    private func number(_ key: String, default value: Double) -> Double { preferences[key] as? Double ?? value }
    private func flag(_ key: String, default value: Bool) -> Bool { preferences[key] as? Bool ?? value }
    private func requireWritable() throws { if !writable { throw CocoaError(.fileWriteNoPermission) } }
    private func savePreferences() throws {
        try requireWritable()
        let data = try JSONSerialization.data(withJSONObject: preferences, options: [.sortedKeys])
        try data.write(to: directory.appendingPathComponent("preferences.json"), options: .atomic)
    }
    private func savePlaylists() throws {
        do {
            try SavedPlaylistStore(fileURL: directory.appendingPathComponent("playlists.json")).save(saved)
            committedSaved = saved
        } catch { saved = committedSaved; throw error }
    }
    private func cancelPendingLoads() {
        currentGeneration = UUID()
        if isScanning { scanGeneration = UUID(); isScanning = false; emit("loading", ["active": false]) }
    }
    private var defaults: PlaybackOptions {
        .init(palClock: flag("palClock", default: true), stereoSeparation: number("stereoSeparation", default: 0.8),
              useInterpolation: flag("useInterpolation", default: true), ledFilterActive: flag("ledFilterActive", default: false))
    }
    private func applySound() {
        let options = (currentID.flatMap { overrides.tracks[$0] } ?? .init()).resolved(defaults: defaults, format: player.activeMod?.format)
        if player.palClock != options.palClock { player.palClock = options.palClock }
        if player.stereoSeparation != Float(options.stereoSeparation) { player.stereoSeparation = Float(options.stereoSeparation) }
        if player.useInterpolation != options.useInterpolation { player.useInterpolation = options.useInterpolation }
        if player.ledFilterActive != options.ledFilterActive { player.ledFilterActive = options.ledFilterActive }
    }
    private func open(_ paths: [String], autoPlay: Bool, restoreLast: Bool = false) async {
        let collections = paths.filter { URL(fileURLWithPath: $0).pathExtension.lowercased() == "savagecollection" }
        pendingCollections += collections
        let audioPaths = paths.filter { !collections.contains($0) }
        if exchangeDocument != nil {
            if !audioPaths.isEmpty { pendingAudio = (audioPaths, autoPlay) }
            return
        }
        if audioPaths.isEmpty { await advancePendingCollection(); return }
        indexTask?.cancel()
        currentGeneration = UUID()
        let generation = UUID(); scanGeneration = generation
        isScanning = true
        let urls = audioPaths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let folder = temporary.appendingPathComponent(UUID().uuidString)
        emit("loading", ["active": true])
        let found = await Task.detached { PlaylistScanner.collectEntries(from: urls, tempDir: folder) }.value
        guard scanGeneration == generation else { return }
        entries = found; remember(found); selection = nil; sendLibrary()
        if writable {
            do { libraryDocument = try await libraryPreferences.registerSources(Dictionary(found.map { ($0.source.id, Date()) }, uniquingKeysWith: { first, _ in first })).document }
            catch { emit("error", ["message": error.localizedDescription]) }
        }
        guard scanGeneration == generation else { return }
        isScanning = false; emit("loading", ["active": false])
        let initial = restoreLast ? found.first { $0.source.id == preferences["lastPlayedSourceID"] as? String } ?? found.first : found.first
        if let first = initial {
            do { try await load(id: first.source.id, play: autoPlay) }
            catch { emit("error", ["message": error.localizedDescription]) }
        } else { emit("notice", ["message": "Keine unterstützten Tracker-Dateien gefunden."]) }
        refreshIndex(generation: generation)
        await advancePendingCollection()
    }
    private func advancePendingCollection() async {
        guard exchangeDocument == nil else { return }
        if let pending = pendingAudio {
            pendingAudio = nil
            await open(pending.paths, autoPlay: pending.autoPlay)
            return
        }
        while exchangeDocument == nil, !pendingCollections.isEmpty {
            let path = pendingCollections.removeFirst()
            await handle(DesktopRequest(values: ["command": "collectionImport", "path": path]))
        }
    }
    private func refreshIndex(generation: UUID) {
        indexTask?.cancel()
        if let metadataIndex {
            let inputs = entries.map { ModuleMetadataInput(id: $0.source.id, url: $0.url) }
            emit("indexing", ["active": true, "completed": 0, "total": inputs.count])
            let owner = self
            indexTask = Task { [weak self] in
                let result = await metadataIndex.refresh(inputs, progress: { progress in
                    guard progress.completed.isMultiple(of: 16) || progress.completed == progress.total else { return }
                    Task { @MainActor in
                        guard owner.scanGeneration == generation else { return }
                        owner.emit("indexing", ["active": true, "completed": progress.completed, "total": progress.total])
                    }
                })
                guard let self, scanGeneration == generation else { return }
                metadata = result.records
                emit("indexing", ["active": false, "completed": result.records.count, "total": inputs.count, "cancelled": result.wasCancelled, "warnings": result.warnings.map(\.rawValue)])
                indexTask = nil; sendLibrary()
            }
        }
    }
    private func load(id: String, play: Bool, paused: Bool = false, manual: Bool = true) async throws {
        guard let entry = knownEntries[id] ?? entries.first(where: { $0.source.id == id }) else { throw CocoaError(.fileReadNoSuchFile) }
        let generation = UUID(); currentGeneration = generation
        let loaded = try await Task.detached {
            let mod = try ModuleLoader.parse(data: BoundedFileReader.read(entry.url, maximumBytes: ModuleMetadataIndex.maximumFileBytes))
            return (mod, RenderEngine.sequencedDuration(of: mod))
        }.value
        guard currentGeneration == generation else { return }
        player.setMod(loaded.0, fallbackName: entry.displayName, precomputedDuration: loaded.1)
        moduleRevision = UUID()
        endPulse = player.songEndPulse
        currentID = id; applySound()
        recent.removeAll { $0.id == id }; recent.insert(entry.reference, at: 0)
        recent = Array(recent.prefix(20))
        if writable {
            do {
                preferences["recent"] = json(recent)
                preferences["lastPlayedSourceID"] = id
                try savePreferences()
            } catch { emit("notice", ["message": "Der Titel wurde geladen; sein Verlauf konnte nicht gespeichert werden: \(error.localizedDescription)"]) }
        }
        guard currentGeneration == generation else { return }
        if play {
            if manual { player.sleepTimer.prepareForManualPlayback() }
            if player.sleepTimer.allowsPlayback() { player.play(); if paused { player.pause() } }
        }
        await markHeardIfPlaying()
        lastPosition = -1; lastPattern = -1
        sendDetails(); sendLibrary()
    }
    private func markHeardIfPlaying() async {
        guard player.isPlaying, !player.isPaused, let id = currentID, !played.contains(id) else { return }
        played.insert(id)
        if writable {
            do { libraryDocument = try await libraryPreferences.markHeard(id).document }
            catch { played.remove(id); emit("notice", ["message": "Der Hörstatus konnte nicht gespeichert werden."]) }
        }
    }
    private func adjacent(backwards: Bool, automatic: Bool = false) async throws {
        if automatic && !player.sleepTimer.allowsPlayback() { return }
        let shouldPlay = player.isPlaying
        let wasPaused = player.isPaused
        if !backwards, let next = queue.popFirst() {
            if resumeSource == nil { resumeSource = currentID }
            if knownEntries[next.track.id] != nil {
                do { try await load(id: next.track.id, play: shouldPlay, paused: wasPaused, manual: !automatic) }
                catch { queue.enqueue(next.track, next: true); sendLibrary(); throw error }
                return
            }
            queue.enqueue(next.track, next: true)
            throw CocoaError(.fileReadNoSuchFile)
        }
        let indices = Dictionary(entries.enumerated().map { ($0.element.source.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let eligible = selection?.compactMap { indices[$0] } ?? Array(entries.indices)
        if backwards, let anchor = resumeSource, knownEntries[anchor] != nil {
            resumeSource = nil
            try await load(id: anchor, play: shouldPlay, paused: wasPaused, manual: !automatic)
            return
        }
        let anchor = resumeSource ?? currentID
        let current = entries.firstIndex { $0.source.id == anchor } ?? -1
        if let next = PlaylistNavigation.adjacentIndex(current: current, eligible: eligible, backwards: backwards,
                    wrap: (preferences["loop"] as? String ?? "playlist") == "playlist", shuffle: flag("shuffle", default: false)) {
            resumeSource = nil; try await load(id: entries[next].source.id, play: shouldPlay, paused: wasPaused, manual: !automatic)
        } else { player.stop() }
    }
    private func remember(_ values: [PlaylistScanner.Entry]) {
        for entry in values { knownEntries[entry.source.id] = entry }
    }
    private func visibleIDs() -> [String] {
        let items = entries.map { entry in
            LibraryQueryItem(id: entry.source.id, displayName: entry.displayName,
                folderPath: entry.folderPath.joined(separator: "/"), metadata: metadata[entry.source.id]?.metadata,
                addedAt: libraryDocument.firstSeenAt[entry.source.id],
                isFavorite: saved.favoriteIDs.contains(entry.source.id), wasPlayed: played.contains(entry.source.id))
        }
        return (try? query.selectIDs(from: items)) ?? []
    }
    private func sendLibrary() {
        let visible = visibleIDs()
        emit("libraryBegin", ["currentID": currentID ?? "", "selection": selection ?? [],
           "playlists": json(saved.playlists), "recent": recent.map { ["id": $0.id, "name": $0.displayName] }, "query": json(query),
           "savedFilters": json(libraryDocument.savedFilters),
           "queue": queue.items.map { ["id": $0.id.uuidString, "sourceID": $0.track.id, "name": $0.track.displayName] }])
        for first in stride(from: 0, to: entries.count, by: 128) {
            let batch = entries[first..<min(entries.count, first + 128)].map { e -> [String: Any] in
            var value: [String: Any] = ["id": e.source.id, "name": e.displayName, "folders": e.folderPath,
                                       "favorite": saved.favoriteIDs.contains(e.source.id), "heard": played.contains(e.source.id)]
            if let record = metadata[e.source.id] { value["metadata"] = json(record) }
            return value
            }
            emit("libraryTracks", ["tracks": batch])
        }
        for first in stride(from: 0, to: visible.count, by: 128) {
            emit("libraryVisible", ["ids": Array(visible[first..<min(visible.count, first + 128)])])
        }
        emit("libraryEnd", [:])
    }
    private func sendDetails() {
        guard let mod = player.activeMod else { return }
        emit("module", ["title": player.trackName, "format": mod.format.rawValue,
            "sourceID": currentID ?? "", "revision": moduleRevision.uuidString,
            "fileURL": currentID.flatMap { knownEntries[$0]?.source.location.absoluteString } ?? "",
            "channels": mod.channelCount, "usedChannels": mod.usedChannelCount, "displayChannels": mod.displayChannelIndices,
            "songKeyRange": songKeyRange(mod), "rowCounts": SongPositionLayout(module: mod).rowCounts,
            "orders": Array(mod.patternTable.prefix(mod.length)), "patterns": mod.patterns.count,
            "instruments": mod.instruments.enumerated().compactMap { i, instrument -> [String: Any]? in
                guard i > 0, let instrument else { return nil }
                let sample = mod.previewSelection(instrumentIndex: i)?.sample
                return ["index": i, "name": instrument.name, "samples": instrument.samples.count,
                    "playable": mod.playableInstrumentIndices.contains(i), "frames": sample?.pcm.count ?? 0,
                    "volume": sample?.volume ?? 0, "finetune": sample?.finetune ?? 0, "looped": sample?.isLooped ?? false]
            }, "warnings": mod.compatibilityWarnings, "amigaClock": PlaybackOptions.supportsAmigaClock(mod.format),
            "trackSettings": json(currentID.flatMap { overrides.tracks[$0] } ?? TrackPlaybackOverrides()),
            "markers": json(markerDocument.markers.filter { $0.sourceID == currentID })])
    }
    private func tick() {
        if let error = player.playbackError, error != lastPlaybackError {
            emit("error", ["message": "Die Audioausgabe konnte nicht gestartet werden: \(error)"])
        }
        lastPlaybackError = player.playbackError
        if player.songEndPulse != endPulse {
            endPulse = player.songEndPulse
            if player.isPlaying && !player.isPaused && player.sleepTimer.allowsPlayback() {
                let loop = preferences["loop"] as? String ?? "playlist"
                if loop == "track" { player.resetElapsedToLoopStart() }
                else if loop == "none" { player.stop() }
                else { Task { try? await adjacent(backwards: false, automatic: true) } }
            }
        }
        let visualizer = player.visualizerState
        let animating = player.isPlaying && !player.isPaused
        if player.visualizersVisible && (animating || visualizerWasAnimating || lastVisualizerRevision != moduleRevision) {
            emit("visualizer", ["vu": visualizer.vuLevels,
                "waves": visualizer.channelWaveforms, "master": visualizer.masterSamples])
            lastVisualizerRevision = moduleRevision
        }
        visualizerWasAnimating = animating && player.visualizersVisible
        // Tracker/Transport brauchen keine 60 vollständigen Zustandsmeldungen
        // pro Sekunde. Die Bilddaten invalidieren nur ihre eigenen QML-Views.
        if ContinuousClock.now >= nextStateUpdate {
            nextStateUpdate = .now + .milliseconds(50)
            emit("state", ["playing": player.isPlaying, "paused": player.isPaused,
                "position": player.currentPosition, "row": player.currentRow, "bpm": player.bpm, "speed": player.speed,
                "sound": ["palClock": player.palClock, "stereoSeparation": player.stereoSeparation,
                          "useInterpolation": player.useInterpolation, "ledFilterActive": player.ledFilterActive],
                "elapsed": visualizer.elapsedTime, "duration": visualizer.totalDuration,
                "muted": (0..<player.channelCount).map { player.isMuted(channelIndex: $0) },
                "solo": (0..<player.channelCount).map { player.isSoloed(channelIndex: $0) },
                "timerSeconds": player.sleepTimer.snapshot.remainingSeconds, "timerActive": player.sleepTimer.snapshot.isActive,
                "timerPhase": String(describing: player.sleepTimer.snapshot.phase),
                "markerSaving": markerWritesInFlight > 0,
                "sectionActive": player.sectionLoopIsActive, "sectionPreparing": player.sectionLoopIsPreparing,
                "sectionError": player.sectionLoopError?.localizedDescription ?? "",
                "sectionProgress": player.sectionLoopProgress])
        }
        if let mod = player.activeMod, mod.patternTable.indices.contains(player.currentPosition) {
            let pattern = mod.patternTable[player.currentPosition]
            if pattern != lastPattern || player.currentPosition != lastPosition, mod.patterns.indices.contains(pattern) {
                lastPattern = pattern; lastPosition = player.currentPosition
                emit("pattern", ["index": pattern, "position": player.currentPosition,
                    "rows": mod.patterns[pattern].rows.map { row in row.notes.map { note in
                        let text = TrackerNoteText(note)
                        return ["noteText": text.note, "instrumentText": text.instrument, "volumeText": text.volume, "effectText": text.effect, "key": note.key, "period": note.period, "instrument": note.instrument,
                         "effect": note.effectId, "hasEffect": note.hasEffect, "data": note.effectData, "volume": note.volume, "volCmd": note.volCmd] as [String: Any]
                    } }])
            }
        }
        if noteRainVisible { updateNotes() }
    }
    private func updateNotes() {
        guard let source = player.notePreviewSource else {
            noteTask?.cancel(); noteTask = nil; noteSource = nil; notes = []; nextNoteSongEnd = nil
            emit("notes", ["time": 0, "notes": [], "overflow": false, "preparing": false]); return
        }
        let time = Double(source.exchange.frame) / source.configuration.sampleRate
        if noteSource != source.id {
            noteTask?.cancel(); noteTask = nil; noteSource = source.id
            noteWorker = NotePreviewWorker(); preparedThrough = 0; notes = []; nextNoteSongEnd = nil
            noteCommandCount = 0; noteRevision = UUID()
        }
        let commands = source.collectCommands()
        if commands.count != noteCommandCount {
            noteCommandCount = commands.count; noteRevision = UUID()
            noteTask?.cancel(); noteTask = nil
            preparedThrough = 0; notes = []; nextNoteSongEnd = nil
        }
        let end = (preferences["loop"] as? String) == "track" ? nil : nextNoteSongEnd
        let displayed = notes.compactMap { note -> [String: Any]? in
            guard let end else { return note }
            guard let start = note["start"] as? Double, start < end else { return nil }
            var clipped = note
            clipped["end"] = min(note["end"] as? Double ?? end, end)
            return clipped
        }
        emit("notes", ["time": time, "notes": displayed, "overflow": source.exchange.hasOverflowed, "preparing": noteTask != nil])
        guard noteTask == nil, preparedThrough < time + 9 else { return }
        let worker = noteWorker, id = source.id, revision = noteRevision
        noteTask = Task { [weak self] in
            do {
                let snapshot = try await worker.preview(source: source, commands: commands, currentTime: time, horizon: 10)
                guard let self, !Task.isCancelled, noteSource == id, noteRevision == revision else { return }
                notes = snapshot.notes.map { ["key": $0.key, "channel": $0.channel, "start": $0.start, "end": $0.end, "isOpen": $0.isOpen] }
                nextNoteSongEnd = snapshot.nextSongEnd
                preparedThrough = snapshot.preparedThrough; noteTask = nil
            } catch { if let self, noteRevision == revision { noteTask = nil } }
        }
    }
    private func songKeyRange(_ mod: Mod) -> [Int] {
        var low = 120, high = -1
        func include(_ key: Int) { if (0..<120).contains(key) { low = min(low, key); high = max(high, key) } }
        for index in Set(mod.patternTable) where mod.patterns.indices.contains(index) {
            for row in mod.patterns[index].rows {
                for note in row.notes {
                    let key = note.period > 0 ? Int((36 + 12 * log2(428.0 / Double(note.period))).rounded()) : note.key
                    include(key)
                    if mod.format == .it, mod.instruments.indices.contains(note.instrument),
                       let mapping = mod.instruments[note.instrument]?.noteSampleMapping,
                       let entry = mapping.entry(forSourceNote: key), entry.sampleID > 0 { include(entry.targetNote) }
                }
            }
        }
        return high >= low ? [low, high] : []
    }
    private func editMarker(_ command: String, _ v: [String: Any]) async throws {
        try requireWritable()
        guard let currentID, let mod = player.activeMod else { return }
        let layout = SongPositionLayout(module: mod)
        guard !layout.rowCounts.isEmpty else { return }
        let position = min(layout.rowCounts.count - 1, max(0, player.currentPosition))
        let row = min(max(0, layout.rowCounts[position] - 1), max(0, player.currentRow))
        let address = SongAddress(position: position, row: row)
        let name = v["text"] as? String ?? "Songstelle"
        let id = (v["id"] as? String).flatMap(UUID.init(uuidString:))
        let editedAddress: SongAddress? = (v["position"] as? Int).flatMap { position in
            guard let row = v["row"] as? Int else { return nil }
            let address = SongAddress(position: position, row: row)
            return layout.contains(address) ? address : nil
        }
        if v["position"] != nil, editedAddress == nil {
            throw NSError(domain: "SavageDesktop", code: 1, userInfo: [NSLocalizedDescriptionKey: "Die gewählte Songadresse ist ungültig."])
        }
        markerWritesInFlight += 1
        defer { markerWritesInFlight -= 1 }
        let snapshot = try await markerStore.update { document in
            if command == "markerAdd" {
                document.markers.append(SongMarker(sourceID: currentID, name: name, address: editedAddress ?? address))
            } else if let id {
                if command == "markerDelete" { document.markers.removeAll { $0.id == id && $0.sourceID == currentID } }
                else if let index = document.markers.firstIndex(where: { $0.id == id && $0.sourceID == currentID }) {
                    document.markers[index].name = name
                    if let editedAddress { document.markers[index].address = editedAddress }
                }
            }
        }
        if snapshot.revision >= markerRevision {
            markerDocument = snapshot.document; markerRevision = snapshot.revision; sendDetails()
        }
    }
    private func beginExport(_ v: [String: Any]) {
        guard exportTask == nil, let mod = exportModule ?? player.activeMod, let path = v["path"] as? String else { return }
        let output: ChannelStemRenderer.Output = (v["kind"] as? String == "stems") ? .channelStems : .stereoMix
        var options = exportOptions
        options.maximumSeconds = v["seconds"] as? Double ?? 180
        let capturedOptions = options
        let destination = URL(fileURLWithPath: path)
        let expected: WAVStamp?
        do { expected = try Self.wavStamp(destination, overwrite: output == .stereoMix && v["overwrite"] as? Bool == true) }
        catch { emit("error", ["message": error.localizedDescription]); return }
        let owner = self
        let coordinator = player
        exportTask = Task { [weak self] in
            let worker = Task.detached {
                if output == .stereoMix {
                    let staging = destination.deletingLastPathComponent().appendingPathComponent(".savage-mix-\(UUID()).wav")
                    defer { try? FileManager.default.removeItem(at: staging) }
                    try coordinator.exportActiveModToWav(mod: mod, stereoSeparation: capturedOptions.stereoSeparation,
                        useInterpolation: capturedOptions.useInterpolation, palClock: capturedOptions.palClock,
                        destinationURL: staging, durationSeconds: capturedOptions.maximumSeconds)
                    try Self.publishWAV(staging, to: destination, replacing: expected)
                    return ["path": path] as [String: String]
                }
                _ = try ChannelStemRenderer.export(mod: mod, to: destination, options: capturedOptions, output: output) { progress in
                    Task { @MainActor in owner.emit("progress", ["value": progress]) }
                }
                return ["path": path]
            }
            do {
                let report = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                self?.emit("complete", ["path": path, "report": report])
            } catch is CancellationError { self?.emit("cancelled", [:]) }
            catch { self?.emit("error", ["message": error.localizedDescription]) }
            self?.exportTask = nil
        }
    }
    private struct WAVStamp: Sendable, Equatable {
        let inode: UInt64, size: UInt64
        let modified: Date
    }
    private nonisolated static func wavStamp(_ url: URL, overwrite: Bool) throws -> WAVStamp? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard overwrite else { throw CocoaError(.fileWriteFileExists) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let inode = attributes[.systemFileNumber] as? NSNumber, let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { throw CocoaError(.fileWriteFileExists) }
        return WAVStamp(inode: inode.uint64Value, size: size.uint64Value, modified: modified)
    }
    private nonisolated static func publishWAV(_ source: URL, to destination: URL, replacing expected: WAVStamp?) throws {
        try Task.checkCancellation()
        if let expected {
            guard try wavStamp(destination, overwrite: true) == expected else {
                throw NSError(domain: "SavageDesktop", code: 2, userInfo: [NSLocalizedDescriptionKey: "Das Ziel wurde während des Exports geändert und bleibt erhalten."])
            }
            let result = source.path.withCString { from in destination.path.withCString { to in rename(from, to) } }
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } else { try FileManager.default.linkItem(at: source, to: destination) }
    }
    private func beginVideoExport(_ v: [String: Any], preview: Bool = false) {
        guard exportTask == nil, let mod = exportModule ?? player.activeMod else { return }
        guard let path = preview ? temporary.appendingPathComponent("preview-\(UUID()).mov").path : v["path"] as? String else { return }
        var audio = exportOptions; audio.sampleRate = 48_000; audio.maximumSeconds = preview ? 5 : (v["seconds"] as? Double ?? 600)
        let options = NoteRainVideoOptions(width: v["width"] as? Int ?? 1280, height: v["height"] as? Int ?? 720,
            framesPerSecond: v["fps"] as? Int ?? 30, lookaheadSeconds: v["horizon"] as? Int ?? 4,
            keyRange: 0...119, appearance: (v["light"] as? Bool ?? (preferences["theme"] as? String == "Light")) ? .light : .dark,
            quality: v["compact"] as? Bool == true ? .compact : .high, audio: audio)
        let owner = self, destination = URL(fileURLWithPath: path)
        if preview { emit("videoPreviewState", ["active": true]) }
        #if os(Linux)
        guard let renderer = ProcessInfo.processInfo.environment["SAVAGE_VIDEO_RENDERER"] else {
            emit("error", ["message": "Der Qt-Videoencoder ist nicht konfiguriert."]); return
        }
        #endif
        exportTask = Task { [weak self] in
            let worker = Task.detached {
                let progress: @Sendable (Double) -> Void = { value in
                    Task { @MainActor in owner.emit("progress", ["value": value]) }
                }
                #if os(Linux)
                return try LinuxNoteRainVideoRenderer.export(mod: mod, to: destination, options: options,
                    renderer: URL(fileURLWithPath: renderer), progress: progress)
                #else
                return try NoteRainVideoRenderer.export(mod: mod, to: destination, options: options, progress: progress)
                #endif
            }
            do {
                let report = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                self?.emit(preview ? "videoPreview" : "complete", ["path": path, "report": owner.json(report)])
            } catch is CancellationError { self?.emit("cancelled", [:]) }
            catch { self?.emit("error", ["message": error.localizedDescription]) }
            if preview { self?.emit("videoPreviewState", ["active": false]) }
            self?.exportTask = nil
        }
    }
    private func beginBatchExport(_ v: [String: Any]) {
        guard exportTask == nil, let path = v["path"] as? String else { return }
        let ids = v["ids"] as? [String] ?? visibleIDs()
        let items = ids.compactMap { id in knownEntries[id] }.map {
            BatchWAVExportItem(source: $0.url, displayName: $0.displayName, sourceDescription: $0.folderPath.joined(separator: "/"))
        }
        let settings = BatchWAVExportSettings(output: v["stems"] as? Bool == true ? .channelStems : .stereoMix,
            conflictPolicy: v["rename"] as? Bool == true ? .keepBoth : .skipExisting,
            audio: .init(maximumSeconds: v["seconds"] as? Double ?? 300, stereoSeparation: Float(v["separation"] as? Double ?? 0.8),
                         useInterpolation: v["interpolation"] as? Bool ?? true, palClock: v["pal"] as? Bool ?? true))
        preferences["batchSettings"] = ["stems": v["stems"] ?? false, "rename": v["rename"] ?? false,
            "seconds": settings.audio.maximumSeconds, "separation": settings.audio.stereoSeparation,
            "interpolation": settings.audio.useInterpolation, "pal": settings.audio.palClock]
        do { try savePreferences(); emit("preferences", preferences) }
        catch { emit("notice", ["message": "Die Exporteinstellungen konnten nicht gespeichert werden."]) }
        let owner = self
        exportTask = Task { [weak self] in
            let worker = Task.detached {
                try BatchWAVExporter.export(items: items, to: URL(fileURLWithPath: path), settings: settings) { progress in
                    Task { @MainActor in owner.emit("progress", ["value": progress.fraction, "title": progress.sourceName]) }
                }
            }
            do {
                let report = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                self?.emit("complete", ["path": path, "report": owner.json(report)])
            } catch is CancellationError { self?.emit("cancelled", [:]) }
            catch { self?.emit("error", ["message": error.localizedDescription]) }
            self?.exportTask = nil
        }
    }
    private func collectionSnapshot() -> CollectionExchangeSnapshot {
        .init(playlists: saved, markers: markerDocument, trackSettings: overrides, playbackDefaults: defaults)
    }
    private func collectionSources(_ snapshot: CollectionExchangeSnapshot) throws -> [CollectionExchangeLocalTrack] {
        try CollectionExchangeSources.make(snapshot: snapshot,
            available: entries.map { .init(reference: $0.reference, url: $0.url) })
    }
    private func persistence() throws -> CollectionExchangePersistence {
        try .init(playlistsURL: directory.appendingPathComponent("playlists.json"),
            markersURL: directory.appendingPathComponent("song-markers.json"),
            trackSettingsURL: directory.appendingPathComponent("track-settings.json"),
            journalURL: directory.appendingPathComponent("collection-journal", isDirectory: true))
    }
    private func preferenceBytes() throws -> Data {
        let file = directory.appendingPathComponent("preferences.json")
        return FileManager.default.fileExists(atPath: file.path) ? try BoundedFileReader.read(file, maximumBytes: 1_048_576) : Data()
    }
    private func replacePreferences(_ before: Data, _ after: Data) throws {
        guard try preferenceBytes() == before else { throw CollectionExchangePersistenceError.staleState }
        let file = directory.appendingPathComponent("preferences.json")
        if after.isEmpty {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        } else { try after.write(to: file, options: .atomic) }
    }
    private func conflictKey(_ id: CollectionExchangeConflictID) -> String {
        switch id {
        case .playlist(let id): "playlist:" + id.uuidString
        case .playlistName(let id): "name:" + id.uuidString
        case .marker(let id): "marker:" + id.uuidString
        case .trackSettings(let id): "settings:" + id
        case .playbackDefaults: "defaults"
        }
    }
    private func sendExchangePreview() throws {
        guard let document = exchangeDocument else { return }
        let preview = try CollectionExchangeImporter.preview(document, into: collectionSnapshot(), mapping: exchangeMapping,
            skippedTrackIDs: exchangeSkipped, resolutions: exchangeResolutions)
        exchangePreview = preview
        exchangeConflictIDs = Dictionary(uniqueKeysWithValues: preview.conflicts.map { (conflictKey($0.id), $0.id) })
        emit("collectionPreview", ["ready": preview.isReady,
            "tracks": document.tracks.map { track in
                ["id": track.id.uuidString, "name": track.descriptor.fileName,
                 "relativePath": track.descriptor.relativePath ?? "",
                 "mapped": exchangeSkipped.contains(track.id) ? "__skip__" : (exchangeMapping[track.id]?.id ?? "")]
            },
            "conflicts": preview.conflicts.map { conflict in
                ["key": conflictKey(conflict.id), "name": conflict.name,
                 "allowed": conflict.allowedResolutions.map(\.rawValue), "selected": exchangeResolutions[conflict.id]?.rawValue ?? ""] as [String: Any]
            }, "playlists": document.playlists.count, "markers": document.markers.count])
    }
    private func applyExchange() async throws {
        try requireWritable()
        guard markerWritesInFlight == 0 else { throw CollectionExchangePersistenceError.busy }
        guard let preview = exchangePreview, preview.isReady else { throw CollectionExchangeError.invalidDecision }
        let next = try preview.result(ifUnchanged: collectionSnapshot())
        let persistence = try persistence(), disk = try persistence.snapshot()
        let before = try preferenceBytes()
        var nextPreferences = preferences
        if let defaults = next.playbackDefaults {
            nextPreferences["palClock"] = defaults.palClock; nextPreferences["stereoSeparation"] = defaults.stereoSeparation
            nextPreferences["useInterpolation"] = defaults.useInterpolation; nextPreferences["ledFilterActive"] = defaults.ledFilterActive
        }
        let after = try JSONSerialization.data(withJSONObject: nextPreferences, options: .sortedKeys)
        _ = try persistence.commit(.init(playlists: next.playlists, markers: next.markers, trackSettings: next.trackSettings),
            replacing: disk, auxiliaryBefore: before, auxiliaryAfter: after) { before, after in try self.replacePreferences(before, after) }
        preferences = nextPreferences; saved = next.playlists; committedSaved = saved; overrides = next.trackSettings
        markerStore = SongMarkerStore(fileURL: directory.appendingPathComponent("song-markers.json"))
        let markers = try await markerStore.snapshot(); markerDocument = markers.document; markerRevision = markers.revision
        exchangeDocument = nil; exchangePreview = nil
        applySound(); sendLibrary(); sendDetails(); emit("preferences", preferences); emit("collectionApplied", [:])
    }
    private func sendInspection() throws {
        guard let mod = inspectionModule else { return }
        let inspection = try ModuleInspection(module: mod)
        emit("inspection", ["title": mod.name, "format": mod.format.displayName,
            "channels": mod.channelCount, "usedChannels": mod.usedChannelCount, "patternCount": mod.patterns.count,
            "sampleCount": inspection.sampleCount, "instrumentCount": inspection.instrumentIndices.count,
            "initialTempo": mod.initialTempo, "initialSpeed": mod.initialSpeed, "initialVolume": mod.initialGlobalVolume,
            "linearFrequency": mod.linearFrequency, "formatCode": mod.format.rawValue, "volumeScale": mod.globalVolumeScale.rawValue,
            "origin": mod.itProperties.map { ["Erstellerversion (cwtv)": String(format: "0x%04X", $0.createdWithVersion),
                "Benötigte IT-Version (cmwt)": String(format: "0x%04X", $0.compatibleWithVersion),
                "IT-Modus": $0.usesInstruments ? "Instrumente" : "Samples",
                "Zuletzt mit OpenMPT gespeichert": $0.openMPTExtensions?.lastSavedWithVersion?.displayName ?? "—"] } ?? [:],
            "findings": json(inspection.compatibilityFindings),
            "patternRows": mod.patterns.indices.map { ["index": $0, "rows": mod.patterns[$0].rows.count, "uses": inspection.patternUseCounts[$0] ?? 0] },
            "orders": inspection.orders.map { ["position": $0.position, "pattern": $0.pattern, "rows": $0.rowCount ?? 0] },
            "tracker": inspection.tracker ?? "", "artist": inspection.artist ?? "", "warnings": inspection.compatibilityWarnings,
            "effects": inspection.effects.map { ["code": $0.code, "name": $0.title.german, "detail": $0.detail.german, "count": $0.count,
                                                 "parameters": $0.parameters, "implemented": $0.implemented, "volumeColumn": $0.isVolumeColumn] },
            "instruments": SampleInspection(module: mod).instruments.map { item in
                ["index": item.id, "name": item.name, "samples": item.sampleIDs.count, "sampleIDs": item.sampleIDs,
                 "keyZones": item.keyZones.map { ["start": $0.sourceNotes.lowerBound, "end": $0.sourceNotes.upperBound,
                    "targetStart": $0.targetNotes.lowerBound, "targetEnd": $0.targetNotes.upperBound, "sample": $0.sampleNumber.map(String.init) ?? "Unbelegt"] }] as [String: Any]
            },
            "samples": SampleInspection(module: mod).samples.map { ["id": $0.id, "number": $0.number,
                "instrument": $0.instrumentIndex ?? 0, "name": $0.sample?.name ?? "", "frames": $0.sample?.pcm.count ?? 0] }])
    }
    private func sendInstrument(_ index: Int) {
        guard let mod = inspectionModule, mod.instruments.indices.contains(index), let instrument = mod.instruments[index] else { return }
        let mapping = SampleInspection(module: mod).instruments.first { $0.id == index }
        emit("instrument", ["index": index, "name": instrument.name, "fadeout": instrument.fadeout,
            "autoVibrato": json(instrument.autoVibrato), "itProperties": json(instrument.itProperties),
            "volumeEnvelope": json(instrument.volumeEnvelope), "panningEnvelope": json(instrument.panningEnvelope),
            "pitchEnvelope": json(instrument.pitchEnvelope),
            "sampleIDs": mapping?.sampleIDs ?? [],
            "keyZones": mapping?.keyZones.map { ["start": $0.sourceNotes.lowerBound, "end": $0.sourceNotes.upperBound,
                "targetStart": $0.targetNotes.lowerBound, "targetEnd": $0.targetNotes.upperBound, "sample": $0.sampleID ?? ""] } ?? []])
    }
    private func sendSample(id: String, zoom: Int, position: Double, focus: String? = nil) throws {
        guard let mod = inspectionModule,
              let entry = SampleInspection(module: mod).samples.first(where: { $0.id == id }) else { return }
        guard let sample = entry.sample else { emit("sample", ["id": id, "empty": true]); return }
        var range = SampleFrameRange(frameCount: sample.pcm.count, zoom: zoom, position: position)
        if focus == "loop", sample.isLooped { range = .init(frameCount: sample.pcm.count, start: sample.loopStart, length: sample.loopLength) }
        if focus == "sustain", let sustain = sample.sustainLoop, sustain.type != .none {
            range = .init(frameCount: sample.pcm.count, start: sustain.start, length: sustain.length)
        }
        if focus != nil, position > 0 { range = .init(frameCount: sample.pcm.count, start: Int((Double(sample.pcm.count - range.count) * position).rounded()), length: range.count) }
        let waveform = try SampleWaveform.make(sample: sample, range: range)
        emit("sample", ["id": id, "name": sample.name, "frames": sample.pcm.count, "volume": sample.volume,
            "loopStart": sample.loopStart, "loopLength": sample.loopLength,
            "loopType": sample.loopType.rawValue, "sustainLoop": json(sample.sustainLoop), "itProperties": json(sample.itProperties),
            "finetune": sample.finetune, "relativeNote": sample.relativeNote, "panning": sample.panning, "c2spd": sample.c2spd,
            "left": waveform.left.map { [$0.minimum, $0.maximum] }, "right": waveform.right?.map { [$0.minimum, $0.maximum] } ?? [],
            "start": waveform.range.lowerBound, "end": waveform.range.upperBound])
    }
    private func json<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value), let result = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return NSNull() }
        return result
    }
    private func emit(_ event: String, _ fields: [String: Any]) {
        var message = fields; message["event"] = event
        guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) else { return }
        data.append(10); output.write(data)
    }
}

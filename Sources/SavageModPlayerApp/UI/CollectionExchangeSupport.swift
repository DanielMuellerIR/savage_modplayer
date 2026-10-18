import SwiftUI
import SavageModPlayerCore

@MainActor
enum CollectionExchangeSupport {
    static func persistence(includeSync: Bool = true) throws -> CollectionExchangePersistence {
        try CollectionExchangePersistence(
            playlistsURL: MainView.catalogURL("playlists.json", environment: "SAVAGE_PLAYLIST_STORE"),
            markersURL: MainView.catalogURL("song-markers.json", environment: "SAVAGE_SONG_MARKER_STORE"),
            trackSettingsURL: MainView.catalogURL("track-playback-settings.json", environment: "SAVAGE_TRACK_PLAYBACK_STORE"),
            journalURL: MainView.catalogURL("collection-import", environment: "SAVAGE_COLLECTION_JOURNAL"),
            syncStateURL: includeSync ? MainView.catalogURL("collection-sync.json", environment: "SAVAGE_COLLECTION_SYNC_STORE") : nil)
    }
    static func preferences() -> CollectionExchangePreferences {
        .init(defaults: .standard, domain: Bundle.main.bundleIdentifier ?? "com.viben.savagemodplayer",
              keys: CollectionExchangeSoundPreferences.keys(prefix: "savage."))
    }
}

@MainActor
final class CollectionExchangeRecovery: ObservableObject {
    @Published private(set) var error: Error?
    init() { recover() }
    func recover() {
        do {
            let preferences = CollectionExchangeSupport.preferences()
            _ = try CollectionExchangeSupport.persistence().recover { try preferences.replace(expected: $0, replacement: $1) }
            error = nil
        } catch { self.error = error }
    }
    func block(_ error: Error) { self.error = error }
}

extension MainView {
    func openCollectionExchange(fileURL: URL? = nil) {
        guard collectionContext == nil, !isCollectingPlaylist, NSApp.mainWindow?.attachedSheet == nil else {
            if let fileURL { pendingCollectionURLs.append(fileURL) }
            return
        }
        do {
            collectionSync?.setPaused(true)
            collectionRecovery.recover()
            if let error = collectionRecovery.error { coordinator.stop(); throw error }
            let binding = try makeCollectionBinding(includeSync: false)
            collectionContext = CollectionExchangeContext(model: binding.makeModel(read: { url, cancelled in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try CollectionExchangeCodec.load(from: url, isCancelled: cancelled)
            }), fileURL: fileURL)
        } catch { collectionSync?.setPaused(false); errorMessage = error.localizedDescription }
    }

    func makeCollectionBinding(includeSync: Bool) throws -> CollectionExchangeStoreBinding {
        let persistence = try CollectionExchangeSupport.persistence(includeSync: includeSync), preferences = CollectionExchangeSupport.preferences()
        let markers = songMarkers, settings = playbackSettings, recovery = collectionRecovery, coordinator = coordinator
        let playlists = $savedPlaylistDocument, favorites = $favorites
        let playlistURLs = $playlist, references = $trackReferences
        let root = autoplayFolderPath.isEmpty ? nil : URL(fileURLWithPath: autoplayFolderPath, isDirectory: true)
        return CollectionExchangeStoreBinding(
            persistence: persistence, preferences: preferences,
            normalize: { documents, raw in
                .init(playlists: documents.playlists, markers: documents.markers, trackSettings: documents.trackSettings,
                      playbackDefaults: try CollectionExchangeSoundPreferences.validatedOptions(in: preferences.values(in: raw), prefix: "savage."))
            }, encode: { candidate, documents, raw in
                let previous = try CollectionExchangeSoundPreferences.validatedOptions(in: preferences.values(in: raw), prefix: "savage.")
                let values = candidate.playbackDefaults.flatMap { $0 == previous ? nil : CollectionExchangeSoundPreferences.values($0, prefix: "savage.") } ?? [:]
                return .init(documents: .init(playlists: candidate.playlists, markers: candidate.markers, trackSettings: candidate.trackSettings), preferences: values)
            }, available: { snapshot in
                var sources: [String: CollectionExchangeResolvedTrack] = [:]
                let references = references.wrappedValue
                for url in playlistURLs.wrappedValue {
                    if let reference = references[url] { sources[reference.id] = .init(reference: reference, url: url) }
                }
                let needed = snapshot.referencedSourceIDs
                for (url, reference) in references where sources[reference.id] == nil && needed.contains(reference.id) {
                    sources[reference.id] = .init(reference: reference, url: url)
                }
                return Array(sources.values)
            }, libraryRoot: root,
            canCapture: { !markers.isSaving && settings.flush() },
            adopt: { documents, snapshot in
                playlists.wrappedValue = documents.playlists; favorites.wrappedValue = documents.playlists.favoriteIDs
                markers.adoptCommitted(documents.markers)
                settings.adoptCommitted(documents.trackSettings, defaults: snapshot.playbackDefaults ?? PlaybackOptions())
            }, recoveryFailed: { error in coordinator.stop(); recovery.block(error) })
    }

    func prepareCollectionSync() {
        do {
            if collectionSync == nil {
                collectionSync = CollectionSyncModel(binding: try makeCollectionBinding(includeSync: true),
                    service: CollectionSyncConfiguration.service())
            }
            collectionSync?.activate()
        } catch { errorMessage = error.localizedDescription }
    }

    func openCollectionSync() {
        guard collectionContext == nil, collectionSyncContext == nil, !isCollectingPlaylist,
              NSApp.mainWindow?.attachedSheet == nil else { return }
        prepareCollectionSync()
        if let collectionSync { collectionSyncContext = .init(model: collectionSync) }
    }

    func openNextCollectionIfPossible() {
        guard collectionContext == nil, !isCollectingPlaylist, NSApp.mainWindow?.attachedSheet == nil else { return }
        if let request = pendingAudioRequest {
            pendingAudioRequest = nil
            if request.epoch == playlistRequestID { handleDroppedURLs(request.urls, autoPlay: request.autoPlay); return }
        }
        guard !pendingCollectionURLs.isEmpty else { return }
        let url = pendingCollectionURLs.removeFirst(); openCollectionExchange(fileURL: url)
    }
}

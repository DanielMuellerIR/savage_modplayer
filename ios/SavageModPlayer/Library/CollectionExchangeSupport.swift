import SwiftUI
import SavageModPlayerCore

@MainActor
enum CollectionExchangeSupport {
    static let prefix = "savage.ios."
    static func persistence(includeSync: Bool = true) throws -> CollectionExchangePersistence {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SavageModPlayer", isDirectory: true)
        return try .init(playlistsURL: support.appendingPathComponent("playlists.json"),
                         markersURL: support.appendingPathComponent("song-markers.json"),
                         trackSettingsURL: support.appendingPathComponent("track-playback-settings.json"),
                         journalURL: support.appendingPathComponent("collection-import", isDirectory: true),
                         syncStateURL: includeSync ? support.appendingPathComponent("collection-sync.json") : nil)
    }
    static func preferences() -> CollectionExchangePreferences {
        .init(defaults: .standard, domain: Bundle.main.bundleIdentifier ?? "com.viben.SavageModPlayer",
              keys: CollectionExchangeSoundPreferences.keys(prefix: prefix).union([LibraryStore.favoritesDefaultsKey]))
    }
    static func binding(library: LibraryStore, playlists: PlaylistCollectionStore, markers: SongMarkersModel,
                        player: PlaybackEngine, settings: PlayerSettings, persistence: CollectionExchangePersistence,
                        preferences: CollectionExchangePreferences, recoveryFailed: @escaping @MainActor (Error) -> Void) -> CollectionExchangeStoreBinding {
        func adapter(_ documents: CollectionExchangeStoredDocuments, _ data: Data) throws -> LibraryCollectionExchangeAdapter {
            let values = try preferences.values(in: data)
            if let favorites = values[LibraryStore.favoritesDefaultsKey], !(favorites is [String]) {
                throw CollectionExchangeError.invalidLocalState
            }
            return try .init(documents: documents, favoritePaths: Set(values[LibraryStore.favoritesDefaultsKey] as? [String] ?? []),
                             availablePaths: library.tracks.map(\.relativePath),
                             defaults: CollectionExchangeSoundPreferences.validatedOptions(in: values, prefix: prefix))
        }
        return CollectionExchangeStoreBinding(
            persistence: persistence, preferences: preferences,
            normalize: { documents, data in try adapter(documents, data).snapshot },
            encode: { snapshot, documents, data in
                let mapping = try adapter(documents, data), result = try mapping.storedResult(from: snapshot)
                var values: [String: Any] = [:]
                if snapshot.playlists.favoriteIDs != mapping.snapshot.playlists.favoriteIDs {
                    values[LibraryStore.favoritesDefaultsKey] = result.favoritePaths.sorted()
                }
                if let defaults = snapshot.playbackDefaults, defaults != mapping.snapshot.playbackDefaults {
                    values.merge(CollectionExchangeSoundPreferences.values(defaults, prefix: prefix)) { _, new in new }
                }
                return .init(documents: result.documents, preferences: values)
            }, available: { _ in
                library.tracks.compactMap { track in track.playlistReference.map { .init(reference: $0, url: track.url) } }
            }, canCapture: { !library.isBusy && !markers.isSaving && player.playbackSettings.flush() },
            adopt: { documents, snapshot in
                let paths = snapshot.playlists.favoriteIDs.compactMap { PlaylistTrackSource(stableID: $0)?.libraryRelativePath }
                playlists.adoptCommitted(documents.playlists); library.adoptCommittedFavorites(Set(paths))
                markers.adoptCommitted(documents.markers)
                let defaults = snapshot.playbackDefaults ?? PlaybackOptions()
                settings.setPlaybackOptions(defaults); settings.objectWillChange.send()
                player.playbackSettings.adoptCommitted(documents.trackSettings, defaults: defaults)
            }, recoveryFailed: recoveryFailed)
    }
}

@MainActor
final class CollectionExchangeBootstrap: ObservableObject {
    @Published private(set) var model: AppModel?
    @Published private(set) var error: Error?
    private var pending: [URL] = []
    init(recoverOnInit: Bool = true) { if recoverOnInit { recover() } }
    func recover() {
        do {
            let preferences = CollectionExchangeSupport.preferences()
            _ = try CollectionExchangeSupport.persistence().recover { try preferences.replace(expected: $0, replacement: $1) }
            let model = AppModel(collectionRecoveryFailure: { [weak self] error in self?.block(error) })
            self.model = model; error = nil
            let urls = pending; pending = []; for url in urls { model.open(url) }
        } catch { self.error = error }
    }
    func open(_ url: URL) { if let model { model.open(url) } else { pending.append(url) } }
    private func block(_ error: Error) { model?.player.stop(); model = nil; self.error = error }
}

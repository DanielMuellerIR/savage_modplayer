import SwiftUI
import SavageModPlayerCore

extension MainView {
    func updateSongMarkerContext() {
        songMarkers.setContext(sourceID: activeTrackSourceID, module: coordinator.activeMod, moduleID: loadedModuleID)
    }
    static func catalogURL(_ name: String, environment: String) -> URL {
        if let path = ProcessInfo.processInfo.environment[environment], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SavageModPlayer").appendingPathComponent(name)
    }

    func refreshLibraryCatalog() {
        if catalog.query.usesFlatList { filteredPlaylistURLs = [] }
        catalog.setFavorites(favorites)
        catalog.setSources(playlist.compactMap { url in
            guard let reference = trackReferences[url] else { return nil }
            return LibraryCatalogSource(id: reference.id, url: url, displayName: reference.displayName,
                folderPath: (folderPathByURL[url] ?? []).joined(separator: "/"))
        })
    }

    func applyCatalogSelection(_ ids: [String]) {
        var urls: [String: URL] = [:]
        for url in playlist {
            if let id = trackReferences[url]?.id, urls[id] == nil { urls[id] = url }
        }
        filteredPlaylistURLs = ids.compactMap { urls[$0] }
    }

    func markActiveTrackHeard() {
        guard coordinator.isPlaying && !coordinator.isPaused, let id = activeTrackSourceID else { return }
        catalog.markHeard(id)
    }
}

extension ModuleMetadata {
    var librarySummary: String {
        let seconds = max(0, Int(durationSeconds.rounded()))
        let duration = (durationIsLimited ? "≥" : "") + String(format: "%d:%02d", seconds / 60, seconds % 60)
        return [format.libraryFamily.rawValue, "\(channelCount)ch", duration, title].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

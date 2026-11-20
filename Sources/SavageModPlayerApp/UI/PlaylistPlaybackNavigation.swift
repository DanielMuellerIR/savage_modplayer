import Foundation
import SavageModPlayerCore

struct PlaylistPlaybackNavigation {
    var queue = TrackQueue()
    var resumeURL: URL?
    var currentIndex = -1

    struct Playlist {
        let urls: [URL]
        let selection: [URL]?
        let wrap: Bool
        let shuffle: Bool

        var eligibleIndices: [Int] {
            guard let selection else { return Array(urls.indices) }
            var indices: [URL: Int] = [:]
            for (index, url) in urls.enumerated() where indices[url] == nil { indices[url] = index }
            return selection.compactMap { indices[$0] }
        }

        func adjacent(to index: Int, backwards: Bool) -> Int? {
            PlaylistNavigation.adjacentIndex(
                current: index, eligible: eligibleIndices, backwards: backwards, wrap: wrap, shuffle: shuffle
            )
        }
    }

    mutating func select(_ index: Int, in urls: [URL], load: (URL) -> Bool) -> Bool {
        guard urls.indices.contains(index), load(urls[index]) else { return false }
        resumeURL = nil
        currentIndex = index
        return true
    }

    mutating func next(in playlist: Playlist, references: [URL: PlaylistTrackReference],
                       loadSelection: (URL) -> Bool, loadQueued: (URL) -> Bool,
                       startQueuedPlayback: () -> Bool, missing: (PlaylistTrackReference) -> Void) -> Bool {
        if let queued = queue.items.first {
            guard let url = TrackQueue.playbackURL(for: queued.track, playlist: playlist.urls, references: references) else {
                missing(queued.track)
                return false
            }
            let origin = playlist.urls.indices.contains(currentIndex) ? playlist.urls[currentIndex] : nil
            guard loadQueued(url) else { return false }
            currentIndex = playlist.urls.firstIndex(of: url) ?? -1
            guard startQueuedPlayback() else { return false }
            if resumeURL == nil { resumeURL = origin }
            queue.remove(id: queued.id)
            return true
        }
        let anchor = resumeURL.flatMap { playlist.urls.firstIndex(of: $0) }
        let start = playlist.shuffle ? currentIndex : anchor ?? currentIndex
        guard let index = playlist.adjacent(to: start, backwards: false) else { return false }
        return select(index, in: playlist.urls, load: loadSelection)
    }

    mutating func previous(in playlist: Playlist, load: (URL) -> Bool) -> Bool {
        let anchor = resumeURL.flatMap { playlist.urls.firstIndex(of: $0) }
        guard let index = anchor ?? playlist.adjacent(to: currentIndex, backwards: true) else { return false }
        return select(index, in: playlist.urls, load: load)
    }
}

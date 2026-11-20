import Foundation
import SavageModPlayerCore

struct DesktopLibraryEvents {
    struct Recent: Encodable {
        let id: String
        let name: String
    }

    struct QueueItem: Encodable {
        let id: String
        let sourceID: String
        let name: String
    }

    struct Begin: Encodable {
        let event = DesktopEvent.libraryBegin.rawValue
        let currentID: String
        let selection: [String]
        let playlists: [SavedPlaylist]
        let recent: [Recent]
        let query: LibraryQuery
        let savedFilters: [SavedLibraryFilter]
        let queue: [QueueItem]
    }

    struct Track: Encodable {
        let id: String
        let name: String
        let folders: [String]
        let favorite: Bool
        let heard: Bool
        let metadata: ModuleMetadataRecord?
    }

    struct Tracks: Encodable {
        let event = DesktopEvent.libraryTracks.rawValue
        let tracks: [Track]
    }

    struct Visible: Encodable {
        let event = DesktopEvent.libraryVisible.rawValue
        let ids: [String]
    }

    struct End: Encodable {
        let event = DesktopEvent.libraryEnd.rawValue
    }
}

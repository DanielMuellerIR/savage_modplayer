import Combine
import Foundation
import SavageModPlayerCore

@MainActor
final class PlaylistCollectionStore: ObservableObject {
    @Published private(set) var document = SavedPlaylistDocument()
    @Published private(set) var canWrite = true
    @Published private(set) var errorMessageKey: String?
    let metadataDidChange = PassthroughSubject<Void, Never>()
    private let store: SavedPlaylistStore

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = SavedPlaylistStore(fileURL: fileURL ?? support
            .appendingPathComponent("SavageModPlayer/playlists.json"))
        do { document = try store.load() }
        catch {
            canWrite = false
            errorMessageKey = "playlists.error.load"
        }
    }

    func adoptCommitted(_ document: SavedPlaylistDocument) {
        self.document = document; canWrite = true; errorMessageKey = nil
    }

    @discardableResult
    func create(name: String) -> UUID? {
        let playlist = SavedPlaylist(name: name, tracks: [])
        return update { $0.playlists.append(playlist) } ? playlist.id : nil
    }

    func rename(id: UUID, name: String) {
        guard let index = document.playlists.firstIndex(where: { $0.id == id }) else { return }
        _ = update { $0.playlists[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func delete(id: UUID) { _ = update { $0.playlists.removeAll { $0.id == id } } }

    func add(_ track: TrackRef, to id: UUID) {
        guard let reference = track.playlistReference,
              let index = document.playlists.firstIndex(where: { $0.id == id }),
              !document.playlists[index].tracks.contains(where: { $0.id == reference.id }) else { return }
        _ = update { $0.playlists[index].tracks.append(reference) }
    }

    func removeTracks(from id: UUID, at offsets: IndexSet) {
        guard let index = document.playlists.firstIndex(where: { $0.id == id }) else { return }
        _ = update {
            for offset in offsets.sorted(by: >) where $0.playlists[index].tracks.indices.contains(offset) {
                $0.playlists[index].tracks.remove(at: offset)
            }
        }
    }

    func moveTracks(in id: UUID, from offsets: IndexSet, to destination: Int) {
        guard let index = document.playlists.firstIndex(where: { $0.id == id }),
              offsets.allSatisfy({ document.playlists[index].tracks.indices.contains($0) }),
              (0...document.playlists[index].tracks.count).contains(destination) else { return }
        _ = update { document in
            let moving = offsets.sorted().map { document.playlists[index].tracks[$0] }
            for offset in offsets.sorted(by: >) { document.playlists[index].tracks.remove(at: offset) }
            let target = destination - offsets.filter { $0 < destination }.count
            document.playlists[index].tracks.insert(contentsOf: moving, at: target)
        }
    }

    private func update(_ change: (inout SavedPlaylistDocument) -> Void) -> Bool {
        guard canWrite else { return false }
        var candidate = document
        change(&candidate)
        do {
            try store.save(candidate)
            document = candidate
            errorMessageKey = nil
            metadataDidChange.send()
            return true
        } catch {
            errorMessageKey = "playlists.error.save"
            return false
        }
    }

    static func resolve(_ playlist: SavedPlaylist, in library: LibraryStore) -> [TrackRef] {
        playlist.tracks.compactMap { reference in
            reference.source.libraryRelativePath.flatMap { library.track(forRelativePath: $0) }
        }
    }
}

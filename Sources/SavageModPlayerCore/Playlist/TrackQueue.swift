import Foundation

public struct TrackQueue: Sendable {
    public struct Item: Identifiable, Sendable {
        public let id: UUID
        public let track: PlaylistTrackReference
    }

    public private(set) var items: [Item] = []
    public init() {}

    public mutating func enqueue(_ track: PlaylistTrackReference, next: Bool = false) {
        let item = Item(id: UUID(), track: track)
        if next { items.insert(item, at: 0) } else { items.append(item) }
    }

    @discardableResult
    public mutating func popFirst() -> Item? {
        items.isEmpty ? nil : items.removeFirst()
    }

    public mutating func remove(id: UUID) { items.removeAll { $0.id == id } }
    public mutating func removeAll() { items.removeAll() }

    public mutating func move(id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
    }

    public static func playbackURL(for track: PlaylistTrackReference, playlist: [URL],
                                   references: [URL: PlaylistTrackReference]) -> URL? {
        // Nach erneutem Oeffnen existieren mehrere Temp-Kopien derselben Quelle.
        // Die aktuelle Listenkopie gewinnt, sonst entstuenden doppelte Titel.
        playlist.first {
            references[$0]?.id == track.id && FileManager.default.fileExists(atPath: $0.path)
        } ?? references.first {
            $0.value.id == track.id && FileManager.default.fileExists(atPath: $0.key.path)
        }?.key
    }
}

public enum PlaylistNavigation {
    // Der Wiedergabebereich ist eine explizite, geordnete Auswahl. Eine blosse
    // Aenderung des Suchtextes ersetzt diesen Bereich nicht mitten im Song.
    public static func adjacentIndex(current: Int, eligible: [Int], backwards: Bool,
                                     wrap: Bool, shuffle: Bool) -> Int? {
        guard !eligible.isEmpty else { return nil }
        if shuffle {
            let others = eligible.filter { $0 != current }
            return others.randomElement() ?? eligible.first
        }
        guard let position = eligible.firstIndex(of: current) else {
            return backwards ? eligible.last : eligible.first
        }
        let next = position + (backwards ? -1 : 1)
        if eligible.indices.contains(next) { return eligible[next] }
        return wrap ? (backwards ? eligible.last : eligible.first) : nil
    }
}

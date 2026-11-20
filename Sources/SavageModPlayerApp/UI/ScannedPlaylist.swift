import Foundation
import SavageModPlayerCore

struct ScannedPlaylist: Sendable {
    let entries: [PlaylistScanner.Entry]
    let tree: PlaylistScanner.FolderNode
    let folderPaths: [URL: [String]]

    init(urls: [URL], tempDir: URL) {
        let collected = PlaylistScanner.collectEntries(from: urls, tempDir: tempDir) { Task.isCancelled }
        let fullTree = PlaylistScanner.buildTree(collected)
        let flattened = PlaylistScanner.flattenedFiles(fullTree)
        var seen = Set<String>()
        entries = flattened.filter { seen.insert($0.source.id).inserted }
        tree = entries.count == flattened.count ? fullTree : PlaylistScanner.buildTree(entries)
        folderPaths = Dictionary(uniqueKeysWithValues: entries.map { ($0.url, $0.folderPath) })
    }
}

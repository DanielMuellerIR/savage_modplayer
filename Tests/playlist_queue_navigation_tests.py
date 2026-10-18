"""Native Navigation: Ein Queue-Titel darf die Ursprungsliste nicht erweitern."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PlaylistQueueNavigationTests(unittest.TestCase):
    def test_queued_track_returns_to_original_list_and_preserves_failed_anchor(self):
        playback = (ROOT / 'Sources/SavageModPlayerApp/UI/MainView+Playback.swift').read_text()
        files = (ROOT / 'Sources/SavageModPlayerApp/UI/MainView+Files.swift').read_text()
        queue = (ROOT / 'Sources/SavageModPlayerCore/Playlist/TrackQueue.swift').read_text()
        navigation = playback[playback.index('    var eligiblePlaylistIndices:'):playback.index('    // Wird ausgeloest')]
        selection = files[files.index('    @discardableResult\n    func selectPlaylistSong'):files.index('    @discardableResult\n    func loadModFile')]
        script = '''import Foundation
public struct PlaylistTrackReference: Sendable {
    let id: String
    var displayName: String { id }
}
''' + queue.replace('import Foundation', '') + '''
class SleepTimer {
    var allowed = true
    func allowsPlayback() -> Bool { allowed }
}
class PlaybackActions {
    func prepareManualPlayback(coordinator: Coordinator) {}
}
class Coordinator {
    let sleepTimer = SleepTimer()
    var isPlaying = false
    var isPaused = false
    func play() { isPlaying = true }
}
class Harness {
    let coordinator = Coordinator()
    let playbackActions = PlaybackActions()
    var playlist: [URL] = []
    var playbackSelection: [URL]?
    var trackReferences: [URL: PlaylistTrackReference] = [:]
    var currentPlaylistIndex = 0
    var queueResumeURL: URL?
    var trackQueue = TrackQueue()
    var errorMessage: String?
    var shuffleEnabled = false
    enum Loop { case playlist, track, none }
    var loopMode = Loop.playlist
    var loaded: [URL] = []
    var failing: URL?
    func expandAncestors(of: URL) {}
    func loadModFile(from url: URL) -> Bool {
        if url == failing { return false }
        loaded.append(url); coordinator.isPlaying = false
        return true
    }
''' + navigation + selection + '''
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let a = root.appendingPathComponent("A.mod"), b = root.appendingPathComponent("B.mod"), c = root.appendingPathComponent("C.mod")
for url in [a,b,c] { try Data([1]).write(to: url) }
let h = Harness()
h.playlist = [a,b]; h.currentPlaylistIndex = 0
h.trackReferences = [a:.init(id:"A"), b:.init(id:"B"), c:.init(id:"C")]
h.trackQueue.enqueue(h.trackReferences[c]!)
assert(h.nextTrack()); assert(h.loaded == [c]); assert(h.playlist == [a,b])
assert(!h.coordinator.isPlaying); assert(h.currentPlaylistIndex == -1)
assert(h.nextTrack()); assert(h.loaded == [c,b]); assert(h.queueResumeURL == nil)
assert(h.nextTrack()); assert(h.loaded == [c,b,a]); assert(h.playlist == [a,b])
h.trackQueue.enqueue(h.trackReferences[c]!); h.failing = c
assert(!h.nextTrack()); assert(h.trackQueue.items.count == 1); assert(h.queueResumeURL == nil)
h.failing = nil; assert(h.nextTrack()); assert(h.queueResumeURL == a)
h.failing = b; assert(!h.nextTrack()); assert(h.queueResumeURL == a)
h.failing = nil; assert(h.nextTrack()); assert(h.loaded.last == b)
h.trackQueue.enqueue(h.trackReferences[c]!)
h.coordinator.sleepTimer.allowed = false
let before = h.loaded
assert(!h.nextTrack(automatic: true))
assert(h.loaded == before && h.trackQueue.items.count == 1)
h.coordinator.sleepTimer.allowed = true
h.coordinator.isPlaying = true
assert(h.nextTrack(automatic: true))
assert(h.loaded.last == c && h.trackQueue.items.isEmpty)
'''
        with tempfile.TemporaryDirectory(prefix='savage-queue-navigation-') as work:
            source = Path(work) / 'main.swift'
            binary = Path(work) / 'test'
            source.write_text(script)
            subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True, timeout=60)
            subprocess.run([str(binary), work], check=True, timeout=10)


if __name__ == '__main__':
    unittest.main()

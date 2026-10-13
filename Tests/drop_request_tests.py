"""Provider-Callbacks gegen unveränderte native Drop-/Auftragsfunktionen prüfen."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeDropRequestTests(unittest.TestCase):
    def test_delayed_provider_obeys_stop_and_new_selection(self):
        view = (ROOT / 'Sources/SavageModPlayerApp/UI/MainView.swift').read_text()
        files = (ROOT / 'Sources/SavageModPlayerApp/UI/MainView+Files.swift').read_text()
        playback = (ROOT / 'Sources/SavageModPlayerApp/UI/MainView+Playback.swift').read_text()
        note_rain = (ROOT / 'Sources/SavageModPlayerApp/UI/NoteRainView.swift').read_text()
        actions = (ROOT / 'Sources/SavageModPlayerApp/UI/PlaybackActions.swift').read_text()
        actions = actions[actions.index('final class PlaybackActions'):]
        transport = playback[playback.index('    func togglePlayback()'):playback.index('    // Zufaelligen')]
        rain_toggle = note_rain[note_rain.index('    private func togglePlayback()'):note_rain.index('    private func updateMuteState()')].replace('private func', 'func')
        self.assertIn('Button(action: togglePlayback)', note_rain)
        self.assertIn('Button(action: stopPlayback)', note_rain)
        for event, action in [('menuPlayStop', 'togglePlayback'), ('menuStop', 'stopPlayback')]:
            receiver = view[view.index('publisher(for: NSNotification.Name("' + event + '"))'):].split('            }', 1)[0]
            self.assertIn(action + '()', receiver)
        media = {}
        for event in ['mediaPlay', 'mediaPause']:
            source = view[view.index('publisher(for: NSNotification.Name("' + event + '"))'):]
            media[event] = source.split('{ _ in', 1)[1].split('\n            }', 1)[0]
        container = view[view.index('final class DropURLsContainer'):view.index('struct MainView')]
        drop = view[view.index('                let requestID = UUID()', view.index('.onDrop(')):
                    view.index('                return true', view.index('.onDrop('))]
        revision = files[files.index('        let requestID: UUID'):files.index('        self.errorMessage = nil')]
        script = '''import Foundation
protocol ObservableObject {}
class Provider {
    var completion: ((URL?, Error?) -> Void)?
    func canLoadObject(ofClass: URL.Type) -> Bool { true }
    func loadObject(ofClass: URL.Type, completionHandler: @escaping (URL?, Error?) -> Void) -> Progress {
        completion = completionHandler
        return Progress(totalUnitCount: 1)
    }
}
''' + container + '''
class ModPlayerCoordinator {
    var activeMod: Bool? = true
    var isPlaying = true
    var isPaused = false
    func stop() { isPlaying = false; isPaused = false }
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func play() { isPlaying = true; isPaused = false }
}
''' + actions + '''
class StateStorage {
    var calls: [(URL, Bool, UUID)] = []
}
struct Harness {
    let storage = StateStorage()
    let coordinator = ModPlayerCoordinator()
    let playbackActions = PlaybackActions()
    var playlistRequestID: UUID {
        get { playbackActions.fileRequestID }
        nonmutating set { playbackActions.fileRequestID = newValue }
    }
    var calls: [(URL, Bool, UUID)] {
        get { storage.calls }
        nonmutating set { storage.calls = newValue }
    }
    func handleDroppedURLs(_ urls: [URL], autoPlay: Bool = false, requestID pendingRequestID: UUID? = nil) {
''' + revision + '''
        calls.append((urls[0], autoPlay, requestID))
    }
''' + transport + '''
    func mediaPlay() {
''' + media['mediaPlay'] + '''
    }
    func mediaPause() {
''' + media['mediaPause'] + '''
    }
    func drop(_ providers: [Provider]) -> Bool {
''' + drop + '''
        return true
    }
}
struct NoteRainActions {
    let coordinator: ModPlayerCoordinator
    let playbackActions: PlaybackActions
''' + rain_toggle + '''
}
func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
let harness = Harness()
let older = Provider()
assert(harness.drop([older]))
let rain = NoteRainActions(coordinator: harness.coordinator, playbackActions: harness.playbackActions)
rain.stopPlayback()
older.completion?(URL(fileURLWithPath: "/synthetic/old.mod"), nil)
drain()
assert(harness.calls.isEmpty, "Alter Drop startet nach Stop")
assert(!harness.coordinator.isPlaying)
for action in [harness.togglePlayback, rain.togglePlayback, harness.stopPlayback, rain.stopPlayback] {
    harness.coordinator.isPlaying = true
    harness.coordinator.isPaused = false
    let pending = Provider()
    assert(harness.drop([pending]))
    action()
    pending.completion?(URL(fileURLWithPath: "/synthetic/old.mod"), nil)
    drain()
    assert(harness.calls.isEmpty, "Transportaktion laesst alten Drop durch")
    assert(harness.coordinator.isPaused || !harness.coordinator.isPlaying)
}
for action in [harness.mediaPlay, harness.mediaPause] {
    harness.coordinator.isPlaying = true
    harness.coordinator.isPaused = true
    let pending = Provider()
    assert(harness.drop([pending]))
    let request = harness.playlistRequestID
    action()
    assert(harness.playlistRequestID != request, "Systemtransport entwertet Auftrag nicht")
    pending.completion?(URL(fileURLWithPath: "/synthetic/old.mod"), nil)
    drain()
    assert(harness.calls.isEmpty, "Alter Drop ersetzt Systemtransport")
}
let first = Provider(), second = Provider()
assert(harness.drop([first]))
assert(harness.drop([second]))
let secondRevision = harness.playlistRequestID
second.completion?(URL(fileURLWithPath: "/synthetic/new.mod"), nil)
drain()
first.completion?(URL(fileURLWithPath: "/synthetic/old.mod"), nil)
drain()
assert(harness.calls.count == 1, "Alter Drop ersetzt neueren")
assert(harness.calls[0].0.lastPathComponent == "new.mod")
assert(harness.calls[0].1)
assert(harness.calls[0].2 == secondRevision, "Notify vergibt eine neue statt der ursprünglichen Revision")
print("Native Drop-Revision: Stop, neuere Auswahl und durchgehende Identität bestanden.")
'''
        with tempfile.TemporaryDirectory(prefix='savage-drop-test-') as directory:
            source = Path(directory) / 'drop.swift'
            source.write_text(script)
            result = subprocess.run(['swift', str(source)], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()

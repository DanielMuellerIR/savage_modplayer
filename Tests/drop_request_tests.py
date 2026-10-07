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
        container = view[view.index('final class DropURLsContainer'):view.index('struct MainView')]
        drop = view[view.index('                let requestID = UUID()', view.index('.onDrop(')):
                    view.index('                return true', view.index('.onDrop('))]
        revision = files[files.index('        let requestID: UUID'):files.index('        self.errorMessage = nil')]
        script = '''import Foundation
class Provider {
    var completion: ((URL?, Error?) -> Void)?
    func canLoadObject(ofClass: URL.Type) -> Bool { true }
    func loadObject(ofClass: URL.Type, completionHandler: @escaping (URL?, Error?) -> Void) -> Progress {
        completion = completionHandler
        return Progress(totalUnitCount: 1)
    }
}
''' + container + '''
class StateStorage {
    var playlistRequestID = UUID()
    var calls: [(URL, Bool, UUID)] = []
}
struct Harness {
    let storage = StateStorage()
    var playlistRequestID: UUID {
        get { storage.playlistRequestID }
        nonmutating set { storage.playlistRequestID = newValue }
    }
    var calls: [(URL, Bool, UUID)] {
        get { storage.calls }
        nonmutating set { storage.calls = newValue }
    }
    func handleDroppedURLs(_ urls: [URL], autoPlay: Bool = false, requestID pendingRequestID: UUID? = nil) {
''' + revision + '''
        calls.append((urls[0], autoPlay, requestID))
    }
    func drop(_ providers: [Provider]) -> Bool {
''' + drop + '''
        return true
    }
}
func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
let harness = Harness()
let older = Provider()
assert(harness.drop([older]))
harness.playlistRequestID = UUID() // dieselbe Entwertung wie Stop/Pause
older.completion?(URL(fileURLWithPath: "/synthetic/old.mod"), nil)
drain()
assert(harness.calls.isEmpty, "Alter Drop startet nach Stop")
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

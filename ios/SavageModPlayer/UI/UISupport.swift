import SavageModPlayerCore
import SwiftUI

// Kleine Helfer, die sich mehrere Ansichten teilen. Sie liegen bewusst an einem
// Ort, damit die eigentlichen Views nur noch Layout enthalten.

// MARK: - Einstellungen aendern

extension PlayerSettings {

    // Einen Wert setzen und die Aenderung ausdruecklich ankuendigen.
    //
    // Warum das noetig ist: `PlayerSettings` legt jeden Wert mit `@AppStorage`
    // ab. Der schreibt zwar sofort in die UserDefaults, meldet die Aenderung
    // aber NICHT an das umgebende Objekt. Ohne diese Ankuendigung saehe SwiftUI
    // keinen Grund, die Ansicht neu zu zeichnen — ein Schalter spraenge um und
    // zeigte gleich darauf wieder seine alte Stellung.
    //
    // Die Wiedergabe erfaehrt davon auf einem anderen Weg: `PlaybackEngine`
    // hoert auf `UserDefaults.didChangeNotification` und zieht Klangwerte von
    // sich aus nach. Hier geht es also ausschliesslich um die Anzeige.
    func set<Value>(_ keyPath: ReferenceWritableKeyPath<PlayerSettings, Value>, to value: Value) {
        objectWillChange.send()
        self[keyPath: keyPath] = value
    }

    // Dasselbe als Binding, damit Toggle, Slider und Picker direkt daran
    // haengen koennen.
    func binding<Value>(_ keyPath: ReferenceWritableKeyPath<PlayerSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { newValue in self.set(keyPath, to: newValue) })
    }
}

// MARK: - Anzeige-Helfer

// Spielzeit als mm:ss. Negative oder unendliche Werte (noch kein Song geladen)
// ergeben "00:00" statt einer sinnlosen Zahl.
func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "00:00" }
    let total = Int(seconds)
    return String(format: "%02d:%02d", total / 60, total % 60)
}

// Kurzes Kuerzel fuers Titelbild. Die MOD-Spielarten (ProTracker, Soundtracker,
// Multichannel) sind fuer den Nutzer alle schlicht "MOD".
func moduleFormatLabel(_ format: ModuleFormat?) -> String {
    switch format {
    case .protracker, .soundtracker, .multichannel: return "MOD"
    case .s3m: return "S3M"
    case .xm: return "XM"
    case .it: return "IT"
    case nil: return "MOD"
    }
}

// Ordnerpfad eines Titels als Text. Liegt der Titel direkt in der Wurzel, gibt
// es keinen Pfad zu zeigen — dann steht dort der Name der Bibliothek.
@ViewBuilder
func folderPathText(_ folderPath: [String]) -> some View {
    if folderPath.isEmpty {
        Text("library.root")
    } else {
        // Text(verbatim:) ist hier Pflicht: Ordnernamen sind Nutzerdaten und
        // duerfen nicht als Lokalisierungs-Schluessel gedeutet werden.
        Text(verbatim: folderPath.joined(separator: " › "))
    }
}

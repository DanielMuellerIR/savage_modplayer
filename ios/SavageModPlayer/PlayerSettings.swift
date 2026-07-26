import Foundation
import SwiftUI

// Alle dauerhaften Einstellungen an einem Ort. Jede steht als @AppStorage in den
// UserDefaults und ueberlebt damit Neustarts — genau wie in der Mac-App, nur mit
// eigenem Schluessel-Praefix, damit sich die beiden Apps nie ins Gehege kommen.
//
// Warum eine Klasse und nicht @AppStorage direkt in den Views: die Wiedergabe
// muss dieselben Werte lesen wie die Oberflaeche (PAL/NTSC und LED-Filter
// wirken im DSP, nicht im Bild). Ein gemeinsames Objekt spart das Durchreichen
// von einem Dutzend Bindings.
@MainActor
final class PlayerSettings: ObservableObject {

    // MARK: - Klang

    // Amiga-Taktrate: PAL (Europa) oder NTSC. Beeinflusst die Tonhoehe von
    // MOD-Dateien hoerbar.
    @AppStorage("savage.ios.palClock") var palClock: Bool = true

    // Der beruehmte Tiefpass des Amiga 500 ("LED-Filter"). Nimmt die Schaerfe
    // aus den Hoehen und klingt fuer viele Ohren nach echtem Amiga.
    @AppStorage("savage.ios.ledFilter") var ledFilterActive: Bool = false

    // Hi-Fi-Interpolation glaettet die Samples. Aus = rauher Originalklang.
    @AppStorage("savage.ios.interpolation") var useInterpolation: Bool = true

    // Wie weit die Kanaele im Stereobild auseinanderliegen. 0 = Mono,
    // 1 = harte Amiga-Trennung (links/rechts vollstaendig getrennt).
    @AppStorage("savage.ios.stereoSeparation") var stereoSeparation: Double = 0.8

    @AppStorage("savage.ios.volume") var volume: Double = 0.6

    // MARK: - Wiedergabe

    @AppStorage("savage.ios.loopMode") private var loopModeRaw: String = LoopMode.playlist.rawValue
    var loopMode: LoopMode {
        get { LoopMode(rawValue: loopModeRaw) ?? .playlist }
        set { loopModeRaw = newValue.rawValue }
    }

    @AppStorage("savage.ios.shuffle") var shuffleEnabled: Bool = false

    // Zuletzt gespielter Titel (relativer Pfad). Beim naechsten Start wird er
    // wieder ausgewaehlt — nicht automatisch abgespielt.
    @AppStorage("savage.ios.lastPlayed") var lastPlayedRelativePath: String = ""

    // Position im zuletzt gespielten Titel (Order-Index), damit die Sitzung dort
    // weitergeht, wo sie aufgehoert hat.
    @AppStorage("savage.ios.lastPosition") var lastPlayedPosition: Int = 0

    // MARK: - Darstellung

    @AppStorage("savage.ios.theme") private var themeRaw: String = PlayerTheme.cyber.rawValue
    var theme: PlayerTheme {
        get { PlayerTheme(rawValue: themeRaw) ?? .cyber }
        set { themeRaw = newValue.rawValue }
    }

    // Wie oft die Visualisierungen pro Sekunde neu gezeichnet werden. Auf einem
    // Telefon ist das der groesste Akku-Hebel der Oberflaeche, deshalb einstellbar.
    @AppStorage("savage.ios.visualizerFPS") var visualizerFrameRate: Int = 20

    // Wie viele Kanal-Oszilloskope hoechstens gleichzeitig gezeichnet werden.
    // Ein IT-Modul kann 64 Kanaele haben — die sind auf einem iPhone-Display
    // weder lesbar noch bezahlbar.
    @AppStorage("savage.ios.maxChannelScopes") var maxVisibleChannelScopes: Int = 8
}

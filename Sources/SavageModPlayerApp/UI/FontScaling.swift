import SwiftUI

// MARK: - Globale UI-Schriftskalierung (macOS-tauglich)
//
// macOS-SwiftUI ignoriert `dynamicTypeSize` — ein globaler Auto-Zoom ist damit
// nicht moeglich. Stattdessen tragen wir einen Skalierungsfaktor im Environment
// (`uiFontScale`, 1.0 = normal), und jede UI-Schriftgroesse multipliziert ihre
// Basisgroesse damit. Gesetzt wird der Faktor am Szenen-Root (siehe AppMain);
// die Stufe (`savage.uiZoom`) haelt CMD +/-/0 fest und persistiert via
// @AppStorage. WICHTIG: NUR die UI-Schrift skaliert — das Tracker-Pattern-Grid
// (TrackerGridView) bleibt bewusst fix.

private struct UIFontScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
    var uiFontScale: CGFloat {
        get { self[UIFontScaleKey.self] }
        set { self[UIFontScaleKey.self] = newValue }
    }
}

// Zoom-Stufe (-3 … +5) auf einen Faktor abbilden (~13 % je Stufe, geklemmt auf
// 0.7 … 1.8) — identisch zum Vorbild Mucke_Baby.
func savageFontScale(_ zoom: Int) -> CGFloat {
    max(0.7, min(1.8, 1 + CGFloat(zoom) * 0.13))
}

// Ersatz fuer `.font(.system(size:weight:design:))`, der den `uiFontScale` aus
// dem Environment einrechnet. Als ViewModifier (nicht freie Funktion), weil nur
// ein View das Environment lesen kann. Anwendung: `.scaledFont(11, weight: .bold)`
// statt `.font(.system(size: 11, weight: .bold))`.
struct ScaledFontModifier: ViewModifier {
    @Environment(\.uiFontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}

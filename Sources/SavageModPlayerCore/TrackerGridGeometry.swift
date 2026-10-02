import Foundation

/// Rechenteil des Tracker-Rasters: welche Pattern-Zeilen ein Zeichenvorgang
/// wirklich braucht.
///
/// Hintergrund (Profil vom 2026-08-23): Der Canvas mit den Kanalzellen ist der
/// teuerste eigene View der Mac-App. Er ist so hoch wie das ganze Pattern —
/// bei 64 Zeilen à 18 Punkten also 1152 Punkte —, sichtbar ist davon aber immer
/// nur ein Ausschnitt. Eine Messung mit einer Sonde im Zeichenblock zeigte
/// Ausschnitte von rund 519 Punkten Höhe, also 29 der 64 Zeilen. Die
/// übrigen 35 Zeilen wurden vollständig gesetzt und gezeichnet, ohne je
/// sichtbar zu werden.
///
/// Diese Berechnung liegt bewusst hier und nicht in der View: Das Testtarget
/// hängt nur vom Core ab, und eine falsche Zeilengrenze wäre ein sichtbarer
/// Fehler (fehlende Zeilen am Rand des Ausschnitts).
public enum TrackerGridGeometry {

    /// Die Zeilen, die im gegebenen Ausschnitt liegen.
    ///
    /// - Parameters:
    ///   - clipMinY: Obere Kante des Ausschnitts in Punkten, gemessen ab dem
    ///     Anfang der Zeichenfläche.
    ///   - clipMaxY: Untere Kante des Ausschnitts.
    ///   - rowHeight: Höhe einer Zeile in Punkten.
    ///   - rowCount: Anzahl der Zeilen im Pattern.
    /// - Returns: Der zu zeichnende Bereich, immer innerhalb von
    ///   `0..<rowCount`. Ein leerer Bereich heißt: nichts zu tun.
    ///
    /// Eine Zeile zählt als sichtbar, sobald sie den Ausschnitt berührt. Die
    /// obere Grenze wird abgerundet und die untere aufgerundet, damit eine nur
    /// halb hereinragende Zeile nicht wegfällt. Zusätzlich kommt oben und unten
    /// je eine Zeile Reserve dazu — sie kostet fast nichts und fängt
    /// Rundungsunterschiede zwischen Punktraster und Bildpunkten ab.
    public static func visibleRowRange(
        clipMinY: Double,
        clipMaxY: Double,
        rowHeight: Double,
        rowCount: Int
    ) -> Range<Int> {
        guard rowCount > 0 else { return 0..<0 }
        // Eine Zeilenhöhe von null oder darunter ist kein sinnvoller Ausschnitt;
        // dann lieber alles zeichnen als nichts.
        guard rowHeight > 0, clipMaxY > clipMinY else { return 0..<rowCount }
        // Ohne gesetzten Ausschnitt meldet der Zeichenkontext ein unendliches
        // Rechteck. `Int(-.infinity)` bricht das Programm ab, deshalb hier
        // zuerst die Prüfung und dann das volle Pattern.
        guard clipMinY.isFinite, clipMaxY.isFinite else { return 0..<rowCount }

        // Vor der Umwandlung nach Int begrenzen: Ein sehr großer Ausschnitt
        // ergäbe sonst eine Zahl, die in kein Int passt.
        let maxRow = Double(rowCount)
        let firstRow = max(-1.0, min(maxRow, (clipMinY / rowHeight).rounded(.down)))
        let lastRow = max(-1.0, min(maxRow, (clipMaxY / rowHeight).rounded(.up)))
        let first = Int(firstRow) - 1
        let last = Int(lastRow) + 1

        let lower = max(0, min(first, rowCount))
        let upper = max(lower, min(last, rowCount))
        return lower..<upper
    }
}

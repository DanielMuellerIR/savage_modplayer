import XCTest
@testable import SavageModPlayerCore

/// Welche Pattern-Zeilen ein Zeichenvorgang des Tracker-Rasters braucht.
///
/// Hintergrund (Profil vom 2026-08-23): Der Canvas ist so hoch wie das ganze
/// Pattern, CoreAnimation fordert ihn aber kachelweise an. Vorher zeichnete er
/// jedes Mal alle Zeilen. Eine zu enge Grenze wäre ein sichtbarer Fehler —
/// am Rand des Ausschnitts fehlten Zeilen. Deshalb prüfen diese Tests vor allem
/// die Ränder.
final class TrackerGridGeometryTests: XCTestCase {

    private let rowHeight = 18.0
    private let rowCount = 64

    private func range(_ minY: Double, _ maxY: Double) -> Range<Int> {
        TrackerGridGeometry.visibleRowRange(
            clipMinY: minY, clipMaxY: maxY,
            rowHeight: rowHeight, rowCount: rowCount)
    }

    /// Der gemessene Realfall: eine Kachel von 519 Punkten in einem Pattern von
    /// 1152 Punkten. Rund 29 Zeilen statt 64.
    func testMeasuredTileCoversFarFewerRowsThanThePattern() {
        let rows = range(640, 640 + 512)
        XCTAssertEqual(rows.lowerBound, 34)
        XCTAssertEqual(rows.upperBound, 64)
        XCTAssertLessThan(rows.count, rowCount / 2)
    }

    /// Jede Zeile, die den Ausschnitt auch nur berührt, muss dabei sein — sonst
    /// fehlt oben oder unten sichtbar eine.
    func testEveryRowTouchingTheClipIsIncluded() {
        for minY in stride(from: 0.0, through: 1152.0, by: 3.0) {
            let maxY = min(1152.0, minY + 519.0)
            let rows = range(minY, maxY)
            for r in 0..<rowCount {
                let top = Double(r) * rowHeight
                let bottom = top + rowHeight
                let touches = bottom > minY && top < maxY
                if touches {
                    XCTAssertTrue(
                        rows.contains(r),
                        "Zeile \(r) beruehrt den Ausschnitt \(minY)…\(maxY), fehlt aber")
                }
            }
        }
    }

    /// Der Bereich bleibt immer innerhalb des Patterns.
    func testRangeStaysInsideThePattern() {
        for (minY, maxY) in [(-5000.0, 5000.0), (-1.0, 1.0), (1100.0, 9999.0), (0.0, 1152.0)] {
            let rows = range(minY, maxY)
            XCTAssertGreaterThanOrEqual(rows.lowerBound, 0)
            XCTAssertLessThanOrEqual(rows.upperBound, rowCount)
            XCTAssertLessThanOrEqual(rows.lowerBound, rows.upperBound)
        }
    }

    /// Ein unendlicher Ausschnitt heißt „kein Ausschnitt gesetzt" — dann wird
    /// alles gezeichnet. Vor der Absicherung brach `Int(-.infinity)` hier ab.
    func testInfiniteClipDrawsEverythingInsteadOfCrashing() {
        XCTAssertEqual(range(-.infinity, .infinity), 0..<rowCount)
        XCTAssertEqual(range(-.infinity, 100), 0..<rowCount)
        XCTAssertEqual(range(0, .infinity), 0..<rowCount)
        XCTAssertEqual(range(.nan, .nan), 0..<rowCount)
    }

    /// Unsinnige Zeilenhöhen zeichnen lieber alles als nichts.
    func testDegenerateInputFallsBackToTheFullPattern() {
        XCTAssertEqual(
            TrackerGridGeometry.visibleRowRange(
                clipMinY: 0, clipMaxY: 100, rowHeight: 0, rowCount: 64),
            0..<64)
        XCTAssertEqual(
            TrackerGridGeometry.visibleRowRange(
                clipMinY: 100, clipMaxY: 100, rowHeight: 18, rowCount: 64),
            0..<64)
    }

    /// Ein leeres Pattern ergibt einen leeren Bereich, keinen Absturz.
    func testEmptyPatternYieldsAnEmptyRange() {
        XCTAssertTrue(
            TrackerGridGeometry.visibleRowRange(
                clipMinY: 0, clipMaxY: 500, rowHeight: 18, rowCount: 0).isEmpty)
    }

    /// Ein Ausschnitt über dem ganzen Pattern zeichnet auch alles.
    func testFullHeightClipCoversEveryRow() {
        XCTAssertEqual(range(0, Double(rowCount) * rowHeight), 0..<rowCount)
    }
}

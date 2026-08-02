import Foundation
import XCTest
@testable import SavageModPlayerCore

// Der Quick-Look-Cache-Schlüssel hängt seit dem Wechsel auf Inhalts-Identität
// an GENAU den eingelesenen Bytes: Ersetzungen mit gleicher Größe/Zeit oder
// eine Änderung zwischen Lesen und Attributabfrage können keine alten
// Audiodaten mehr unter neuer Identität liefern.
final class PreviewCacheIdentityTests: XCTestCase {
    func testDifferentContentsGetDifferentKeys() {
        let first = PreviewCacheIdentity.key(forContents: Data("module-a".utf8))
        let second = PreviewCacheIdentity.key(forContents: Data("module-b".utf8))
        XCTAssertNotEqual(first, second)
    }

    func testReplacementWithSameLengthGetsNewKey() {
        // Gleiche Länge, ein einziges geändertes Byte — genau der Fall, den
        // Größe+Zeitstempel früher nicht unterscheiden konnten.
        var original = [UInt8](repeating: 0x41, count: 4096)
        var replacement = original
        replacement[2048] = 0x42
        XCTAssertNotEqual(
            PreviewCacheIdentity.key(forContents: Data(original)),
            PreviewCacheIdentity.key(forContents: Data(replacement))
        )
        // Auch reine Umordnung derselben Bytes muss unterscheidbar sein.
        original[0] = 0x43
        var swapped = original
        swapped.swapAt(0, 4095)
        XCTAssertNotEqual(
            PreviewCacheIdentity.key(forContents: Data(original)),
            PreviewCacheIdentity.key(forContents: Data(swapped))
        )
    }

    func testIdenticalContentIsStableAndPathIndependent() {
        // Inhaltsgleiche Dateien teilen sich bewusst denselben Schlüssel —
        // der Pfad gehört nicht mehr zur Identität.
        let bytes = Data("same module bytes".utf8)
        XCTAssertEqual(
            PreviewCacheIdentity.key(forContents: bytes),
            PreviewCacheIdentity.key(forContents: bytes)
        )
    }

    func testEmptyAndPrefixContentsDiffer() {
        let empty = PreviewCacheIdentity.key(forContents: Data())
        let zero = PreviewCacheIdentity.key(forContents: Data([0]))
        let zeroZero = PreviewCacheIdentity.key(forContents: Data([0, 0]))
        XCTAssertNotEqual(empty, zero)
        XCTAssertNotEqual(zero, zeroZero)
    }
}

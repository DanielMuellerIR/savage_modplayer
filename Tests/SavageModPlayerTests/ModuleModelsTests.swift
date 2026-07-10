import XCTest
@testable import SavageModPlayerCore

/// Sichert die reinen Datenmodelle für Tracker-Format und Wiedergaberegeln ab.
/// Parser, Loader und DSP werden in diesem Meilenstein bewusst noch nicht verdrahtet.
final class ModuleModelsTests: XCTestCase {

    func testModuleFormatRawValuesAndDisplayNames() {
        let expected: [(ModuleFormat, String, String)] = [
            (.protracker, "protracker", "ProTracker MOD"),
            (.soundtracker, "soundtracker", "Soundtracker (15 Samples)"),
            (.multichannel, "multichannel", "Multichannel MOD"),
            (.s3m, "s3m", "ScreamTracker 3 (S3M)"),
            (.xm, "xm", "FastTracker II (XM)"),
            (.it, "it", "Impulse Tracker (IT)"),
        ]

        for (format, rawValue, displayName) in expected {
            XCTAssertEqual(format.rawValue, rawValue)
            XCTAssertEqual(format.displayName, displayName)
        }
    }

    func testPlaybackSemanticFamiliesAreDistinct() {
        let semantics: [PlaybackSemantics] = [
            .proTracker,
            .screamTracker3,
            .fastTracker2(linearFrequency: true),
            .impulseTracker(ITCompatibility(oldEffects: false, compatibleGxx: false)),
        ]

        for firstIndex in semantics.indices {
            for secondIndex in semantics.indices where firstIndex != secondIndex {
                XCTAssertNotEqual(semantics[firstIndex], semantics[secondIndex])
            }
        }
    }

    func testFastTracker2FrequencyModesSurviveCodableRoundTrip() throws {
        try assertCodableRoundTrip(.fastTracker2(linearFrequency: false))
        try assertCodableRoundTrip(.fastTracker2(linearFrequency: true))
    }

    func testAllITCompatibilityFlagCombinationsSurviveCodableRoundTrip() throws {
        for oldEffects in [false, true] {
            for compatibleGxx in [false, true] {
                let compatibility = ITCompatibility(
                    oldEffects: oldEffects,
                    compatibleGxx: compatibleGxx
                )
                try assertCodableRoundTrip(.impulseTracker(compatibility))
            }
        }
    }

    func testLoaderExtensionsRemainUnchangedUntilITParserIntegration() {
        XCTAssertEqual(ModuleLoader.supportedExtensions, Set(["mod", "s3m", "xm"]))
        XCTAssertFalse(ModuleLoader.supportedExtensions.contains("it"))
    }

    func testSpecialNoteSentinelsAreDistinctAndOutsideRegularKeys() {
        XCTAssertEqual(Note.keyFade, 252)
        XCTAssertEqual(Note.keyOff, 253)
        XCTAssertEqual(Note.keyCut, 254)

        let sentinels = [Note.keyFade, Note.keyOff, Note.keyCut]

        XCTAssertEqual(Set(sentinels).count, sentinels.count)
        for sentinel in sentinels {
            XCTAssertFalse((0...119).contains(sentinel))
            XCTAssertNotEqual(sentinel, -1)
        }
    }

    func testSpecialNoteMappingIsExact() {
        XCTAssertEqual(makeNote(key: Note.keyOff).specialNote, .off)
        XCTAssertEqual(makeNote(key: Note.keyCut).specialNote, .cut)
        XCTAssertEqual(makeNote(key: Note.keyFade).specialNote, .fade)

        for regularKey in [-1, 0, 95, 119] {
            XCTAssertNil(makeNote(key: regularKey).specialNote)
        }
    }

    func testSpecialNotesSurviveNoteCodableRoundTrip() throws {
        let expected: [(Int, SpecialNote)] = [
            (Note.keyOff, .off),
            (Note.keyCut, .cut),
            (Note.keyFade, .fade),
        ]

        for (key, specialNote) in expected {
            let encoded = try JSONEncoder().encode(makeNote(key: key))
            let decoded = try JSONDecoder().decode(Note.self, from: encoded)
            XCTAssertEqual(decoded.key, key)
            XCTAssertEqual(decoded.specialNote, specialNote)
        }
    }

    /// Erstellt eine ansonsten leere Note, damit der jeweilige Schlüssel isoliert
    /// geprüft wird und keine Effekt- oder Instrumentdaten das Ergebnis beeinflussen.
    private func makeNote(key: Int) -> Note {
        Note(instrument: 0, period: 0, effectId: 0, effectData: 0, key: key)
    }

    /// Kodiert und dekodiert einen Wert wie bei einer späteren Speicherung.
    private func assertCodableRoundTrip(
        _ original: PlaybackSemantics,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlaybackSemantics.self, from: encoded)
        XCTAssertEqual(decoded, original, file: file, line: line)
    }
}

import XCTest
@testable import SavageModPlayerCore

final class CollectionExchangePreferencesTests: XCTestCase {
    func testMalformedSoundPreferencesFailInsteadOfBecomingDefaults() async throws {
        try await MainActor.run {
            let defaults = try CollectionExchangeSoundPreferences.validatedOptions(in: [:], prefix: "test.")
            XCTAssertEqual(defaults, PlaybackOptions())
            XCTAssertFalse(try CollectionExchangeSoundPreferences.validatedOptions(in: ["test.palClock": 0], prefix: "test.").palClock)
            for key in ["palClock", "interpolation", "ledFilter"] {
                for value: Any in ["false", 2, -1, Double.nan, [true]] {
                    XCTAssertThrowsError(try CollectionExchangeSoundPreferences.validatedOptions(in: ["test." + key: value], prefix: "test."))
                }
            }
            for value: Any in ["0.8", true, Double.nan, Double.infinity, -0.01, 1.01] {
                XCTAssertThrowsError(try CollectionExchangeSoundPreferences.validatedOptions(in: ["test.stereoSeparation": value], prefix: "test."))
            }
            XCTAssertEqual(try CollectionExchangeSoundPreferences.validatedOptions(in: ["test.stereoSeparation": 0.0], prefix: "test.").stereoSeparation, 0)
            XCTAssertEqual(try CollectionExchangeSoundPreferences.validatedOptions(in: ["test.stereoSeparation": 1.0], prefix: "test.").stereoSeparation, 1)
        }
    }
    func testNonFiniteOriginalPreferenceCanBeRestoredWithoutCreatingARecoveryConflict() async throws {
        try await MainActor.run {
            let domain = "CollectionPreferences-\(UUID())", defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain); defaults.synchronize() }
            defaults.set(Double.nan, forKey: "separation")
            let store = CollectionExchangePreferences(defaults: defaults, domain: domain, keys: ["separation"])
            let before = try store.capture(), after = try store.assigning(["separation": 0.8], to: before)
            try store.replace(expected: before, replacement: after)
            try store.replace(expected: after, replacement: before)
            XCTAssertTrue(defaults.double(forKey: "separation").isNaN)
        }
    }
    func testAbsentKeysAndOriginalPropertyListTypesSurviveRollback() async throws {
        try await MainActor.run {
            let domain = "CollectionPreferences-\(UUID())"
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain); defaults.synchronize() }
            defaults.register(defaults: ["clock": true, "separation": 0.8])
            defaults.set(["ä/song.mod"], forKey: "favorites")
            defaults.set("preserve", forKey: "unrelated")
            let store = CollectionExchangePreferences(defaults: defaults, domain: domain, keys: ["clock", "separation", "favorites"])
            let before = try store.capture()
            let after = try store.assigning(["clock": false, "separation": 0.25, "favorites": ["new.it"]], to: before)
            try store.replace(expected: before, replacement: after)
            XCTAssertFalse(defaults.bool(forKey: "clock")); XCTAssertEqual(defaults.double(forKey: "separation"), 0.25)
            try store.replace(expected: after, replacement: before)
            let raw = defaults.persistentDomain(forName: domain)!
            XCTAssertNil(raw["clock"]); XCTAssertNil(raw["separation"])
            XCTAssertEqual(raw["favorites"] as? [String], ["ä/song.mod"])
            XCTAssertEqual(raw["unrelated"] as? String, "preserve")
            try store.replace(expected: after, replacement: before)
            XCTAssertTrue(defaults.bool(forKey: "clock"))
        }
    }

    func testInterveningPreferencesAndUnknownKeysArePreserved() async throws {
        try await MainActor.run {
            let domain = "CollectionPreferences-\(UUID())"; let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain); defaults.synchronize() }
            let store = CollectionExchangePreferences(defaults: defaults, domain: domain, keys: ["clock"])
            let before = try store.capture(), after = try store.assigning(["clock": false], to: before)
            defaults.set("foreign", forKey: "clock")
            XCTAssertThrowsError(try store.replace(expected: before, replacement: after))
            XCTAssertEqual(defaults.string(forKey: "clock"), "foreign")
            XCTAssertThrowsError(try store.assigning(["unrelated": true], to: before))
        }
    }

    func testStableSourceIDsReconstructMissingUnicodeAndArchiveSourcesWithoutResolvingLinks() throws {
        let source = PlaylistTrackSource(location: URL(fileURLWithPath: "/synthetic/missing/ä.zip"))
            .appendingArchiveMember("packs/inside.zip").appendingArchiveMember("same/é.mod")
        XCTAssertEqual(PlaylistTrackSource(stableID: source.id)?.id, source.id)
        XCTAssertEqual(PlaylistTrackSource(stableID: source.id)?.archiveMembers, source.archiveMembers)
        let library = PlaylistTrackSource(libraryRelativePath: "songs/🎵/é.mod")!
        XCTAssertEqual(PlaylistTrackSource(stableID: library.id)?.libraryRelativePath, library.libraryRelativePath)
        for bad in ["", "source-v1:4:file", "source-v1:999999999999:a", "source-v1:-1:a", "library-v1:3:../",
                    "source-v1:16:https://test.mod", "library-v1:1:ä", "library-v1:1:aextra", "source-v1:0:"] {
            XCTAssertNil(PlaylistTrackSource(stableID: bad), bad)
        }
    }
}

import XCTest
@testable import SavageModPlayerCore

@MainActor
final class SongMarkerPrecisionTests: XCTestCase {
    func testPrecisionAtPositiveAndNegativeSecondBoundariesAcrossISOAndNumericEncoders() async throws {
        let bases: [Double] = [-2_147_483_647, -1, 0, 719_000_000, 812_345_678, 2_147_483_647]
        let fractions: [Double] = [0, Double.ulpOfOne, 0.0000001, 0.125, 0.5, 0.9999998, 0.9999999]
        for base in bases {
            for fraction in fractions {
                let date = Date(timeIntervalSinceReferenceDate: base + fraction)
                let marker = SongMarker(sourceID: "synthetic", name: "Boundary", address: .init(position: 0, row: 0), createdAt: date)
                var document = SongMarkerDocument(); document.markers = [marker]
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let iso = try decoder.decode(SongMarkerDocument.self, from: SongMarkerStore.encodedData(document))
                XCTAssertEqual(iso.markers.first?.createdAt.timeIntervalSinceReferenceDate, date.timeIntervalSinceReferenceDate)
                let numeric = try JSONDecoder().decode(SongMarker.self, from: JSONEncoder().encode(marker))
                XCTAssertEqual(numeric.createdAt.timeIntervalSinceReferenceDate, date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private struct LegacyDocument: Decodable {
        struct Marker: Decodable { let id: UUID; let sourceID: String; let name: String; let address: SongAddress; let createdAt: Date }
        let formatVersion: Int
        let markers: [Marker]
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MarkerPrecision-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testStoreAndImportJournalRetainExactSubsecondCreationTime() async throws {
        let root = try directory(), file = root.appendingPathComponent("markers.json")
        let marker = SongMarker(sourceID: "synthetic", name: "Position", address: .init(position: 1, row: 16),
                                createdAt: Date(timeIntervalSinceReferenceDate: 812_345_678.1234567))
        let store = SongMarkerStore(fileURL: file)
        _ = try await store.update { $0.markers = [marker] }
        let reopened = try await SongMarkerStore(fileURL: file).snapshot()
        XCTAssertEqual(reopened.document.markers.first?.createdAt, marker.createdAt)
        let persistence = try CollectionExchangePersistence(playlistsURL: root.appendingPathComponent("playlists.json"),
                                                            markersURL: file, trackSettingsURL: root.appendingPathComponent("settings.json"),
                                                            journalURL: root.appendingPathComponent("journal", isDirectory: true))
        var document = SongMarkerDocument(); document.markers = [marker]
        _ = try persistence.commit(.init(playlists: .init(), markers: document, trackSettings: .init()),
                                   replacing: persistence.snapshot(), auxiliaryBefore: Data(), auxiliaryAfter: Data()) { _, _ in }
        XCTAssertEqual(try persistence.snapshot().documents.markers.markers.first?.createdAt, marker.createdAt)
    }

    func testOlderFilesAndReadersRemainCompatibleWithTheOptionalPrecision() async throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 1_700_000_000.125)
        let marker = SongMarker(id: id, sourceID: "synthetic", name: "Position", address: .init(position: 0, row: 0), createdAt: date)
        var document = SongMarkerDocument(); document.markers = [marker]
        let data = try SongMarkerStore.encodedData(document)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let oldReader = try decoder.decode(LegacyDocument.self, from: data)
        XCTAssertEqual(oldReader.formatVersion, 1)
        XCTAssertEqual(oldReader.markers.first?.id, id)
        XCTAssertEqual(oldReader.markers.first?.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
        let legacy = Data("{\"formatVersion\":1,\"markers\":[{\"id\":\"\(id)\",\"sourceID\":\"synthetic\",\"name\":\"Position\",\"address\":{\"position\":0,\"row\":0},\"createdAt\":\"2023-11-14T22:13:20Z\"}]}".utf8)
        let newReader = try decoder.decode(SongMarkerDocument.self, from: legacy)
        XCTAssertEqual(newReader.markers.first?.createdAt, oldReader.markers.first?.createdAt)
        XCTAssertFalse(String(decoding: try SongMarkerStore.encodedData(newReader), as: UTF8.self).contains("createdAtReferenceSeconds"))
    }

    func testContradictoryPrecisionRemainsReadOnlyAndDefaultEncoderKeepsNegativeDates() async throws {
        let root = try directory(), file = root.appendingPathComponent("invalid.json")
        let marker = SongMarker(sourceID: "synthetic", name: "Position", address: .init(position: 0, row: 0), createdAt: Date(timeIntervalSinceReferenceDate: -0.375))
        let data = try JSONEncoder().encode(marker)
        XCTAssertEqual(try JSONDecoder().decode(SongMarker.self, from: data), marker)
        var document = SongMarkerDocument(); document.markers = [marker]
        let encoded = try SongMarkerStore.encodedData(document)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var markers = try XCTUnwrap(object["markers"] as? [[String: Any]])
        markers[0]["createdAtReferenceSeconds"] = 2.0
        object["markers"] = markers
        let invalid = try JSONSerialization.data(withJSONObject: object)
        try invalid.write(to: file)
        let store = SongMarkerStore(fileURL: file)
        do { _ = try await store.snapshot(); XCTFail("Contradictory date accepted") } catch { }
        do { _ = try await store.update { $0.markers = [] }; XCTFail("Corrupt file replaced") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), invalid)
    }

    func testRepeatingTheManualFileImportPreservesThePreciseLocalTimestamp() async throws {
        let reference = PlaylistTrackReference(source: .init(location: URL(fileURLWithPath: "/synthetic/song.mod")), displayName: "song.mod")
        let marker = SongMarker(sourceID: reference.id, name: "Position", address: .init(position: 0, row: 0),
                                createdAt: Date(timeIntervalSinceReferenceDate: 812_345_678.1234567))
        var local = CollectionExchangeSnapshot(); local.markers.markers = [marker]
        let sources = [CollectionExchangeLocalTrack(reference: reference, descriptor: .init(fileName: "song.mod"))]
        let exported = try CollectionExchangeExporter.makeDocument(from: local, sources: sources)
        let received = try CollectionExchangeCodec.decode(CollectionExchangeCodec.encode(exported))
        XCTAssertNotEqual(received.markers.first?.createdAt, marker.createdAt)
        let mapping = [try XCTUnwrap(received.tracks.first).id: reference]
        let preview = try CollectionExchangeImporter.preview(received, into: local, mapping: mapping)
        XCTAssertTrue(preview.conflicts.isEmpty)
        XCTAssertEqual(try preview.result(ifUnchanged: local).markers.markers.first?.createdAt, marker.createdAt)
    }
}

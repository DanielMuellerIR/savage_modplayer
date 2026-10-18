import XCTest
import SwiftUI
@testable import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class CollectionSyncServiceAcceptanceTests: XCTestCase {
    private struct Configuration: Decodable {
        let runID: UUID
        let phase: String
        let expectedAccountScope: String
        let environment: String?
        let collectionID: UUID?
        let generation: UUID?
        let playlistID: UUID?
        let expectedChangeTag: String?
    }

    // Ein normaler Testlauf darf weder das iCloud-Konto abfragen noch Testdaten
    // senden. Der freigegebene Gerätelauf übergibt seinen eigenen Prüfauftrag.
    func testExplicitCloudKitAccountAndAppRoundTrip() async throws {
        guard let request = ProcessInfo.processInfo.environment["SAVAGE_CLOUDKIT_ACCEPTANCE"] else {
            throw XCTSkip("Separat freigegebene CloudKit-Geräteabnahme erforderlich.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Die Dienstabnahme benötigt ein echtes iPhone.")
        #else
        let config = try JSONDecoder().decode(Configuration.self, from: Data(request.utf8))
        let environment = config.environment ?? "Development"
        guard ["account", "adopt-and-edit", "concurrent-conflict", "verify-concurrent"].contains(config.phase),
              ["Development", "Production"].contains(environment),
              config.expectedAccountScope.count == 64,
              Bundle.main.object(forInfoDictionaryKey: "CollectionSyncContainerEnvironment") as? String == environment,
              Bundle.main.object(forInfoDictionaryKey: "CollectionSyncContainerIdentifier") as? String == "iCloud.com.viben.SavageModPlayer" else {
            throw CollectionSyncError.invalidCheckpoint
        }
        let service = try XCTUnwrap(CollectionSyncConfiguration.service())
        let scope = try await service.backend.currentAccountScope()
        guard scope == config.expectedAccountScope else {
            XCTFail("Mac und iPhone verwenden verschiedene iCloud-Konten.")
            return
        }
        let evidence = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudKitAcceptance/\(config.runID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        if config.phase == "account" {
            try receipt(["accountMatches": true, "databaseReadOrWrite": false], at: evidence.appendingPathComponent("account.json"))
            return
        }
        let collection = try XCTUnwrap(config.collectionID), generation = try XCTUnwrap(config.generation)
        let playlist = try XCTUnwrap(config.playlistID), expectedTag = try XCTUnwrap(config.expectedChangeTag)
        let initialAsset = try await service.backend.fetch()
        let initial = try CollectionSyncCodec.decode(XCTUnwrap(initialAsset).data)
        let initialDocument = try initial.exchangeDocument()
        let concurrent = config.phase == "concurrent-conflict"
        let verification = config.phase == "verify-concurrent"
        guard initial.collectionID == collection, initial.generation == generation,
              initialAsset?.changeTag == expectedTag,
              initialDocument.playlists.count == 1,
              initialDocument.playlists[0].id == playlist,
              initialDocument.playlists[0].name == (verification ? "Synthetic CloudKit iPhone conflict" :
                (concurrent ? "Synthetic CloudKit iPhone edit" : "Synthetic CloudKit Mac seed")),
              verification ? (initialDocument.favoriteTrackIDs.count == 1 && initialDocument.markers.isEmpty) :
                concurrent ? (initialDocument.favoriteTrackIDs.count == 1 && initialDocument.markers.count == 1) :
                (initialDocument.favoriteTrackIDs.isEmpty && initialDocument.markers.isEmpty && initialDocument.trackSettings.isEmpty) else {
            throw CollectionSyncError.stalePreview
        }
        let fixture = try await CollectionSyncAppFixture(service: service, emptyCollection: true)
        var phase = "setup"
        do {
            await fixture.sync.beginSetup()
            if let error = fixture.sync.error { throw error }
            phase = "mapping"
            await fixture.sync.assignUniqueSuggestions()
            guard fixture.sync.tracks.count == 2, fixture.sync.mapping.count == 2 else {
                throw CollectionSyncError.incompleteSnapshot
            }
            for conflict in fixture.sync.conflicts { fixture.sync.resolve(conflict.id, with: .useRemote) }
            guard fixture.sync.canConfirm else { throw CollectionSyncError.invalidCheckpoint }
            phase = "confirm"
            await fixture.sync.confirm()
            try await self.settled(fixture.sync)
            XCTAssertTrue(fixture.model.playlists.document.playlists.contains(where: { $0.id == playlist }))
            phase = "adopted-view"
            try await capture(fixture, to: evidence.appendingPathComponent("adopted.png"))

            if verification {
                let stored = try fixture.state().observed.exchangeDocument()
                XCTAssertEqual(stored.playlists.first?.id, playlist)
                XCTAssertEqual(stored.playlists.first?.name, "Synthetic CloudKit iPhone conflict")
                XCTAssertTrue(stored.markers.isEmpty)
                XCTAssertEqual(stored.favoriteTrackIDs, initialDocument.favoriteTrackIDs)
                XCTAssertEqual(stored.trackSettings, initialDocument.trackSettings)
                let after = try await service.backend.fetch()
                guard after?.changeTag == expectedTag else { throw CollectionSyncError.stalePreview }
                try receipt(["accountMatches": true, "collectionID": collection.uuidString,
                             "generation": generation.uuidString, "playlistID": playlist.uuidString,
                             "changeTag": expectedTag, "markerDeletionAdopted": true],
                            at: evidence.appendingPathComponent("verify-concurrent.json"))
                try await fixture.close()
                return
            }

            if concurrent {
                phase = "concurrent-conflict"
                try await concurrentConflict(fixture, service: service, config: config, evidence: evidence)
                try await fixture.close()
                return
            }

            phase = "local-edits"
            fixture.model.playlists.rename(id: playlist, name: "Synthetic CloudKit iPhone edit")
            fixture.model.library.toggleFavorite("A/" + fixture.longName)
            XCTAssertTrue(fixture.model.player.playbackSettings.updateTitle("A/" + fixture.longName) { $0.ledFilterActive = true })
            let track = try XCTUnwrap(fixture.model.library.tracks.first)
            let module = try ModuleLoader.parse(data: Data(contentsOf: track.url))
            fixture.model.markers.setContext(sourceID: track.relativePath, module: module, moduleID: UUID())
            let markerSaved = await fixture.model.markers.save(name: "Synthetic CloudKit iPhone marker", address: .init(position: 0, row: 8))
            XCTAssertTrue(markerSaved)
            phase = "publish"
            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline {
                if !fixture.sync.isBusy {
                    let observed = try fixture.state().observed.exchangeDocument()
                    if fixture.sync.status == .current,
                       observed.playlists.contains(where: { $0.id == playlist && $0.name == "Synthetic CloudKit iPhone edit" }),
                       observed.markers.contains(where: { $0.name == "Synthetic CloudKit iPhone marker" }),
                       observed.trackSettings.contains(where: { $0.overrides.ledFilterActive == true }) { break }
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            if let error = fixture.sync.error { throw error }
            guard !fixture.sync.isBusy, fixture.sync.status == .current else { throw CollectionSyncError.invalidCheckpoint }
            let publishedAsset = try await service.backend.fetch()
            let published = try CollectionSyncCodec.decode(XCTUnwrap(publishedAsset).data)
            guard published.collectionID == collection, published.generation == generation else { throw CollectionSyncError.mismatchedCollection }
            let document = try published.exchangeDocument()
            XCTAssertTrue(document.playlists.contains(where: { $0.id == playlist && $0.name == "Synthetic CloudKit iPhone edit" }))
            XCTAssertTrue(document.markers.contains(where: { $0.name == "Synthetic CloudKit iPhone marker" }))
            XCTAssertTrue(document.trackSettings.contains(where: { $0.overrides.ledFilterActive == true }))
            XCTAssertEqual(fixture.defaults.double(forKey: "savage.ios.volume"), 0.37)
            XCTAssertFalse(fixture.model.player.coordinator.isPlaying)
            XCTAssertNotEqual(initialAsset?.changeTag, publishedAsset?.changeTag)
            try await capture(fixture, to: evidence.appendingPathComponent("published.png"))
            try receipt(["accountMatches": true, "collectionID": collection.uuidString,
                         "generation": generation.uuidString, "playlistID": playlist.uuidString,
                         "playlists": document.playlists.map(\.name), "markers": document.markers.map(\.name),
                         "favorites": document.favoriteTrackIDs.count, "changeTag": publishedAsset!.changeTag,
                         "localVolumePreserved": true], at: evidence.appendingPathComponent("adopt-and-edit.json"))
        } catch {
            try receipt(["phase": phase, "error": String(describing: error),
                         "syncStatus": String(describing: fixture.sync.status),
                         "syncBusy": fixture.sync.isBusy, "libraryBusy": fixture.model.library.isBusy,
                         "markerSaving": fixture.model.markers.isSaving], at: evidence.appendingPathComponent("failure.json"))
            try await fixture.close(); throw error
        }
        try await fixture.close()
        #endif
    }

    private func concurrentConflict(_ fixture: CollectionSyncAppFixture, service: CollectionSyncService,
                                    config: Configuration, evidence: URL) async throws {
        let playlist = try XCTUnwrap(config.playlistID), originalTag = try XCTUnwrap(config.expectedChangeTag)
        let before = try fixture.state().observed.exchangeDocument()
        let marker = try XCTUnwrap(before.markers.first)
        fixture.sync.deactivate()
        fixture.model.playlists.rename(id: playlist, name: "Synthetic CloudKit iPhone conflict")
        let track = try XCTUnwrap(fixture.model.library.tracks.first { $0.relativePath.hasPrefix("A/") })
        let module = try ModuleLoader.parse(data: Data(contentsOf: track.url))
        fixture.model.markers.setContext(sourceID: track.relativePath, module: module, moduleID: UUID())
        await fixture.model.markers.delete(id: marker.id)
        XCTAssertTrue(fixture.model.markers.markers.isEmpty)
        try await Task.sleep(for: .seconds(1))
        let pausedAsset = try await service.backend.fetch()
        guard pausedAsset?.changeTag == originalTag else { throw CollectionSyncError.stalePreview }
        try receipt(["accountMatches": true, "changeTag": originalTag, "pausedWritesBlocked": true,
                     "playlistID": playlist.uuidString, "markerID": marker.id.uuidString],
                    at: evidence.appendingPathComponent("waiting-for-mac.json"))

        // Der zweite echte Client darf erst ändern, nachdem das iPhone seinen
        // lokalen Stand gespeichert und den unveränderten Server bestätigt hat.
        let signal = evidence.appendingPathComponent("mac-conflict-ready.json")
        let deadline = Date().addingTimeInterval(180)
        while !FileManager.default.fileExists(atPath: signal.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let ready = try JSONSerialization.jsonObject(with: Data(contentsOf: signal)) as? [String: String]
        let macTag = try XCTUnwrap(ready?["changeTag"])
        guard ready?["runID"] == config.runID.uuidString, macTag != originalTag else {
            throw CollectionSyncError.stalePreview
        }
        fixture.sync.activate()
        let reviewDeadline = Date().addingTimeInterval(120)
        while (fixture.sync.isBusy || fixture.sync.status != .review), Date() < reviewDeadline {
            if let error = fixture.sync.error { throw error }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !fixture.sync.isBusy, fixture.sync.status == .review,
              fixture.sync.conflicts.contains(where: { $0.id == .playlist(playlist) }),
              !fixture.sync.canConfirm else { throw CollectionSyncError.unresolvedConflicts }
        let pendingAsset = try await service.backend.fetch()
        XCTAssertEqual(pendingAsset?.changeTag, macTag)
        try await capture(fixture, to: evidence.appendingPathComponent("concurrent-conflict.png"), expectedStatus: .review) {
            for conflict in fixture.sync.conflicts { fixture.sync.resolve(conflict.id, with: .keepLocal) }
            guard fixture.sync.canConfirm else { throw CollectionSyncError.unresolvedConflicts }
            await fixture.sync.confirm()
            try await self.settled(fixture.sync)
        }
        let finalAsset = try await service.backend.fetch()
        let publishedAsset = try XCTUnwrap(finalAsset)
        let published = try CollectionSyncCodec.decode(publishedAsset.data)
        let document = try published.exchangeDocument()
        XCTAssertEqual(published.collectionID, config.collectionID)
        XCTAssertEqual(published.generation, config.generation)
        XCTAssertEqual(document.playlists.first?.id, playlist)
        XCTAssertEqual(document.playlists.first?.name, "Synthetic CloudKit iPhone conflict")
        XCTAssertTrue(document.markers.isEmpty)
        XCTAssertTrue(published.cells.contains { $0.id == .marker(marker.id) && $0.value == .deleted })
        XCTAssertEqual(document.favoriteTrackIDs, before.favoriteTrackIDs)
        XCTAssertEqual(document.trackSettings, before.trackSettings)
        XCTAssertNotEqual(publishedAsset.changeTag, macTag)
        XCTAssertEqual(fixture.defaults.double(forKey: "savage.ios.volume"), 0.37)
        XCTAssertFalse(fixture.model.player.coordinator.isPlaying)
        try await capture(fixture, to: evidence.appendingPathComponent("concurrent-resolved.png"))
        try receipt(["accountMatches": true, "collectionID": published.collectionID.uuidString,
                     "generation": published.generation.uuidString, "playlistID": playlist.uuidString,
                     "markerID": marker.id.uuidString, "changeTag": publishedAsset.changeTag,
                     "pausedWritesBlocked": true, "conflictRequiredDecision": true,
                     "markerTombstonePublished": true, "localVolumePreserved": true],
                    at: evidence.appendingPathComponent("concurrent-conflict.json"))
    }

    private func receipt(_ values: [String: Any], at url: URL) throws {
        try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]).write(to: url, options: .atomic)
    }

    private func settled(_ model: CollectionSyncModel) async throws {
        // Das Übernehmen löst die regulären App-Abonnements aus. Auch deren
        // nachfolgender Abgleich muss vor der nächsten Teständerung enden.
        let deadline = Date().addingTimeInterval(120)
        while (model.isBusy || model.status != .current), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if let error = model.error { throw error }
        guard !model.isBusy, model.status == .current else { throw CollectionSyncError.invalidCheckpoint }
    }

    private func capture(_ fixture: CollectionSyncAppFixture, to url: URL,
                         expectedStatus: CollectionSyncModel.Status = .current,
                         afterCapture: (() async throws -> Void)? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let view = Color.clear.sheet(isPresented: .constant(true)) { CollectionSyncView(model: fixture.sync) }
        let host = UIHostingController(rootView: view), window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds; window.rootViewController = host; window.makeKeyAndVisible()
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(500))
        // Die Ansicht startet selbst einen Abgleich. Dessen Dateizugriffe müssen
        // vor dem Schließen beendet sein, bevor der Test Metadaten verändert.
        let deadline = Date().addingTimeInterval(120)
        while fixture.sync.isBusy, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if let error = fixture.sync.error { throw error }
        guard !fixture.sync.isBusy, fixture.sync.status == expectedStatus else { throw CollectionSyncError.invalidCheckpoint }
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let picture = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try XCTUnwrap(picture.pngData()).write(to: url, options: .atomic)
        try await afterCapture?()
        await withCheckedContinuation { continuation in
            host.dismiss(animated: false) { continuation.resume() }
        }
    }
}

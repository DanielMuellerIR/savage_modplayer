import XCTest
@testable import SavageModPlayerCore

final class CollectionSyncApplicationStateTests: XCTestCase {
    private struct Fixture {
        let account = CollectionSyncAccountToken(scope: String(repeating: "a", count: 64), epoch: UUID())
        let collection = UUID(), generation = UUID(), a = UUID(), b = UUID(), list = UUID(), marker = UUID()
        let first = PlaylistTrackReference(source: PlaylistTrackSource(libraryRelativePath: "A/song.mod")!, displayName: "song.mod")
        let second = PlaylistTrackReference(source: PlaylistTrackSource(libraryRelativePath: "B/song.mod")!, displayName: "song.mod")
        var metadata: CollectionExchangeSnapshot {
            var result = CollectionExchangeSnapshot(playbackDefaults: .init())
            result.playlists.playlists = [.init(id: list, name: "Original", tracks: [first, second])]
            result.playlists.favoriteIDs = [first.id]
            result.markers.markers = [.init(id: marker, sourceID: second.id, name: "Position",
                address: .init(position: 2, row: 7), createdAt: Date(timeIntervalSinceReferenceDate: 812_345_678.1234567))]
            result.trackSettings.tracks[first.id] = .init(palClock: false, stereoSeparation: 0.3)
            return result
        }
        var sources: [CollectionExchangeLocalTrack] {
            [first, second].map { .init(reference: $0, descriptor: .init(fileName: "song.mod", relativePath: $0.source.libraryRelativePath, byteCount: 2112)) }
        }
        var registry: CollectionSyncTrackRegistry {
            .init(account: account, collectionID: collection, generation: generation,
                  bindings: [.init(id: a, reference: first), .init(id: b, reference: second)])
        }
        func state() throws -> CollectionSyncApplicationState {
            let exported = try registry.export(from: metadata, sources: sources, account: account)
            let observed = try CollectionSyncSnapshot(document: exported.document, collectionID: collection, generation: generation)
            return .init(localState: .init(checkpoint: .init(account: account, base: observed, local: observed,
                                                           serverChangeTag: "before"), registry: exported.registry),
                         observed: observed, hasStoredPreferences: true)
        }
        func remoteChoices(_ original: CollectionSyncSnapshot) -> CollectionSyncSnapshot {
            var result = original
            result.cells.removeAll { [.playlist(list), .favorite(a), .defaultSetting(.ledFilterActive)].contains($0.id) }
            result.cells += [.init(.playlist(list), .playlist(.init(id: list, name: "Remote choice", trackIDs: [b, a]))),
                             .init(.favorite(a), .deleted), .init(.defaultSetting(.ledFilterActive), .flag(true))]
            return result
        }
        func project(_ snapshot: CollectionSyncSnapshot, into metadata: CollectionExchangeSnapshot) throws -> CollectionExchangeSnapshot {
            let mapping = try registry.mapping(for: snapshot, available: [first, second], account: account)
            return try CollectionSyncProjection(snapshot: snapshot, into: metadata, mapping: mapping,
                collectionID: collection, generation: generation).result(ifUnchanged: metadata, mapping: mapping)
        }
    }

    func testSavedLocalDeletesBecomeTombstonesAndRemovedOverridesBecomeInheritance() throws {
        let f = Fixture(), state = try f.state()
        var metadata = f.metadata
        metadata.playlists.playlists.removeAll(); metadata.playlists.favoriteIDs.removeAll()
        metadata.markers.markers.removeAll(); metadata.trackSettings.tracks.removeAll()
        let changed = try state.capturing(metadata, sources: f.sources, metadataFilesExist: true)
        let values = changed.localState.checkpoint.local.indexed()
        XCTAssertEqual(values[.playlist(f.list)], .deleted)
        XCTAssertEqual(values[.marker(f.marker)], .deleted)
        XCTAssertEqual(values[.favorite(f.a)], .deleted)
        for field in CollectionSyncField.allCases { XCTAssertEqual(values[.trackSetting(f.a, field)], .inherit) }
        XCTAssertEqual(values[.track(f.a)], state.localState.checkpoint.local.indexed()[.track(f.a)])
        XCTAssertTrue(try changed.hasPendingChanges())
    }

    func testUnavailableMusicAndDeviceSpecificHintsDoNotChangeGlobalIdentityOrDeleteMetadata() throws {
        let f = Fixture(), state = try f.state()
        let unavailable = f.sources.map { source in
            CollectionExchangeLocalTrack(reference: source.reference,
                descriptor: .init(fileName: "song.mod", relativePath: "different-root/song.mod", byteCount: nil))
        }
        let captured = try state.capturing(f.metadata, sources: unavailable, metadataFilesExist: true)
        XCTAssertEqual(captured.localState, state.localState)
        XCTAssertFalse(try captured.hasPendingChanges())
    }

    func testMissingMetadataFilesOrPreviouslyStoredPreferencesNeverBecomeDeletions() throws {
        let f = Fixture(), state = try f.state()
        XCTAssertThrowsError(try state.capturing(.init(), sources: [], metadataFilesExist: false))
        XCTAssertThrowsError(try state.capturing(f.metadata, sources: f.sources, metadataFilesExist: true,
                                                preferencesAvailable: false))
        XCTAssertFalse(try state.hasPendingChanges())
    }

    func testRestartBeforeProjectionDoesNotUndoAlreadyConfirmedRemoteChoices() throws {
        let f = Fixture(), initial = try f.state(), desired = f.remoteChoices(initial.observed)
        let prepared = try initial.preparing(desired, registry: f.registry, ifUnchanged: initial)
        let restarted = try CollectionSyncApplicationCodec.decode(CollectionSyncApplicationCodec.encode(prepared))
        let recaptured = try restarted.capturing(f.metadata, sources: f.sources, metadataFilesExist: true)
        XCTAssertEqual(recaptured.localState.checkpoint.local.indexed(), desired.indexed())
        XCTAssertEqual(recaptured.observed.indexed(), initial.observed.indexed())
        XCTAssertTrue(try recaptured.hasPendingChanges())
    }

    func testNewLocalEditDuringPublicationKeepsRemoteChoicesAndCannotAcknowledgeOldUpload() throws {
        let f = Fixture(), initial = try f.state(), desired = f.remoteChoices(initial.observed)
        let prepared = try initial.preparing(desired, registry: f.registry, ifUnchanged: initial)
        var later = f.metadata; later.trackSettings.tracks[f.first.id]?.useInterpolation = false
        let changed = try prepared.capturing(later, sources: f.sources, metadataFilesExist: true)
        XCTAssertEqual(changed.localState.checkpoint.local.indexed()[.playlist(f.list)], desired.indexed()[.playlist(f.list)])
        XCTAssertEqual(changed.localState.checkpoint.local.indexed()[.favorite(f.a)], .deleted)
        XCTAssertEqual(changed.localState.checkpoint.local.indexed()[.trackSetting(f.a, .useInterpolation)], .flag(false))
        let oldReceipt = CollectionSyncServerVersion(snapshot: desired, changeTag: "published", account: f.account)
        XCTAssertThrowsError(try changed.confirming(oldReceipt, projected: later, sources: f.sources)) {
            XCTAssertEqual($0 as? CollectionSyncError, .stalePreview)
        }
        XCTAssertTrue(try changed.hasPendingChanges())
    }

    func testPublishedButUnappliedRestartConvergesThenAcknowledgesTheActualProjection() throws {
        let f = Fixture(), initial = try f.state(), desired = f.remoteChoices(initial.observed)
        let prepared = try initial.preparing(desired, registry: f.registry, ifUnchanged: initial)
        let restarted = try CollectionSyncApplicationCodec.decode(CollectionSyncApplicationCodec.encode(prepared))
        let plan = try CollectionSyncMergePlan(base: restarted.localState.checkpoint.base,
            local: restarted.localState.checkpoint.local, remote: desired)
        XCTAssertTrue(plan.conflicts.isEmpty)
        let merged = try plan.result(ifUnchanged: restarted.localState.checkpoint.local)
        let projected = try f.project(merged, into: f.metadata)
        XCTAssertEqual(projected.playlists.playlists.first?.name, "Remote choice")
        XCTAssertTrue(projected.playlists.favoriteIDs.isEmpty)
        let confirmed = try restarted.confirming(.init(snapshot: merged, changeTag: "published", account: f.account),
                                                  projected: projected, sources: f.sources)
        XCTAssertFalse(try confirmed.hasPendingChanges())
        XCTAssertFalse(confirmed.needsProjection)
        XCTAssertEqual(confirmed.localState.checkpoint.serverChangeTag, "published")
        XCTAssertEqual(confirmed.localState.checkpoint.base.indexed(), merged.indexed())
        XCTAssertEqual(try confirmed.capturing(projected, sources: f.sources, metadataFilesExist: true).localState,
                       confirmed.localState)
    }

    func testKeepBothCopyIdentitySurvivesAnUnappliedRestartWithoutCreatingAnotherCopy() throws {
        let f = Fixture(), initial = try f.state(), copyID = UUID()
        var desired = initial.observed
        desired.cells.append(.init(.playlist(copyID), .playlist(.init(id: copyID, name: "Both", trackIDs: [f.b, f.a]))))
        let prepared = try initial.preparing(desired, registry: f.registry, ifUnchanged: initial)
        let restarted = try CollectionSyncApplicationCodec.decode(CollectionSyncApplicationCodec.encode(prepared))
        let recaptured = try restarted.capturing(f.metadata, sources: f.sources, metadataFilesExist: true)
        XCTAssertEqual(try recaptured.localState.checkpoint.local.exchangeDocument().playlists.count, 2)
        let projected = try f.project(desired, into: f.metadata)
        let confirmed = try recaptured.confirming(.init(snapshot: desired, changeTag: "published", account: f.account),
                                                   projected: projected, sources: f.sources)
        let repeated = try confirmed.capturing(projected, sources: f.sources, metadataFilesExist: true)
        XCTAssertEqual(Set(try repeated.localState.checkpoint.local.exchangeDocument().playlists.map(\.id)), [f.list, copyID])
        XCTAssertFalse(try repeated.hasPendingChanges())
    }

    func testDisabledOrChangedAccountCannotAdoptALateReceipt() throws {
        let f = Fixture(), initial = try f.state(), desired = f.remoteChoices(initial.observed)
        var disabled = try initial.preparing(desired, registry: f.registry, ifUnchanged: initial)
        disabled.isEnabled = false
        XCTAssertThrowsError(try disabled.confirming(.init(snapshot: desired, changeTag: "late", account: f.account),
                                                     projected: f.project(desired, into: f.metadata), sources: f.sources))
        let otherAccount = CollectionSyncAccountToken(scope: f.account.scope, epoch: UUID())
        XCTAssertThrowsError(try initial.confirming(.init(snapshot: initial.observed, changeTag: "late", account: otherAccount),
                                                    projected: f.metadata, sources: f.sources)) {
            XCTAssertEqual($0 as? CollectionSyncError, .staleAccount)
        }
        let restored = try CollectionSyncApplicationCodec.decode(CollectionSyncApplicationCodec.encode(disabled))
        XCTAssertFalse(restored.isEnabled)
        XCTAssertTrue(try restored.hasPendingChanges())
    }

    func testAppStateCodecPreservesFractionalDatesAndRejectsOtherFormatsAndFutureVersions() throws {
        let f = Fixture(), state = try f.state(), encoded = try CollectionSyncApplicationCodec.encode(state)
        XCTAssertEqual(try CollectionSyncApplicationCodec.decode(encoded), state)
        XCTAssertThrowsError(try CollectionSyncApplicationCodec.decode(CollectionSyncCodec.encode(state.observed)))
        XCTAssertThrowsError(try CollectionSyncCodec.decode(encoded))
        var fields = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        fields["schemaVersion"] = 2
        XCTAssertThrowsError(try CollectionSyncApplicationCodec.decode(JSONSerialization.data(withJSONObject: fields))) {
            XCTAssertEqual($0 as? CollectionSyncError, .unsupportedVersion(2))
        }
        fields["schemaVersion"] = 1
        var observation = fields["observed"] as! [String: Any]
        observation["generation"] = UUID().uuidString; fields["observed"] = observation
        XCTAssertThrowsError(try CollectionSyncApplicationCodec.decode(JSONSerialization.data(withJSONObject: fields)))
    }
}

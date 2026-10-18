#if canImport(Combine)
import XCTest
@testable import SavageModPlayerCore

@MainActor
final class CollectionExchangeModelTests: XCTestCase {
    private final class CapturedState {
        var value: CollectionExchangeModel.State
        init(_ value: CollectionExchangeModel.State) { self.value = value }
    }
    private func fixture() -> (CollectionExchangeModel.State, CollectionExchangeDocument) {
        let reference = PlaylistTrackReference(source: .init(location: URL(fileURLWithPath: "/synthetic/song.mod")), displayName: "song.mod")
        let source = CollectionExchangeLocalTrack(reference: reference, descriptor: .init(fileName: "song.mod"))
        var document = CollectionExchangeDocument(); let track = ExchangeTrack(descriptor: source.descriptor)
        document.tracks = [track]; document.favoriteTrackIDs = [track.id]
        return (.init(snapshot: .init(), sources: [source]), document)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
    func testMappedPreviewRequiresExplicitApplyAndBadReplacementCannotApplyOldFile() async throws {
        let (state, document) = fixture(); var applied = 0
        let model = CollectionExchangeModel(capture: { state }, apply: { _ in applied += 1; return false }, read: { _, _ in throw CollectionExchangeError.invalidDocument })
        await model.load(); try await model.receive(document); try await wait { model.isReady }
        XCTAssertEqual(applied, 0); XCTAssertEqual(model.mapping.count, 1)
        await model.loadFile(URL(fileURLWithPath: "/synthetic/bad.savagecollection"))
        XCTAssertFalse(model.isReady); XCTAssertNil(model.incoming); XCTAssertNotNil(model.error)
        await model.applyImport(); XCTAssertEqual(applied, 0)
        try await model.receive(document); try await wait { model.isReady }
        await model.applyImport(); XCTAssertEqual(applied, 1); XCTAssertEqual(model.completion, .imported)
    }
    func testCanceledReadCannotReplaceANewerPreview() async throws {
        let (state, first) = fixture(); var newer = first; newer.id = UUID()
        let entered = expectation(description: "Reader entered")
        let model = CollectionExchangeModel(capture: { state }, apply: { _ in false }, read: { _, cancelled in
            entered.fulfill(); let deadline = Date().addingTimeInterval(3)
            while !cancelled(), Date() < deadline { Thread.sleep(forTimeInterval: 0.002) }
            if cancelled() { throw CancellationError() }; return first
        })
        await model.load()
        let reading = Task { await model.loadFile(URL(fileURLWithPath: "/synthetic/slow")) }
        await fulfillment(of: [entered], timeout: 2)
        model.cancel(); try await model.receive(newer); await reading.value
        try await wait { model.isReady }
        XCTAssertEqual(model.incoming?.id, newer.id)
    }
    func testDuplicateAutomaticMatchesStayUnresolvedUntilOneIsSkipped() async throws {
        let (state, original) = fixture(); var document = original
        document.tracks.append(ExchangeTrack(descriptor: original.tracks[0].descriptor))
        let model = CollectionExchangeModel(capture: { state }, apply: { _ in false })
        await model.load(); try await model.receive(document); try await wait { !model.isBusy }
        XCTAssertTrue(model.mapping.isEmpty); XCTAssertEqual(model.preview?.unresolvedTrackIDs.count, 2)
        model.assign(state.sources[0], to: document.tracks[0].id); try await wait { !model.isBusy }
        model.skip(document.tracks[1].id); try await wait { model.isReady }
        XCTAssertEqual(model.mapping.count, 1); XCTAssertEqual(model.skipped.count, 1)
    }
    func testExportRejectsAChangedLocalSnapshotInsteadOfSavingAnOldSummary() async throws {
        let (state, _) = fixture(); let current = CapturedState(state)
        let model = CollectionExchangeModel(capture: { current.value }, apply: { _ in false })
        await model.load()
        var changed = state.snapshot; changed.playlists.favoriteIDs = [state.sources[0].reference.id]
        current.value = .init(snapshot: changed, sources: state.sources)
        do { _ = try await model.exportData(); XCTFail("Stale export was accepted") }
        catch { XCTAssertEqual(error as? CollectionExchangeError, .stalePreview) }
        XCTAssertFalse(model.isBusy)
    }
}
#endif

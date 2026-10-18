#if canImport(Combine)
import Foundation
import Combine

public struct CollectionSyncService: Sendable {
    public let backend: any CollectionSyncAssetBackend
    public let prepareNewCollection: @Sendable (CollectionSyncAccountToken) async throws -> Void
    public init(backend: any CollectionSyncAssetBackend,
                prepareNewCollection: @escaping @Sendable (CollectionSyncAccountToken) async throws -> Void = { _ in }) {
        self.backend = backend; self.prepareNewCollection = prepareNewCollection
    }
}

@MainActor
public final class CollectionSyncModel: ObservableObject {
    public enum Status: Equatable { case off, notConfigured, syncing, review, current, waiting, failed }
    public struct TrackChoice: Identifiable, Sendable {
        public let id: UUID
        public let descriptor: ExchangeTrackDescriptor
        public let suggestions: [CollectionExchangeLocalTrack]
    }
    @Published public private(set) var status: Status = .off
    @Published public private(set) var isEnabled = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var hasPendingChanges = false
    @Published public private(set) var lastSuccessfulSync: Date?
    @Published public private(set) var cleanupPending = false
    @Published public private(set) var error: Error?
    @Published public private(set) var conflicts: [CollectionSyncConflict] = []
    @Published public private(set) var resolutions: [CollectionSyncKey: CollectionSyncResolution] = [:]
    @Published public private(set) var tracks: [TrackChoice] = []
    @Published public private(set) var mapping: [UUID: PlaylistTrackReference] = [:]
    @Published public private(set) var sources: [CollectionExchangeLocalTrack] = []
    public var isConfigured: Bool { service != nil }
    public var isFirstSetup: Bool { preview?.stored == nil }
    public var isRelinking: Bool { preview?.stored == nil && preview?.captured.disk.documents.syncState != nil }
    public var canConfirm: Bool {
        !isBusy && preview != nil && tracks.allSatisfy { mapping[$0.id] != nil }
            && conflicts.allSatisfy { resolutions[$0.id] != nil } && error == nil
    }

    private struct Preview: Sendable {
        var captured: CollectionExchangeStoreBinding.Capture
        var stored: CollectionSyncApplicationState?
        var account: CollectionSyncAccountToken
        var remote: CollectionSyncServerVersion?
        var registry: CollectionSyncTrackRegistry
        var initialRegistry: CollectionSyncTrackRegistry
        var observed: CollectionSyncSnapshot
        var local: CollectionSyncSnapshot
        var plan: CollectionSyncMergePlan
    }
    private let binding: CollectionExchangeStoreBinding
    private let service: CollectionSyncService?
    private var preview: Preview?
    private var request = UUID()
    private var task: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var active = true
    private var paused = false

    public init(binding: CollectionExchangeStoreBinding, service: CollectionSyncService? = nil) {
        self.binding = binding; self.service = service
    }
    deinit { task?.cancel(); retryTask?.cancel() }

    public func activate() {
        active = true
        schedule(force: true)
    }
    public func deactivate() { active = false; cancelOperation() }
    public func setPaused(_ value: Bool) {
        paused = value
        cancelOperation()
        if !value && active { schedule(force: true) }
    }
    public func metadataDidChange() {
        cancelOperation()
        schedule(force: false)
    }
    private func schedule(force: Bool) {
        guard active, !paused else { return }
        task?.cancel()
        task = Task { [weak self] in
            do { if !force { try await Task.sleep(for: .milliseconds(300)) } }
            catch { return }
            await self?.synchronize(force: force)
        }
    }
    private func cancelOperation() {
        task?.cancel(); retryTask?.cancel(); request = UUID(); isBusy = false
        clearPreview()
    }
    public func cancelReview() {
        cancelOperation(); error = nil
        status = service == nil ? .notConfigured : (isEnabled ? .waiting : .off)
    }
    private func clearPreview() {
        preview = nil; conflicts = []; resolutions = [:]; tracks = []; mapping = [:]; sources = []
    }

    public func disable() async {
        cancelOperation()
        let token = UUID(); request = token; isBusy = true; error = nil
        defer { if request == token { isBusy = false } }
        do {
            let captured = try await binding.captureStorage()
            try check(token)
            cleanupPending = false
            if let data = captured.disk.documents.syncState {
                var state = try await Task.detached { try CollectionSyncApplicationCodec.decode(data) }.value
                try check(token)
                state.isEnabled = false
                try await persist(state, captured: captured, token: token)
                try await show(state, token: token)
            } else { isEnabled = false }
            status = service == nil ? .notConfigured : .off
        } catch { fail(error, token: token) }
    }

    // Einrichtung und Kontozugriff beginnen ausschließlich nach dieser Aktion.
    // Beim normalen Start wird nur ein bereits eingeschalteter Stand fortgesetzt.
    public func beginSetup() async { await synchronize(force: true, setup: true) }

    public func synchronize(force: Bool = true, setup: Bool = false) async {
        guard !isBusy, !paused, active else { return }
        clearPreview(); error = nil; retryTask?.cancel()
        let token = UUID(); request = token; isBusy = true
        defer { if request == token { isBusy = false } }
        do {
            var captured = try await binding.captureStorage()
            try check(token)
            cleanupPending = false
            let rawState = captured.disk.documents.syncState
            var stored = try await Task.detached { try rawState.map(CollectionSyncApplicationCodec.decode) }.value
            try check(token)
            if let state = stored { try await show(state, token: token) }
            else { isEnabled = false; hasPendingChanges = false; lastSuccessfulSync = nil }
            guard let service else { status = .notConfigured; return }
            guard setup || stored?.isEnabled == true else { status = .off; return }
            if var state = stored {
                let previous = state, observation = captured
                let preferenceKeys = Set(try binding.storedPreferenceValues(in: captured).keys)
                state = try await Task.detached {
                    try previous.capturing(observation.snapshot, sources: observation.sources,
                        metadataFilesExist: observation.disk.metadataFilesExist, preferencesAvailable: !preferenceKeys.isEmpty,
                        preferenceKeys: preferenceKeys)
                }.value
                try check(token)
                if state != stored {
                    let savedData = try await persist(state, captured: captured, token: token)
                    captured = try await binding.captureStorage()
                    try check(token)
                    guard captured.disk.documents.syncState == savedData else {
                        throw CollectionSyncError.stalePreview
                    }
                    stored = state
                }
                try await show(state, token: token)
                if !force, !hasPendingChanges { status = .current; return }
            }
            status = .syncing
            let scope = try await service.backend.currentAccountScope()
            try check(token)
            if setup, let previous = stored, previous.localState.checkpoint.account.scope != scope {
                if previous.needsProjection {
                    let observation = captured
                    let unchanged = try await Task.detached {
                        let local = previous.localState
                        let mapping = try local.registry.mapping(for: local.checkpoint.local,
                            available: observation.sources.map(\.reference), account: local.checkpoint.account)
                        let projection = try CollectionSyncProjection(snapshot: local.checkpoint.local,
                            into: observation.snapshot, mapping: mapping,
                            collectionID: local.registry.collectionID, generation: local.registry.generation)
                        return try projection.result(ifUnchanged: observation.snapshot, mapping: mapping) == observation.snapshot
                    }.value
                    try check(token)
                    guard unchanged else { throw CollectionSyncError.unappliedDecisions }
                }
                // Das neue Konto erhält erst nach einer eigenen Vorschau die
                // tatsächlichen App-Metadaten. Der alte Stand bleibt bis dahin.
                stored = nil
            }
            let account = stored?.localState.checkpoint.account ?? .init(scope: scope, epoch: UUID())
            try account.validate()
            guard account.scope == scope else { throw CollectionSyncError.staleAccount }
            let remote: CollectionSyncServerVersion?
            if let stored {
                let client = try client(service, state: stored)
                remote = try await client.fetch(account: account)
            } else {
                let asset = try await service.backend.fetch()
                try check(token)
                guard try await service.backend.currentAccountScope() == scope else { throw CollectionSyncError.staleAccount }
                if let asset {
                    try CollectionSyncTransportClient.validateTag(asset.changeTag)
                    let snapshot = try await Task.detached { try CollectionSyncCodec.decode(asset.data) }.value
                    try check(token)
                    remote = .init(snapshot: snapshot, changeTag: asset.changeTag, account: account)
                } else { remote = nil }
            }
            try check(token)
            let observation = captured, previous = stored
            let prepared = try await Task.detached {
                try Self.makePreview(captured: observation, stored: previous, account: account, remote: remote)
            }.value
            try check(token)
            preview = prepared.preview; sources = captured.sources
            mapping = prepared.mapping; tracks = prepared.tracks
            conflicts = prepared.preview.plan.conflicts; resolutions = [:]
            if stored == nil { try await rebuildInitialPlan(token: token) }
            if !setup, stored != nil, conflicts.isEmpty, tracks.isEmpty {
                try await finish(token: token, service: service)
            } else { status = .review }
        } catch { fail(error, token: token) }
    }

    private nonisolated static func makePreview(captured: CollectionExchangeStoreBinding.Capture,
                             stored: CollectionSyncApplicationState?, account: CollectionSyncAccountToken,
                             remote: CollectionSyncServerVersion?) throws -> (preview: Preview, mapping: [UUID: PlaylistTrackReference], tracks: [TrackChoice]) {
        let collection = stored?.localState.checkpoint.local.collectionID ?? remote?.snapshot.collectionID ?? UUID()
        let generation = stored?.localState.checkpoint.local.generation ?? remote?.snapshot.generation ?? UUID()
        let empty = CollectionSyncSnapshot(collectionID: collection, generation: generation)
        let registry = stored?.localState.registry ?? .init(account: account, collectionID: collection, generation: generation)
        let exported = try registry.export(from: captured.snapshot, sources: captured.sources, account: account)
        let observed = try CollectionSyncSnapshot(document: exported.document, collectionID: collection, generation: generation)
        let local = stored?.localState.checkpoint.local ?? observed
        let plan = try CollectionSyncMergePlan(base: stored?.localState.checkpoint.base ?? empty,
            local: local, remote: remote?.snapshot ?? empty)
        let preview = Preview(captured: captured, stored: stored, account: account, remote: remote,
                        registry: exported.registry, initialRegistry: exported.registry,
                        observed: observed, local: local, plan: plan)
        let sources = captured.sources
        let mapping = try registry.mapping(for: remote?.snapshot ?? local, available: sources.map(\.reference), account: account)
        let document = try (remote?.snapshot ?? empty).exchangeDocument()
        let matches = try CollectionExchangeMatcher.match(document, against: sources)
        let missing = (remote?.snapshot ?? empty).mappingRequirements().required.subtracting(mapping.keys)
        let byID = Dictionary(uniqueKeysWithValues: sources.map { ($0.reference.id, $0) })
        let tracks: [TrackChoice] = document.tracks.filter { missing.contains($0.id) }.map { track in
            let ids: [String]
            switch matches[track.id] {
            case .matched(let id): ids = [id]
            case .ambiguous(let found, _): ids = found
            default: ids = []
            }
            return .init(id: track.id, descriptor: track.descriptor, suggestions: ids.compactMap { byID[$0] })
        }
        // Vorschläge sind noch keine bestätigte Titelidentität.
        return (preview, mapping, tracks)
    }

    public func assign(_ source: CollectionExchangeLocalTrack, to id: UUID) async {
        guard !isBusy, tracks.contains(where: { $0.id == id }), sources.contains(source),
              !mapping.contains(where: { $0.key != id && $0.value.id == source.reference.id }) else { return }
        let token = UUID(); request = token; isBusy = true; error = nil
        defer { if request == token { isBusy = false } }
        do {
            if let p = preview, p.stored != nil {
                _ = try await Task.detached { try p.registry.assigning(id, to: source.reference, account: p.account) }.value
                try check(token)
            }
            mapping[id] = source.reference; resolutions = [:]
            try await rebuildInitialPlan(token: token)
            status = .review
        } catch { fail(error, token: token) }
    }
    public func unassign(_ id: UUID) async {
        guard !isBusy, tracks.contains(where: { $0.id == id }) else { return }
        let token = UUID(); request = token; isBusy = true
        defer { if request == token { isBusy = false } }
        mapping.removeValue(forKey: id); resolutions = [:]; error = nil
        do { try await rebuildInitialPlan(token: token); status = .review }
        catch { fail(error, token: token) }
    }
    public func assignUniqueSuggestions() async {
        guard !isBusy, let p = preview else { return }
        let token = UUID(); request = token; isBusy = true
        defer { if request == token { isBusy = false } }
        let assigned = Set(mapping.values.map(\.id))
        let owners = Dictionary(uniqueKeysWithValues: p.registry.bindings.map { ($0.reference.id, $0.id) })
        let proposed = tracks.compactMap { track -> (UUID, PlaylistTrackReference)? in
            guard mapping[track.id] == nil, track.suggestions.count == 1 else { return nil }
            let source = track.suggestions[0].reference
            guard !assigned.contains(source.id),
                  p.stored == nil || owners[source.id] == nil || owners[source.id] == track.id else { return nil }
            return (track.id, source)
        }
        let counts = Dictionary(grouping: proposed, by: { $0.1.id }).mapValues(\.count)
        var updated = mapping
        for (id, reference) in proposed where counts[reference.id] == 1 { updated[id] = reference }
        mapping = updated
        resolutions = [:]; error = nil
        do { try await rebuildInitialPlan(token: token); status = .review }
        catch { fail(error, token: token) }
    }
    public func resolve(_ id: CollectionSyncKey, with decision: CollectionSyncResolution?) {
        guard !isBusy, conflicts.contains(where: { $0.id == id }) else { return }
        resolutions[id] = decision
    }
    private func rebuildInitialPlan(token: UUID) async throws {
        guard let p = preview, p.stored == nil else { return }
        let mapping = mapping
        let updated = try await Task.detached { try Self.initialPreview(p, mapping: mapping) }.value
        try check(token)
        preview = updated; conflicts = updated.plan.conflicts
    }
    private nonisolated static func initialPreview(_ previous: Preview, mapping: [UUID: PlaylistTrackReference]) throws -> Preview {
        var p = previous
        let assignedSources = Set(mapping.values.map(\.id))
        var registry = CollectionSyncTrackRegistry(account: p.account,
            collectionID: p.initialRegistry.collectionID, generation: p.initialRegistry.generation,
            bindings: p.initialRegistry.bindings.filter { !assignedSources.contains($0.reference.id) })
        registry = try registry.assigning(mapping, account: p.account)
        let exported = try registry.export(from: p.captured.snapshot, sources: p.captured.sources, account: p.account)
        let local = try CollectionSyncSnapshot(document: exported.document,
            collectionID: registry.collectionID, generation: registry.generation)
        let empty = CollectionSyncSnapshot(collectionID: registry.collectionID, generation: registry.generation)
        p.local = local; p.observed = local; p.registry = exported.registry
        p.plan = try .init(base: empty, local: local, remote: p.remote?.snapshot ?? empty)
        return p
    }
    public func confirm() async {
        guard canConfirm, let service else { return }
        let token = UUID(); request = token; isBusy = true; error = nil; status = .syncing
        defer { if request == token { isBusy = false } }
        do { try await finish(token: token, service: service) }
        catch { fail(error, token: token) }
    }

    private func finish(token: UUID, service: CollectionSyncService) async throws {
        guard let p = preview else { throw CollectionSyncError.stalePreview }
        let fresh = try await binding.captureStorage()
        try check(token)
        guard try sameStorage(fresh, p.captured) else { throw CollectionSyncError.stalePreview }
        let mapping = mapping, resolutions = resolutions
        let preferenceKeys = Set(try binding.storedPreferenceValues(in: fresh).keys)
        let prepared = try await Task.detached {
            try Self.prepare(p, captured: fresh, mapping: mapping, resolutions: resolutions,
                             preferenceKeys: preferenceKeys)
        }.value
        try check(token)
        let state = prepared.state, target = state.localState.checkpoint.local, registry = state.localState.registry
        let stagedResult = try binding.commit(fresh.snapshot, replacing: fresh, syncState: prepared.data, adoptMetadata: false)
        try await show(state, token: token)
        guard stagedResult == .complete else { throw CollectionExchangePersistenceError.recoveryRequired }
        let transport = try client(service, state: state)
        let server: CollectionSyncServerVersion
        if let remote = p.remote, prepared.matchesRemote {
            let latest = try await transport.fetch(account: p.account)
            guard latest.changeTag == remote.changeTag, latest.snapshot == target else {
                throw CollectionSyncTransportError.conflict
            }
            server = latest
        }
        else {
            if p.remote == nil { try await service.prepareNewCollection(p.account) }
            try check(token)
            server = try await transport.save(target, replacing: p.remote?.changeTag, account: p.account)
        }
        try check(token)
        let current = try await binding.captureStorage()
        try check(token)
        guard current.disk.documents.syncState == prepared.data,
              current.snapshot == fresh.snapshot else { throw CollectionSyncError.stalePreview }
        let candidate = try await Task.detached {
            let finalMapping = try registry.mapping(for: target, available: current.sources.map(\.reference), account: p.account)
            let projection = try CollectionSyncProjection(snapshot: target, into: current.snapshot, mapping: finalMapping,
                collectionID: target.collectionID, generation: target.generation)
            return try projection.result(ifUnchanged: current.snapshot, mapping: finalMapping)
        }.value
        try check(token)
        let projectedPreferenceKeys = Set(try binding.preferenceValues(after: candidate, replacing: current).keys)
        let confirmed = try await Task.detached {
            let confirmed = try state.confirming(server, projected: candidate, sources: current.sources,
                preferencesAvailable: !projectedPreferenceKeys.isEmpty, preferenceKeys: projectedPreferenceKeys)
            return (confirmed, try CollectionSyncApplicationCodec.encode(confirmed))
        }.value
        guard try await service.backend.currentAccountScope() == p.account.scope else { throw CollectionSyncError.staleAccount }
        try check(token)
        cleanupPending = try binding.commit(candidate, replacing: current, syncState: confirmed.1) == .cleanupPending
        try await show(confirmed.0, token: token)
        clearPreview(); error = nil; status = .current
    }

    private nonisolated static func prepare(_ p: Preview, captured: CollectionExchangeStoreBinding.Capture,
        mapping: [UUID: PlaylistTrackReference], resolutions: [CollectionSyncKey: CollectionSyncResolution],
        preferenceKeys: Set<String>) throws -> (state: CollectionSyncApplicationState, data: Data, matchesRemote: Bool) {
        let registry = try p.registry.assigning(mapping, account: p.account)
        let target = try p.plan.result(ifUnchanged: p.local, resolutions: resolutions)
        var state: CollectionSyncApplicationState
        if let stored = p.stored {
            state = try stored.preparing(target, registry: registry, ifUnchanged: stored)
            state.isEnabled = true
        } else {
            let empty = CollectionSyncSnapshot(collectionID: target.collectionID, generation: target.generation)
            state = .init(localState: .init(checkpoint: .init(account: p.account, base: empty, local: target), registry: registry),
                observed: p.observed, needsProjection: true,
                hasStoredPreferences: !preferenceKeys.isEmpty, storedPreferenceKeys: preferenceKeys)
        }
        try state.validate()
        let projectedMapping = try registry.mapping(for: target, available: captured.sources.map(\.reference), account: p.account)
        let projection = try CollectionSyncProjection(snapshot: target, into: captured.snapshot, mapping: projectedMapping,
            collectionID: target.collectionID, generation: target.generation)
        guard projection.isReady else { throw CollectionExchangeError.unmappedSources }
        return (state, try CollectionSyncApplicationCodec.encode(state), p.remote?.snapshot.indexed() == target.indexed())
    }

    private func sameStorage(_ a: CollectionExchangeStoreBinding.Capture,
                             _ b: CollectionExchangeStoreBinding.Capture) throws -> Bool {
        let aPreferences = try binding.storedPreferenceValues(in: a)
        let bPreferences = try binding.storedPreferenceValues(in: b)
        return a.snapshot == b.snapshot && a.disk.documents == b.disk.documents
            && NSDictionary(dictionary: aPreferences).isEqual(to: bPreferences)
    }
    private func client(_ service: CollectionSyncService, state: CollectionSyncApplicationState) throws -> CollectionSyncTransportClient {
        try .init(backend: service.backend, account: state.localState.checkpoint.account,
                  collectionID: state.localState.checkpoint.local.collectionID, generation: state.localState.checkpoint.local.generation)
    }
    @discardableResult
    private func persist(_ state: CollectionSyncApplicationState,
                         captured: CollectionExchangeStoreBinding.Capture, token: UUID) async throws -> Data {
        let data = try await Task.detached { try CollectionSyncApplicationCodec.encode(state) }.value
        try check(token)
        let result = try binding.commit(captured.snapshot, replacing: captured,
            syncState: data, adoptMetadata: false)
        guard result == .complete else { throw CollectionExchangePersistenceError.recoveryRequired }
        return data
    }
    private func show(_ state: CollectionSyncApplicationState, token: UUID) async throws {
        let pending = try await Task.detached { try state.hasPendingChanges() }.value
        try check(token)
        isEnabled = state.isEnabled; lastSuccessfulSync = state.lastSuccessfulSync
        hasPendingChanges = pending
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard request == token, active, !paused else { throw CancellationError() }
    }
    private func fail(_ error: Error, token: UUID) {
        guard request == token, !(error is CancellationError) else { return }
        self.error = error
        if case CollectionSyncTransportError.temporarilyUnavailable(let retryAfter) = error {
            status = .waiting
            if let retryAfter, retryAfter.isFinite, active, !paused, isEnabled {
                retryTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(min(3600, max(5, retryAfter)))) }
                    catch { return }
                    guard let self, self.request == token else { return }
                    await self.synchronize()
                }
            }
        } else { status = .failed }
    }
}
#endif

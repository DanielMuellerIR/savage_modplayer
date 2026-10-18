#if canImport(Combine)
import Combine
import Foundation

@MainActor
public final class TrackPlaybackSettingsModel: ObservableObject {
    public enum Issue: Sendable { case load, save }
    @Published public private(set) var defaults: PlaybackOptions
    @Published public private(set) var sourceID: String?
    @Published public private(set) var format: ModuleFormat?
    @Published public private(set) var sourceDescription = ""
    @Published public private(set) var document = TrackPlaybackSettingsDocument()
    @Published public private(set) var issue: Issue?
    @Published public private(set) var isSaving = false
    @Published private var separationDraft: SeparationDraft?
    public var onResolvedChange: (@MainActor (PlaybackOptions) -> Void)?
    public let metadataDidChange = PassthroughSubject<Void, Never>()
    private let store: TrackPlaybackSettingsStore
    private let saveDefaults: @MainActor (PlaybackOptions) -> Void
    private var writeTask: Task<Void, Never>?
    private struct SeparationDraft { let sourceID: String; let value: Double }

    public init(fileURL: URL, defaults: PlaybackOptions = PlaybackOptions(),
                saveDefaults: @escaping @MainActor (PlaybackOptions) -> Void = { _ in }) {
        self.store = TrackPlaybackSettingsStore(fileURL: fileURL)
        self.defaults = defaults; self.saveDefaults = saveDefaults
        do { document = try store.load() } catch { issue = .load }
    }

    deinit { writeTask?.cancel() }

    public var effective: PlaybackOptions {
        overrides(for: sourceID).resolved(defaults: defaults, format: format)
    }
    public var canWriteTitles: Bool { issue != .load }

    public func adoptCommitted(_ document: TrackPlaybackSettingsDocument, defaults: PlaybackOptions) {
        writeTask?.cancel(); writeTask = nil; separationDraft = nil; isSaving = false
        self.document = document; self.defaults = defaults; issue = nil; publishResolved()
    }

    public func overrides(for sourceID: String?) -> TrackPlaybackOverrides {
        guard let sourceID else { return TrackPlaybackOverrides() }
        var result = document.tracks[sourceID] ?? TrackPlaybackOverrides()
        if let separationDraft, separationDraft.sourceID == sourceID {
            result.stereoSeparation = separationDraft.value
        }
        return result
    }

    public func setContext(sourceID: String?, format: ModuleFormat?, sourceDescription: String = "") {
        flush()
        self.sourceID = sourceID.flatMap { TrackPlaybackSettingsStore.validID($0) ? $0 : nil }
        self.format = format
        self.sourceDescription = self.sourceID == nil ? "" : sourceDescription
        publishResolved()
    }

    public func updateDefaults(_ value: PlaybackOptions, persist: Bool = true) {
        let value = PlaybackOptions(palClock: value.palClock, stereoSeparation: value.stereoSeparation,
                                    useInterpolation: value.useInterpolation, ledFilterActive: value.ledFilterActive)
        guard defaults != value else { return }
        defaults = value
        if persist { saveDefaults(value) }
        publishResolved()
        metadataDidChange.send()
    }

    @discardableResult
    public func updateTitle(_ sourceID: String, change: (inout TrackPlaybackOverrides) -> Void) -> Bool {
        guard canWriteTitles, TrackPlaybackSettingsStore.validID(sourceID) else { return false }
        guard flush() else { return false }
        var value = overrides(for: sourceID)
        change(&value)
        return saveTitle(sourceID, value: value)
    }

    public func resetTitle(_ sourceID: String) {
        guard canWriteTitles, TrackPlaybackSettingsStore.validID(sourceID) else { return }
        if separationDraft?.sourceID == sourceID {
            writeTask?.cancel(); separationDraft = nil; isSaving = false
        } else if !flush() { return }
        if !saveTitle(sourceID, value: TrackPlaybackOverrides()) { publishResolved() }
    }

    // Reglerbewegungen wirken sofort, schreiben aber erst nach einer kurzen
    // Ruhephase. Ein Titelwechsel/Schließen sichert den letzten Wert synchron.
    public func previewSeparation(_ value: Double, for sourceID: String) {
        guard canWriteTitles, TrackPlaybackSettingsStore.validID(sourceID),
              document.tracks[sourceID]?.stereoSeparation != nil, value.isFinite else { return }
        if let separationDraft, separationDraft.sourceID != sourceID, !flush() { return }
        separationDraft = SeparationDraft(sourceID: sourceID, value: min(1, max(0, value)))
        isSaving = true; publishResolved()
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            self?.flush()
        }
    }

    @discardableResult
    public func flush() -> Bool {
        writeTask?.cancel(); writeTask = nil
        guard let draft = separationDraft else { return true }
        separationDraft = nil; isSaving = false
        var value = document.tracks[draft.sourceID] ?? TrackPlaybackOverrides()
        value.stereoSeparation = draft.value
        let saved = saveTitle(draft.sourceID, value: value)
        if !saved { publishResolved() }
        return saved
    }

    public func setPALClock(_ value: Bool) { setBool(value, override: \.palClock, global: \.palClock) }
    public func setInterpolation(_ value: Bool) { setBool(value, override: \.useInterpolation, global: \.useInterpolation) }
    public func setFilter(_ value: Bool) { setBool(value, override: \.ledFilterActive, global: \.ledFilterActive) }
    public func setSeparation(_ value: Double) {
        if let sourceID, overrides(for: sourceID).stereoSeparation != nil {
            previewSeparation(value, for: sourceID)
        } else {
            var next = defaults; next.stereoSeparation = value; updateDefaults(next)
        }
    }

    private func setBool(_ value: Bool, override field: WritableKeyPath<TrackPlaybackOverrides, Bool?>,
                         global: WritableKeyPath<PlaybackOptions, Bool>) {
        if let sourceID, overrides(for: sourceID)[keyPath: field] != nil {
            updateTitle(sourceID) { $0[keyPath: field] = value }
        } else {
            var next = defaults; next[keyPath: global] = value; updateDefaults(next)
        }
    }

    private func saveTitle(_ sourceID: String, value: TrackPlaybackOverrides) -> Bool {
        var next = document
        next.tracks[sourceID] = value.isEmpty ? nil : value
        guard next != document else { publishResolved(); return true }
        do {
            try store.save(next)
            document = next; issue = nil; publishResolved(); metadataDidChange.send(); return true
        } catch { issue = .save; return false }
    }

    private func publishResolved() { onResolvedChange?(effective) }
}
#endif

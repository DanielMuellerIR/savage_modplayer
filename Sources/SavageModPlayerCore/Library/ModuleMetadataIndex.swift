import Foundation

public struct ModuleMetadata: Codable, Equatable, Sendable {
    public let title: String
    public let format: ModuleFormat
    public let channelCount: Int
    public let instrumentCount: Int
    public let sampleCount: Int
    public let patternCount: Int
    public let instrumentNames: [String]
    public let durationSeconds: Double
    public let durationIsLimited: Bool

    static func inspect(_ mod: Mod, durationLimit: Double = 600) -> Self {
        let instruments = mod.instruments.compactMap { $0 }
        let samples = mod.format == .it ? mod.samplePool.compactMap { $0 }
            : instruments.flatMap(\.samples)
        let activeInstruments = instruments.filter {
            $0.samples.contains { !$0.pcm.isEmpty } || $0.noteSampleMapping != nil || $0.itProperties != nil
        }
        let seconds = RenderEngine.sequencedDuration(of: mod, maximumSeconds: durationLimit)
        return Self(title: String(mod.name.prefix(256)), format: mod.format,
                    channelCount: mod.channelCount, instrumentCount: activeInstruments.count,
                    sampleCount: samples.filter { !$0.pcm.isEmpty }.count,
                    patternCount: mod.patterns.count,
                    instrumentNames: instruments.map { String($0.name.prefix(256)) }.filter { !$0.isEmpty },
                    durationSeconds: seconds, durationIsLimited: seconds >= durationLimit)
    }
}

public enum ModuleMetadataFailure: String, Codable, Sendable {
    case unavailable, invalidModule, oversizedFile, changedDuringRead
}

public struct ModuleMetadataRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let metadata: ModuleMetadata?
    public let failure: ModuleMetadataFailure?
    public let detail: String?
    public let indexedAt: Date
    fileprivate let stamp: LibraryFileStamp?
}

public struct ModuleMetadataInput: Sendable {
    public let id: String
    public let url: URL
    public init(id: String, url: URL) { self.id = id; self.url = url }
}

public enum ModuleMetadataWarning: String, Sendable {
    case rebuiltCache, cacheWriteFailed, capacityLimited, invalidSource
}

public struct ModuleMetadataProgress: Sendable {
    public let completed: Int
    public let total: Int
}

public struct ModuleMetadataResult: Sendable {
    public let records: [String: ModuleMetadataRecord]
    public let refreshedCount: Int
    public let reusedCount: Int
    public let wasCancelled: Bool
    public let warnings: [ModuleMetadataWarning]
}

// Der Actor serialisiert Cache und Parserarbeit auf seinem eigenen Executor.
// Weder UI-/Audiozustand noch PCM-Daten landen im gespeicherten Index.
public actor ModuleMetadataIndex {
    public static let maximumFileBytes = 64 * 1024 * 1024
    public static let maximumCacheBytes = 32 * 1024 * 1024
    public static let maximumEntries = 50_000
    private let cacheURL: URL
    private let durationLimit: Double
    private var records: [String: ModuleMetadataRecord] = [:]
    private var didLoad = false
    private var cacheIsSource = false

    public enum ConfigurationError: Error { case invalidDurationLimit }

    public init(cacheURL: URL, durationLimit: Double = 600) throws {
        guard durationLimit.isFinite, durationLimit > 0, durationLimit <= 600 else {
            throw ConfigurationError.invalidDurationLimit
        }
        self.cacheURL = cacheURL
        self.durationLimit = durationLimit
    }

    public func refresh(
        _ inputs: [ModuleMetadataInput], discardUnlisted: Bool = false,
        isCancelled: @Sendable () -> Bool = { Task.isCancelled },
        progress: @Sendable (ModuleMetadataProgress) -> Void = { _ in }
    ) -> ModuleMetadataResult {
        if isCancelled() {
            return ModuleMetadataResult(records: records, refreshedCount: 0, reusedCount: 0,
                                        wasCancelled: true, warnings: [])
        }
        if !cacheIsSource {
            let destination = cacheURL.standardizedFileURL.resolvingSymlinksInPath()
            for input in inputs {
                if isCancelled() {
                    return ModuleMetadataResult(records: records, refreshedCount: 0, reusedCount: 0,
                                                wasCancelled: true, warnings: [])
                }
                if input.url.standardizedFileURL.resolvingSymlinksInPath() == destination {
                    cacheIsSource = true
                    break
                }
            }
        }
        var warnings: [ModuleMetadataWarning] = cacheIsSource ? [.cacheWriteFailed] : []
        var changed = cacheIsSource ? false : loadIfNeeded(warnings: &warnings)
        var seen: Set<String> = []
        var selected: [ModuleMetadataInput] = []
        var completeSelection = true
        var cancelled = false
        for input in inputs {
            guard !isCancelled() else { cancelled = true; completeSelection = false; break }
            guard !input.id.isEmpty, input.id.utf8.count <= 16_384 else {
                completeSelection = false
                if !warnings.contains(.invalidSource) { warnings.append(.invalidSource) }
                continue
            }
            guard !seen.contains(input.id) else { continue }
            guard selected.count < Self.maximumEntries else {
                completeSelection = false
                warnings.append(.capacityLimited)
                break
            }
            seen.insert(input.id)
            selected.append(input)
        }
        var refreshed = 0, reused = 0
        for input in selected {
            guard !isCancelled() else { cancelled = true; break }
            guard let result = inspect(input, isCancelled: isCancelled) else { cancelled = true; break }
            if result.reused { reused += 1 }
            else {
                records[input.id] = result.record
                refreshed += 1
                changed = true
            }
            progress(ModuleMetadataProgress(completed: refreshed + reused, total: selected.count))
        }
        if discardUnlisted && !cancelled && completeSelection {
            let filtered = records.filter { seen.contains($0.key) }
            changed = changed || filtered.count != records.count
            records = filtered
        }
        if changed { persist(preferred: Set(selected.map(\.id)), warnings: &warnings) }
        return ModuleMetadataResult(records: records, refreshedCount: refreshed,
                                    reusedCount: reused, wasCancelled: cancelled, warnings: warnings)
    }

    private func inspect(_ input: ModuleMetadataInput, isCancelled: () -> Bool)
        -> (record: ModuleMetadataRecord, reused: Bool)? {
        #if canImport(Darwin)
        let scoped = input.url.startAccessingSecurityScopedResource()
        defer { if scoped { input.url.stopAccessingSecurityScopedResource() } }
        #endif
        var stamp: LibraryFileStamp?
        func record(metadata: ModuleMetadata? = nil, failure: ModuleMetadataFailure? = nil,
                    detail: String? = nil, stamp: LibraryFileStamp?) -> ModuleMetadataRecord {
            ModuleMetadataRecord(id: input.id, metadata: metadata, failure: failure,
                                 detail: detail, indexedAt: Date(), stamp: stamp)
        }
        do {
            let file = try LibraryFileReader(input.url)
            defer { file.close() }
            stamp = file.stamp
            if let cached = records[input.id], cached.stamp == stamp { return (cached, true) }
            guard file.stamp.size <= Self.maximumFileBytes else { throw LibraryFileReadError.oversized }
            let data = try file.read(limit: Self.maximumFileBytes, isCancelled: isCancelled)
            guard !isCancelled() else { return nil }
            let content: Result<ModuleMetadata, Error>
            do {
                let mod = try ModuleLoader.parse(data: data)
                guard !isCancelled() else { return nil }
                content = .success(ModuleMetadata.inspect(mod, durationLimit: durationLimit))
            } catch { content = .failure(error) }
            guard !isCancelled() else { return nil }
            let current = try LibraryFileReader(input.url)
            defer { current.close() }
            guard current.stamp == stamp, data.count == file.stamp.size else {
                return (record(failure: .changedDuringRead, stamp: nil), false)
            }
            switch content {
            case .success(let metadata): return (record(metadata: metadata, stamp: stamp), false)
            case .failure(let error):
                return (record(failure: .invalidModule, detail: String(error.localizedDescription.prefix(512)), stamp: stamp), false)
            }
        } catch is CancellationError { return nil }
        catch LibraryFileReadError.oversized { return (record(failure: .oversizedFile, stamp: stamp), false) }
        catch { return (record(failure: .unavailable, stamp: nil), false) }
    }

    private struct Cache: Codable {
        var version = 1
        let durationLimit: Double
        let records: [ModuleMetadataRecord]
    }

    private func loadIfNeeded(warnings: inout [ModuleMetadataWarning]) -> Bool {
        guard !didLoad else { return false }
        didLoad = true
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return false }
        do {
            let file = try LibraryFileReader(cacheURL)
            defer { file.close() }
            guard file.stamp.size <= Self.maximumCacheBytes else { throw LibraryFileReadError.oversized }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(Cache.self, from: file.read(limit: Self.maximumCacheBytes))
            guard cache.version == 1, cache.durationLimit == durationLimit,
                  cache.records.count <= Self.maximumEntries,
                  Set(cache.records.map(\.id)).count == cache.records.count,
                  cache.records.allSatisfy(isValidCachedRecord) else { throw MetadataReadError.invalidCache }
            records = Dictionary(uniqueKeysWithValues: cache.records.map { ($0.id, $0) })
            return false
        } catch {
            warnings.append(.rebuiltCache)
            return true
        }
    }

    private func isValidCachedRecord(_ record: ModuleMetadataRecord) -> Bool {
        guard !record.id.isEmpty, record.id.utf8.count <= 16_384,
              (record.metadata != nil) != (record.failure != nil) else { return false }
        guard let metadata = record.metadata else { return true }
        guard metadata.durationSeconds.isFinite, metadata.durationSeconds >= 0,
              metadata.durationSeconds <= durationLimit, (1...64).contains(metadata.channelCount),
              metadata.instrumentCount >= 0, metadata.sampleCount >= 0, metadata.patternCount >= 0,
              metadata.title.count <= 256, metadata.instrumentNames.count <= 256,
              metadata.instrumentNames.allSatisfy({ $0.count <= 256 }) else { return false }
        return metadata.durationIsLimited == (metadata.durationSeconds >= durationLimit)
    }

    private func persist(preferred: Set<String>, warnings: inout [ModuleMetadataWarning]) {
        // Vor dem JSON-Encoding konservativ begrenzen, damit auch sehr lange
        // Quellennamen keinen grossen Zwischenpuffer erzeugen.
        let ordered = records.values.map { (record: $0, preferred: preferred.contains($0.id)) }.sorted {
            if $0.preferred != $1.preferred { return $0.preferred }
            return $0.record.indexedAt > $1.record.indexedAt
        }
        var kept: [ModuleMetadataRecord] = [], budget = 1_024
        for candidate in ordered {
            let record = candidate.record
            var strings = record.id.utf8.count
            strings += record.detail?.utf8.count ?? 0
            if let metadata = record.metadata {
                strings += metadata.title.utf8.count
                for name in metadata.instrumentNames { strings += name.utf8.count }
            }
            let estimate = 1_024 + strings * 8
            if kept.count < Self.maximumEntries && budget + estimate <= Self.maximumCacheBytes {
                kept.append(record); budget += estimate
            }
        }
        if kept.count < records.count {
            records = Dictionary(uniqueKeysWithValues: kept.map { ($0.id, $0) })
            if !warnings.contains(.capacityLimited) { warnings.append(.capacityLimited) }
        }
        guard !cacheIsSource else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Cache(durationLimit: durationLimit, records: kept))
            guard data.count <= Self.maximumCacheBytes else { throw LibraryFileReadError.oversized }
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
        } catch { warnings.append(.cacheWriteFailed) }
    }
}

private enum MetadataReadError: Error { case invalidCache }

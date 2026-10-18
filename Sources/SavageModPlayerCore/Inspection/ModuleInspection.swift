import Foundation

public struct InspectorText: Sendable, Equatable {
    public let german: String
    public let english: String
    public init(_ german: String, _ english: String) { self.german = german; self.english = english }
    public func value(languageCode: String) -> String { languageCode == "de" ? german : english }
}

public struct InspectedOrder: Identifiable, Sendable {
    public var id: Int { position }
    public let position: Int
    public let pattern: Int
    public let rowCount: Int?
}

public struct InspectedEffect: Identifiable, Sendable {
    public let id: String
    public let code: String
    public let title: InspectorText
    public let detail: InspectorText
    public let count: Int
    public let parameters: [Int]
    public let isVolumeColumn: Bool
    public let implemented: Bool
}

public struct ModuleInspection: Sendable {
    public let orders: [InspectedOrder]
    public let patternUseCounts: [Int: Int]
    public let effects: [InspectedEffect]
    public let instrumentIndices: [Int]
    public let sampleCount: Int
    public let tracker: String?
    public let artist: String?
    public let compatibilityFindings: [ITCapabilityFinding]
    public let compatibilityWarnings: [String]

    public init(module: Mod) throws {
        var orders: [InspectedOrder] = [], useCounts: [Int: Int] = [:]
        for (position, pattern) in module.patternTable.prefix(max(0, module.length)).enumerated() {
            try Task.checkCancellation()
            let rows = module.patterns.indices.contains(pattern) ? module.patterns[pattern].rows.count : nil
            orders.append(InspectedOrder(position: position, pattern: pattern, rowCount: rows))
            useCounts[pattern, default: 0] += 1
        }
        struct Counter {
            let description: EffectDescription
            var count = 0
            var parameters: Set<Int> = []
        }
        var counts: [String: Counter] = [:]
        var mainDescriptions: [Int: EffectDescription] = [:], volumeDescriptions: [Int: EffectDescription] = [:]
        func add(_ description: EffectDescription, parameter: Int) {
            counts[description.id, default: Counter(description: description)].count += 1
            counts[description.id, default: Counter(description: description)].parameters.insert(parameter)
        }
        for pattern in module.patterns {
            for row in pattern.rows {
                try Task.checkCancellation()
                for note in row.notes {
                    if note.hasEffect {
                        let description = mainDescriptions[note.effectId] ?? EffectDescription.main(format: module.format, id: note.effectId)
                        mainDescriptions[note.effectId] = description
                        add(description, parameter: note.effectData)
                    }
                    if module.format == .xm, note.volCmd > 0 {
                        let description = volumeDescriptions[note.volCmd] ?? EffectDescription.volume(format: .xm, value: note.volCmd)
                        volumeDescriptions[note.volCmd] = description
                        add(description, parameter: note.volCmd)
                    } else if module.format == .it || module.format == .s3m, note.volume >= 0 {
                        let description = volumeDescriptions[note.volume] ?? EffectDescription.volume(format: module.format, value: note.volume)
                        volumeDescriptions[note.volume] = description
                        add(description, parameter: note.volume)
                    }
                }
            }
        }
        self.orders = orders
        patternUseCounts = useCounts
        effects = counts.values.map { item in
            let description = item.description
            return InspectedEffect(id: description.id, code: description.code, title: description.title,
                                   detail: description.detail, count: item.count, parameters: item.parameters.sorted(),
                                   isVolumeColumn: description.volumeColumn, implemented: description.implemented)
        }.sorted { ($0.isVolumeColumn ? 1 : 0, $0.code, $0.id) < ($1.isVolumeColumn ? 1 : 0, $1.code, $1.id) }
        instrumentIndices = module.instruments.indices.dropFirst().filter { module.instruments[$0] != nil }
        sampleCount = module.format == .it ? max(0, module.samplePool.count - 1)
            : module.instruments.compactMap { $0 }.reduce(0) { $0 + $1.samples.count }
        tracker = module.itProperties?.trackerIdentity?.displayName
        let artist = module.itProperties?.openMPTExtensions?.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist?.isEmpty == false ? artist : nil
        compatibilityFindings = module.itProperties?.capabilityReport?.findings.filter(\.detected) ?? []
        compatibilityWarnings = module.compatibilityWarnings
    }
}

public struct EnvelopeInspection: Sendable {
    public let envelope: Envelope
    public let lastTick: Int
    public let sustainTicks: ClosedRange<Int>?
    public let loopTicks: ClosedRange<Int>?

    public init(envelope: Envelope) {
        self.envelope = envelope
        lastTick = max(1, envelope.points.map(\.frame).max() ?? 0)
        func ticks(_ first: Int, _ last: Int, enabled: Bool) -> ClosedRange<Int>? {
            guard enabled, first <= last, envelope.points.indices.contains(first), envelope.points.indices.contains(last) else { return nil }
            let lower = envelope.points[first].frame, upper = envelope.points[last].frame
            guard lower >= 0, lower <= upper else { return nil }
            return lower...upper
        }
        sustainTicks = ticks(envelope.sustainStart, envelope.sustainEnd, enabled: envelope.sustainEnabled)
        loopTicks = ticks(envelope.loopStart, envelope.loopEnd, enabled: envelope.loopEnabled)
    }
}

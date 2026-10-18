import Foundation

public struct InspectedSample: Identifiable, Sendable {
    public let id: String
    public let number: Int
    public let instrumentIndex: Int?
    public let sample: Sample?
}

public struct SampleKeyZone: Identifiable, Sendable, Equatable {
    public var id: Int { sourceNotes.lowerBound }
    public let sourceNotes: ClosedRange<Int>
    public let targetNotes: ClosedRange<Int>
    public let sampleID: String?
    public let sampleNumber: Int?
}

public struct InspectedInstrument: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let sampleIDs: [String]
    public let keyZones: [SampleKeyZone]
}

public struct SampleInspection: Sendable {
    public let samples: [InspectedSample]
    public let instruments: [InspectedInstrument]

    public init(module: Mod) {
        var samples: [InspectedSample] = []
        var instruments: [InspectedInstrument] = []
        if module.format == .it {
            for index in module.samplePool.indices.dropFirst() {
                samples.append(InspectedSample(id: "pool-\(index)", number: index,
                                               instrumentIndex: nil, sample: module.samplePool[index]))
            }
        }
        for index in module.instruments.indices.dropFirst() {
            guard let instrument = module.instruments[index] else { continue }
            var ids: [String] = []
            var keys: [(Int, String?, Int?)] = []
            if module.format == .it, let mapping = instrument.noteSampleMapping {
                for entry in mapping.entries {
                    let available = entry.sampleID > 0 && module.samplePool.indices.contains(entry.sampleID)
                    let id = available ? "pool-\(entry.sampleID)" : nil
                    if let id, !ids.contains(id) { ids.append(id) }
                    keys.append((entry.targetNote, id, entry.sampleID > 0 ? entry.sampleID : nil))
                }
            } else if module.format == .it {
                let id = "pool-\(index)"
                if module.samplePool.indices.contains(index) { ids = [id] }
            } else {
                for sampleIndex in instrument.samples.indices {
                    let id = "instrument-\(index)-\(sampleIndex)"
                    ids.append(id)
                    samples.append(InspectedSample(id: id, number: sampleIndex + 1,
                                                   instrumentIndex: index, sample: instrument.samples[sampleIndex]))
                }
                for note in instrument.keymap.indices.prefix(96) {
                    let sampleIndex = Int(instrument.keymap[note])
                    let available = ids.indices.contains(sampleIndex)
                    keys.append((note, available ? ids[sampleIndex] : nil, available ? sampleIndex + 1 : nil))
                }
            }
            instruments.append(InspectedInstrument(id: index, name: instrument.name,
                                                   sampleIDs: ids, keyZones: Self.zones(keys)))
        }
        self.samples = samples
        self.instruments = instruments
    }

    private static func zones(_ keys: [(Int, String?, Int?)]) -> [SampleKeyZone] {
        var result: [SampleKeyZone] = []
        for (source, entry) in keys.enumerated() {
            if let previous = result.last,
               previous.sampleID == entry.1, previous.sampleNumber == entry.2,
               previous.targetNotes.upperBound + 1 == entry.0 {
                result[result.count - 1] = SampleKeyZone(sourceNotes: previous.sourceNotes.lowerBound...source,
                    targetNotes: previous.targetNotes.lowerBound...entry.0,
                    sampleID: entry.1, sampleNumber: entry.2)
            } else {
                result.append(SampleKeyZone(sourceNotes: source...source, targetNotes: entry.0...entry.0,
                                             sampleID: entry.1, sampleNumber: entry.2))
            }
        }
        return result
    }

    public static func noteName(_ note: Int) -> String {
        guard (0..<120).contains(note) else { return "—" }
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[note % 12])-\(note / 12)"
    }
}

public struct SampleFrameRange: Sendable, Equatable, Hashable {
    public let lowerBound: Int
    public let upperBound: Int
    public var count: Int { upperBound - lowerBound }

    public init(frameCount: Int, zoom: Int = 1, position: Double = 0) {
        let total = max(0, frameCount)
        let width = total == 0 ? 0 : max(1, total / max(1, min(64, zoom)))
        let fraction = position.isFinite ? max(0, min(1, position)) : 0
        let start = Int((Double(total - width) * fraction).rounded())
        lowerBound = start
        upperBound = start + width
    }

    public init(frameCount: Int, start: Int, length: Int) {
        let total = max(0, frameCount)
        let lower = min(total, max(0, start))
        lowerBound = lower
        upperBound = lower + min(total - lower, max(0, length))
    }
}

public struct SampleWaveform: Sendable {
    public struct Peak: Sendable, Equatable {
        public let minimum: Float
        public let maximum: Float
    }
    public let range: SampleFrameRange
    public let left: [Peak]
    public let right: [Peak]?

    public static func make(sample: Sample, range: SampleFrameRange, maximumBins: Int = 1600) throws -> Self {
        let safe = SampleFrameRange(frameCount: sample.pcm.count, start: range.lowerBound, length: range.count)
        let bins = min(safe.count, max(1, min(4096, maximumBins)))
        func peaks(_ pcm: [Float]) throws -> [Peak] {
            var result: [Peak] = []
            result.reserveCapacity(bins)
            guard bins > 0 else { return result }
            for bin in 0..<bins {
                try Task.checkCancellation()
                let first = safe.lowerBound + bin * safe.count / bins
                let last = safe.lowerBound + (bin + 1) * safe.count / bins
                var minimum = Float.greatestFiniteMagnitude, maximum = -Float.greatestFiniteMagnitude
                var hasValue = false
                for index in first..<last where pcm.indices.contains(index) {
                    if index & 4095 == 0 { try Task.checkCancellation() }
                    let value = pcm[index].isFinite ? min(1, max(-1, pcm[index])) : 0
                    minimum = min(minimum, value)
                    maximum = max(maximum, value)
                    hasValue = true
                }
                result.append(Peak(minimum: hasValue ? minimum : 0, maximum: hasValue ? maximum : 0))
            }
            return result
        }
        return try Self(range: safe, left: peaks(sample.pcm), right: sample.rightPCM.map { try peaks($0) })
    }
}

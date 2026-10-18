import XCTest
@testable import SavageModPlayerCore

final class SampleInspectionTests: XCTestCase {
    private func sample(_ values: [Float], right: [Float]? = nil) -> Sample {
        Sample(pcm: values, loopStart: 1, loopLength: 2, loopType: .pingpong,
               volume: 48, finetune: -2, rightPCM: right,
               sustainLoop: SampleLoop(start: 0, length: 1, type: .forward))
    }
    private func module(format: ModuleFormat, instruments: [Instrument?], pool: [Sample?] = [nil]) -> Mod {
        Mod(name: "Inspection", length: 0, patternTable: [], instruments: instruments,
            samplePool: pool, patterns: [], format: format)
    }

    func testXMIncludesUnmappedSamplesAndMergesOnlyContinuousKeyRanges() {
        let instrument = Instrument(index: 1, name: "Multi", samples: [sample([0.1]), sample([0.2]), sample([])],
                                    keymap: (0..<96).map { $0 < 48 ? 0 : 1 })
        let inspection = SampleInspection(module: module(format: .xm, instruments: [nil, instrument]))
        XCTAssertEqual(inspection.samples.count, 3)
        XCTAssertEqual(inspection.instruments[0].sampleIDs.count, 3)
        let zones = inspection.instruments[0].keyZones
        XCTAssertEqual(zones.map(\.sourceNotes), [0...47, 48...95])
        XCTAssertEqual(zones.map(\.sampleNumber), [1, 2])
        XCTAssertEqual(SampleInspection.noteName(48), "C-4")
        XCTAssertEqual(SampleInspection.noteName(119), "B-9")
        let single = SampleInspection(module: module(format: .protracker, instruments: [nil,
            Instrument(index: 1, name: "Single", samples: [sample([0.1])])]))
        XCTAssertTrue(single.instruments[0].keyZones.isEmpty, "Keine erfundene Tastentabelle für MOD")
    }

    func testITUsesGlobalPoolAndPreservesTransposedAndUnassignedKeys() throws {
        let mapping = try NoteSampleMapping(entries: (0..<120).map { note in
            try .init(targetNote: note < 12 ? note + 12 : note, sampleID: note < 12 ? 2 : 0)
        })
        let instrument = Instrument(index: 1, name: "IT", samples: [], noteSampleMapping: mapping)
        let inspection = SampleInspection(module: module(format: .it, instruments: [nil, instrument],
                                                         pool: [nil, sample([0.1]), sample([0.2]), nil]))
        XCTAssertEqual(inspection.samples.map(\.id), ["pool-1", "pool-2", "pool-3"])
        XCTAssertNil(inspection.samples.last?.sample)
        XCTAssertEqual(inspection.instruments[0].sampleIDs, ["pool-2"])
        XCTAssertEqual(inspection.instruments[0].keyZones[0].sourceNotes, 0...11)
        XCTAssertEqual(inspection.instruments[0].keyZones[0].targetNotes, 12...23)
        XCTAssertNil(inspection.instruments[0].keyZones[1].sampleID)
    }

    func testViewportKeepsBothEdgesAndClampsMalformedLoopBounds() {
        XCTAssertEqual(SampleFrameRange(frameCount: 100, zoom: 4, position: 0).lowerBound, 0)
        let end = SampleFrameRange(frameCount: 100, zoom: 4, position: 1)
        XCTAssertEqual(end.lowerBound, 75)
        XCTAssertEqual(end.upperBound, 100)
        XCTAssertEqual(SampleFrameRange(frameCount: 0).count, 0)
        XCTAssertEqual(SampleFrameRange(frameCount: 1, zoom: 64).count, 1)
        let clipped = SampleFrameRange(frameCount: 20, start: 18, length: .max)
        XCTAssertEqual(clipped.lowerBound, 18)
        XCTAssertEqual(clipped.upperBound, 20)
        XCTAssertEqual(SampleFrameRange(frameCount: 20, start: .max, length: .max).count, 0)
        XCTAssertEqual(SampleFrameRange(frameCount: 20, zoom: 2, position: .nan).lowerBound, 0)
    }

    func testWaveformRetainsNarrowPeaksAndBothStereoChannelsAcrossZoom() throws {
        var left = [Float](repeating: 0.2, count: 10_000)
        left[1234] = -0.5; left[9999] = 0.5
        var right = [Float](repeating: -0.1, count: 10_000)
        right[1234] = 0.4
        let sound = sample(left, right: right)
        let waveform = try SampleWaveform.make(sample: sound, range: .init(frameCount: left.count), maximumBins: 100)
        XCTAssertEqual(waveform.left.count, 100)
        XCTAssertEqual(waveform.left[0].minimum, 0.2)
        XCTAssertEqual(waveform.left[12].minimum, -0.5)
        XCTAssertEqual(waveform.right?[12].maximum, 0.4)
        XCTAssertEqual(waveform.left.last?.maximum, 0.5)
        let zoomed = try SampleWaveform.make(sample: sound, range: .init(frameCount: left.count, zoom: 64, position: 1))
        XCTAssertEqual(zoomed.left.last?.maximum, 0.5)
        XCTAssertEqual(try SampleWaveform.make(sample: sample([]), range: .init(frameCount: 0)).left.count, 0)
    }

    func testWaveformCancellationAndNonFiniteValuesAreSafe() async throws {
        let sound = sample([.nan, .infinity, -.infinity, 0.4])
        let result = try SampleWaveform.make(sample: sound, range: .init(frameCount: 4), maximumBins: 4)
        XCTAssertEqual(result.left.map(\.maximum), [0, 0, 0, 0.4])
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try SampleWaveform.make(sample: sound, range: .init(frameCount: 4))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled waveform completed") }
        catch is CancellationError { }
    }
}

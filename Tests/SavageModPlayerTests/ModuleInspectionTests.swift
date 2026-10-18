import XCTest
@testable import SavageModPlayerCore

final class ModuleInspectionTests: XCTestCase {
    private func note(_ effect: Int, _ data: Int = 0, present: Bool? = nil, volume: Int = -1, volCmd: Int = 0) -> Note {
        Note(instrument: 0, period: 0, effectId: effect, effectData: data, volume: volume, volCmd: volCmd, effectPresent: present)
    }
    func testRepeatedOrdersAndUnreferencedPatternsDoNotMultiplyStaticEffectCounts() throws {
        let p0 = Pattern(rows: [Row(notes: [note(0x0C, present: true), note(0, present: false)])])
        let p1 = Pattern(rows: [Row(notes: [note(ModuleEffect.keyOff, 4)])])
        let mod = Mod(name: "Static", length: 3, patternTable: [0, 0, 1], instruments: [nil], patterns: [p0, p1], format: .xm)
        let result = try ModuleInspection(module: mod)
        XCTAssertEqual(result.orders.map(\.pattern), [0, 0, 1])
        XCTAssertEqual(result.patternUseCounts[0], 2)
        XCTAssertEqual(result.effects.count, 2)
        XCTAssertEqual(result.effects.first { $0.code == "Cxx" }?.count, 1)
        XCTAssertEqual(result.effects.first { $0.code == "Cxx" }?.parameters, [0])
    }
    func testFormatSpecificCodesAndVolumeColumnsRemainDistinct() throws {
        XCTAssertEqual(EffectDescription.main(format: .xm, id: ModuleEffect.tremor).code, "Txy")
        XCTAssertEqual(EffectDescription.main(format: .s3m, id: ModuleEffect.tremor).code, "Ixy")
        XCTAssertEqual(EffectDescription.main(format: .it, id: ModuleEffect.impulseTrackerCommand(20)).code, "Txx")
        XCTAssertFalse(EffectDescription.main(format: .protracker, id: 0xEF).implemented)
        let pattern = Pattern(rows: [Row(notes: [note(0x0C, 10, volCmd: 0x84), note(0, present: false, volCmd: 0x80)])])
        let mod = Mod(name: "Columns", length: 1, patternTable: [0], instruments: [nil], patterns: [pattern], format: .xm)
        let result = try ModuleInspection(module: mod)
        XCTAssertEqual(result.effects.filter(\.isVolumeColumn).count, 1)
        XCTAssertEqual(result.effects.first { $0.isVolumeColumn }?.count, 2)
        XCTAssertEqual(result.effects.first { $0.isVolumeColumn }?.parameters, [0x80, 0x84])
        XCTAssertTrue(EffectDescription.volume(format: .it, value: 223).implemented)
        XCTAssertFalse(EffectDescription.volume(format: .it, value: 213).implemented)
        let s3m = Mod(name: "Volume", length: 1, patternTable: [0], instruments: [nil],
                      patterns: [Pattern(rows: [Row(notes: [note(0, present: false, volume: 0)])])], format: .s3m)
        XCTAssertEqual(try ModuleInspection(module: s3m).effects.first?.parameters, [0])
        XCTAssertTrue(try ModuleInspection(module: s3m).effects.first?.isVolumeColumn == true)
    }
    func testEnvelopeRangesUsePointTicksAndRejectInvalidIndices() {
        let points = [EnvelopePoint(frame: 0, value: 64), .init(frame: 5, value: 32), .init(frame: 20, value: 0)]
        let envelope = Envelope(points: points, sustainStart: 1, sustainEnd: 1, loopStart: 0, loopEnd: 2,
                                sustainEnabled: true, loopEnabled: true, carryEnabled: true, valueMode: .filter)
        let result = EnvelopeInspection(envelope: envelope)
        XCTAssertEqual(result.lastTick, 20)
        XCTAssertEqual(result.sustainTicks, 5...5)
        XCTAssertEqual(result.loopTicks, 0...20)
        let invalid = Envelope(points: points, sustainPoint: 100, loopStart: -1, loopEnd: 1,
                               sustainEnabled: true, loopEnabled: true)
        XCTAssertNil(EnvelopeInspection(envelope: invalid).sustainTicks)
        XCTAssertNil(EnvelopeInspection(envelope: invalid).loopTicks)
    }
    func testArtistComesOnlyFromExplicitMetadataAndFindingsPreserveUsage() throws {
        let finding = ITCapabilityFinding(feature: .pluginInstrument, identifier: "plugin-1", detected: true,
                                          used: true, support: .unsupported, detail: "Plugin", warning: "No plugin output")
        let properties = ITModuleProperties(createdWithVersion: 0x214, compatibleWithVersion: 0x214,
            usesInstruments: true, stereo: true, volumeZeroMixOptimization: false, linearSlides: false,
            patternHighlight: 0, mixVolume: 128, panSeparation: 128, pitchWheelDepth: 0,
            hasSongMessage: false, songMessageLength: 0, songMessageOffset: 0,
            usesMIDIPitchController: false, hasEmbeddedMIDIConfiguration: false, unknownHeaderFlags: 0, unknownSpecialFlags: 0,
            trackerIdentity: ITTrackerIdentity(family: .impulseTracker, rawCreatedWith: 0x214, displayName: "Impulse Tracker 2.14"),
            openMPTExtensions: ITOpenMPTExtensions(artist: "  Explicit artist  "), capabilityReport: ITCapabilityReport(findings: [finding]))
        let instrument = Instrument(index: 1, name: "Copyright / someone", samples: [])
        let mod = Mod(name: "Metadata", length: 0, patternTable: [], instruments: [nil, instrument], patterns: [], format: .it, itProperties: properties)
        let result = try ModuleInspection(module: mod)
        XCTAssertEqual(result.artist, "Explicit artist")
        XCTAssertEqual(result.tracker, "Impulse Tracker 2.14")
        XCTAssertEqual(result.compatibilityFindings, [finding])
        XCTAssertEqual(result.compatibilityWarnings, ["No plugin output"])
        let plain = Mod(name: "Metadata", length: 0, patternTable: [], instruments: [nil, instrument], patterns: [])
        XCTAssertNil(try ModuleInspection(module: plain).artist)
    }
    func testCancelledInspectionThrowsBeforeScanningPatterns() async {
        let mod = Mod(name: "Cancelled", length: 1, patternTable: [0], instruments: [nil], patterns: [Pattern(rows: [])])
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try ModuleInspection(module: mod)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled inspection completed") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}

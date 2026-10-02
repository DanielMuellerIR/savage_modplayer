#if canImport(AVFoundation) && canImport(Combine)
import AVFoundation
import XCTest
@testable import SavageModPlayerCore

final class InstrumentExportTests: XCTestCase {
    @MainActor
    func testStereoSampleExportPreservesBothChannels() throws {
        let sample = Sample(pcm: [0, 0, 0, 0], loopStart: 0, loopLength: 0, loopType: .none,
                            volume: 64, finetune: 0, rightPCM: [0.25, -0.5, 0.75, -1])
        let instrument = Instrument(index: 1, name: "stereo", samples: [sample])
        let mod = Mod(name: "stereo export", length: 1, patternTable: [0],
                      instruments: [nil, instrument],
                      patterns: [Pattern(rows: [Row(notes: [Note(instrument: 0, period: 0, effectId: 0, effectData: 0)])])],
                      channelCount: 1, format: .it)
        let coordinator = ModPlayerCoordinator()
        coordinator.setMod(mod)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("sample-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: destination) }
        try coordinator.exportInstrumentToWav(index: 1, destinationURL: destination)
        let file = try AVAudioFile(forReading: destination)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4))
        try file.read(into: buffer)
        XCTAssertEqual(buffer.frameLength, 4)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: channels[0], count: 4)), sample.pcm)
        if file.processingFormat.channelCount == 2 {
            XCTAssertEqual(Array(UnsafeBufferPointer(start: channels[1], count: 4)), sample.rightPCM)
        }
    }
}
#endif

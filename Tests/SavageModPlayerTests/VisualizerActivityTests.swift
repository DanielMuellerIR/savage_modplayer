import XCTest
@testable import SavageModPlayerCore

final class VisualizerActivityTests: XCTestCase {
    func testHiddenVisualizerDoesNotCaptureOrPublishAndPreservesAudio() {
        let mod = ModParser.generateDemoMod()
        let rate = 44_100.0
        let visible = RealtimeVisualizationExchange(channelCapacity: mod.channelCount)
        let hidden = RealtimeVisualizationExchange(channelCapacity: mod.channelCount)
        let visibleState = RenderEngine.makeRenderState(for: mod, sampleRate: rate)
        let hiddenState = RenderEngine.makeRenderState(for: mod, sampleRate: rate)
        let visibleBlock = RenderEngine.createRenderBlock(state: visibleState,
            vuBuffer: visible.makeVUBuffer(), waveBuffer: visible.makeWaveBuffer(),
            dspChannels: RenderEngine.makeRenderChannels(for: mod), mod: mod, sampleRate: rate)
        let hiddenBlock = RenderEngine.createRenderBlock(state: hiddenState,
            vuBuffer: hidden.makeVUBuffer(), waveBuffer: hidden.makeWaveBuffer(),
            dspChannels: RenderEngine.makeRenderChannels(for: mod), mod: mod, sampleRate: rate)
        let first = StereoRenderBuffer(capacity: 512)
        let second = StereoRenderBuffer(capacity: 512)
        let hiddenWaves = hidden.makeWaveBuffer()
        hiddenWaves.channelWavesPointer.update(repeating: 42, count: mod.channelCount * 32)
        hiddenWaves.masterWavesPointer.update(repeating: 42, count: 128)
        hidden.isEnabled = false
        for _ in 0..<100 {
            visibleBlock(512, first.left, first.right)
            hiddenBlock(512, second.left, second.right)
            XCTAssertEqual(Array(UnsafeBufferPointer(start: first.left, count: 512)),
                           Array(UnsafeBufferPointer(start: second.left, count: 512)))
            XCTAssertEqual(Array(UnsafeBufferPointer(start: first.right, count: 512)),
                           Array(UnsafeBufferPointer(start: second.right, count: 512)))
        }
        XCTAssertFalse(hidden.withLatestSnapshot(channelCount: mod.channelCount) { _, _, _ in })
        XCTAssertEqual(Array(UnsafeBufferPointer(start: hiddenWaves.channelWavesPointer,
            count: mod.channelCount * 32)), Array(repeating: 42, count: mod.channelCount * 32))
        XCTAssertEqual(Array(UnsafeBufferPointer(start: hiddenWaves.masterWavesPointer, count: 128)),
                       Array(repeating: 42, count: 128))
        XCTAssertEqual(hiddenState.waveWriteIndex, 0)
        hidden.isEnabled = true
        hiddenBlock(512, second.left, second.right)
        XCTAssertTrue(hidden.withLatestSnapshot(channelCount: mod.channelCount) { _, waves, master in
            XCTAssertFalse(UnsafeBufferPointer(start: waves, count: mod.channelCount * 32).contains(42))
            XCTAssertFalse(UnsafeBufferPointer(start: master, count: 128).contains(42))
        })
    }

    @MainActor
    func testDesktopDefaultsTo60AndCompactDropsAllVisualizerBuffers() async {
        let player = ModPlayerCoordinator()
        XCTAssertEqual(player.visualizerFrameRate, 60)
        player.setMod(ModParser.generateDemoMod())
        XCTAssertFalse(player.visualizerState.channelWaveforms.isEmpty)
        player.visualizersVisible = false
        XCTAssertTrue(player.visualizerState.channelWaveforms.isEmpty)
        XCTAssertTrue(player.visualizerState.masterSamples.isEmpty)
        XCTAssertTrue(player.visualizerState.vuLevels.isEmpty)
    }
}

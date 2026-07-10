import Foundation
import XCTest
@testable import SavageModPlayerCore

/// Regressionen fuer den blockweisen Float-/Stem-Capture des Offline-Renderers.
/// Die Fixture ist absichtlich kurz und geloopt: Der Renderer liefert mehrere
/// feste Bloecke, ohne songlange Stem-Puffer anzulegen.
final class ModuleRendererFloatCaptureTests: XCTestCase {

    private func makeCaptureMod() -> Mod {
        let leftInstrument = Instrument(
            index: 1, name: "left", length: 4, finetune: 0, volume: 64,
            repeatOffset: 0, repeatLength: 4,
            bytes: [Int8](repeating: 20, count: 4), isLooped: true)
        let rightInstrument = Instrument(
            index: 2, name: "right", length: 4, finetune: 0, volume: 64,
            repeatOffset: 0, repeatLength: 4,
            bytes: [Int8](repeating: 40, count: 4), isLooped: true)
        let row = Row(notes: [
            Note(instrument: 1, period: 428, effectId: 0, effectData: 0),
            Note(instrument: 2, period: 428, effectId: 0, effectData: 0)
        ])
        return Mod(
            name: "float-capture",
            length: 1,
            patternTable: [0],
            instruments: [nil, leftInstrument, rightInstrument],
            patterns: [Pattern(rows: [row])],
            channelCount: 2,
            channelPannings: [0.0, 1.0]
        )
    }

    private func pcmInt16(_ wav: Data, frame: Int, channel: Int) -> Int {
        let offset = 44 + frame * 4 + channel * 2
        let bits = UInt16(wav[offset]) | (UInt16(wav[offset + 1]) << 8)
        return Int(Int16(bitPattern: bits))
    }

    func testBlockCaptureReconstructsRawMixAndWAV() throws {
        let mod = makeCaptureMod()
        let baseline = try ModuleRenderer.renderWavData(
            mod: mod, maxDurationSeconds: 0.03, normalize: false)
        var blocks: [RenderCaptureBlock] = []
        let capturedWav = try ModuleRenderer.renderWavDataWithCapture(
            mod: mod, maxDurationSeconds: 0.03, normalize: false) { block in
            blocks.append(block)
        }

        // Capture darf den bisherigen Default-WAV-Pfad byteweise nicht veraendern.
        XCTAssertEqual(capturedWav, baseline)
        XCTAssertEqual(blocks.count, 2, "0,03 s muessen exakt zwei Renderbloecke liefern")
        XCTAssertTrue(blocks.allSatisfy { $0.frameCount == 1024 })
        let capturedFrames = blocks.reduce(0) { $0 + $1.frameCount }
        XCTAssertEqual(capturedFrames, 2048)
        XCTAssertEqual((capturedWav.count - 44) / 4, 2048)
        XCTAssertEqual(capturedFrames, (capturedWav.count - 44) / 4,
                       "Capture und WAV muessen exakt dieselbe Framezahl abdecken")

        // Stereo-Panning: p=0/1 mit Separation 0.8 ergibt effektiv 0.1/0.9.
        // MixGain ist bei zwei Kanaelen 1.0. Die Float-Stems muessen den
        // ungefilterten Mix vor tanh daher exakt rekonstruieren.
        let leftGain: Float = 0.9
        let rightGain: Float = 0.1
        var wavFrame = 0
        for block in blocks {
            XCTAssertEqual(block.channelCount, 2)
            for frame in 0..<block.frameCount {
                let stem0 = block.stems[frame]
                let stem1 = block.stems[block.frameCount + frame]
                XCTAssertGreaterThan(abs(stem0 - stem1), 0.01,
                                     "Die Testkanaele muessen unterscheidbare Stems liefern")

                let expectedLeft = stem0 * leftGain + stem1 * rightGain
                let expectedRight = stem0 * rightGain + stem1 * leftGain
                XCTAssertEqual(block.stereoLeft[frame], expectedLeft, accuracy: 0.000001)
                XCTAssertEqual(block.stereoRight[frame], expectedRight, accuracy: 0.000001)

                // Der Renderer limitiert genau diesen Float-Mix mit tanh und
                // wandelt ihn danach in 16-Bit-PCM. Erlaubt ist maximal 1 LSB.
                let limitedLeft = tanh(expectedLeft)
                let limitedRight = tanh(expectedRight)
                let expectedPCMLeft = Int16(max(-1.0, min(1.0, limitedLeft)) * 32767.0)
                let expectedPCMRight = Int16(max(-1.0, min(1.0, limitedRight)) * 32767.0)
                XCTAssertLessThanOrEqual(abs(pcmInt16(capturedWav, frame: wavFrame, channel: 0)
                                              - Int(expectedPCMLeft)), 1)
                XCTAssertLessThanOrEqual(abs(pcmInt16(capturedWav, frame: wavFrame, channel: 1)
                                              - Int(expectedPCMRight)), 1)
                wavFrame += 1
            }
        }
        XCTAssertEqual(wavFrame, capturedFrames)
    }
}

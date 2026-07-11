import XCTest
@testable import SavageModPlayerCore

final class ITSampleDecompressorTests: XCTestCase {
    func testIT214AndIT215EightBitGoldenVectors() throws {
        let it214 = block(bitValues: [(1, 9), (1, 9), (254, 9)])
        let decoded214 = try ITSampleDecompressor.decompress(
            data: it214, offset: 0, frameCount: 3,
            bitDepth: .eight, stereo: false, version: .it214
        )
        XCTAssertEqual(decoded214.left, [1, 2, 0])
        XCTAssertNil(decoded214.right)
        XCTAssertEqual(decoded214.bytesConsumed, it214.count)

        let it215 = block(bitValues: [(1, 9), (1, 9), (1, 9)])
        let decoded215 = try ITSampleDecompressor.decompress(
            data: it215, offset: 0, frameCount: 3,
            bitDepth: .eight, stereo: false, version: .it215
        )
        XCTAssertEqual(decoded215.left, [1, 3, 6])
    }

    func testIT214AndIT215SixteenBitGoldenVectors() throws {
        let it214 = block(bitValues: [(1, 17), (1, 17), (65_534, 17)])
        XCTAssertEqual(
            try ITSampleDecompressor.decompress(
                data: it214, offset: 0, frameCount: 3,
                bitDepth: .sixteen, stereo: false, version: .it214
            ).left,
            [1, 2, 0]
        )

        let it215 = block(bitValues: [(1, 17), (1, 17), (1, 17)])
        XCTAssertEqual(
            try ITSampleDecompressor.decompress(
                data: it215, offset: 0, frameCount: 3,
                bitDepth: .sixteen, stereo: false, version: .it215
            ).left,
            [1, 3, 6]
        )
    }

    func testAllThreeWidthChangeModes() throws {
        let payload = bitPayload([
            (262, 9), // Modus C: 9 -> 7
            (63, 7),  // Modus B: 7 -> 4
            (1, 4),   // erstes Delta
            (8, 4),   // Modus A-Marker
            (7, 3),   // Modus A: 4 -> 9
            (1, 9),   // zweites Delta
        ])
        let data = lengthPrefixed(payload)
        let result = try ITSampleDecompressor.decompress(
            data: data, offset: 0, frameCount: 2,
            bitDepth: .eight, stereo: false, version: .it214
        )
        XCTAssertEqual(result.left, [1, 2])
    }

    func testStereoUsesIndependentChannelBlocks() throws {
        let left = block(bitValues: [(1, 9), (1, 9), (254, 9)])
        let right = block(bitValues: [(255, 9), (255, 9), (2, 9)])
        let result = try ITSampleDecompressor.decompress(
            data: left + right, offset: 0, frameCount: 3,
            bitDepth: .eight, stereo: true, version: .it214
        )
        XCTAssertEqual(result.left, [1, 2, 0])
        XCTAssertEqual(result.right, [-1, -2, 0])
        XCTAssertEqual(result.bytesConsumed, left.count + right.count)
    }

    func testIntegratorResetsAtBlockBoundary() throws {
        let blockFrames = 32_768
        var firstValues = [(Int, Int)]()
        firstValues.reserveCapacity(blockFrames)
        firstValues.append((1, 9))
        firstValues += Array(repeating: (0, 9), count: blockFrames - 1)
        let first = block(bitValues: firstValues)
        let second = block(bitValues: [(1, 9)])

        let result = try ITSampleDecompressor.decompress(
            data: first + second, offset: 0, frameCount: blockFrames + 1,
            bitDepth: .eight, stereo: false, version: .it214
        )
        XCTAssertEqual(result.left[0], 1)
        XCTAssertEqual(result.left[blockFrames - 1], 1)
        XCTAssertEqual(result.left[blockFrames], 1)
    }

    func testSixteenBitIntegratorResetsAtBlockBoundary() throws {
        let blockFrames = 16_384
        var firstValues = [(Int, Int)]()
        firstValues.reserveCapacity(blockFrames)
        firstValues.append((1, 17))
        firstValues += Array(repeating: (0, 17), count: blockFrames - 1)
        let first = block(bitValues: firstValues)
        let second = block(bitValues: [(1, 17)])

        let result = try ITSampleDecompressor.decompress(
            data: first + second, offset: 0, frameCount: blockFrames + 1,
            bitDepth: .sixteen, stereo: false, version: .it215
        )
        XCTAssertEqual(result.left[0], 1)
        XCTAssertEqual(result.left[blockFrames - 1], Int32(blockFrames))
        XCTAssertEqual(result.left[blockFrames], 1)
    }

    func testDecoderHonorsSampleOffsetInsideLargerData() throws {
        let compressed = block(bitValues: [(1, 9), (1, 9), (254, 9)])
        let prefix = Data(repeating: 0xA5, count: 7)
        let suffix = Data(repeating: 0x5A, count: 5)
        let result = try ITSampleDecompressor.decompress(
            data: prefix + compressed + suffix,
            offset: prefix.count,
            frameCount: 3,
            bitDepth: .eight,
            stereo: false,
            version: .it214
        )

        XCTAssertEqual(result.left, [1, 2, 0])
        XCTAssertEqual(result.bytesConsumed, compressed.count)
    }

    func testMalformedAndMutatedInputsFailWithoutLooping() {
        XCTAssertThrowsError(try ITSampleDecompressor.decompress(
            data: Data([0, 0]), offset: 0, frameCount: 1,
            bitDepth: .eight, stereo: false, version: .it214
        )) {
            XCTAssertEqual($0 as? ITSampleDecompressor.DecompressionError, .invalidBlockLength(0))
        }

        XCTAssertThrowsError(try ITSampleDecompressor.decompress(
            data: Data([5, 0, 1]), offset: 0, frameCount: 1,
            bitDepth: .eight, stereo: false, version: .it214
        )) {
            XCTAssertEqual(
                $0 as? ITSampleDecompressor.DecompressionError,
                .truncatedBlock(expected: 5, available: 1)
            )
        }

        XCTAssertThrowsError(try ITSampleDecompressor.decompress(
            data: lengthPrefixed(Data([1])), offset: 0, frameCount: 8,
            bitDepth: .eight, stereo: false, version: .it214
        )) {
            XCTAssertEqual($0 as? ITSampleDecompressor.DecompressionError, .unexpectedEndOfBlock)
        }

        // Modus C fordert Breite 16 an, obwohl 8-Bit maximal 9 erlaubt.
        let invalidWidth = block(bitValues: [(271, 9)])
        XCTAssertThrowsError(try ITSampleDecompressor.decompress(
            data: invalidWidth, offset: 0, frameCount: 1,
            bitDepth: .eight, stereo: false, version: .it214
        )) {
            XCTAssertEqual($0 as? ITSampleDecompressor.DecompressionError, .invalidBitWidth(16))
        }

        // Jede Kürzung eines gültigen Blocks muss kontrolliert scheitern.
        let valid = block(bitValues: [(1, 9), (1, 9), (1, 9)])
        for length in 0..<valid.count {
            XCTAssertThrowsError(try ITSampleDecompressor.decompress(
                data: valid.prefix(length), offset: 0, frameCount: 3,
                bitDepth: .eight, stereo: false, version: .it214
            ))
        }
    }

    // MARK: - Handprüfbarer LSB-first-Writer für Golden-Vektoren

    private func block(bitValues: [(Int, Int)]) -> Data {
        lengthPrefixed(bitPayload(bitValues))
    }

    private func lengthPrefixed(_ payload: Data) -> Data {
        var data = Data([
            UInt8(truncatingIfNeeded: payload.count),
            UInt8(truncatingIfNeeded: payload.count >> 8),
        ])
        data.append(payload)
        return data
    }

    private func bitPayload(_ values: [(Int, Int)]) -> Data {
        var bytes = [UInt8]()
        var accumulator: UInt64 = 0
        var bitCount = 0

        for (value, width) in values {
            let mask = (UInt64(1) << width) - 1
            accumulator |= (UInt64(value) & mask) << bitCount
            bitCount += width
            while bitCount >= 8 {
                bytes.append(UInt8(truncatingIfNeeded: accumulator))
                accumulator >>= 8
                bitCount -= 8
            }
        }
        if bitCount > 0 {
            bytes.append(UInt8(truncatingIfNeeded: accumulator))
        }
        return Data(bytes)
    }
}

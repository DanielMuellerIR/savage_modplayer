import Foundation

// Isolierte IT214-/IT215-Dekompression. Der Decoder arbeitet ausschließlich auf
// Integer-Samplewerten; Normalisierung und Sample-Metadaten bleiben im ITParser.
public enum ITSampleDecompressor {
    public enum BitDepth: Int, Sendable, Equatable {
        case eight = 8
        case sixteen = 16

        fileprivate var defaultWidth: Int { self == .eight ? 9 : 17 }
        fileprivate var blockFrames: Int { 0x8000 / (rawValue / 8) }
        fileprivate var fetchWidthA: Int { self == .eight ? 3 : 4 }
        fileprivate var lowerB: Int { self == .eight ? -4 : -8 }
        fileprivate var upperB: Int { self == .eight ? 3 : 7 }
    }

    public enum Version: Sendable, Equatable {
        case it214
        case it215
    }

    public struct Result: Sendable, Equatable {
        public let left: [Int32]
        public let right: [Int32]?
        public let bytesConsumed: Int
    }

    public enum DecompressionError: Error, LocalizedError, Equatable {
        case invalidOffset(Int)
        case invalidFrameCount(Int)
        case truncatedBlockHeader
        case invalidBlockLength(Int)
        case truncatedBlock(expected: Int, available: Int)
        case unexpectedEndOfBlock
        case invalidBitWidth(Int)

        public var errorDescription: String? {
            switch self {
            case let .invalidOffset(offset):
                return "Ungültiger IT-Sample-Datenoffset \(offset)."
            case let .invalidFrameCount(count):
                return "Ungültige IT-Sample-Framezahl \(count)."
            case .truncatedBlockHeader:
                return "Abgeschnittener IT-Kompressionsblock-Header."
            case let .invalidBlockLength(length):
                return "Ungültige IT-Kompressionsblocklänge \(length)."
            case let .truncatedBlock(expected, available):
                return "Abgeschnittener IT-Kompressionsblock: \(expected) Bytes erwartet, \(available) vorhanden."
            case .unexpectedEndOfBlock:
                return "IT-Kompressionsblock endet vor allen Samplewerten."
            case let .invalidBitWidth(width):
                return "Ungültige IT-Kompressionsbitbreite \(width)."
            }
        }
    }

    private struct LSBBitReader {
        let bytes: Data
        let base: Data.Index
        var byteOffset = 0
        var bitBuffer: UInt64 = 0
        var availableBits = 0

        init(_ bytes: Data) {
            self.bytes = bytes
            self.base = bytes.startIndex
        }

        mutating func readBits(_ count: Int) throws -> Int {
            guard (1...17).contains(count) else {
                throw DecompressionError.invalidBitWidth(count)
            }
            while availableBits < count {
                guard byteOffset < bytes.count else {
                    throw DecompressionError.unexpectedEndOfBlock
                }
                bitBuffer |= UInt64(bytes[base + byteOffset]) << availableBits
                byteOffset += 1
                availableBits += 8
            }
            let mask = (UInt64(1) << count) - 1
            let value = Int(bitBuffer & mask)
            bitBuffer >>= count
            availableBits -= count
            return value
        }
    }

    public static func decompress(
        data: Data,
        offset: Int,
        frameCount: Int,
        bitDepth: BitDepth,
        stereo: Bool,
        version: Version
    ) throws -> Result {
        guard offset >= 0, offset <= data.count else {
            throw DecompressionError.invalidOffset(offset)
        }
        guard frameCount >= 0 else {
            throw DecompressionError.invalidFrameCount(frameCount)
        }

        var cursor = offset
        let left = try decompressChannel(
            data: data,
            cursor: &cursor,
            frameCount: frameCount,
            bitDepth: bitDepth,
            version: version
        )
        let right = stereo
            ? try decompressChannel(
                data: data,
                cursor: &cursor,
                frameCount: frameCount,
                bitDepth: bitDepth,
                version: version
            )
            : nil
        return Result(left: left, right: right, bytesConsumed: cursor - offset)
    }

    private static func decompressChannel(
        data: Data,
        cursor: inout Int,
        frameCount: Int,
        bitDepth: BitDepth,
        version: Version
    ) throws -> [Int32] {
        var output = [Int32]()
        output.reserveCapacity(frameCount)

        while output.count < frameCount {
            guard cursor <= data.count - 2 else {
                throw DecompressionError.truncatedBlockHeader
            }
            let base = data.startIndex
            let blockLength = Int(data[base + cursor]) | (Int(data[base + cursor + 1]) << 8)
            cursor += 2
            guard blockLength > 0 else {
                throw DecompressionError.invalidBlockLength(blockLength)
            }
            let available = data.count - cursor
            guard blockLength <= available else {
                throw DecompressionError.truncatedBlock(expected: blockLength, available: available)
            }

            let blockStart = data.index(data.startIndex, offsetBy: cursor)
            let blockEnd = data.index(blockStart, offsetBy: blockLength)
            let block = data.subdata(in: blockStart..<blockEnd)
            cursor += blockLength
            let targetFrames = min(frameCount - output.count, bitDepth.blockFrames)
            output += try decompressBlock(
                block,
                frameCount: targetFrames,
                bitDepth: bitDepth,
                version: version
            )
        }
        return output
    }

    private static func decompressBlock(
        _ block: Data,
        frameCount: Int,
        bitDepth: BitDepth,
        version: Version
    ) throws -> [Int32] {
        var reader = LSBBitReader(block)
        var width = bitDepth.defaultWidth
        var firstIntegrator: UInt32 = 0
        var secondIntegrator: UInt32 = 0
        var output = [Int32]()
        output.reserveCapacity(frameCount)

        while output.count < frameCount {
            guard (1...bitDepth.defaultWidth).contains(width) else {
                throw DecompressionError.invalidBitWidth(width)
            }

            let encoded = try reader.readBits(width)
            let topBit = 1 << (width - 1)
            var sampleDelta: Int?

            if width <= 6 {
                // Modus A: eindeutiger Marker, danach 3/4 Bit neue Breite.
                if encoded == topBit {
                    width = try changedWidth(
                        current: width,
                        encoded: reader.readBits(bitDepth.fetchWidthA),
                        maximum: bitDepth.defaultWidth
                    )
                } else {
                    sampleDelta = signExtended(encoded, topBit: topBit)
                }
            } else if width < bitDepth.defaultWidth {
                // Modus B: ein kleiner Wertebereich um das Vorzeichenbit ist
                // für Breitenwechsel reserviert.
                let markerStart = topBit + bitDepth.lowerB
                let markerEnd = topBit + bitDepth.upperB
                if (markerStart...markerEnd).contains(encoded) {
                    width = try changedWidth(
                        current: width,
                        encoded: encoded - markerStart,
                        maximum: bitDepth.defaultWidth
                    )
                } else {
                    sampleDelta = signExtended(encoded, topBit: topBit)
                }
            } else {
                // Modus C: Breite 9/17 besitzt ein zusätzliches Markerbit.
                if encoded & topBit != 0 {
                    let newWidth = (encoded & ~topBit) + 1
                    guard (1...bitDepth.defaultWidth).contains(newWidth) else {
                        throw DecompressionError.invalidBitWidth(newWidth)
                    }
                    width = newWidth
                } else {
                    sampleDelta = encoded & ~topBit
                }
            }

            guard let sampleDelta else { continue }
            firstIntegrator &+= UInt32(bitPattern: Int32(sampleDelta))
            secondIntegrator &+= firstIntegrator
            let integrated = version == .it215 ? secondIntegrator : firstIntegrator
            if bitDepth == .eight {
                output.append(Int32(Int8(bitPattern: UInt8(truncatingIfNeeded: integrated))))
            } else {
                output.append(Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: integrated))))
            }
        }
        return output
    }

    private static func changedWidth(
        current: Int,
        encoded: Int,
        maximum: Int
    ) throws -> Int {
        var width = encoded + 1
        if width >= current { width += 1 }
        guard (1...maximum).contains(width) else {
            throw DecompressionError.invalidBitWidth(width)
        }
        return width
    }

    private static func signExtended(_ value: Int, topBit: Int) -> Int {
        value & topBit != 0 ? value - (topBit << 1) : value
    }
}

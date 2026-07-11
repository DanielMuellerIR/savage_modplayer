import XCTest
@testable import SavageModPlayerCore

final class ITInstrumentParserTests: XCTestCase {
    func testModernInstrumentParsesMappingPropertiesAndAllEnvelopes() throws {
        var instrument = modernInstrument()
        instrument[0x11] = 3 // NNA Fade
        instrument[0x12] = 2 // DCT Sample
        instrument[0x13] = 1 // DCA Off
        putWord(257, at: 0x14, in: &instrument)
        instrument[0x16] = UInt8(bitPattern: -12)
        instrument[0x17] = 60
        instrument[0x18] = 96
        instrument[0x19] = 48
        instrument[0x1A] = 120 // OpenMPT-kompatibel auf 100 begrenzen
        instrument[0x1B] = 80  // OpenMPT-kompatibel auf 64 begrenzen
        instrument[0x3A] = 0x80 | 70
        instrument[0x3B] = 0x80 | 23

        for note in 0..<120 {
            instrument[0x40 + note * 2] = UInt8(note == 7 ? 255 : 119 - note)
            instrument[0x41 + note * 2] = UInt8((note % 99) + 1)
        }
        writeEnvelope(
            at: 0x130, flags: 0x0F,
            points: [(0, 64), (4, 48), (8, 0)],
            loop: (0, 2), sustain: (1, 2), in: &instrument
        )
        writeEnvelope(
            at: 0x182, flags: 0x09,
            points: [(0, -32), (5, 0), (10, 32)], in: &instrument
        )
        writeEnvelope(
            at: 0x1D4, flags: 0x81,
            points: [(0, -8), (6, 12)], in: &instrument
        )

        let module = try ITParser.parse(data: makeIT(instrument: instrument))
        let parsed = try XCTUnwrap(module.instruments[1])
        XCTAssertEqual(parsed.name, "Modern Instrument")
        XCTAssertEqual(parsed.fadeout, 257 << 5)
        XCTAssertEqual(parsed.samples.count, 0)

        let properties = try XCTUnwrap(parsed.itProperties)
        XCTAssertEqual(properties.newNoteAction, .noteFade)
        XCTAssertEqual(properties.duplicateCheckType, .sample)
        XCTAssertEqual(properties.duplicateCheckAction, .noteOff)
        XCTAssertEqual(properties.globalVolume, 96)
        XCTAssertEqual(properties.defaultPanning, 48)
        XCTAssertEqual(properties.pitchPanSeparation, -12)
        XCTAssertEqual(properties.pitchPanCenter, 60)
        XCTAssertEqual(properties.randomVolumeVariation, 100)
        XCTAssertEqual(properties.randomPanningVariation, 64)
        XCTAssertEqual(properties.initialFilterCutoff, 70)
        XCTAssertEqual(properties.initialFilterResonance, 23)

        let mapping = try XCTUnwrap(parsed.noteSampleMapping)
        XCTAssertEqual(mapping.entry(forSourceNote: 0)?.targetNote, 119)
        XCTAssertEqual(mapping.entry(forSourceNote: 0)?.sampleID, 1)
        XCTAssertEqual(mapping.entry(forSourceNote: 7)?.targetNote, 7, "ungültige Zielnote fällt auf die Quellnote zurück")
        XCTAssertEqual(mapping.entry(forSourceNote: 119)?.sampleID, 21)

        let volume = try XCTUnwrap(parsed.volumeEnvelope)
        XCTAssertEqual(volume.points, [
            EnvelopePoint(frame: 0, value: 64),
            EnvelopePoint(frame: 4, value: 48),
            EnvelopePoint(frame: 8, value: 0),
        ])
        XCTAssertTrue(volume.loopEnabled)
        XCTAssertTrue(volume.sustainEnabled)
        XCTAssertTrue(volume.carryEnabled)
        XCTAssertEqual(volume.sustainStart, 1)
        XCTAssertEqual(volume.sustainEnd, 2)

        let pan = try XCTUnwrap(parsed.panningEnvelope)
        XCTAssertEqual(pan.points.map(\.value), [0, 32, 64])
        XCTAssertTrue(pan.carryEnabled)
        XCTAssertEqual(pan.valueMode, .standard)

        let filter = try XCTUnwrap(parsed.pitchEnvelope)
        XCTAssertEqual(filter.points.map(\.value), [24, 44])
        XCTAssertEqual(filter.valueMode, .filter)
    }

    func testModernDisabledPanAndPitchEnvelopeArePreservedSemantically() throws {
        var instrument = modernInstrument()
        instrument[0x19] = 0x80 | 17
        writeEnvelope(
            at: 0x1D4, flags: 0x01,
            points: [(0, -32), (3, 32)], in: &instrument
        )
        let parsed = try XCTUnwrap(try ITParser.parse(data: makeIT(instrument: instrument)).instruments[1])
        XCTAssertNil(parsed.itProperties?.defaultPanning)
        XCTAssertEqual(parsed.pitchEnvelope?.valueMode, .pitch)
        XCTAssertEqual(parsed.pitchEnvelope?.points.map(\.value), [0, 64])
        XCTAssertNil(parsed.volumeEnvelope)
        XCTAssertNil(parsed.panningEnvelope)
    }

    func testOldInstrumentParsesSeparateLayout() throws {
        var instrument = oldInstrument()
        instrument[0x11] = 0x07
        instrument[0x12] = 0
        instrument[0x13] = 2
        instrument[0x14] = 1
        instrument[0x15] = 2
        putWord(77, at: 0x18, in: &instrument)
        instrument[0x1A] = 2
        instrument[0x1B] = 1
        for note in 0..<120 {
            instrument[0x40 + note * 2] = UInt8(note)
            instrument[0x41 + note * 2] = UInt8(note % 3)
        }
        let nodes = [(0, 64), (3, 40), (9, 0)]
        for (index, point) in nodes.enumerated() {
            instrument[0x1F8 + index * 2] = UInt8(point.0)
            instrument[0x1F9 + index * 2] = UInt8(point.1)
        }
        instrument[0x1F8 + nodes.count * 2] = 0xFF

        let module = try ITParser.parse(data: makeIT(
            instrument: instrument, compatibleWithVersion: 0x01FF
        ))
        let parsed = try XCTUnwrap(module.instruments[1])
        XCTAssertEqual(parsed.name, "Old Instrument")
        XCTAssertEqual(parsed.fadeout, 77 << 6)
        XCTAssertEqual(parsed.itProperties?.newNoteAction, .noteOff)
        XCTAssertEqual(parsed.itProperties?.duplicateCheckType, .note)
        XCTAssertEqual(parsed.itProperties?.duplicateCheckAction, .cut)
        XCTAssertEqual(parsed.itProperties?.globalVolume, 128)
        XCTAssertNil(parsed.itProperties?.defaultPanning)
        XCTAssertEqual(parsed.volumeEnvelope?.points.map(\.frame), [0, 3, 9])
        XCTAssertEqual(parsed.volumeEnvelope?.points.map(\.value), [64, 40, 0])
        XCTAssertTrue(parsed.volumeEnvelope?.loopEnabled == true)
        XCTAssertTrue(parsed.volumeEnvelope?.sustainEnabled == true)
        XCTAssertNil(parsed.panningEnvelope)
        XCTAssertNil(parsed.pitchEnvelope)
    }

    func testMalformedInstrumentHeadersValuesEnvelopesAndTruncationFailCleanly() {
        var badSignature = modernInstrument()
        badSignature[0] = 0
        XCTAssertThrowsError(try ITParser.parse(data: makeIT(instrument: badSignature))) {
            XCTAssertEqual($0 as? ITParser.ParserError, .invalidInstrumentHeader(1))
        }

        var badNNA = modernInstrument()
        badNNA[0x11] = 4
        XCTAssertThrowsError(try ITParser.parse(data: makeIT(instrument: badNNA))) {
            XCTAssertEqual(
                $0 as? ITParser.ParserError,
                .invalidInstrumentValue(instrument: 1, field: "NNA", value: 4)
            )
        }

        var badEnvelope = modernInstrument()
        writeEnvelope(
            at: 0x130, flags: 0x03,
            points: [(0, 64), (4, 0)], loop: (1, 0), in: &badEnvelope
        )
        XCTAssertThrowsError(try ITParser.parse(data: makeIT(instrument: badEnvelope))) {
            guard case .invalidInstrumentEnvelope(instrument: 1, envelope: "Volume", reason: _)? = $0 as? ITParser.ParserError else {
                return XCTFail("Falscher Fehler: \($0)")
            }
        }

        var badMap = modernInstrument()
        badMap[0x41] = 100
        XCTAssertThrowsError(try ITParser.parse(data: makeIT(instrument: badMap))) {
            XCTAssertEqual(
                $0 as? ITParser.ParserError,
                .invalidInstrumentValue(instrument: 1, field: "noteMap[0].sample", value: 100)
            )
        }

        let complete = makeIT(instrument: modernInstrument())
        let instrumentOffset = 0xCA
        for length in instrumentOffset..<(instrumentOffset + 554) {
            XCTAssertThrowsError(try ITParser.parse(data: complete.prefix(length)), "Prefix \(length) wurde akzeptiert")
        }
        XCTAssertNoThrow(try ITParser.parse(data: complete))
    }

    // MARK: - Selbst erzeugte, freie Binär-Fixtures

    private func modernInstrument() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 554)
        bytes.replaceSubrange(0..<4, with: Array("IMPI".utf8))
        write("Modern Instrument", at: 0x20, in: &bytes)
        bytes[0x17] = 60
        bytes[0x18] = 128
        bytes[0x19] = 32
        for note in 0..<120 {
            bytes[0x40 + note * 2] = UInt8(note)
        }
        return bytes
    }

    private func oldInstrument() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 554)
        bytes.replaceSubrange(0..<4, with: Array("IMPI".utf8))
        write("Old Instrument", at: 0x20, in: &bytes)
        bytes[0x1F8] = 0xFF
        for note in 0..<120 {
            bytes[0x40 + note * 2] = UInt8(note)
        }
        return bytes
    }

    private func makeIT(instrument: [UInt8], compatibleWithVersion: Int = 0x0215) -> Data {
        precondition(instrument.count == 554)
        var bytes = [UInt8](repeating: 0, count: 0xC0)
        bytes.replaceSubrange(0..<4, with: Array("IMPM".utf8))
        write("Instrument Fixture", at: 4, in: &bytes)
        putWord(2, at: 0x20, in: &bytes)
        putWord(1, at: 0x22, in: &bytes)
        putWord(0, at: 0x24, in: &bytes)
        putWord(1, at: 0x26, in: &bytes)
        putWord(0x0214, at: 0x28, in: &bytes)
        putWord(compatibleWithVersion, at: 0x2A, in: &bytes)
        putWord(0x0005, at: 0x2C, in: &bytes) // Stereo + Instrument-Modus
        bytes[0x30] = 128
        bytes[0x31] = 128
        bytes[0x32] = 6
        bytes[0x33] = 125
        bytes[0x34] = 128
        for channel in 0..<64 {
            bytes[0x40 + channel] = 32
            bytes[0x80 + channel] = 64
        }
        bytes += [0, 255]
        appendDword(0xCA, to: &bytes)
        appendDword(0, to: &bytes) // leeres Pattern mit 64 Reihen
        XCTAssertEqual(bytes.count, 0xCA)
        bytes += instrument
        return Data(bytes)
    }

    private func writeEnvelope(
        at offset: Int,
        flags: UInt8,
        points: [(tick: Int, value: Int)],
        loop: (Int, Int) = (0, 0),
        sustain: (Int, Int) = (0, 0),
        in bytes: inout [UInt8]
    ) {
        bytes[offset] = flags
        bytes[offset + 1] = UInt8(points.count)
        bytes[offset + 2] = UInt8(loop.0)
        bytes[offset + 3] = UInt8(loop.1)
        bytes[offset + 4] = UInt8(sustain.0)
        bytes[offset + 5] = UInt8(sustain.1)
        for (index, point) in points.enumerated() {
            bytes[offset + 6 + index * 3] = UInt8(bitPattern: Int8(point.value))
            putWord(point.tick, at: offset + 7 + index * 3, in: &bytes)
        }
    }

    private func write(_ value: String, at offset: Int, in bytes: inout [UInt8]) {
        let encoded = Array(value.utf8)
        bytes.replaceSubrange(offset..<(offset + encoded.count), with: encoded)
    }

    private func putWord(_ value: Int, at offset: Int, in bytes: inout [UInt8]) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    private func appendDword(_ value: Int, to bytes: inout [UInt8]) {
        for byte in 0..<4 {
            bytes.append(UInt8(truncatingIfNeeded: value >> (byte * 8)))
        }
    }
}

import XCTest
@testable import SavageModPlayerCore

final class ITParserTests: XCTestCase {
    private struct PatternSpec {
        let rows: Int
        let packed: [UInt8]
    }

    func testHeaderOrdersChannelStateAndCompatibilityProfile() throws {
        var pannings = [UInt8](repeating: 32, count: 64)
        pannings[0] = 0
        pannings[1] = 64
        pannings[2] = 100
        pannings[3] = 0x80 | 32
        var volumes = [UInt8](repeating: 64, count: 64)
        volumes[0] = 12
        volumes[63] = 34

        let packed = patternData(rows: 32, populatedRows: [
            [0x81, 0x08, 2, 1], // B01 springt auf den Skip-Order 1 -> echte Position 1
        ])
        let data = makeIT(
            orders: [0, 254, 1, 255, 0],
            patterns: [PatternSpec(rows: 32, packed: packed), nil],
            flags: 0x00FD,
            special: 0x8008,
            pannings: pannings,
            volumes: volumes
        )

        XCTAssertTrue(ITParser.canParse(data: data))
        let module = try ITParser.parse(data: data)

        XCTAssertEqual(module.name, "Synthetic IT")
        XCTAssertEqual(module.format, .it)
        XCTAssertEqual(module.patternTable, [0, 1])
        XCTAssertEqual(module.length, 2)
        XCTAssertEqual(module.channelCount, 64)
        XCTAssertEqual(module.initialSpeed, 6)
        XCTAssertEqual(module.initialTempo, 125)
        XCTAssertEqual(module.initialGlobalVolume, 128)
        XCTAssertEqual(module.channelPannings[0], 0)
        XCTAssertEqual(module.channelPannings[1], 1)
        XCTAssertEqual(module.channelPannings[2], 0.5)
        XCTAssertTrue(module.channelSurrounds[2])
        XCTAssertTrue(module.channelDisabled[3])
        XCTAssertEqual(module.channelVolumes[0], 12)
        XCTAssertEqual(module.channelVolumes[63], 34)
        XCTAssertEqual(module.playbackSemantics, .impulseTracker(
            ITCompatibility(oldEffects: true, compatibleGxx: true)
        ))

        let properties = try XCTUnwrap(module.itProperties)
        XCTAssertEqual(properties.createdWithVersion, 0x0214)
        XCTAssertEqual(properties.compatibleWithVersion, 0x0215)
        XCTAssertTrue(properties.usesInstruments)
        XCTAssertTrue(properties.stereo)
        XCTAssertFalse(properties.volumeZeroMixOptimization)
        XCTAssertTrue(properties.linearSlides)
        XCTAssertEqual(properties.patternHighlight, 0)
        XCTAssertFalse(properties.hasSongMessage)
        XCTAssertEqual(properties.songMessageLength, 0)
        XCTAssertEqual(properties.songMessageOffset, 0)
        XCTAssertTrue(properties.usesMIDIPitchController)
        XCTAssertTrue(properties.hasEmbeddedMIDIConfiguration)
        XCTAssertEqual(properties.unknownHeaderFlags, 0)
        XCTAssertEqual(properties.unknownSpecialFlags, 0x8000)
        XCTAssertNil(properties.openMPTExtensions?.midiConfiguration)
        XCTAssertFalse(module.compatibilityWarnings.contains { $0.contains("MIDI") })
        XCTAssertTrue(module.compatibilityWarnings.contains { $0.contains("0x8000") })

        let jump = module.patterns[0].rows[0].notes[0]
        XCTAssertTrue(jump.hasEffect)
        XCTAssertEqual(jump.effectId, ModuleEffect.impulseTrackerCommand(2))
        XCTAssertEqual(jump.effectData, 1)
        XCTAssertEqual(module.patterns[1].rows.count, 64)
    }

    func testBareStructuredOpenMPTExtensionMarkerIsNotAWarning() throws {
        var data = makeIT(patterns: [nil])
        data.append(contentsOf: Data("MPTX".utf8))
        let module = try ITParser.parse(data: data)
        XCTAssertFalse(module.itProperties?.hasUnsupportedExtensions == true)
        XCTAssertTrue(module.compatibilityWarnings.isEmpty)
    }

    func testModuleLoaderDispatchesITByContent() throws {
        let module = try ModuleLoader.parse(data: makeIT(patterns: [nil]))
        XCTAssertEqual(module.format, .it)
        XCTAssertEqual(module.name, "Synthetic IT")
    }

    func testAllDirectMaskBitsAndEveryReuseCombination() throws {
        var rows = [[UInt8]]()
        // Direkte Bits 1/2/4/8 setzen alle Last-Values; A00 bleibt explizit präsent.
        rows.append([0x81, 0x0F, 60, 7, 0, 1, 0])
        for combination in 0..<16 {
            rows.append([0x81, UInt8(combination << 4)])
        }
        let data = makeIT(
            patterns: [PatternSpec(rows: 32, packed: patternData(rows: 32, populatedRows: rows))]
        )
        let pattern = try ITParser.parse(data: data).patterns[0]

        let direct = pattern.rows[0].notes[0]
        XCTAssertEqual(direct.key, 60)
        XCTAssertEqual(direct.instrument, 7)
        XCTAssertEqual(direct.volume, 0)
        XCTAssertTrue(direct.hasEffect)
        XCTAssertEqual(direct.effectId, ModuleEffect.impulseTrackerCommand(1))
        XCTAssertEqual(direct.effectData, 0)

        for combination in 0..<16 {
            let note = pattern.rows[combination + 1].notes[0]
            XCTAssertEqual(note.key, combination & 1 != 0 ? 60 : -1)
            XCTAssertEqual(note.instrument, combination & 2 != 0 ? 7 : 0)
            XCTAssertEqual(note.volume, combination & 4 != 0 ? 0 : -1)
            XCTAssertEqual(note.hasEffect, combination & 8 != 0)
            if combination & 8 != 0 {
                XCTAssertEqual(note.effectId, ModuleEffect.impulseTrackerCommand(1))
                XCTAssertEqual(note.effectData, 0)
            }
        }
    }

    func testMaskReuseWithoutNewMaskUsesPreviousChannelMask() throws {
        let rows: [[UInt8]] = [
            [0x81, 0x01, 10],
            [0x01, 11], // Bit 7 fehlt: vorherige Maske 0x01 gilt weiter.
        ]
        let data = makeIT(
            patterns: [PatternSpec(rows: 32, packed: patternData(rows: 32, populatedRows: rows))]
        )
        let pattern = try ITParser.parse(data: data).patterns[0]
        XCTAssertEqual(pattern.rows[0].notes[0].key, 10)
        XCTAssertEqual(pattern.rows[1].notes[0].key, 11)
    }

    func testSpecialNotesRawVolumeAndReservedCommandsArePreserved() throws {
        let rows: [[UInt8]] = [
            [0x81, 0x0D, 255, 128, 31, 0],
            [0x81, 0x05, 254, 192],
            [0x81, 0x01, 253],
            [0x81, 0x01, 120],
        ]
        let data = makeIT(
            patterns: [PatternSpec(rows: 32, packed: patternData(rows: 32, populatedRows: rows))]
        )
        let pattern = try ITParser.parse(data: data).patterns[0]

        XCTAssertEqual(pattern.rows[0].notes[0].specialNote, .off)
        XCTAssertEqual(pattern.rows[0].notes[0].volume, 128)
        XCTAssertEqual(pattern.rows[0].notes[0].effectId, ModuleEffect.impulseTrackerCommand(31))
        XCTAssertEqual(pattern.rows[1].notes[0].specialNote, .cut)
        XCTAssertEqual(pattern.rows[1].notes[0].volume, 192)
        XCTAssertEqual(pattern.rows[2].notes[0].specialNote, .fade)
        XCTAssertEqual(pattern.rows[3].notes[0].specialNote, .fade)
    }

    func testMaximumChannelAndTwoHundredRows() throws {
        var populated = [[UInt8]]()
        populated.append([0xC0, 0x01, 119]) // Marker 64 + neue Maske -> Kanalindex 63
        let data = makeIT(
            patterns: [PatternSpec(rows: 200, packed: patternData(rows: 200, populatedRows: populated))]
        )
        let pattern = try ITParser.parse(data: data).patterns[0]
        XCTAssertEqual(pattern.rows.count, 200)
        XCTAssertTrue(pattern.rows.allSatisfy { $0.notes.count == 64 })
        XCTAssertEqual(pattern.rows[0].notes[63].key, 119)
        XCTAssertEqual(pattern.rows[199].notes[63].key, -1)
    }

    func testZeroPatternOffsetCreatesEmptySixtyFourRowPattern() throws {
        let module = try ITParser.parse(data: makeIT(patterns: [nil]))
        XCTAssertEqual(module.patterns[0].rows.count, 64)
        XCTAssertTrue(module.patterns[0].rows.allSatisfy { row in
            row.notes.count == 64 && row.notes.allSatisfy { $0.key == -1 && !$0.hasEffect }
        })
    }

    func testSongMessageMetadataIsBoundsCheckedAndPreserved() throws {
        var valid = makeIT(patterns: [nil])
        let messageOffset = valid.count
        valid.append(contentsOf: [65, 13, 66, 0])
        setWord(0x0001, at: 0x2E, in: &valid)
        setWord(4, at: 0x36, in: &valid)
        setDword(messageOffset, at: 0x38, in: &valid)

        let properties = try XCTUnwrap(ITParser.parse(data: valid).itProperties)
        XCTAssertTrue(properties.hasSongMessage)
        XCTAssertEqual(properties.songMessageLength, 4)
        XCTAssertEqual(properties.songMessageOffset, messageOffset)

        var invalid = valid
        setDword(invalid.count + 1, at: 0x38, in: &invalid)
        XCTAssertThrowsError(try ITParser.parse(data: invalid)) {
            guard case .invalidOffset(kind: "SongMessage", index: 0, offset: _)? = $0 as? ITParser.ParserError else {
                return XCTFail("Falscher Fehler: \($0)")
            }
        }
    }

    func testEveryTruncationFailsWithoutCrash() {
        let fixture = makeIT(patterns: [PatternSpec(
            rows: 32,
            packed: patternData(rows: 32, populatedRows: [[0x81, 0x0F, 48, 1, 64, 1, 0]])
        )])

        for length in 0..<fixture.count {
            XCTAssertThrowsError(try ITParser.parse(data: fixture.prefix(length)), "Prefix \(length) wurde akzeptiert")
        }
        XCTAssertNoThrow(try ITParser.parse(data: fixture))
    }

    func testInvalidSignatureCountsOrdersRowsOffsetsAndPackedValuesFailCleanly() {
        XCTAssertFalse(ITParser.canParse(data: Data("NOPE".utf8)))
        XCTAssertThrowsError(try ITParser.parse(data: Data(repeating: 0, count: 0xC0))) {
            XCTAssertEqual($0 as? ITParser.ParserError, .invalidSignature)
        }

        var tooManyPatterns = makeIT()
        setWord(241, at: 0x26, in: &tooManyPatterns)
        XCTAssertThrowsError(try ITParser.parse(data: tooManyPatterns)) {
            guard case .unsupportedCounts? = $0 as? ITParser.ParserError else {
                return XCTFail("Falscher Fehler: \($0)")
            }
        }

        let missingPattern = try? ITParser.parse(data: makeIT(orders: [0, 1, 255], patterns: [nil]))
        XCTAssertEqual(missingPattern?.patternTable, [0])

        for rows in [0, 1_025] {
            let data = makeIT(patterns: [PatternSpec(rows: rows, packed: [])])
            XCTAssertThrowsError(try ITParser.parse(data: data)) {
                XCTAssertEqual($0 as? ITParser.ParserError, .invalidPatternRows(pattern: 0, rows: rows))
            }
        }

        var badOffset = makeIT(patterns: [nil])
        let patternOffsetTable = 0xC0 + 2
        setDword(badOffset.count + 1, at: patternOffsetTable, in: &badOffset)
        XCTAssertThrowsError(try ITParser.parse(data: badOffset)) {
            guard case .invalidOffset(kind: "Pattern", index: 0, offset: _)? = $0 as? ITParser.ParserError else {
                return XCTFail("Falscher Fehler: \($0)")
            }
        }

        let badInstrument = makeIT(
            patterns: [nil],
            instrumentOffsets: [0]
        )
        XCTAssertThrowsError(try ITParser.parse(data: badInstrument)) {
            XCTAssertEqual($0 as? ITParser.ParserError, .invalidOffset(kind: "Instrument", index: 0, offset: 0))
        }

        let badVolume = makeIT(patterns: [PatternSpec(
            rows: 32,
            packed: patternData(rows: 32, populatedRows: [[0x81, 0x04, 213]])
        )])
        XCTAssertThrowsError(try ITParser.parse(data: badVolume)) {
            guard case .invalidPatternValue(pattern: 0, row: 0, channel: 0, field: "volume", value: 213)? = $0 as? ITParser.ParserError else {
                return XCTFail("Falscher Fehler: \($0)")
            }
        }
    }

    func testEmptySongAfterSkipAndEndMarkersIsRejected() {
        let data = makeIT(orders: [254, 255], patterns: [nil])
        XCTAssertThrowsError(try ITParser.parse(data: data)) {
            XCTAssertEqual($0 as? ITParser.ParserError, .emptySong)
        }
    }

    // MARK: - Selbst erzeugte, frei eincheckbare IT-Fixtures

    private func patternData(rows: Int, populatedRows: [[UInt8]]) -> [UInt8] {
        var data = [UInt8]()
        for row in 0..<rows {
            if row < populatedRows.count {
                data += populatedRows[row]
            }
            data.append(0)
        }
        return data
    }

    private func makeIT(
        orders: [UInt8] = [0, 255],
        patterns: [PatternSpec?] = [nil],
        flags: Int = 0x0001,
        special: Int = 0,
        pannings: [UInt8] = [UInt8](repeating: 32, count: 64),
        volumes: [UInt8] = [UInt8](repeating: 64, count: 64),
        instrumentOffsets: [Int] = [],
        sampleOffsets: [Int] = []
    ) -> Data {
        precondition(pannings.count == 64 && volumes.count == 64)
        var bytes = [UInt8](repeating: 0, count: 0xC0)
        bytes.replaceSubrange(0..<4, with: Array("IMPM".utf8))
        let name = Array("Synthetic IT".utf8)
        bytes.replaceSubrange(4..<(4 + name.count), with: name)
        putWord(orders.count, at: 0x20, in: &bytes)
        putWord(instrumentOffsets.count, at: 0x22, in: &bytes)
        putWord(sampleOffsets.count, at: 0x24, in: &bytes)
        putWord(patterns.count, at: 0x26, in: &bytes)
        putWord(0x0214, at: 0x28, in: &bytes)
        putWord(0x0215, at: 0x2A, in: &bytes)
        putWord(flags, at: 0x2C, in: &bytes)
        putWord(special, at: 0x2E, in: &bytes)
        bytes[0x30] = 128
        bytes[0x31] = 128
        bytes[0x32] = 6
        bytes[0x33] = 125
        bytes[0x34] = 128
        bytes[0x35] = 0
        bytes.replaceSubrange(0x40..<0x80, with: pannings)
        bytes.replaceSubrange(0x80..<0xC0, with: volumes)
        bytes += orders

        for offset in instrumentOffsets { appendDword(offset, to: &bytes) }
        for offset in sampleOffsets { appendDword(offset, to: &bytes) }
        let patternOffsetTable = bytes.count
        bytes += [UInt8](repeating: 0, count: patterns.count * 4)

        for (index, pattern) in patterns.enumerated() {
            guard let pattern else { continue }
            putDword(bytes.count, at: patternOffsetTable + index * 4, in: &bytes)
            appendWord(pattern.packed.count, to: &bytes)
            appendWord(pattern.rows, to: &bytes)
            bytes += [0, 0, 0, 0]
            bytes += pattern.packed
        }
        return Data(bytes)
    }

    private func putWord(_ value: Int, at offset: Int, in bytes: inout [UInt8]) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    private func putDword(_ value: Int, at offset: Int, in bytes: inout [UInt8]) {
        for byte in 0..<4 {
            bytes[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8))
        }
    }

    private func appendWord(_ value: Int, to bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func appendDword(_ value: Int, to bytes: inout [UInt8]) {
        for byte in 0..<4 {
            bytes.append(UInt8(truncatingIfNeeded: value >> (byte * 8)))
        }
    }

    private func setWord(_ value: Int, at offset: Int, in data: inout Data) {
        data[data.startIndex + offset] = UInt8(truncatingIfNeeded: value)
        data[data.startIndex + offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    private func setDword(_ value: Int, at offset: Int, in data: inout Data) {
        for byte in 0..<4 {
            data[data.startIndex + offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8))
        }
    }
}

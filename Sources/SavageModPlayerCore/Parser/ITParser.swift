import Foundation

// Strikter Parser für den strukturellen IT-Kern. M2 liest Header, Orders und
// Patterns, aktiviert das Format aber noch nicht im öffentlichen ModuleLoader.
// Instrumente, Samples und Wiedergabe folgen in den späteren Meilensteinen.
public enum ITParser {
    public enum ParserError: Error, LocalizedError, Equatable {
        case fileTooSmall
        case invalidSignature
        case unsupportedCounts(orders: Int, instruments: Int, samples: Int, patterns: Int)
        case invalidHeaderValue(String, Int)
        case emptySong
        case invalidOrder(Int)
        case invalidOffset(kind: String, index: Int, offset: Int)
        case invalidPatternRows(pattern: Int, rows: Int)
        case invalidPatternValue(pattern: Int, row: Int, channel: Int, field: String, value: Int)
        case truncatedPattern(Int)

        public var errorDescription: String? {
            switch self {
            case .fileTooSmall:
                return "Datei zu klein für ein gültiges Impulse-Tracker-Modul."
            case .invalidSignature:
                return "Keine IMPM-Signatur — kein Impulse-Tracker-Modul."
            case let .unsupportedCounts(orders, instruments, samples, patterns):
                return "IT-Anzahlen außerhalb der sicheren Grenzen (Orders \(orders), Instrumente \(instruments), Samples \(samples), Patterns \(patterns))."
            case let .invalidHeaderValue(field, value):
                return "Ungültiger IT-Headerwert \(field)=\(value)."
            case .emptySong:
                return "Leeres IT-Modul: keine abspielbaren Songpositionen."
            case let .invalidOrder(order):
                return "Ungültiger IT-Orderwert \(order)."
            case let .invalidOffset(kind, index, offset):
                return "Ungültiger IT-Offset für \(kind) \(index): \(offset)."
            case let .invalidPatternRows(pattern, rows):
                return "IT-Pattern \(pattern) hat ungültige Zeilenzahl \(rows)."
            case let .invalidPatternValue(pattern, row, channel, field, value):
                return "IT-Pattern \(pattern), Zeile \(row), Kanal \(channel): ungültiges Feld \(field)=\(value)."
            case let .truncatedPattern(pattern):
                return "IT-Pattern \(pattern) ist abgeschnitten."
            }
        }
    }

    private static let headerSize = 0xC0
    private static let channelCount = 64
    private static let maximumOrders = 256
    private static let maximumInstruments = 99
    private static let maximumSamples = 99
    private static let maximumPatterns = 200

    private struct Reader {
        let data: Data
        let base: Data.Index

        init(_ data: Data) {
            self.data = data
            self.base = data.startIndex
        }

        func byte(_ offset: Int) throws -> Int {
            guard offset >= 0, offset < data.count else { throw ParserError.fileTooSmall }
            return Int(data[base + offset])
        }

        func word(_ offset: Int) throws -> Int {
            try byte(offset) | (byte(offset + 1) << 8)
        }

        func dword(_ offset: Int) throws -> Int {
            try word(offset) | (word(offset + 2) << 16)
        }

        func string(_ offset: Int, length: Int) throws -> String {
            guard offset >= 0, length >= 0, offset <= data.count - length else {
                throw ParserError.fileTooSmall
            }
            let bytes = (0..<length).map { data[base + offset + $0] }.prefix { $0 != 0 }
            return (String(bytes: bytes, encoding: .isoLatin1) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public static func canParse(data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let base = data.startIndex
        return data[base] == 0x49 && data[base + 1] == 0x4D
            && data[base + 2] == 0x50 && data[base + 3] == 0x4D
    }

    public static func parse(data: Data) throws -> Mod {
        guard data.count >= headerSize else { throw ParserError.fileTooSmall }
        guard canParse(data: data) else { throw ParserError.invalidSignature }
        let reader = Reader(data)

        let orderCount = try reader.word(0x20)
        let instrumentCount = try reader.word(0x22)
        let sampleCount = try reader.word(0x24)
        let patternCount = try reader.word(0x26)
        guard orderCount <= maximumOrders,
              instrumentCount <= maximumInstruments,
              sampleCount <= maximumSamples,
              patternCount <= maximumPatterns else {
            throw ParserError.unsupportedCounts(
                orders: orderCount,
                instruments: instrumentCount,
                samples: sampleCount,
                patterns: patternCount
            )
        }

        let tablesSize = orderCount + instrumentCount * 4 + sampleCount * 4 + patternCount * 4
        guard tablesSize <= data.count - headerSize else { throw ParserError.fileTooSmall }

        let createdWithVersion = try reader.word(0x28)
        let compatibleWithVersion = try reader.word(0x2A)
        let flags = try reader.word(0x2C)
        let special = try reader.word(0x2E)
        let patternHighlight = try reader.word(0x1E)
        let globalVolume = try reader.byte(0x30)
        let mixVolume = try reader.byte(0x31)
        let initialSpeed = try reader.byte(0x32)
        let initialTempo = try reader.byte(0x33)
        let panSeparation = try reader.byte(0x34)
        let pitchWheelDepth = try reader.byte(0x35)
        let songMessageLength = try reader.word(0x36)
        let songMessageOffset = try reader.dword(0x38)

        guard globalVolume <= 128 else {
            throw ParserError.invalidHeaderValue("globalVolume", globalVolume)
        }
        guard mixVolume <= 128 else {
            throw ParserError.invalidHeaderValue("mixVolume", mixVolume)
        }
        guard initialSpeed > 0 else {
            throw ParserError.invalidHeaderValue("initialSpeed", initialSpeed)
        }
        guard initialTempo >= 32 else {
            throw ParserError.invalidHeaderValue("initialTempo", initialTempo)
        }
        guard panSeparation <= 128 else {
            throw ParserError.invalidHeaderValue("panSeparation", panSeparation)
        }
        let hasSongMessage = special & 0x01 != 0
        if hasSongMessage {
            guard songMessageOffset > 0,
                  songMessageOffset <= data.count - songMessageLength else {
                throw ParserError.invalidOffset(
                    kind: "SongMessage", index: 0, offset: songMessageOffset
                )
            }
        }

        var channelPannings = [Float]()
        var channelVolumes = [Int]()
        var channelSurrounds = [Bool]()
        var channelDisabled = [Bool]()
        channelPannings.reserveCapacity(channelCount)
        channelVolumes.reserveCapacity(channelCount)
        channelSurrounds.reserveCapacity(channelCount)
        channelDisabled.reserveCapacity(channelCount)

        for channel in 0..<channelCount {
            let rawPan = try reader.byte(0x40 + channel)
            let pan = rawPan & 0x7F
            let disabled = rawPan & 0x80 != 0
            let surround = pan == 100
            guard surround || pan <= 64 else {
                throw ParserError.invalidHeaderValue("channelPan[\(channel)]", rawPan)
            }
            let volume = try reader.byte(0x80 + channel)
            guard volume <= 64 else {
                throw ParserError.invalidHeaderValue("channelVolume[\(channel)]", volume)
            }

            channelPannings.append(surround ? 0.5 : Float(pan) / 64.0)
            channelVolumes.append(volume)
            channelSurrounds.append(surround)
            channelDisabled.append(disabled)
        }

        let ordersOffset = headerSize
        let instrumentOffsetsOffset = ordersOffset + orderCount
        let sampleOffsetsOffset = instrumentOffsetsOffset + instrumentCount * 4
        let patternOffsetsOffset = sampleOffsetsOffset + sampleCount * 4

        // M3/M6 lesen den Inhalt. M2 validiert bereits alle 32-Bit-Ziele, damit
        // abgeschnittene oder überlaufende Tabellen kontrolliert scheitern.
        try validateOffsets(
            reader: reader,
            count: instrumentCount,
            tableOffset: instrumentOffsetsOffset,
            kind: "Instrument",
            minimumBytes: 4
        )
        try validateOffsets(
            reader: reader,
            count: sampleCount,
            tableOffset: sampleOffsetsOffset,
            kind: "Sample",
            minimumBytes: 4
        )

        let (patternTable, orderMap) = try parseOrders(
            reader: reader,
            offset: ordersOffset,
            count: orderCount,
            patternCount: patternCount
        )
        guard !patternTable.isEmpty else { throw ParserError.emptySong }

        var patterns = [Pattern]()
        patterns.reserveCapacity(patternCount)
        for patternIndex in 0..<patternCount {
            let offset = try reader.dword(patternOffsetsOffset + patternIndex * 4)
            if offset == 0 {
                patterns.append(emptyPattern(rowCount: 64))
            } else {
                patterns.append(try parsePattern(
                    reader: reader,
                    patternIndex: patternIndex,
                    offset: offset,
                    orderMap: orderMap
                ))
            }
        }

        let usesInstruments = flags & 0x04 != 0
        let slotCount = usesInstruments ? instrumentCount : sampleCount
        let compatibility = ITCompatibility(
            oldEffects: flags & 0x10 != 0,
            compatibleGxx: flags & 0x20 != 0
        )
        let properties = ITModuleProperties(
            createdWithVersion: createdWithVersion,
            compatibleWithVersion: compatibleWithVersion,
            usesInstruments: usesInstruments,
            stereo: flags & 0x01 != 0,
            volumeZeroMixOptimization: flags & 0x02 != 0,
            linearSlides: flags & 0x08 != 0,
            patternHighlight: patternHighlight,
            mixVolume: mixVolume,
            panSeparation: panSeparation,
            pitchWheelDepth: pitchWheelDepth,
            hasSongMessage: hasSongMessage,
            songMessageLength: songMessageLength,
            songMessageOffset: songMessageOffset,
            usesMIDIPitchController: flags & 0x40 != 0,
            hasEmbeddedMIDIConfiguration: flags & 0x80 != 0 || special & 0x08 != 0,
            unknownHeaderFlags: flags & ~0x00FF,
            unknownSpecialFlags: special & ~0x0009
        )

        return Mod(
            name: try reader.string(0x04, length: 26),
            length: patternTable.count,
            patternTable: patternTable,
            instruments: [Instrument?](repeating: nil, count: slotCount + 1),
            patterns: patterns,
            channelCount: channelCount,
            format: .it,
            initialSpeed: initialSpeed,
            initialTempo: initialTempo,
            initialGlobalVolume: globalVolume,
            channelPannings: channelPannings,
            linearFrequency: properties.linearSlides,
            channelVolumes: channelVolumes,
            channelSurrounds: channelSurrounds,
            channelDisabled: channelDisabled,
            playbackSemantics: .impulseTracker(compatibility),
            itProperties: properties
        )
    }

    private static func validateOffsets(
        reader: Reader,
        count: Int,
        tableOffset: Int,
        kind: String,
        minimumBytes: Int
    ) throws {
        for index in 0..<count {
            let offset = try reader.dword(tableOffset + index * 4)
            guard offset > 0, offset <= reader.data.count - minimumBytes else {
                throw ParserError.invalidOffset(kind: kind, index: index, offset: offset)
            }
        }
    }

    private static func parseOrders(
        reader: Reader,
        offset: Int,
        count: Int,
        patternCount: Int
    ) throws -> ([Int], [Int]) {
        var patternTable = [Int]()
        var filteredIndex = [Int?](repeating: nil, count: count)
        var ended = false

        for rawIndex in 0..<count {
            let value = try reader.byte(offset + rawIndex)
            if ended { continue }
            switch value {
            case 255:
                ended = true
            case 254:
                continue
            case 0..<patternCount:
                filteredIndex[rawIndex] = patternTable.count
                patternTable.append(value)
            default:
                throw ParserError.invalidOrder(value)
            }
        }

        var orderMap = [Int](repeating: 0, count: max(1, count))
        var next = max(0, patternTable.count - 1)
        if count > 0 {
            for rawIndex in stride(from: count - 1, through: 0, by: -1) {
                if let mapped = filteredIndex[rawIndex] {
                    next = mapped
                }
                orderMap[rawIndex] = next
            }
        }
        return (patternTable, orderMap)
    }

    private static func emptyPattern(rowCount: Int) -> Pattern {
        let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
        return Pattern(rows: (0..<rowCount).map { _ in
            Row(notes: [Note](repeating: empty, count: channelCount))
        })
    }

    private static func parsePattern(
        reader: Reader,
        patternIndex: Int,
        offset: Int,
        orderMap: [Int]
    ) throws -> Pattern {
        guard offset >= 0, offset <= reader.data.count - 8 else {
            throw ParserError.invalidOffset(kind: "Pattern", index: patternIndex, offset: offset)
        }
        let packedLength = try reader.word(offset)
        let rowCount = try reader.word(offset + 2)
        guard (32...200).contains(rowCount) else {
            throw ParserError.invalidPatternRows(pattern: patternIndex, rows: rowCount)
        }
        let packedStart = offset + 8
        guard packedLength <= reader.data.count - packedStart else {
            throw ParserError.truncatedPattern(patternIndex)
        }
        let packedEnd = packedStart + packedLength

        let empty = Note(instrument: 0, period: 0, effectId: 0, effectData: 0)
        var grid = (0..<rowCount).map { _ in
            [Note](repeating: empty, count: channelCount)
        }
        var masks = [Int](repeating: 0, count: channelCount)
        var lastNotes = [Int?](repeating: nil, count: channelCount)
        var lastInstruments = [Int?](repeating: nil, count: channelCount)
        var lastVolumes = [Int?](repeating: nil, count: channelCount)
        var lastCommands = [(Int, Int)?](repeating: nil, count: channelCount)

        var cursor = packedStart
        var row = 0

        func nextByte() throws -> Int {
            guard cursor < packedEnd else { throw ParserError.truncatedPattern(patternIndex) }
            defer { cursor += 1 }
            return try reader.byte(cursor)
        }

        while row < rowCount {
            let marker = try nextByte()
            if marker == 0 {
                row += 1
                continue
            }

            let channel = (marker - 1) & 63
            if marker & 0x80 != 0 {
                masks[channel] = try nextByte()
            }
            let mask = masks[channel]

            var noteValue: Int?
            var instrumentValue: Int?
            var volumeValue: Int?
            var commandValue: (Int, Int)?

            if mask & 0x01 != 0 {
                let value = try nextByte()
                lastNotes[channel] = value
                noteValue = value
            }
            if mask & 0x02 != 0 {
                let value = try nextByte()
                guard value <= 99 else {
                    throw ParserError.invalidPatternValue(
                        pattern: patternIndex, row: row, channel: channel,
                        field: "instrument", value: value
                    )
                }
                lastInstruments[channel] = value
                instrumentValue = value
            }
            if mask & 0x04 != 0 {
                let value = try nextByte()
                guard value <= 212 else {
                    throw ParserError.invalidPatternValue(
                        pattern: patternIndex, row: row, channel: channel,
                        field: "volume", value: value
                    )
                }
                lastVolumes[channel] = value
                volumeValue = value
            }
            if mask & 0x08 != 0 {
                let command = try nextByte()
                let value = try nextByte()
                guard command <= 31 else {
                    throw ParserError.invalidPatternValue(
                        pattern: patternIndex, row: row, channel: channel,
                        field: "command", value: command
                    )
                }
                lastCommands[channel] = (command, value)
                commandValue = (command, value)
            }

            if mask & 0x10 != 0 { noteValue = lastNotes[channel] }
            if mask & 0x20 != 0 { instrumentValue = lastInstruments[channel] }
            if mask & 0x40 != 0 { volumeValue = lastVolumes[channel] }
            if mask & 0x80 != 0 { commandValue = lastCommands[channel] }

            grid[row][channel] = makeNote(
                noteValue: noteValue,
                instrumentValue: instrumentValue,
                volumeValue: volumeValue,
                commandValue: commandValue,
                orderMap: orderMap
            )
        }

        return Pattern(rows: grid.map { Row(notes: $0) })
    }

    private static func makeNote(
        noteValue: Int?,
        instrumentValue: Int?,
        volumeValue: Int?,
        commandValue: (Int, Int)?,
        orderMap: [Int]
    ) -> Note {
        let key: Int
        if let noteValue {
            switch noteValue {
            case 0...119:
                key = noteValue
            case 255:
                key = Note.keyOff
            case 254:
                key = Note.keyCut
            default:
                key = Note.keyFade
            }
        } else {
            key = -1
        }

        let command = commandValue?.0 ?? 0
        var parameter = commandValue?.1 ?? 0
        if command == 2 { // Bxx: rohe Order-Position auf gefilterte Liste abbilden
            parameter = parameter < orderMap.count ? orderMap[parameter] : 0
        }
        let effectPresent = commandValue != nil && command != 0
        let effectID = effectPresent ? ModuleEffect.impulseTrackerCommand(command) : 0

        return Note(
            instrument: instrumentValue ?? 0,
            period: 0,
            effectId: effectID,
            effectData: parameter,
            key: key,
            volume: volumeValue ?? -1,
            effectPresent: effectPresent
        )
    }
}

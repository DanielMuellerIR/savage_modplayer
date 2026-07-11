import Foundation

// Liest ModPlug-/OpenMPT-Erweiterungen nur an ihren strukturell erlaubten
// Positionen. Marker in Pattern- oder PCM-Daten werden dadurch nie verwechselt.
enum ITOpenMPTExtensionParser {
    private static let midiConfigurationSize = 4_896

    private struct Builder {
        var chunks: [ITExtensionChunk] = []
        var instrumentFields: [ITInstrumentExtensionField] = []
        var defaultTempo: Int?
        var rowsPerBeat: Int?
        var rowsPerMeasure: Int?
        var channelCount: Int?
        var extraChannelSettings: [ITChannelSetting] = []
        var tempoMode: ITTempoMode = .classic
        var rawTempoMode: Int?
        var mixLevel: ITMixLevel?
        var rawMixLevel: Int?
        var createdWithVersion: OpenMPTVersion?
        var lastSavedWithVersion: OpenMPTVersion?
        var samplePreamp: Int?
        var synthPreamp: Int?
        var restartPosition: Int?
        var playBehaviours: [ITPlayBehaviourState] = []
        var artist: String?
        var channelColors: [Int?] = []
        var hasMIDIMapping = false
        var midiConfiguration: ITMIDIConfiguration?
        var channelPluginAssignments: [Int] = []
        var plugins: [ITPluginDefinition] = []
        var isMPTM = false

        func finish() -> ITOpenMPTExtensions {
            ITOpenMPTExtensions(
                chunks: chunks,
                instrumentFields: instrumentFields,
                defaultTempo: defaultTempo,
                rowsPerBeat: rowsPerBeat,
                rowsPerMeasure: rowsPerMeasure,
                channelCount: channelCount,
                extraChannelSettings: extraChannelSettings,
                tempoMode: tempoMode,
                rawTempoMode: rawTempoMode,
                mixLevel: mixLevel,
                rawMixLevel: rawMixLevel,
                createdWithVersion: createdWithVersion,
                lastSavedWithVersion: lastSavedWithVersion,
                samplePreamp: samplePreamp,
                synthPreamp: synthPreamp,
                restartPosition: restartPosition,
                playBehaviours: playBehaviours,
                artist: artist,
                channelColors: channelColors,
                hasMIDIMapping: hasMIDIMapping,
                midiConfiguration: midiConfiguration,
                channelPluginAssignments: channelPluginAssignments,
                plugins: plugins,
                isMPTM: isMPTM
            )
        }
    }

    static func parse(
        data: Data,
        tablesEnd: Int,
        firstPayloadOffset: Int,
        payloadEnd: Int,
        instrumentOffsets: [Int],
        flags: Int,
        special: Int
    ) throws -> ITOpenMPTExtensions {
        guard tablesEnd >= 0, tablesEnd <= data.count,
              firstPayloadOffset >= tablesEnd, firstPayloadOffset <= data.count,
              payloadEnd >= firstPayloadOffset, payloadEnd <= data.count else {
            throw ITParser.ParserError.invalidExtension("ungueltige Bereichsgrenze")
        }

        var builder = Builder()
        try parseHeaderTail(
            data: data,
            start: tablesEnd,
            end: firstPayloadOffset,
            flags: flags,
            special: special,
            builder: &builder
        )
        try parseEmbeddedInstrumentExtensions(
            data: data,
            offsets: instrumentOffsets,
            builder: &builder
        )
        try parseEndExtensions(
            data: data,
            start: payloadEnd,
            instrumentCount: instrumentOffsets.count,
            builder: &builder
        )
        detectMPTM(data: data, builder: &builder)
        return builder.finish()
    }

    // Sehr alte ModPlug-/OpenMPT-Dateien erweitern den 554-Byte-IT-Header
    // direkt um 120 hohe Sample-Map-Bytes und optional einen MSNI-Block. Diese
    // Daten werden nur am jeweiligen Instrument-Parapointer gelesen.
    private static func parseEmbeddedInstrumentExtensions(
        data: Data,
        offsets: [Int],
        builder: inout Builder
    ) throws {
        guard !offsets.isEmpty else { return }
        var pluginSlots = [Int](repeating: 0, count: offsets.count)
        var extendedMaps = [Int](repeating: 0, count: offsets.count)

        for (index, offset) in offsets.enumerated() {
            guard offset >= 0, offset <= data.count - 554 else { continue }
            var cursor = offset + 554
            let marker = fourCC(data, offset + 550)
            if marker == "XTPM" || marker == "MPTX" {
                guard cursor <= data.count - 120 else {
                    throw ITParser.ParserError.invalidExtension(
                        "abgeschnittene erweiterte Sample-Map von Instrument \(index + 1)"
                    )
                }
                let highBytes = data[cursor..<(cursor + 120)]
                extendedMaps[index] = highBytes.contains(where: { $0 != 0 }) ? 1 : 0
                builder.chunks.append(chunk(
                    marker, .instrument, 120, .compatibility,
                    "Erweiterte Sample-Map von Instrument \(index + 1)"
                ))
                cursor += 120
            }

            guard cursor <= data.count - 8, fourCC(data, cursor) == "MSNI" else { continue }
            let size = unsigned(data, cursor + 4, 4)
            guard size <= data.count - cursor - 8 else {
                throw ITParser.ParserError.invalidExtension(
                    "abgeschnittener MSNI-Block von Instrument \(index + 1)"
                )
            }
            let payloadStart = cursor + 8
            if size >= 5, fourCC(data, payloadStart) == "GULP" {
                pluginSlots[index] = unsigned(data, payloadStart + 4, 1)
                builder.chunks.append(chunk(
                    "MSNI", .instrument, size, .routing,
                    "Historischer Plugin-Slot von Instrument \(index + 1)"
                ))
            } else {
                builder.chunks.append(chunk(
                    "MSNI", .instrument, size, .unknownPlayback,
                    "Unbekannte historische Instrumentdaten von Instrument \(index + 1)"
                ))
            }
        }

        if pluginSlots.contains(where: { $0 > 0 }) {
            builder.instrumentFields.append(ITInstrumentExtensionField(
                id: "GULP",
                property: .pluginSlot,
                entrySize: 1,
                values: pluginSlots
            ))
        }
        if extendedMaps.contains(where: { $0 != 0 }) {
            builder.instrumentFields.append(ITInstrumentExtensionField(
                id: "XMAP",
                property: .extendedSampleMap,
                entrySize: 1,
                values: extendedMaps
            ))
        }
    }

    // Nach den Offsettabellen duerfen Edit History, MIDI-Makros und alte
    // ModPlug-IFF-Chunks bis zum ersten echten Payload-Pointer folgen.
    private static func parseHeaderTail(
        data: Data,
        start: Int,
        end: Int,
        flags: Int,
        special: Int,
        builder: inout Builder
    ) throws {
        var cursor = start
        if special & 0x02 != 0 {
            // Einige alte Schism-/UNMO3-Dateien setzen das History-Bit, ohne
            // den Block zu schreiben. Wie OpenMPT akzeptieren wir den Block
            // deshalb nur, wenn er komplett vor dem ersten Parapointer liegt.
            if cursor <= end - 2 {
                let count = unsigned(data, cursor, 2)
                let bytes = count.multipliedReportingOverflow(by: 8)
                if !bytes.overflow, bytes.partialValue <= end - cursor - 2 {
                    cursor += 2 + bytes.partialValue
                }
            }
        }

        if flags & 0x80 != 0 || special & 0x08 != 0 {
            // Auch dieses Flag ist in historischen Exporten gelegentlich
            // falsch gesetzt. Eine fehlende Tabelle darf den PCM-Kern nicht
            // unspielbar machen; tatsächlich vorhandene Tabellen bleiben
            // vollständig und strukturell gebunden.
            if midiConfigurationSize <= end - cursor {
                builder.midiConfiguration = parseMIDIConfiguration(
                    data.subdata(in: cursor..<(cursor + midiConfigurationSize))
                )
                cursor += midiConfigurationSize
            }
        }

        while cursor < end {
            guard cursor <= end - 8 else { break }
            let id = fourCC(data, cursor)
            guard isASCIIChunkID(id) else { break }
            let size = unsigned(data, cursor + 4, 4)
            guard size <= end - cursor - 8 else {
                throw ITParser.ParserError.invalidExtension("abgeschnittener ModPlug-Chunk \(id)")
            }
            let payloadStart = cursor + 8
            let payloadEnd = payloadStart + size
            let payload = data.subdata(in: payloadStart..<payloadEnd)
            try parseLegacyChunk(id: id, payload: payload, builder: &builder)
            cursor = payloadEnd
        }
    }

    private static func parseLegacyChunk(
        id: String,
        payload: Data,
        builder: inout Builder
    ) throws {
        switch id {
        case "PNAM":
            builder.chunks.append(chunk(id, .legacyModPlug, payload.count, .metadata, "Patternnamen"))
        case "CNAM":
            builder.chunks.append(chunk(id, .legacyModPlug, payload.count, .metadata, "Kanalnamen"))
        case "CHFX":
            guard payload.count % 4 == 0 else {
                throw ITParser.ParserError.invalidExtension("ungueltige CHFX-Groesse")
            }
            builder.channelPluginAssignments = stride(from: 0, to: payload.count, by: 4).map {
                unsigned(payload, $0, 4)
            }
            builder.chunks.append(chunk(id, .legacyModPlug, payload.count, .routing, "Kanal-Plugin-Routing"))
        case let value where pluginSlot(from: value) != nil:
            guard payload.count >= 9, let slot = pluginSlot(from: value) else {
                throw ITParser.ParserError.invalidExtension("abgeschnittener Plugin-Chunk \(id)")
            }
            builder.plugins.append(ITPluginDefinition(
                slot: slot,
                typeID: unsigned(payload, 0, 4),
                uniqueID: unsigned(payload, 4, 4),
                routingFlags: unsigned(payload, 8, 1)
            ))
            builder.chunks.append(chunk(id, .legacyModPlug, payload.count, .routing, "Plugin-Slot \(slot)"))
        case "MODU":
            builder.chunks.append(chunk(id, .legacyModPlug, payload.count, .metadata, "BeRoTracker-Erkennung"))
        default:
            builder.chunks.append(chunk(
                id, .legacyModPlug, payload.count, .unknownPlayback,
                "Unbekannter alter ModPlug-Chunk"
            ))
        }
    }

    private static func parseEndExtensions(
        data: Data,
        start: Int,
        instrumentCount: Int,
        builder: inout Builder
    ) throws {
        var cursor = start
        if matchesMarker(data, cursor, ["XTPM", "MPTX"]) {
            cursor += 4
            try parseInstrumentExtensions(
                data: data,
                cursor: &cursor,
                instrumentCount: instrumentCount,
                builder: &builder
            )
        }
        if matchesMarker(data, cursor, ["STPM", "MPTS"]) {
            cursor += 4
            try parseSongExtensions(data: data, cursor: &cursor, builder: &builder)
        }
    }

    private static func parseInstrumentExtensions(
        data: Data,
        cursor: inout Int,
        instrumentCount: Int,
        builder: inout Builder
    ) throws {
        while cursor < data.count {
            if matchesMarker(data, cursor, ["STPM", "MPTS"]) || matches228(data, cursor) {
                return
            }
            guard cursor <= data.count - 6 else {
                throw ITParser.ParserError.invalidExtension("abgeschnittener XTPM-Chunk-Header")
            }
            let id = fourCC(data, cursor)
            guard isASCIIChunkID(id) else {
                throw ITParser.ParserError.invalidExtension("ungueltige XTPM-Chunk-ID")
            }
            let entrySize = unsigned(data, cursor + 4, 2)
            let total = entrySize.multipliedReportingOverflow(by: instrumentCount)
            guard entrySize > 0, !total.overflow,
                  total.partialValue <= data.count - cursor - 6 else {
                throw ITParser.ParserError.invalidExtension("ungueltiger XTPM-Chunk \(id)")
            }
            let payloadStart = cursor + 6
            let values = (0..<instrumentCount).map { instrument in
                sizedUnsigned(data, payloadStart + instrument * entrySize, entrySize)
            }
            let property = instrumentProperty(for: id)
            let classification: ITExtensionClassification = property == nil
                ? .unknownPlayback
                : (property == .pluginSlot || property == .midiChannel ? .routing : .playback)
            builder.chunks.append(chunk(
                id, .instrument, total.partialValue, classification,
                property.map { String(describing: $0) } ?? "Unbekannte Instrumenteigenschaft"
            ))
            if let property {
                builder.instrumentFields.append(ITInstrumentExtensionField(
                    id: id,
                    property: property,
                    entrySize: entrySize,
                    values: values
                ))
            }
            cursor = payloadStart + total.partialValue
        }
    }

    private static func parseSongExtensions(
        data: Data,
        cursor: inout Int,
        builder: inout Builder
    ) throws {
        while cursor < data.count {
            if matches228(data, cursor) { return }
            guard cursor <= data.count - 6 else {
                throw ITParser.ParserError.invalidExtension("abgeschnittener STPM-Chunk-Header")
            }
            let id = fourCC(data, cursor)
            guard isASCIIChunkID(id) else {
                throw ITParser.ParserError.invalidExtension("ungueltige STPM-Chunk-ID")
            }
            let size = unsigned(data, cursor + 4, 2)
            guard size <= data.count - cursor - 6 else {
                throw ITParser.ParserError.invalidExtension("abgeschnittener STPM-Chunk \(id)")
            }
            let payloadStart = cursor + 6
            let payload = data.subdata(in: payloadStart..<(payloadStart + size))
            try parseSongChunk(id: id, payload: payload, builder: &builder)
            cursor = payloadStart + size
        }
    }

    private static func parseSongChunk(
        id: String,
        payload: Data,
        builder: inout Builder
    ) throws {
        let value = sizedUnsigned(payload, 0, payload.count)
        switch id {
        case "..TD":
            builder.defaultTempo = value
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "Default-Tempo \(value)"))
        case "DTFR":
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "Gebrochener MPTM-Tempoanteil \(value)"))
        case ".BPR":
            builder.rowsPerBeat = value
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "\(value) Reihen pro Beat"))
        case ".MPR":
            builder.rowsPerMeasure = value
            builder.chunks.append(chunk(id, .song, payload.count, .metadata, "\(value) Reihen pro Takt"))
        case "...C":
            builder.channelCount = value
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "\(value) Kanaele"))
        case "SnhC":
            guard payload.count % 2 == 0 else {
                throw ITParser.ParserError.invalidExtension("ungueltige SnhC-Groesse")
            }
            builder.extraChannelSettings = stride(from: 0, to: payload.count, by: 2).map { offset in
                let rawPan = unsigned(payload, offset, 1)
                let pan = rawPan & 0x7F
                return ITChannelSetting(
                    panning: pan == 100 ? 32 : min(64, pan),
                    volume: min(64, unsigned(payload, offset + 1, 1)),
                    muted: rawPan & 0x80 != 0,
                    surround: pan == 100
                )
            }
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "Zusaetzliche Kanaleinstellungen"))
        case "..MT":
            builder.rawTempoMode = value
            builder.tempoMode = ITTempoMode(rawValue: value) ?? .classic
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "Tempo-Modus \(value)"))
        case ".MMP":
            builder.rawMixLevel = value
            builder.mixLevel = ITMixLevel(rawValue: value)
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "Mix-Level \(value)"))
        case ".VWC":
            builder.createdWithVersion = OpenMPTVersion(rawValue: value)
            builder.chunks.append(chunk(id, .song, payload.count, .metadata, "Erstellt mit OpenMPT \(builder.createdWithVersion!.displayName)"))
        case "VWSL":
            builder.lastSavedWithVersion = value == 0 ? nil : OpenMPTVersion(rawValue: value)
            let version = builder.lastSavedWithVersion?.displayName ?? "unbekannt"
            builder.chunks.append(chunk(
                id, .song, payload.count, .metadata,
                "Zuletzt gespeichert mit OpenMPT \(version)"
            ))
        case ".APS":
            builder.samplePreamp = value
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "Sample-Preamp \(value)"))
        case "VTSV":
            builder.synthPreamp = value
            builder.chunks.append(chunk(id, .song, payload.count, .routing, "Synth-/Plugin-Preamp \(value)"))
        case "..PR":
            builder.restartPosition = value
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "Restart-Position \(value)"))
        case "RSMP", "CUES", "SWNG":
            builder.chunks.append(chunk(id, .song, payload.count, .playback, "Bekannte MPTM-Wiedergabeeigenschaft"))
        case ".FSM":
            var states: [ITPlayBehaviourState] = []
            for byteIndex in payload.indices {
                let byte = Int(payload[byteIndex])
                for bit in 0..<8 where byte & (1 << bit) != 0 {
                    let position = byteIndex * 8 + bit
                    states.append(ITPlayBehaviourState(
                        bit: position,
                        behaviour: ITPlayBehaviour(rawValue: position)
                    ))
                }
            }
            builder.playBehaviours = states
            builder.chunks.append(chunk(id, .song, payload.count, .compatibility, "OpenMPT-Wiedergabeverhalten"))
        case "AUTH":
            builder.artist = String(data: payload, encoding: .utf8)
            builder.chunks.append(chunk(id, .song, payload.count, .metadata, "Interpret"))
        case "AMIM":
            builder.hasMIDIMapping = !payload.isEmpty
            builder.chunks.append(chunk(id, .song, payload.count, .metadata, "MIDI-Mapping"))
        case "CCOL":
            guard payload.count % 4 == 0 else {
                throw ITParser.ParserError.invalidExtension("ungueltige CCOL-Groesse")
            }
            builder.channelColors = stride(from: 0, to: payload.count, by: 4).map { offset in
                guard unsigned(payload, offset + 3, 1) == 0 else { return nil }
                return unsigned(payload, offset, 1)
                    | (unsigned(payload, offset + 1, 1) << 8)
                    | (unsigned(payload, offset + 2, 1) << 16)
            }
            builder.chunks.append(chunk(id, .song, payload.count, .metadata, "Kanalfarben"))
        default:
            builder.chunks.append(chunk(
                id, .song, payload.count, .unknownPlayback,
                "Unbekannter potentiell klangrelevanter STPM-Chunk"
            ))
        }
    }

    private static func detectMPTM(data: Data, builder: inout Builder) {
        guard data.count >= 8 else { return }
        let pointer = unsigned(data, data.count - 4, 4)
        guard pointer >= 0, pointer <= data.count - 4, matches228(data, pointer) else { return }
        builder.isMPTM = true
        builder.chunks.append(chunk("228\\x04", .mptm, data.count - pointer, .unknownPlayback, "MPTM-Containerdaten"))
    }

    private static func parseMIDIConfiguration(_ data: Data) -> ITMIDIConfiguration {
        let macros = stride(from: 0, to: min(data.count, midiConfigurationSize), by: 32).map { offset in
            let end = min(data.count, offset + 32)
            let bytes = data[offset..<end].prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
                .replacingOccurrences(of: " ", with: "")
        }
        let global = Array(macros.prefix(9))
        let parameterized = Array(macros.dropFirst(9).prefix(16))
        let fixed = Array(macros.dropFirst(25).prefix(128))
        return ITMIDIConfiguration(
            globalMacros: global,
            parameterizedMacros: parameterized,
            fixedMacros: fixed,
            usesDefaultFilterSetup: isDefaultMIDIConfiguration(
                global: global, parameterized: parameterized, fixed: fixed
            )
        )
    }

    private static func isDefaultMIDIConfiguration(
        global: [String],
        parameterized: [String],
        fixed: [String]
    ) -> Bool {
        let expectedGlobal = ["FF", "FC", "", "9cnv", "9cn0", "", "", "", "Ccp"]
        guard global.map({ $0.lowercased() }) == expectedGlobal.map({ $0.lowercased() }),
              parameterized.count == 16, fixed.count == 128,
              parameterized[0].lowercased() == "f0f000z",
              parameterized.dropFirst().allSatisfy({ $0.isEmpty }) else { return false }
        for index in fixed.indices {
            let expected = index < 16 ? String(format: "F0F001%02X", index * 8) : ""
            if fixed[index].lowercased() != expected.lowercased() { return false }
        }
        return true
    }

    private static func instrumentProperty(for id: String) -> ITInstrumentExtensionProperty? {
        switch id {
        case "..OF": return .fadeout
        case "...P": return .panning
        case "..BM": return .midiBank
        case "..PM": return .midiProgram
        case "..CM": return .midiChannel
        case ".PiM": return .pluginSlot
        case "..RV": return .volumeRamp
        case "...R": return .resamplingMode
        case "..SC": return .cutoffSwing
        case "..SR": return .resonanceSwing
        case "..MF": return .filterMode
        case "HEVP": return .pluginVelocityHandling
        case "HOVP": return .pluginVolumeHandling
        case "NREV": return .volumeEnvelopeReleaseNode
        case "NREA": return .panningEnvelopeReleaseNode
        case "NREP": return .pitchEnvelopeReleaseNode
        case "DWPM": return .midiPitchWheelDepth
        case "LTTP": return .pitchTempoLockInteger
        case "PTTF": return .pitchTempoLockFraction
        case "..EV", "..EP", ".EiP", ".[PV", ".[EV", ".[PP", ".[EP", "[PiP", "[EiP",
             ".SLV", ".ELV", ".SBV", ".SEV", ".SLP", ".ELP", ".SBP", ".SEP",
             "SLiP", "ELiP", "SBiP", "SEiP", ".ANN", ".TCD", ".AND", "..SP",
             "..SV", ".CFI", ".RFI", ".SPP", ".CPP", "GFLV", "GFLA", "GFLP",
             ".[MN", "..n[", ".nf[":
            return .otherKnown
        default:
            return nil
        }
    }

    private static func pluginSlot(from id: String) -> Int? {
        let bytes = Array(id.utf8)
        guard bytes.count == 4, bytes[0] == 0x46 else { return nil }
        if bytes[1] == 0x58,
           let tens = digit(bytes[2]), let ones = digit(bytes[3]) {
            return tens * 10 + ones + 1
        }
        if let hundreds = digit(bytes[1]), let tens = digit(bytes[2]), let ones = digit(bytes[3]) {
            return hundreds * 100 + tens * 10 + ones + 1
        }
        return nil
    }

    private static func digit(_ byte: UInt8) -> Int? {
        guard byte >= 48, byte <= 57 else { return nil }
        return Int(byte - 48)
    }

    private static func chunk(
        _ id: String,
        _ context: ITExtensionContext,
        _ size: Int,
        _ classification: ITExtensionClassification,
        _ summary: String
    ) -> ITExtensionChunk {
        ITExtensionChunk(
            id: id,
            context: context,
            size: size,
            classification: classification,
            summary: summary
        )
    }

    private static func matchesMarker(_ data: Data, _ offset: Int, _ markers: [String]) -> Bool {
        guard offset >= 0, offset <= data.count - 4 else { return false }
        return markers.contains { fourCC(data, offset) == $0 }
    }

    private static func matches228(_ data: Data, _ offset: Int) -> Bool {
        guard offset >= 0, offset <= data.count - 4 else { return false }
        return data[offset] == 0x32 && data[offset + 1] == 0x32
            && data[offset + 2] == 0x38 && data[offset + 3] == 0x04
    }

    private static func fourCC(_ data: Data, _ offset: Int) -> String {
        guard offset >= 0, offset <= data.count - 4 else { return "" }
        return String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
    }

    private static func isASCIIChunkID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        return bytes.count == 4 && bytes.allSatisfy { (0x20...0x7F).contains($0) }
    }

    private static func unsigned(_ data: Data, _ offset: Int, _ size: Int) -> Int {
        guard offset >= 0, size >= 0, offset <= data.count - size else { return 0 }
        var value: UInt64 = 0
        for index in 0..<min(size, 8) {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        return Int(truncatingIfNeeded: value)
    }

    private static func sizedUnsigned(_ data: Data, _ offset: Int, _ size: Int) -> Int {
        unsigned(data, offset, min(size, 8))
    }
}

// Defensive Erstellererkennung nach der aktuellen OpenMPT-Tracker-ID-Tabelle.
// Nur cmwt wird spaeter fuer die Strukturkompatibilitaet ausgewertet.
enum ITTrackerDetector {
    static func identify(
        createdWithVersion cwtv: Int,
        compatibleWithVersion cmwt: Int,
        reserved: Int,
        extensions: ITOpenMPTExtensions
    ) -> ITTrackerIdentity {
        let high = cwtv & 0xF000
        let low = cwtv & 0x0FFF
        switch high {
        case 0x0000:
            let major = (cwtv >> 8) & 0x0F
            let minor = cwtv & 0xFF
            return ITTrackerIdentity(
                family: .impulseTracker,
                rawCreatedWith: cwtv,
                displayName: String(format: "Impulse Tracker %d.%02X", major, minor)
            )
        case 0x1000:
            return ITTrackerIdentity(
                family: .schismTracker,
                rawCreatedWith: cwtv,
                displayName: schismDisplayName(cwtv: cwtv, reserved: reserved)
            )
        case 0x4000:
            return ITTrackerIdentity(
                family: .pyIT,
                rawCreatedWith: cwtv,
                displayName: String(format: "pyIT %d.%02X", (low >> 8) & 0x0F, low & 0xFF)
            )
        case 0x5000:
            let major = (low >> 8) & 0x0F
            let minor = low & 0xFF
            let reservedBytes = (0..<4).map { UInt8(truncatingIfNeeded: reserved >> ($0 * 8)) }
            let compatibilityExport = String(decoding: reservedBytes, as: UTF8.self) != "OMPT"
            let full = extensions.lastSavedWithVersion ?? extensions.createdWithVersion
            let display = full.map { "OpenMPT \($0.displayName)" }
                ?? String(format: "OpenMPT %d.%02X", major, minor)
            return ITTrackerIdentity(
                family: .openMPT,
                rawCreatedWith: cwtv,
                displayName: display + (compatibilityExport ? " (Kompatibilitaetsexport)" : ""),
                compatibilityExport: compatibilityExport,
                createdWithOpenMPT: extensions.createdWithVersion,
                lastSavedWithOpenMPT: extensions.lastSavedWithVersion ?? full
            )
        case 0x6000:
            return simple(.beRoTracker, "BeRoTracker", cwtv)
        case 0x7000:
            if cwtv == 0x7FFF, cmwt == 0x0215 { return simple(.munch, "munch.py", cwtv) }
            return ITTrackerIdentity(
                family: .itmck,
                rawCreatedWith: cwtv,
                displayName: String(format: "ITMCK %d.%d.%d", (cwtv >> 8) & 0x0F, (cwtv >> 4) & 0x0F, cwtv & 0x0F)
            )
        case 0x8000:
            return simple(.tralala, "Tralala", cwtv)
        case 0xC000:
            return simple(.chickDune, "ChickDune ChipTune Tracker", cwtv)
        case 0xD000:
            if cwtv == 0xDAEB { return simple(.spc2it, "spc2it", cwtv) }
            if cwtv == 0xD1CE { return simple(.itwriter, "itwriter", cwtv) }
            return simple(.unknown, String(format: "Unbekannter Tracker (cwtv=0x%04X)", cwtv), cwtv)
        case 0xE000 where cwtv == 0xEFFF:
            return simple(.roseTracker, "rosetracker", cwtv)
        default:
            return simple(.unknown, String(format: "Unbekannter Tracker (cwtv=0x%04X)", cwtv), cwtv)
        }
    }

    private static func simple(_ family: ITTrackerFamily, _ name: String, _ raw: Int) -> ITTrackerIdentity {
        ITTrackerIdentity(family: family, rawCreatedWith: raw, displayName: name)
    }

    private static func schismDisplayName(cwtv: Int, reserved: Int) -> String {
        let value = cwtv & 0x0FFF
        if value <= 0x50 { return String(format: "Schism Tracker 0.%02X", value) }
        let days = value < 0x0FFF ? value - 0x50 : reserved
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2009
        components.month = 10
        components.day = 31
        guard let epoch = components.date,
              let date = components.calendar?.date(byAdding: .day, value: days, to: epoch) else {
            return "Schism Tracker"
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return "Schism Tracker \(formatter.string(from: date))"
    }
}

// Erstellt aus Dateiinhalt, Engine-Faehigkeiten und tatsaechlich erreichbaren
// Patterndaten die Warnmatrix. Nur verwendete, fehlende Audiofaehigkeiten werden
// nach aussen als Warnung ausgegeben.
enum ITCapabilityAnalyzer {
    private struct Usage {
        var instruments = Set<Int>()
        // 1-basierte IT-Sample-IDs, aber nur fuer wirklich getriggerte Noten.
        var samples = Set<Int>()
        var channels = Set<Int>()
        var audibleChannels = Set<Int>()
        var commands = Set<Int>()
        var usesInstrumentOnlyCell = false
        var usesPortamento = false
        var usesTonePortamento = false
        var usesVolumeColumnTonePortamento = false
        var usesTonePortamentoWithoutNote = false
        var usesPatternLoop = false
        var usesNoteDelay = false
        var usesNoteCut = false
        var usesRowDelayWithNoteDelay = false
        var usesNoteOff = false
        var usesFilterMacro = false
        var usesFilterResetOnPortaSampleChange = false
        var usesInitialNoteMemory = false
        var usesEmptyMapSlot = false
        var usesInstrumentOnlyOffset = false
        var usesDoublePortamento = false
        var usesCarryAfterNoteOff = false
        var usesNoteCutWithPortamento = false
        var usesStoppedFilterEnvelopeAtStart = false
        var usesInstrumentWithNoteOff = false
        var usesReleaseNode = false
        var usesReleaseNodePastSustain = false
        var usesSurroundPanningOverride = false
        var usesVolumeColumnSlide = false
        var usesEffectColumnVolumeSlide = false
        var usesSpeedOne = false
        var customMIDIMacroDetails: [String] = []
    }

    static func analyze(
        compatibleWithVersion: Int,
        initialSpeed: Int,
        usesInstruments: Bool,
        usesMIDIPitchController: Bool,
        unknownHeaderFlags: Int,
        unknownSpecialFlags: Int,
        extensions: ITOpenMPTExtensions,
        instruments: [Instrument?],
        samples: [Sample],
        patterns: [Pattern],
        patternTable: [Int]
    ) -> ITCapabilityReport {
        let usage = collectUsage(
            extensions: extensions,
            initialSpeed: initialSpeed,
            usesInstruments: usesInstruments,
            instruments: instruments,
            samples: samples,
            patterns: patterns,
            patternTable: patternTable
        )
        var findings: [ITCapabilityFinding] = []

        // cmwt=2.16 kennzeichnet in OpenMPT/Schism die IT-Filter-Envelope-
        // Interpretation. Savage parst und rendert diese bereits; erst eine
        // unbekannte neuere Strukturversion ist eine echte Capability-Luecke.
        let supportedFormat = compatibleWithVersion <= 0x0216
        findings.append(ITCapabilityFinding(
            feature: .formatCompatibility,
            identifier: String(format: "cmwt=0x%04X", compatibleWithVersion),
            detected: true,
            // cmwt beschreibt die Semantik der gesamten geladenen IT-Datei und
            // ist daher immer verwendet, nicht erst im Fehlerfall.
            used: true,
            support: supportedFormat ? .supported : .unsupported,
            detail: supportedFormat ? "IT-2.14-/2.15-/2.16-Struktur" : "Neuere IT-Struktursemantik",
            warning: supportedFormat ? nil : String(
                format: "Die Datei benoetigt IT %X.%02X; Savage unterstuetzt IT 2.14/2.15/2.16.",
                compatibleWithVersion >> 8,
                compatibleWithVersion & 0xFF
            )
        ))

        let tempoModeKnown = extensions.rawTempoMode == nil
            || ITTempoMode(rawValue: extensions.rawTempoMode!) != nil
        findings.append(ITCapabilityFinding(
            feature: .tempoMode,
            identifier: "tempo-mode",
            detected: extensions.rawTempoMode != nil,
            used: extensions.rawTempoMode != nil,
            support: tempoModeKnown ? .supported : .unsupported,
            detail: tempoModeKnown ? String(describing: extensions.tempoMode) : "Unbekannter Modus \(extensions.rawTempoMode!)",
            warning: tempoModeKnown ? nil : "Der Song verwendet den unbekannten OpenMPT-Tempo-Modus \(extensions.rawTempoMode!); das Timing kann abweichen."
        ))

        if let rawMix = extensions.rawMixLevel {
            let supported = rawMix == ITMixLevel.original.rawValue
                || rawMix == ITMixLevel.compatible.rawValue
            findings.append(ITCapabilityFinding(
                feature: .mixLevel,
                identifier: "mix-level-\(rawMix)",
                detected: true,
                used: true,
                support: supported ? .supported : .differentPlayback,
                detail: extensions.mixLevel.map { String(describing: $0) } ?? "Unbekannt",
                warning: supported ? nil : "Der Song verwendet OpenMPT-Mix-Level \(rawMix); Savage mischt diesen Modus noch nicht exakt nach."
            ))
        }

        if let preamp = extensions.samplePreamp {
            findings.append(ITCapabilityFinding(
                feature: .samplePreamp,
                identifier: "sample-preamp",
                detected: true,
                used: true,
                support: .supported,
                detail: "Sample-Preamp \(preamp)"
            ))
        }
        if let restart = extensions.restartPosition {
            findings.append(ITCapabilityFinding(
                feature: .restartPosition,
                identifier: "restart-position",
                detected: true,
                used: restart > 0,
                support: .supported,
                detail: "Order \(restart)"
            ))
        }
        if let channels = extensions.channelCount {
            let supported = (1...64).contains(channels)
            findings.append(ITCapabilityFinding(
                feature: .channelLayout,
                identifier: "channels",
                detected: true,
                used: true,
                support: supported ? .supported : .unsupported,
                detail: "\(channels) deklarierte Kanaele",
                warning: supported ? nil : "Der Song deklariert \(channels) Kanaele; Savage kann hoechstens 64 IT-Kanaele wiedergeben."
            ))
        }

        if extensions.isMPTM {
            findings.append(ITCapabilityFinding(
                feature: .mptmContainer,
                identifier: "228\\x04",
                detected: true,
                used: true,
                support: .unsupported,
                detail: "MPTM-spezifischer Container",
                warning: "Die Datei verwendet MPTM-Containerdaten; MPTM ist kein unterstuetztes Wiedergabeformat."
            ))
        }

        for state in extensions.playBehaviours {
            findings.append(playBehaviourFinding(
                state,
                usage: usage,
                usesInstruments: usesInstruments,
                samples: samples,
                instruments: instruments
            ))
        }

        appendInstrumentPropertyFindings(
            extensions: extensions,
            usage: usage,
            findings: &findings
        )

        var usedMIDIInstrument = false
        for instrumentIndex in usage.instruments.sorted() {
            guard instruments.indices.contains(instrumentIndex),
                  let properties = instruments[instrumentIndex]?.itProperties else { continue }
            if properties.midiChannel > 0 {
                usedMIDIInstrument = true
                findings.append(ITCapabilityFinding(
                    feature: .midiInstrument,
                    identifier: "instrument-\(instrumentIndex)",
                    detected: true,
                    used: true,
                    support: .unsupported,
                    detail: "MIDI-Kanal \(properties.midiChannel)",
                    warning: "Instrument \(instrumentIndex) sendet Noten an MIDI-Kanal \(properties.midiChannel); externe MIDI-Ausgabe wird nicht wiedergegeben."
                ))
            }
            if let slot = properties.pluginSlot, slot > 0 {
                findings.append(ITCapabilityFinding(
                    feature: .pluginInstrument,
                    identifier: "instrument-\(instrumentIndex)-plugin-\(slot)",
                    detected: true,
                    used: true,
                    support: .unsupported,
                    detail: "Plugin-Slot \(slot)",
                    warning: "Instrument \(instrumentIndex) verwendet Plugin-Slot \(slot); Plugin-Audio wird nicht wiedergegeben."
                ))
            }
        }

        if usesMIDIPitchController, usedMIDIInstrument {
            findings.append(ITCapabilityFinding(
                feature: .midiInstrument,
                identifier: "midi-pitch-controller",
                detected: true,
                used: true,
                support: .unsupported,
                detail: "MIDI-Pitchsteuerung",
                warning: "Der verwendete MIDI-Instrumentpfad nutzt externe Pitchsteuerung; diese MIDI-Daten werden nicht ausgegeben."
            ))
        }

        for channel in usage.audibleChannels.sorted() where extensions.channelPluginAssignments.indices.contains(channel) {
            let slot = extensions.channelPluginAssignments[channel]
            guard slot > 0 else { continue }
            findings.append(ITCapabilityFinding(
                feature: .channelPlugin,
                identifier: "channel-\(channel + 1)-plugin-\(slot)",
                detected: true,
                used: true,
                support: .unsupported,
                detail: "Kanal \(channel + 1) -> Plugin-Slot \(slot)",
                warning: "Kanal \(channel + 1) routet hoerbares Material an Plugin-Slot \(slot); der Plugin-Effekt wird nicht wiedergegeben."
            ))
        }
        for plugin in extensions.plugins
        where plugin.routingFlags & 0x01 != 0 && !usage.audibleChannels.isEmpty {
            findings.append(ITCapabilityFinding(
                feature: .masterPlugin,
                identifier: "master-plugin-\(plugin.slot)",
                detected: true,
                used: true,
                support: .unsupported,
                detail: "Plugin-Slot \(plugin.slot) liegt auf dem Mastermix",
                warning: "Plugin-Slot \(plugin.slot) bearbeitet den Mastermix; dieser Plugin-Effekt wird nicht wiedergegeben."
            ))
        }

        for detail in usage.customMIDIMacroDetails {
            findings.append(ITCapabilityFinding(
                feature: .midiMacro,
                identifier: detail,
                detected: true,
                used: true,
                support: .unsupported,
                detail: detail,
                warning: "Der Song verwendet das nicht unterstuetzte MIDI-/Plugin-Makro \(detail)."
            ))
        }

        for extensionChunk in extensions.chunks where extensionChunk.classification == .unknownPlayback {
            let used = extensionChunk.context == .instrument
                ? !usage.instruments.isEmpty
                : true
            findings.append(ITCapabilityFinding(
                feature: .unknownExtension,
                identifier: extensionChunk.id,
                detected: true,
                used: used,
                support: .unsupported,
                detail: extensionChunk.summary,
                warning: "Unbekannter klangrelevanter \(extensionChunk.context.rawValue)-Chunk \(extensionChunk.id) wird ignoriert."
            ))
        }
        if unknownHeaderFlags != 0 {
            findings.append(ITCapabilityFinding(
                feature: .unknownExtension,
                identifier: String(format: "header-0x%04X", unknownHeaderFlags),
                detected: true,
                used: true,
                support: .unsupported,
                detail: "Unbekannte IT-Headerflags",
                warning: String(format: "Unbekannte klangrelevante IT-Headerflags 0x%04X werden ignoriert.", unknownHeaderFlags)
            ))
        }
        if unknownSpecialFlags != 0 {
            findings.append(ITCapabilityFinding(
                feature: .unknownExtension,
                identifier: String(format: "special-0x%04X", unknownSpecialFlags),
                detected: true,
                used: true,
                support: .unsupported,
                detail: "Unbekannte IT-Specialflags",
                warning: String(format: "Unbekannte klangrelevante IT-Specialflags 0x%04X werden ignoriert.", unknownSpecialFlags)
            ))
        }
        return ITCapabilityReport(findings: findings)
    }

    private static func appendInstrumentPropertyFindings(
        extensions: ITOpenMPTExtensions,
        usage: Usage,
        findings: inout [ITCapabilityFinding]
    ) {
        for field in extensions.instrumentFields {
            for instrument in usage.instruments.sorted() {
                guard instrument > 0, field.values.indices.contains(instrument - 1) else { continue }
                let value = field.values[instrument - 1]
                let identifier = "instrument-\(instrument)-\(field.id)"
                switch field.property {
                case .fadeout, .panning:
                    findings.append(ITCapabilityFinding(
                        feature: .instrumentProperty,
                        identifier: identifier,
                        detected: true,
                        used: true,
                        support: .supported,
                        detail: "Instrument \(instrument): \(field.property.rawValue)=\(value)"
                    ))
                case .midiBank, .midiProgram, .midiChannel, .pluginSlot,
                     .midiPitchWheelDepth, .pluginVelocityHandling, .pluginVolumeHandling:
                    // Die eigentliche Warnung wird nur erzeugt, wenn der damit
                    // konfigurierte MIDI-/Plugin-Pfad im Pattern erreicht wird.
                    continue
                case .volumeRamp:
                    appendUnsupportedInstrumentProperty(
                        field: field, instrument: instrument, value: value,
                        active: value > 0,
                        detail: "individuelle Lautstaerkerampe",
                        findings: &findings
                    )
                case .resamplingMode:
                    appendUnsupportedInstrumentProperty(
                        field: field, instrument: instrument, value: value,
                        active: value >= 0 && value < 5,
                        detail: "individueller Resampling-Modus",
                        findings: &findings
                    )
                case .cutoffSwing:
                    appendUnsupportedInstrumentProperty(
                        field: field, instrument: instrument, value: value,
                        active: value > 0,
                        detail: "zufaellige Filter-Cutoff-Abweichung",
                        findings: &findings
                    )
                case .resonanceSwing:
                    appendUnsupportedInstrumentProperty(
                        field: field, instrument: instrument, value: value,
                        active: value > 0,
                        detail: "zufaellige Filter-Resonanz-Abweichung",
                        findings: &findings
                    )
                case .filterMode:
                    appendUnsupportedInstrumentProperty(
                        field: field, instrument: instrument, value: value,
                        active: value == 1,
                        detail: "Hochpass-Filtermodus",
                        findings: &findings
                    )
                case .volumeEnvelopeReleaseNode, .panningEnvelopeReleaseNode,
                     .pitchEnvelopeReleaseNode:
                    appendUnsupportedInstrumentProperty(
                        field: field, instrument: instrument, value: value,
                        active: value != 0xFF,
                        detail: "Envelope-Release-Knoten",
                        findings: &findings
                    )
                case .pitchTempoLockInteger, .pitchTempoLockFraction:
                    appendUnsupportedInstrumentProperty(
                        field: field, instrument: instrument, value: value,
                        active: value != 0,
                        detail: "Pitch-/Tempo-Lock",
                        findings: &findings
                    )
                case .extendedSampleMap:
                    appendUnsupportedInstrumentProperty(
                        field: field, instrument: instrument, value: value,
                        active: value != 0,
                        detail: "erweiterte Sample-Map ueber 255 Samples",
                        findings: &findings
                    )
                case .otherKnown:
                    appendUnsupportedInstrumentProperty(
                        field: field, instrument: instrument, value: value,
                        active: true,
                        detail: "weitere bekannte OpenMPT-Instrumenteigenschaft",
                        findings: &findings
                    )
                }
            }
        }
    }

    private static func appendUnsupportedInstrumentProperty(
        field: ITInstrumentExtensionField,
        instrument: Int,
        value: Int,
        active: Bool,
        detail: String,
        findings: inout [ITCapabilityFinding]
    ) {
        guard active else { return }
        findings.append(ITCapabilityFinding(
            feature: .instrumentProperty,
            identifier: "instrument-\(instrument)-\(field.id)",
            detected: true,
            used: true,
            support: .differentPlayback,
            detail: "Instrument \(instrument): \(detail) (\(field.id)=\(value))",
            warning: "Instrument \(instrument) verwendet \(detail) (\(field.id)=\(value)); Savage bildet diese Klangeigenschaft noch nicht exakt nach."
        ))
    }

    private static func collectUsage(
        extensions: ITOpenMPTExtensions,
        initialSpeed: Int,
        usesInstruments: Bool,
        instruments: [Instrument?],
        samples: [Sample],
        patterns: [Pattern],
        patternTable: [Int]
    ) -> Usage {
        var usage = Usage()
        usage.usesSpeedOne = initialSpeed == 1
        var macroSelection = [Int](repeating: 0, count: 64)
        var selectedInstrument = [Int](repeating: 0, count: 64)
        var hasSeenNote = [Bool](repeating: false, count: 64)
        var filterActive = [Bool](repeating: false, count: 64)
        var surroundActive = [Bool](repeating: false, count: 64)
        var releasedInstrument = [Int?](repeating: nil, count: 64)
        for patternIndex in patternTable where patterns.indices.contains(patternIndex) {
            for row in patterns[patternIndex].rows {
                var rowHasDelay = false
                var rowHasNoteDelay = false
                for (channel, note) in row.notes.enumerated() {
                    guard channel < 64 else { continue }
                    let hasMusicalContent = note.instrument > 0 || note.key >= 0 || note.specialNote != nil
                        || note.period > 0 || note.volume >= 0 || note.hasEffect
                    if hasMusicalContent { usage.channels.insert(channel) }
                    let command = note.hasEffect
                        && note.effectId > ModuleEffect.impulseTrackerCommandBase
                        ? note.effectId - ModuleEffect.impulseTrackerCommandBase
                        : 0
                    let normalNote = note.key >= 0 && note.key < 120
                    let volumeTonePortamento = (193...202).contains(note.volume)
                    let tonePortamento = command == 7 || command == 12 || volumeTonePortamento
                    let anyPortamento = command == 5 || command == 6 || tonePortamento

                    if !hasSeenNote[channel], !normalNote,
                       note.instrument > 0 || tonePortamento || command == 15 {
                        usage.usesInitialNoteMemory = true
                    }
                    if note.instrument > 0 { selectedInstrument[channel] = note.instrument }
                    let instrumentIndex = selectedInstrument[channel]
                    let selected = instruments.indices.contains(instrumentIndex)
                        ? instruments[instrumentIndex]
                        : nil

                    if normalNote {
                        if instrumentIndex > 0 { usage.instruments.insert(instrumentIndex) }
                        let mappedSampleID = selected?.noteSampleMapping?
                            .entry(forSourceNote: note.key)?.sampleID ?? 0
                        let hasPCM: Bool
                        if usesInstruments {
                            hasPCM = mappedSampleID > 0
                                && samples.indices.contains(mappedSampleID - 1)
                                && !samples[mappedSampleID - 1].pcm.isEmpty
                        } else {
                            hasPCM = selected?.primarySample.map { !$0.pcm.isEmpty } == true
                        }
                        let hasExternalPath = selected?.itProperties.map {
                            $0.midiChannel > 0 || ($0.pluginSlot ?? 0) > 0
                        } == true
                        if hasPCM || hasExternalPath {
                            usage.audibleChannels.insert(channel)
                        }
                        if hasPCM {
                            let sampleID = usesInstruments ? mappedSampleID : instrumentIndex
                            if sampleID > 0 { usage.samples.insert(sampleID) }
                        }
                        if usesInstruments,
                           let mapping = selected?.noteSampleMapping?.entry(forSourceNote: note.key),
                           mapping.sampleID == 0 {
                            usage.usesEmptyMapSlot = true
                        }
                        if let released = releasedInstrument[channel], released == instrumentIndex,
                           selected.map({ instrument in
                               instrument.volumeEnvelope?.carryEnabled == true
                                   || instrument.panningEnvelope?.carryEnabled == true
                                   || instrument.pitchEnvelope?.carryEnabled == true
                           }) == true {
                            usage.usesCarryAfterNoteOff = true
                        }
                        releasedInstrument[channel] = nil
                        hasSeenNote[channel] = true
                    }
                    if note.instrument > 0, note.key < 0, note.specialNote == nil {
                        usage.usesInstrumentOnlyCell = true
                    }
                    if note.specialNote == .off {
                        usage.usesNoteOff = true
                        if note.instrument > 0 { usage.usesInstrumentWithNoteOff = true }
                        releasedInstrument[channel] = instrumentIndex > 0 ? instrumentIndex : nil
                    }
                    if note.volume >= 65, note.volume <= 124 { usage.usesVolumeColumnSlide = true }
                    if volumeTonePortamento {
                        usage.usesVolumeColumnTonePortamento = true
                    }
                    if anyPortamento { usage.usesPortamento = true }
                    if tonePortamento {
                        usage.usesTonePortamento = true
                        if !normalNote { usage.usesTonePortamentoWithoutNote = true }
                    }
                    if command == 15, note.instrument > 0, !normalNote {
                        usage.usesInstrumentOnlyOffset = true
                    }
                    if volumeTonePortamento, [5, 6, 7, 12].contains(command) {
                        usage.usesDoublePortamento = true
                    }
                    if !usesInstruments, tonePortamento, note.instrument > 0,
                       filterActive[channel] {
                        usage.usesFilterResetOnPortaSampleChange = true
                    }
                    if surroundActive[channel],
                       command == 24 || command == 16 || (128...192).contains(note.volume) {
                        usage.usesSurroundPanningOverride = true
                    }

                    guard command > 0 else { continue }
                    usage.commands.insert(command)
                    if command == 1, note.effectData == 1 { usage.usesSpeedOne = true }
                    if command == 4 || command == 11 || command == 12 {
                        usage.usesEffectColumnVolumeSlide = true
                    }
                    if command == 19 {
                        let subcommand = (note.effectData >> 4) & 0x0F
                        if subcommand == 0x0B { usage.usesPatternLoop = true }
                        if subcommand == 0x06 { rowHasDelay = true }
                        if subcommand == 0x08, surroundActive[channel] {
                            usage.usesSurroundPanningOverride = true
                        }
                        if subcommand == 0x09 {
                            surroundActive[channel] = note.effectLow == 1
                        }
                        if subcommand == 0x0C {
                            usage.usesNoteCut = true
                            if volumeTonePortamento { usage.usesNoteCutWithPortamento = true }
                        }
                        if subcommand == 0x0D {
                            usage.usesNoteDelay = true
                            rowHasNoteDelay = true
                        }
                        if subcommand == 0x07, note.effectLow == 0x0B,
                           normalNote, selected?.pitchEnvelope?.valueMode == .filter {
                            usage.usesStoppedFilterEnvelopeAtStart = true
                        }
                        if subcommand == 0x0F, channel < macroSelection.count {
                            macroSelection[channel] = note.effectData & 0x0F
                        }
                    }
                    if command == 26 {
                        usage.usesFilterMacro = true
                        filterActive[channel] = true
                        if let detail = unsupportedMacroDetail(
                            parameter: note.effectData,
                            selection: channel < macroSelection.count ? macroSelection[channel] : 0,
                            configuration: extensions.midiConfiguration
                        ) {
                            let command = String(format: "%02X", note.effectData)
                            usage.customMIDIMacroDetails.append(
                                "Kanal \(channel + 1), Z\(command): \(detail)"
                            )
                        }
                    }
                }
                if rowHasDelay && rowHasNoteDelay {
                    usage.usesRowDelayWithNoteDelay = true
                }
            }
        }
        usage.customMIDIMacroDetails = Array(Set(usage.customMIDIMacroDetails)).sorted()
        // Release-Knoten sind XTPM-Instrumentfelder. Auch dazu gehoerende alte
        // MSF.-Semantik ist nur relevant, wenn genau dieses Instrument in der
        // abgespielten Order-Liste getriggert wird.
        for field in extensions.instrumentFields where [
            ITInstrumentExtensionProperty.volumeEnvelopeReleaseNode,
            .panningEnvelopeReleaseNode,
            .pitchEnvelopeReleaseNode,
        ].contains(field.property) {
            for instrumentID in usage.instruments {
                let valueIndex = instrumentID - 1
                guard field.values.indices.contains(valueIndex) else { continue }
                let releaseNode = field.values[valueIndex]
                guard releaseNode != 0xFF else { continue }
                usage.usesReleaseNode = true
                guard instruments.indices.contains(instrumentID),
                      let instrument = instruments[instrumentID] else { continue }
                let envelope: Envelope?
                switch field.property {
                case .volumeEnvelopeReleaseNode: envelope = instrument.volumeEnvelope
                case .panningEnvelopeReleaseNode: envelope = instrument.panningEnvelope
                case .pitchEnvelopeReleaseNode: envelope = instrument.pitchEnvelope
                default: envelope = nil
                }
                if let envelope,
                   envelope.sustainEnabled,
                   releaseNode > envelope.sustainEnd {
                    usage.usesReleaseNodePastSustain = true
                }
            }
        }
        return usage
    }

    private static func unsupportedMacroDetail(
        parameter: Int,
        selection: Int,
        configuration: ITMIDIConfiguration?
    ) -> String? {
        guard let configuration else { return nil }
        let macro: String
        if parameter < 0x80 {
            guard configuration.parameterizedMacros.indices.contains(selection) else { return "ungueltige Makrobank" }
            macro = configuration.parameterizedMacros[selection]
            if macro.lowercased() == "f0f000z" { return nil }
        } else {
            let index = parameter - 0x80
            guard configuration.fixedMacros.indices.contains(index) else { return "ungueltiges Festmakro" }
            macro = configuration.fixedMacros[index]
            if index < 16, macro.lowercased() == String(format: "F0F001%02X", index * 8).lowercased() {
                return nil
            }
        }
        return macro.isEmpty ? nil : macro
    }

    private static func playBehaviourFinding(
        _ state: ITPlayBehaviourState,
        usage: Usage,
        usesInstruments: Bool,
        samples: [Sample],
        instruments: [Instrument?]
    ) -> ITCapabilityFinding {
        let support = playBehaviourSupport(state)
        let used = playBehaviourUsed(
            state,
            usage: usage,
            usesInstruments: usesInstruments,
            samples: samples,
            instruments: instruments
        )
        let name = state.behaviour?.displayName ?? "unbekanntes Bit \(state.bit)"
        let needsGenericWarning = support == .unsupported || support == .differentPlayback
        // Bits 94/97 werden durch das konkrete NREV/NREA/NREP-Instrumentfeld
        // bereits mit Instrumentnummer und Wert gemeldet. Eine zweite generische
        // Warnung wuerde denselben fehlenden Release-Knoten doppelt anzeigen.
        let warning = needsGenericWarning && ![94, 97].contains(state.bit)
            ? "OpenMPT-Wiedergabeverhalten \(name) (Bit \(state.bit)) wird fuer diesen Song noch nicht unterstuetzt."
            : nil
        return ITCapabilityFinding(
            feature: .playBehaviour,
            identifier: "MSF.\(state.bit)",
            detected: true,
            used: used,
            support: support,
            detail: name,
            warning: warning
        )
    }

    private static func playBehaviourSupport(_ state: ITPlayBehaviourState) -> ITCapabilitySupport {
        guard let behaviour = state.behaviour else { return .unsupported }
        let bit = behaviour.rawValue
        if bit == 0 { return .metadataOnly }
        if [2, 3, 101, 117, 121, 126, 130, 131].contains(bit) { return .midiOrPluginOnly }
        if bit == 6
            || ((7...50).contains(bit) && bit != 49)
            || [87, 88, 100, 102, 103, 104, 115, 119, 120, 122, 123, 124,
                127, 132, 134, 135, 136].contains(bit) {
            return .supported
        }
        if [1, 49, 94, 97, 116].contains(bit) {
            return .unsupported
        }
        return .irrelevantForPCM
    }

    private static func playBehaviourUsed(
        _ state: ITPlayBehaviourState,
        usage: Usage,
        usesInstruments: Bool,
        samples: [Sample],
        instruments: [Instrument?]
    ) -> Bool {
        guard let behaviour = state.behaviour else { return true }
        let bit = behaviour.rawValue
        let usedInstruments = usage.instruments.compactMap { index -> Instrument? in
            guard instruments.indices.contains(index) else { return nil }
            return instruments[index]
        }
        let usedSamples = usage.samples.compactMap { sampleID -> Sample? in
            let index = sampleID - 1
            return samples.indices.contains(index) ? samples[index] : nil
        }
        let usesInstrumentNotes = usesInstruments && !usedInstruments.isEmpty
        let usesPingPong = usedSamples.contains {
            $0.loopType == .pingpong || $0.sustainLoop?.type == .pingpong
        }
        let usesEnvelopes = usedInstruments.contains {
            $0.volumeEnvelope != nil || $0.panningEnvelope != nil || $0.pitchEnvelope != nil
        }
        let usesFilter = usage.usesFilterMacro || usedInstruments.compactMap(\.itProperties).contains {
            $0.initialFilterCutoff != nil || $0.initialFilterResonance != nil
        }
        let usesSwing = usedInstruments.compactMap(\.itProperties).contains {
            $0.randomVolumeVariation > 0 || $0.randomPanningVariation > 0
        }
        let usesMultipleSamples = usedInstruments.contains { instrument in
            guard let mapping = instrument.noteSampleMapping else { return false }
            return Set(mapping.entries.map(\.sampleID).filter { $0 > 0 }).count > 1
        }
        let usesPitchPanSeparation = usedInstruments.compactMap(\.itProperties).contains {
            $0.pitchPanSeparation != 0
        }
        switch bit {
        case 0: return false
        case 1: return usesSwing
        case 2, 3, 101, 117, 121, 126, 130, 131: return false
        case 6:
            return usage.usesSpeedOne
                && (!usage.commands.intersection([5, 6, 7, 12]).isEmpty
                    || usage.usesVolumeColumnTonePortamento)
        case 7, 8: return !usage.channels.isEmpty
        case 9: return usage.commands.contains(23)
        case 10: return usage.usesSurroundPanningOverride
        case 11: return usesInstruments && usage.usesInstrumentOnlyCell
        case 12: return usage.usesVolumeColumnTonePortamento
        case 13: return usage.commands.contains(10)
        case 14: return usage.usesNoteDelay
        case 15: return usage.usesPortamento
        case 25: return usage.usesTonePortamento
        case 32, 42: return usage.usesTonePortamento && usesInstruments
        case 39: return usage.usesTonePortamentoWithoutNote
        case 40: return usage.usesTonePortamento && usage.usesNoteOff
        case 46: return usage.usesTonePortamento
        case 16, 17, 26, 49, 103: return usage.usesPatternLoop
        case 18, 33, 116: return usesPingPong
        case 19, 31: return usesEnvelopes
        case 20: return usesInstrumentNotes && usage.usesNoteCut
        case 24: return usesMultipleSamples
        case 29, 102, 104: return usesInstrumentNotes
        case 43: return usage.usesEmptyMapSlot
        case 50, 100: return usage.usesInstrumentWithNoteOff
        case 87: return usesMultipleSamples && usage.usesInstrumentOnlyCell
        case 115: return usesPitchPanSeparation
        case 21: return !usage.commands.intersection([8, 18, 25]).isEmpty
        case 22: return usage.commands.contains(9)
        case 23, 38: return usage.commands.contains(17)
        case 27, 35: return usage.commands.contains(15)
        case 28: return usesSwing
        case 30: return usage.usesNoteCut
        case 34: return usesInstrumentNotes
        case 36: return usesFilter
        case 37: return usage.usesSurroundPanningOverride
        case 41, 135: return usage.usesVolumeColumnSlide || usage.usesEffectColumnVolumeSlide
        case 44: return !usage.commands.isEmpty
        case 45, 47: return usage.commands.contains(25)
        case 48: return usesInstrumentNotes
        case 88: return usage.usesRowDelayWithNoteDelay
        case 94: return usage.usesReleaseNode
        case 97: return usage.usesReleaseNodePastSustain
        case 119: return usage.usesFilterResetOnPortaSampleChange
        case 120: return usage.usesInitialNoteMemory
        case 122: return usage.usesPortamento && usedSamples.contains { $0.sustainLoop != nil }
        case 123: return usage.usesEmptyMapSlot
        case 124: return usage.usesInstrumentOnlyOffset
        case 127: return usage.usesDoublePortamento
        case 132: return usesEnvelopes && usage.usesCarryAfterNoteOff
        case 134: return usage.usesNoteCutWithPortamento
        case 136: return usage.usesStoppedFilterEnvelopeAtStart
        default: return false
        }
    }
}

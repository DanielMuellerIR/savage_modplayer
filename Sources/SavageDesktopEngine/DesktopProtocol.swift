import Foundation

enum DesktopCommandName: String, Sendable {
    case batchExport
    case bpm
    case clear
    case collectionApply
    case collectionCancel
    case collectionExport
    case collectionImport
    case collectionMap
    case collectionResolve
    case compact
    case defaultOption
    case demo
    case enqueue
    case export
    case exportCancel
    case favorite
    case filterDelete
    case filterOpen
    case filterSave
    case indexCancel
    case indexRefresh
    case inspect
    case instrument
    case load
    case markUnheard
    case markerAdd
    case markerDelete
    case markerRename
    case mute
    case next
    case notes
    case open
    case option
    case pause
    case play
    case playlistAdd
    case playlistDelete
    case playlistMove
    case playlistOpen
    case playlistRename
    case playlistSave
    case playlistTrackMove
    case playlistTrackRemove
    case prepareExport
    case prepareSampleExport
    case preview
    case previous
    case query
    case queueClear
    case queueMove
    case queueRemove
    case quit
    case recentLoad
    case resume
    case sample
    case sampleExport
    case sampleExportCancel
    case section
    case sectionCancel
    case seek
    case seekSeconds
    case selection
    case solo
    case speed
    case stop
    case stopPreview
    case timer
    case timerExtend
    case trackSettings
    case videoExport
    case videoPreview
    case volume
}

enum DesktopEvent: String, Sendable {
    case cancelled
    case collectionApplied
    case collectionPreview
    case complete
    case error
    case exportPrepared
    case indexing
    case inspection
    case instrument
    case libraryBegin
    case libraryEnd
    case libraryTracks
    case libraryVisible
    case loading
    case module
    case notes
    case notice
    case pattern
    case preferences
    case progress
    case ready
    case sample
    case sampleExportPrepared
    case state
    case testScanReturned
    case testScanWaiting
    case videoPreview
    case videoPreviewState
    case visualizer
}

enum DesktopValue: Codable, Sendable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([DesktopValue])
    case object([String: DesktopValue])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let flag = try? value.decode(Bool.self) { self = .bool(flag) }
        else if let integer = try? value.decode(Int.self) { self = .integer(integer) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([DesktopValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: DesktopValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var result = encoder.singleValueContainer()
        switch self {
        case .null: try result.encodeNil()
        case .bool(let value): try result.encode(value)
        case .integer(let value): try result.encode(value)
        case .number(let value): try result.encode(value)
        case .string(let value): try result.encode(value)
        case .array(let values): try result.encode(values)
        case .object(let values): try result.encode(values)
        }
    }

    var integer: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    var number: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .number(let value): return value
        default: return nil
        }
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var strings: [String]? {
        guard case .array(let values) = self else { return nil }
        let strings = values.compactMap(\.string)
        return strings.count == values.count ? strings : nil
    }

    var object: [String: DesktopValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var foundationValue: Any {
        // Die Einstellungsdatei und ältere UI-Pfade greifen über NSNumber
        // auf numerische Werte zu, auch wenn sie als Ganzzahl eingehen.
        switch self {
        case .null: return NSNull()
        case .bool(let value): return NSNumber(value: value)
        case .integer(let value): return NSNumber(value: value)
        case .number(let value): return NSNumber(value: value)
        case .string(let value): return value
        case .array(let values): return values.map(\.foundationValue)
        case .object(let values): return values.mapValues(\.foundationValue)
        }
    }
}

struct DesktopRequest: Decodable, Sendable {
    enum Field: String, Sendable {
        case autoPlay
        case choice
        case compact
        case enabled
        case end
        case focus
        case fps
        case height
        case horizon
        case id
        case ids
        case index
        case interpolation
        case kind
        case light
        case next
        case overwrite
        case pal
        case path
        case paths
        case playlist
        case position
        case query
        case rename
        case revision
        case row
        case seconds
        case separation
        case setting
        case settings
        case snapshot
        case start
        case stems
        case text
        case token
        case track
        case value
        case video
        case width

    }

    let command: DesktopCommandName?
    let commandName: String
    private let fields: [Field: DesktopValue]

    init(from decoder: Decoder) throws {
        let source = try [String: DesktopValue](from: decoder)
        commandName = source["command"]?.string ?? ""
        command = DesktopCommandName(rawValue: commandName)
        fields = Dictionary(uniqueKeysWithValues: source.compactMap { key, value in
            Field(rawValue: key).map { ($0, value) }
        })
    }

    init(_ command: DesktopCommandName, _ fields: [Field: DesktopValue] = [:]) {
        self.command = command
        commandName = command.rawValue
        self.fields = fields
    }

    subscript(field: Field) -> DesktopValue? { fields[field] }

    func decode<Value: Decodable>(_ type: Value.Type, field: Field) throws -> Value {
        let data = try JSONEncoder().encode(fields[field] ?? .object([:]))
        return try JSONDecoder().decode(type, from: data)
    }
}

func desktopJSONObject<T: Encodable>(_ value: T) -> Any {
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value), let result = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return NSNull() }
    return result
}

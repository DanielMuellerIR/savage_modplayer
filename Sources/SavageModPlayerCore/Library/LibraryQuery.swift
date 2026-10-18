import Foundation

public enum LibraryFormatFamily: String, Codable, CaseIterable, Sendable {
    case mod = "MOD", s3m = "S3M", xm = "XM", it = "IT"
}

public extension ModuleFormat {
    var libraryFamily: LibraryFormatFamily {
        switch self {
        case .protracker, .soundtracker, .multichannel: return .mod
        case .s3m: return .s3m
        case .xm: return .xm
        case .it: return .it
        }
    }
}

public enum LibrarySort: String, Codable, CaseIterable, Sendable {
    case sourceOrder, filename, title, format, channels, duration, newest
}

public struct LibraryQueryItem: Sendable {
    public let id: String
    public let displayName: String
    public let folderPath: String
    public let metadata: ModuleMetadata?
    public let addedAt: Date?
    public let isFavorite: Bool
    public let wasPlayed: Bool?

    public init(id: String, displayName: String, folderPath: String = "",
                metadata: ModuleMetadata? = nil, addedAt: Date? = nil,
                isFavorite: Bool = false, wasPlayed: Bool? = false) {
        self.id = id; self.displayName = displayName; self.folderPath = folderPath
        self.metadata = metadata; self.addedAt = addedAt
        self.isFavorite = isFavorite; self.wasPlayed = wasPlayed
    }
}

public struct LibraryQuery: Codable, Equatable, Sendable {
    public var search = ""
    public var format: LibraryFormatFamily?
    public var minimumChannels = 0
    public var favoritesOnly = false
    public var unheardOnly = false
    public var addedWithinDays: Int?
    public var sort = LibrarySort.sourceOrder
    public var reversed = false
    public init() {}

    public var isFiltering: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || format != nil
            || minimumChannels > 0 || favoritesOnly || unheardOnly || addedWithinDays != nil
    }
    public var usesFlatList: Bool { isFiltering || sort != .sourceOrder || reversed }

    var isValid: Bool {
        search.count <= 2_048 && (0...64).contains(minimumChannels)
            && (addedWithinDays.map { (1...3_650).contains($0) } ?? true)
    }

    public func selectIDs(
        from items: [LibraryQueryItem], now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { Task.isCancelled }
    ) throws -> [String] {
        let tokens = Self.fold(search).split(whereSeparator: \.isWhitespace).map(String.init)
        let earliest = addedWithinDays.map { now.addingTimeInterval(-Double($0) * 86_400) }
        var selected: [LibraryQueryItem] = []
        for item in items {
            if isCancelled() { throw CancellationError() }
            if favoritesOnly && !item.isFavorite { continue }
            if unheardOnly && item.wasPlayed != false { continue }
            if let format, item.metadata?.format.libraryFamily != format { continue }
            if minimumChannels > 0 && (item.metadata?.channelCount ?? 0) < minimumChannels { continue }
            if let earliest, item.addedAt.map({ $0 >= earliest }) != true { continue }
            if !tokens.isEmpty {
                var fields = [item.displayName, item.folderPath]
                if let metadata = item.metadata {
                    fields += [metadata.title, metadata.format.displayName, metadata.format.libraryFamily.rawValue]
                    fields += metadata.instrumentNames
                }
                let text = Self.fold(fields.joined(separator: "\n"))
                if !tokens.allSatisfy({ text.contains($0) }) { continue }
            }
            selected.append(item)
        }
        if sort == .sourceOrder {
            return (reversed ? Array(selected.reversed()) : selected).map(\.id)
        }
        return try selected.sorted { left, right in
            if isCancelled() { throw CancellationError() }
            let leftMissing = isMissingSortValue(left), rightMissing = isMissingSortValue(right)
            if leftMissing != rightMissing { return !leftMissing }
            let result = compare(left, right)
            if result != .orderedSame { return reversed ? result == .orderedDescending : result == .orderedAscending }
            let names = left.displayName.localizedStandardCompare(right.displayName)
            if names != .orderedSame { return names == .orderedAscending }
            let folders = left.folderPath.localizedStandardCompare(right.folderPath)
            return folders == .orderedSame ? left.id < right.id : folders == .orderedAscending
        }.map(\.id)
    }

    private func isMissingSortValue(_ item: LibraryQueryItem) -> Bool {
        switch sort {
        case .sourceOrder, .filename: return false
        case .newest: return item.addedAt == nil
        case .title: return item.metadata?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        case .format, .channels, .duration: return item.metadata == nil
        }
    }

    private func compare(_ left: LibraryQueryItem, _ right: LibraryQueryItem) -> ComparisonResult {
        switch sort {
        case .sourceOrder: return .orderedSame
        case .filename: return left.displayName.localizedStandardCompare(right.displayName)
        case .title: return (left.metadata?.title ?? "").localizedStandardCompare(right.metadata?.title ?? "")
        case .format:
            return (left.metadata?.format.libraryFamily.rawValue ?? "").compare(right.metadata?.format.libraryFamily.rawValue ?? "")
        case .channels: return Self.compareNumbers(left.metadata?.channelCount ?? 0, right.metadata?.channelCount ?? 0)
        case .duration: return Self.compareNumbers(left.metadata?.durationSeconds ?? 0, right.metadata?.durationSeconds ?? 0)
        case .newest:
            return (right.addedAt ?? .distantPast).compare(left.addedAt ?? .distantPast)
        }
    }

    private static func compareNumbers<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
    }
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

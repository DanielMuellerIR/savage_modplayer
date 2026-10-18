public struct SongAddress: Codable, Hashable, Comparable, Sendable {
    public var position: Int
    public var row: Int
    public init(position: Int, row: Int) { self.position = position; self.row = row }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.position, lhs.row) < (rhs.position, rhs.row) }
    public var isValidStorageValue: Bool { (0..<1_000_000).contains(position) && (0..<1_000_000).contains(row) }
}

public struct SongSection: Equatable, Sendable {
    public let start: SongAddress
    public let end: SongAddress
    public init?(start: SongAddress, end: SongAddress) {
        guard start <= end else { return nil }
        self.start = start; self.end = end
    }
}

public struct SongPositionLayout: Sendable {
    public let rowCounts: [Int]
    public let offsets: [Int]
    public var totalRows: Int { offsets.last ?? 0 }
    public init(module: Mod) {
        rowCounts = module.patternTable.prefix(max(0, module.length)).map { index in
            module.patterns.indices.contains(index) ? module.patterns[index].rows.count : 0
        }
        var offsets = [0]
        for count in rowCounts { offsets.append(offsets.last! + count) }
        self.offsets = offsets
    }
    public func contains(_ address: SongAddress) -> Bool {
        rowCounts.indices.contains(address.position) && (0..<rowCounts[address.position]).contains(address.row)
    }
    public func index(of address: SongAddress) -> Int? {
        contains(address) ? offsets[address.position] + address.row : nil
    }
    public func rows(in section: SongSection, at position: Int) -> ClosedRange<Int>? {
        guard contains(section.start), contains(section.end), section.start <= section.end,
              (section.start.position...section.end.position).contains(position), rowCounts.indices.contains(position),
              rowCounts[position] > 0 else { return nil }
        let first = position == section.start.position ? section.start.row : 0
        let last = position == section.end.position ? section.end.row : rowCounts[position] - 1
        return first...last
    }
}

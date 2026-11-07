import Foundation

public enum BoundedFileReader {
    public static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes > 0, maximumBytes < Int.max else { throw CocoaError(.fileReadTooLarge) }
        let file = try LibraryFileReader(url)
        defer { file.close() }
        return try file.read(limit: maximumBytes)
    }
}

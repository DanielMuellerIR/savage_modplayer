import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct LibraryFileStamp: Codable, Equatable, Sendable {
    let size: Int64
    let device: UInt64
    let inode: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
}

enum LibraryFileReadError: Error { case unavailable, oversized }

final class LibraryFileReader {
    let stamp: LibraryFileStamp
    private let handle: FileHandle

    init(_ url: URL) throws {
        guard url.isFileURL else { throw LibraryFileReadError.unavailable }
        // Erst den offenen Deskriptor pruefen. O_NONBLOCK verhindert, dass ein
        // ausgetauschtes Modul als FIFO den gesamten Index dauerhaft anhaelt.
        let descriptor = url.withUnsafeFileSystemRepresentation { name -> Int32 in
            guard let name else { return -1 }
            return open(name, O_RDONLY | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw LibraryFileReadError.unavailable }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size >= 0 else {
            #if canImport(Darwin)
            _ = Darwin.close(descriptor)
            #else
            _ = Glibc.close(descriptor)
            #endif
            throw LibraryFileReadError.unavailable
        }
        #if canImport(Darwin)
        let modified = info.st_mtimespec
        #else
        let modified = info.st_mtim
        #endif
        stamp = LibraryFileStamp(size: Int64(info.st_size), device: UInt64(truncatingIfNeeded: info.st_dev),
                                  inode: UInt64(info.st_ino), modifiedSeconds: Int64(modified.tv_sec),
                                  modifiedNanoseconds: Int64(modified.tv_nsec))
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    func close() { try? handle.close() }

    func read(limit: Int, isCancelled: () -> Bool = { false }) throws -> Data {
        var data = Data()
        while data.count <= limit {
            guard !isCancelled() else { throw CancellationError() }
            guard let chunk = try handle.read(upToCount: min(256 * 1024, limit + 1 - data.count)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= limit else { throw LibraryFileReadError.oversized }
        return data
    }
}

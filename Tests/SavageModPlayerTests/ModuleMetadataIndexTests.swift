import XCTest
@testable import SavageModPlayerCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@MainActor
final class ModuleMetadataIndexTests: XCTestCase {
    private var work: URL!
    override func setUp() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("MetadataIndex-\(UUID())")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: work) }

    private func input(_ name: String, data: Data = IndexFixtures.mod()) throws -> ModuleMetadataInput {
        let url = work.appendingPathComponent(name)
        try data.write(to: url)
        return ModuleMetadataInput(id: name, url: url)
    }
    private func index(limit: Double = 600) throws -> ModuleMetadataIndex {
        try ModuleMetadataIndex(cacheURL: work.appendingPathComponent("cache.json"), durationLimit: limit)
    }

    func testAllFourFormatsUseTheActualParsersAndRunOffMainThread() async throws {
        let inputs = try [input("a.mod"), input("b.s3m", data: IndexFixtures.s3m()),
                          input("c.xm", data: IndexFixtures.xm()), input("d.it", data: IndexFixtures.it())]
        let result = try await index().refresh(inputs, progress: { _ in XCTAssertFalse(Thread.isMainThread) })
        XCTAssertEqual(result.refreshedCount, 4)
        for (input, format) in zip(inputs, [ModuleFormat.protracker, .s3m, .xm, .it]) {
            let record = try XCTUnwrap(result.records[input.id])
            XCTAssertNil(record.failure, record.detail ?? "")
            let metadata = try XCTUnwrap(record.metadata)
            XCTAssertEqual(metadata.format, format)
            XCTAssertGreaterThan(metadata.channelCount, 0)
            XCTAssertGreaterThan(metadata.durationSeconds, 0)
            XCTAssertFalse(metadata.durationIsLimited)
        }
        let mod = try XCTUnwrap(result.records["a.mod"]?.metadata)
        XCTAssertEqual(mod.title, "Index MOD")
        XCTAssertEqual(mod.instrumentCount, 1)
        XCTAssertEqual(mod.sampleCount, 1)
        XCTAssertEqual(mod.patternCount, 1)
    }

    func testUnchangedFilesAreReusedAfterRestartAndChangedBytesAreReparsed() async throws {
        let item = try input("same.mod")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: item.url.path)
        let first = try await index().refresh([item, item])
        XCTAssertEqual(first.refreshedCount, 1)
        let next = try index()
        let cached = await next.refresh([item])
        XCTAssertEqual(cached.reusedCount, 1)
        XCTAssertEqual(cached.records[item.id]?.metadata, first.records[item.id]?.metadata)
        let firstDate = try XCTUnwrap(first.records[item.id]?.indexedAt)
        let savedDate = try XCTUnwrap(cached.records[item.id]?.indexedAt)
        XCTAssertEqual(savedDate.timeIntervalSince1970, firstDate.timeIntervalSince1970, accuracy: 1)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: work.appendingPathComponent("cache.json"))) as? [String: Any])
        let rows = try XCTUnwrap(json["records"] as? [[String: Any]])
        let date = try XCTUnwrap(rows.first?["indexedAt"] as? String)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: date))
        var changed = IndexFixtures.mod()
        changed.replaceSubrange(0..<9, with: Data("NEW TITLE".utf8))
        try changed.write(to: item.url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_600_000_001)], ofItemAtPath: item.url.path)
        let updated = await next.refresh([item])
        XCTAssertEqual(updated.refreshedCount, 1)
        XCTAssertEqual(updated.records[item.id]?.metadata?.title, "NEW TITLE")
    }

    func testMissingCorruptOversizedAndDirectoryInputsDoNotStopTheBatch() async throws {
        let good = try input("good.mod")
        let corrupt = try input("bad.mod", data: Data("invalid".utf8))
        let missing = ModuleMetadataInput(id: "missing", url: work.appendingPathComponent("gone.mod"))
        let huge = work.appendingPathComponent("huge.mod")
        XCTAssertTrue(FileManager.default.createFile(atPath: huge.path, contents: nil))
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(ModuleMetadataIndex.maximumFileBytes + 1))
        try handle.close()
        let result = try await index().refresh([missing, corrupt, ModuleMetadataInput(id: "huge", url: huge),
                                          ModuleMetadataInput(id: "directory", url: work), good])
        XCTAssertEqual(result.records[missing.id]?.failure, .unavailable)
        XCTAssertEqual(result.records[corrupt.id]?.failure, .invalidModule)
        XCTAssertEqual(result.records["huge"]?.failure, .oversizedFile)
        XCTAssertEqual(result.records["directory"]?.failure, .unavailable)
        XCTAssertNotNil(result.records[good.id]?.metadata)
    }

    func testCancellationKeepsPartialCacheAndUnvisitedRecords() async throws {
        let inputs = try [input("a.mod"), input("b.mod"), input("c.mod")]
        let service = try index()
        _ = await service.refresh(inputs)
        try IndexFixtures.mod().write(to: inputs[0].url, options: .atomic)
        let flag = IndexTestFlag()
        let partial = await service.refresh(Array(inputs.prefix(2)), discardUnlisted: true,
            isCancelled: { flag.value }, progress: { _ in flag.raise() })
        XCTAssertTrue(partial.wasCancelled)
        XCTAssertEqual(partial.refreshedCount, 1)
        XCTAssertNotNil(partial.records["c.mod"], "Abbruch darf noch nicht besuchte Einträge nicht entfernen")
        let restart = try await index().refresh(inputs)
        XCTAssertEqual(restart.reusedCount, 3)
        let pruned = await service.refresh(Array(inputs.prefix(2)), discardUnlisted: true)
        XCTAssertNil(pruned.records["c.mod"])
    }

    func testDurationLimitIsExplicitAndInvalidLimitsAreRejected() async throws {
        for limit in [0.0, -.infinity, .infinity, .nan, 601] { XCTAssertThrowsError(try index(limit: limit)) }
        let item = try input("bounded.mod")
        let result = try await index(limit: 0.04).refresh([item])
        let metadata = try XCTUnwrap(result.records[item.id]?.metadata)
        XCTAssertEqual(metadata.durationSeconds, 0.04, accuracy: 0.0001)
        XCTAssertTrue(metadata.durationIsLimited)
        let full = try await index().refresh([item])
        XCTAssertFalse(try XCTUnwrap(full.records[item.id]?.metadata).durationIsLimited)
    }

    func testInvalidIdentifiersCannotPruneAnExistingSnapshot() async throws {
        let item = try input("keep.mod")
        let service = try index()
        _ = await service.refresh([item])
        let invalid = ModuleMetadataInput(id: "", url: item.url)
        let result = await service.refresh([invalid], discardUnlisted: true)
        XCTAssertTrue(result.warnings.contains(.invalidSource))
        XCTAssertNotNil(result.records[item.id])
    }

    func testCorruptCacheIsRebuiltAndSaveFailureKeepsTheSource() async throws {
        let item = try input("source.mod")
        try Data("broken".utf8).write(to: work.appendingPathComponent("cache.json"))
        let rebuilt = try await index().refresh([item])
        XCTAssertTrue(rebuilt.warnings.contains(.rebuiltCache))
        XCTAssertNotNil(rebuilt.records[item.id]?.metadata)
        let blocker = work.appendingPathComponent("blocker")
        try Data("keep".utf8).write(to: blocker)
        let service = try ModuleMetadataIndex(cacheURL: blocker.appendingPathComponent("cache.json"))
        let result = await service.refresh([item])
        XCTAssertTrue(result.warnings.contains(.cacheWriteFailed))
        XCTAssertNotNil(result.records[item.id]?.metadata)
        XCTAssertEqual(try Data(contentsOf: item.url), IndexFixtures.mod())
        XCTAssertEqual(try Data(contentsOf: blocker), Data("keep".utf8))
    }

    func testNamedPipeDoesNotBlockIndexing() async throws {
        let fifo = work.appendingPathComponent("pipe.mod")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let flag = IndexTestFlag()
        let service = try index()
        let task = Task {
            let result = await service.refresh([ModuleMetadataInput(id: "fifo", url: fifo)])
            flag.raise()
            return result
        }
        let deadline = Date().addingTimeInterval(2)
        while !flag.value && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let finishedWithoutWriter = flag.value
        // Bei einer Regression den blockierten Leser freigeben, damit der Test
        // rot endet und nicht den gesamten Testprozess dauerhaft festhaelt.
        let writer = open(fifo.path, O_WRONLY | O_NONBLOCK)
        if writer >= 0 { _ = close(writer) }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(finishedWithoutWriter)
        XCTAssertEqual(result.records["fifo"]?.failure, .unavailable)
    }

    func testCacheCannotOverwriteAnInputOrItsSymbolicLinkAlias() async throws {
        let source = try input("keep.mod")
        let alias = work.appendingPathComponent("cache.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source.url)
        let service = try ModuleMetadataIndex(cacheURL: alias)
        let result = await service.refresh([source])
        XCTAssertNotNil(result.records[source.id]?.metadata)
        XCTAssertTrue(result.warnings.contains(.cacheWriteFailed))
        let other = try input("other.mod")
        _ = await service.refresh([other])
        XCTAssertEqual(try Data(contentsOf: source.url), IndexFixtures.mod())
        XCTAssertEqual(try Data(contentsOf: alias), IndexFixtures.mod())
    }

    func testLongIdentifiersCannotCreateAnUnboundedCache() async throws {
        let item = try input("shared.mod")
        let inputs = (0..<1_000).map {
            ModuleMetadataInput(id: String(repeating: "x", count: 16_000) + String($0), url: item.url)
        }
        let result = try await index(limit: 0.02).refresh(inputs)
        XCTAssertTrue(result.warnings.contains(.capacityLimited))
        XCTAssertLessThan(result.records.count, inputs.count)
        let size = try work.appendingPathComponent("cache.json").resourceValues(forKeys: [.fileSizeKey]).fileSize!
        XCTAssertLessThanOrEqual(size, ModuleMetadataIndex.maximumCacheBytes)
    }
}

private final class IndexTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.withLock { raised } }
    func raise() { lock.withLock { raised = true } }
}

private enum IndexFixtures {
    private static func word(_ value: Int, _ offset: Int, _ data: inout Data) {
        data[offset] = UInt8(value & 255); data[offset + 1] = UInt8((value >> 8) & 255)
    }
    static func mod() -> Data {
        var d = Data(repeating: 0, count: 1084 + 1024 + 4)
        d.replaceSubrange(0..<9, with: Data("Index MOD".utf8))
        d[43] = 2; d[45] = 64; d[950] = 1
        d.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        return d
    }
    static func s3m() -> Data {
        var d = Data(repeating: 0, count: 0x70 + 66)
        d.replaceSubrange(0..<9, with: Data("Index S3M".utf8))
        d[0x1C] = 0x1A; d[0x1D] = 0x10
        word(2, 0x20, &d); word(1, 0x24, &d); word(2, 0x2A, &d)
        d.replaceSubrange(0x2C..<0x30, with: Data("SCRM".utf8))
        d[0x30] = 64; d[0x31] = 6; d[0x32] = 125; d[0x33] = 0xC0
        for i in 0..<32 { d[0x40 + i] = i < 2 ? UInt8(i * 8) : 255 }
        d[0x61] = 255; word(7, 0x62, &d); word(66, 0x70, &d)
        return d
    }
    static func xm() -> Data {
        var d = Data(repeating: 0, count: 345)
        d.replaceSubrange(0..<17, with: Data("Extended Module: ".utf8))
        d.replaceSubrange(17..<25, with: Data("Index XM".utf8)); d[37] = 0x1A
        word(0x0104, 58, &d); word(276, 60, &d); word(1, 64, &d)
        word(2, 68, &d); word(1, 70, &d); word(1, 74, &d)
        word(6, 76, &d); word(125, 78, &d); word(9, 336, &d); word(64, 341, &d)
        return d
    }
    static func it() -> Data {
        var d = Data(repeating: 0, count: 198)
        d.replaceSubrange(0..<4, with: Data("IMPM".utf8))
        d.replaceSubrange(4..<12, with: Data("Index IT".utf8))
        word(2, 0x20, &d); word(1, 0x26, &d); word(0x0214, 0x28, &d)
        word(0x0214, 0x2A, &d); word(1, 0x2C, &d)
        d[0x30] = 128; d[0x31] = 128; d[0x32] = 6; d[0x33] = 125; d[0x34] = 128
        for i in 0..<64 { d[0x40 + i] = 32; d[0x80 + i] = 64 }
        d[193] = 255
        return d
    }
}

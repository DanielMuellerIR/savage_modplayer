import Foundation
import XCTest
@testable import SavageModPlayerCore

final class PreviewCacheIdentityTests: XCTestCase {
    func testSameBasenameSizeAndTimestampInDifferentDirectoriesDoNotCollide() {
        let date = Date(timeIntervalSinceReferenceDate: 123_456.75)
        let first = PreviewCacheIdentity.key(
            sourceURL: URL(fileURLWithPath: "/tmp/album-a/song.xm"),
            fileSize: 4096,
            modificationDate: date
        )
        let second = PreviewCacheIdentity.key(
            sourceURL: URL(fileURLWithPath: "/tmp/album-b/song.xm"),
            fileSize: 4096,
            modificationDate: date
        )
        XCTAssertNotEqual(first, second)
    }

    func testReplacementWithinSameWholeSecondGetsNewKey() {
        let url = URL(fileURLWithPath: "/tmp/song.xm")
        let first = PreviewCacheIdentity.key(
            sourceURL: url,
            fileSize: 4096,
            modificationDate: Date(timeIntervalSinceReferenceDate: 123_456.125)
        )
        let replacement = PreviewCacheIdentity.key(
            sourceURL: url,
            fileSize: 4096,
            modificationDate: Date(timeIntervalSinceReferenceDate: 123_456.875)
        )
        XCTAssertNotEqual(first, replacement)
    }

    func testIdenticalIdentityIsStable() {
        let url = URL(fileURLWithPath: "/tmp/song.xm")
        let date = Date(timeIntervalSinceReferenceDate: 123_456.5)
        XCTAssertEqual(
            PreviewCacheIdentity.key(sourceURL: url, fileSize: 7, modificationDate: date),
            PreviewCacheIdentity.key(sourceURL: url, fileSize: 7, modificationDate: date)
        )
    }
}

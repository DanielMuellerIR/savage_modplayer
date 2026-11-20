import Foundation

enum ModuleTestFixtures {
    static let proTrackerPatternOffset = 1084

    static func proTracker(title: String, sample: [UInt8] = [0, 0, 0, 0]) -> Data {
        precondition(sample.count.isMultiple(of: 2) && sample.count <= Int(UInt16.max) * 2)
        let sampleOffset = proTrackerPatternOffset + 64 * 4 * 4
        var data = Data(repeating: 0, count: sampleOffset + sample.count)
        let name = title.utf8.prefix(20)
        data.replaceSubrange(0..<name.count, with: name)
        let wordCount = UInt16(sample.count / 2)
        data[42] = UInt8(wordCount >> 8)
        data[43] = UInt8(truncatingIfNeeded: wordCount)
        data[45] = 64
        data[950] = 1
        data.replaceSubrange(1080..<proTrackerPatternOffset, with: "M.K.".utf8)
        data.replaceSubrange(sampleOffset..<data.count, with: sample)
        return data
    }
}

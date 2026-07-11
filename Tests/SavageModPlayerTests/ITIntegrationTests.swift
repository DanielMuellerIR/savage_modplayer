import Foundation
import XCTest
@testable import SavageModPlayerCore

/// Öffentliches M10-Gate über den kompletten lokal vorhandenen IT-Korpus.
/// Die Dateien bleiben gitignored; auf CI ohne Korpus wird der Test übersprungen.
final class ITIntegrationTests: XCTestCase {
    func testCompleteLocalCorpusClassifiesSupportedAndShortPatternFiles() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("audio/it-tests", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { throw XCTSkip("Kein lokaler IT-Korpus") }
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "it" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw XCTSkip("Kein lokaler IT-Korpus") }

        var sampleModeCount = 0
        var instrumentModeCount = 0
        var hasNNA = false
        var hasFilter = false
        var hasStereo = false
        var shortPatternFiles = 0
        for file in files {
            let module: Mod
            do {
                module = try ModuleLoader.parse(data: Data(contentsOf: file))
            } catch let error as ITParser.ParserError {
                if case let .invalidPatternRows(_, rows) = error, rows > 0, rows < 32 {
                    shortPatternFiles += 1
                    continue
                }
                throw error
            }
            XCTAssertEqual(module.format, .it, file.lastPathComponent)
            if module.itProperties?.usesInstruments == true {
                instrumentModeCount += 1
            } else {
                sampleModeCount += 1
            }
            hasNNA = hasNNA || module.instruments.compactMap { $0?.itProperties }
                .contains { $0.newNoteAction != .cut }
            hasFilter = hasFilter || module.instruments.compactMap { $0?.pitchEnvelope }
                .contains { $0.valueMode == .filter }
            hasStereo = hasStereo || module.samplePool.compactMap { $0 }
                .contains { $0.rightPCM != nil }

            let wav = try ModuleRenderer.renderWavData(
                mod: module,
                sampleRate: 8_000,
                maxDurationSeconds: 0.05,
                normalize: false,
                useInterpolation: false
            )
            XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        }

        XCTAssertGreaterThan(sampleModeCount, 0)
        XCTAssertGreaterThan(instrumentModeCount, 0)
        XCTAssertGreaterThan(shortPatternFiles, 0,
                             "Korpus soll die dokumentierte 32-Row-Untergrenze abdecken")
        XCTAssertTrue(hasNNA, "Korpus muss mindestens eine NNA-Datei enthalten")
        XCTAssertTrue(hasFilter, "Korpus muss mindestens eine Filterdatei enthalten")
        XCTAssertTrue(hasStereo, "Korpus muss mindestens ein Stereo-Sample enthalten")
    }
}

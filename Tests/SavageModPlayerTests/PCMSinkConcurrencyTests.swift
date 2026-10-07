import Foundation
import XCTest
@testable import SavageModPlayerCore

#if os(macOS) || os(Linux)
final class PCMSinkConcurrencyTests: XCTestCase {
    private final class Results: @unchecked Sendable {
        let lock = NSLock()
        var starts = 0
        var errors: [Error] = []
        func record(_ error: Error? = nil) {
            lock.lock()
            defer { lock.unlock() }
            if let error { errors.append(error) } else { starts += 1 }
        }
    }

    func testConcurrentStartsAndStopsKeepOneOwner() throws {
        #if os(macOS)
        let sink: any PCMSink = AVAudioEnginePCMSink(format: AVAudioEnginePCMSink.hardwareFormat())
        #else
        let sink: any PCMSink = ALSAPCMSink()
        #endif
        defer { sink.stop() }
        let results = Results()
        let ready = DispatchGroup()
        let gate = DispatchSemaphore(value: 0)
        for _ in 0..<2 {
            ready.enter()
            DispatchQueue.global().async {
                gate.wait()
                do {
                    try sink.start { samples, frames in
                        for index in samples.indices { samples[index] = 0 }
                        return frames
                    }
                    results.record()
                } catch { results.record(error) }
                ready.leave()
            }
        }
        gate.signal()
        gate.signal()
        XCTAssertEqual(ready.wait(timeout: .now() + 5), .success)
        if results.starts == 0 {
            throw XCTSkip("Keine nutzbare Audioausgabe: \(results.errors)")
        }
        XCTAssertEqual(results.starts, 1, "Nur ein Start darf Gerät und Puffer besitzen")
        XCTAssertEqual(results.errors.count, 1)
        if let error = results.errors.first {
            guard case PCMSinkError.invalidState = error else {
                return XCTFail("Zweiter Start muss invalidState liefern: \(error)")
            }
        }
        DispatchQueue.concurrentPerform(iterations: 8) { _ in sink.stop() }
        XCTAssertEqual(sink.waitUntilFinished(), .stopped)
        XCTAssertFalse(sink.isRunning)
    }
}
#endif

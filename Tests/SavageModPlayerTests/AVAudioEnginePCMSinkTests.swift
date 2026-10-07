#if os(macOS)
import AVFoundation
import CoreAudio
import XCTest
@testable import SavageModPlayerCore

final class AVAudioEnginePCMSinkTests: XCTestCase {
    private struct TailFixture: @unchecked Sendable {
        let timing: UnsafeMutablePointer<Double>
    }

    private func hardwareFormat() throws -> PCMFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            throw XCTSkip("Kein Standard-Audioausgabegerät")
        }
        return AVAudioEnginePCMSink.hardwareFormat()
    }

    func testStaleValidHostTimeCannotFinishBeforeRenderedBuffer() {
        let end = AVAudioEnginePCMSink.finalFrameHostTime(
            reportedHostTime: 10, hostTimeValid: true, renderedAt: 1_000,
            validFrames: 511, hostTicksPerFrame: 2.5)
        XCTAssertEqual(end, 2_278)
    }

    func testFutureHostTimeAndMissingTimestampKeepTheirDeadlines() {
        XCTAssertEqual(AVAudioEnginePCMSink.finalFrameHostTime(
            reportedHostTime: 2_000, hostTimeValid: true, renderedAt: 1_000,
            validFrames: 511, hostTicksPerFrame: 2.5), 3_278)
        XCTAssertEqual(AVAudioEnginePCMSink.finalFrameHostTime(
            reportedHostTime: 9_000, hostTimeValid: false, renderedAt: 1_000,
            validFrames: 511, hostTicksPerFrame: 2.5), 2_278)
    }

    func testNaturalEndWaitsForLastPartialBuffer() throws {
        let rate = try hardwareFormat().sampleRate
        let ticksPerSecond = Double(AVAudioTime.hostTime(forSeconds: 1))
        let fixture = TailFixture(timing: .allocate(capacity: 2))
        fixture.timing.initialize(repeating: 0, count: 2)
        let sink = AVAudioEnginePCMSink(format: PCMFormat(sampleRate: rate))
        defer {
            sink.stop()
            fixture.timing.deallocate()
        }

        do {
            try sink.start { samples, requested in
                let valid = max(0, requested - 1)
                for index in 0..<(valid * 2) { samples[index] = 0 }
                fixture.timing[0] = Double(mach_absolute_time()) / ticksPerSecond
                fixture.timing[1] = Double(valid) / rate
                return valid
            }
        } catch PCMSinkError.deviceUnavailable(let detail) {
            throw XCTSkip("Keine Audioausgabe: \(detail)")
        }

        XCTAssertEqual(sink.waitUntilFinished(), .sourceFinished)
        let returnedAt = Double(mach_absolute_time()) / ticksPerSecond
        XCTAssertGreaterThan(fixture.timing[1], 0)
        XCTAssertGreaterThanOrEqual(
            returnedAt - fixture.timing[0], fixture.timing[1],
            "Das Ende wird gemeldet, bevor der letzte Teilpuffer ausgespielt sein kann."
        )
        XCTAssertEqual(sink.waitUntilFinished(), .sourceFinished)
    }

    func testStopReleasesAllWaiters() throws {
        let sink = AVAudioEnginePCMSink(format: try hardwareFormat())
        defer { sink.stop() }
        do {
            try sink.start { samples, requested in
                for index in 0..<(requested * 2) { samples[index] = 0 }
                return requested
            }
        } catch PCMSinkError.deviceUnavailable(let detail) {
            throw XCTSkip("Keine Audioausgabe: \(detail)")
        }

        let waiters = (0..<2).map { expectation(description: "Warter \($0)") }
        for waiter in waiters {
            Thread.detachNewThread {
                XCTAssertEqual(sink.waitUntilFinished(), .stopped)
                waiter.fulfill()
            }
        }
        sink.stop()
        wait(for: waiters, timeout: 2)
        XCTAssertEqual(sink.waitUntilFinished(), .stopped)
    }
}
#endif

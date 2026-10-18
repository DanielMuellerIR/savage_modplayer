import XCTest
@testable import SavageModPlayerCore

final class SleepTimerTests: XCTestCase {
    private let origin: UInt64 = 100_000_000_000

    private func output(_ gain: SleepTimerGain, at now: UInt64, frames: Int = 4,
                        values: [Float]? = nil) -> ([Float], [Float]) {
        var left = values ?? Array(repeating: 1, count: frames)
        var right = left.map { -$0 }
        let count = UInt32(left.count)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                gain.process(frames: count, left: l.baseAddress!, right: r.baseAddress!, now: now)
            }
        }
        return (left, right)
    }

    func testInactiveTimerPreservesEverySampleBit() {
        let signal = SleepTimerSignal()
        let gain = SleepTimerGain(signal: signal, sampleRate: 1_000, now: origin)
        let values: [Float] = [0, -0.0, .nan, .infinity, -.infinity, .leastNonzeroMagnitude, 0.12345]
        let result = output(gain, at: origin, values: values)
        XCTAssertEqual(result.0.map(\.bitPattern), values.map(\.bitPattern))
        XCTAssertEqual(result.1.map(\.bitPattern), values.map { (-$0).bitPattern })
    }

    func testFadeStartsInsideBlockAtCorrectFrame() {
        let signal = SleepTimerSignal()
        XCTAssertTrue(signal.start(seconds: 20, now: origin))
        let start = origin + 9_998_000_000
        let gain = SleepTimerGain(signal: signal, sampleRate: 1_000, now: start)
        let result = output(gain, at: start)
        for (actual, expected) in zip(result.0, [Float(1), 1, 1, 0.9999]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000001)
        }
        XCTAssertEqual(result.1, result.0.map { -$0 })
    }

    func testDeadlineInsideBlockAndLateCallbackAreSilent() {
        let signal = SleepTimerSignal()
        signal.start(seconds: 20, now: origin)
        let start = signal.deadline - 2_000_000
        let gain = SleepTimerGain(signal: signal, sampleRate: 1_000, now: start)
        let result = output(gain, at: start)
        XCTAssertEqual(result.0[0], 0.0002, accuracy: 0.0000001)
        XCTAssertEqual(result.0[1], 0.0001, accuracy: 0.0000001)
        XCTAssertEqual(Array(result.0[2...]), [0, 0])
        let late = output(gain, at: signal.deadline + 1, values: [.nan, .infinity, 1, -1])
        XCTAssertEqual(late.0, [0, 0, 0, 0])
        XCTAssertEqual(late.1, [0, 0, 0, 0])
    }

    func testCancelAndExtendRecoverSmoothly() {
        for cancel in [true, false] {
            let signal = SleepTimerSignal()
            signal.start(seconds: 20, now: origin)
            let now = origin + 15_000_000_000
            let gain = SleepTimerGain(signal: signal, sampleRate: 1_000, now: now)
            if cancel { signal.cancel() } else { XCTAssertTrue(signal.extend(minutes: 15, now: now)) }
            let desiredVolume: Float = 0.3
            let result = output(gain, at: now, values: Array(repeating: desiredVolume, count: 60)).0
            XCTAssertEqual(result[0], desiredVolume * 0.52, accuracy: 0.000001)
            XCTAssertEqual(result.last!, desiredVolume, accuracy: 0.000001)
            for pair in zip(result, result.dropFirst()) {
                XCTAssertGreaterThanOrEqual(pair.1, pair.0)
                XCTAssertLessThanOrEqual(pair.1 - pair.0, desiredVolume * 0.02001)
            }
        }
    }

    func testNewOutputUsesCurrentFadeAndSharedDeadline() {
        let signal = SleepTimerSignal()
        signal.start(seconds: 20, now: origin)
        let now = origin + 18_000_000_000
        let song = SleepTimerGain(signal: signal, sampleRate: 1_000, now: now)
        let preview = SleepTimerGain(signal: signal, sampleRate: 48_000, now: now)
        XCTAssertEqual(output(song, at: now).0[0], 0.2, accuracy: 0.000001)
        XCTAssertEqual(output(preview, at: now).0[0], 0.2, accuracy: 0.000001)
        signal.cancel()
        XCTAssertGreaterThan(output(song, at: now).0[0], 0.2)
        XCTAssertGreaterThan(output(preview, at: now).0[0], 0.2)
    }

    func testInvalidDurationAndOverflowPreserveDeadline() {
        let signal = SleepTimerSignal()
        signal.start(seconds: 60, now: origin)
        let deadline = signal.deadline
        for seconds in [Double.nan, .infinity, -.infinity, 0, -1, 43_201] {
            XCTAssertFalse(signal.start(seconds: seconds, now: origin))
            XCTAssertEqual(signal.deadline, deadline)
        }
        XCTAssertFalse(signal.start(seconds: 60, now: .max - 1))
        XCTAssertEqual(signal.deadline, deadline)
        XCTAssertTrue(signal.extend(minutes: 720, now: origin))
        XCTAssertEqual(signal.deadline - origin, SleepTimerSignal.maximumNanoseconds)
        XCTAssertFalse(signal.extend(minutes: 1, now: signal.deadline))
    }

    func testPlatformClockIsPositiveAndMonotonic() {
        let first = SleepTimerClock.now()
        XCTAssertGreaterThan(first, 0)
        XCTAssertGreaterThanOrEqual(SleepTimerClock.now(), first)
    }
}

#if canImport(Combine)
private final class SleepTestClock: Sendable {
    let value = LockFreeAtomicUInt64(100_000_000_000)
    func now() -> UInt64 { value.loadAcquire() }
}

@MainActor
final class SleepTimerControllerTests: XCTestCase {
    func testDelayedRefreshExpiresOnceAndBlocksAutomaticResume() {
        let clock = SleepTestClock()
        let timer = SleepTimerController(now: { clock.now() })
        var expirations = 0
        timer.onExpired = { expirations += 1 }
        XCTAssertTrue(timer.start(minutes: 1))
        clock.value.storeRelease(clock.now() + 55_000_000_000)
        timer.refresh()
        XCTAssertEqual(timer.snapshot.phase, .fading)
        XCTAssertEqual(timer.snapshot.remainingSeconds, 5)
        clock.value.storeRelease(clock.now() + 30_000_000_000)
        XCTAssertFalse(timer.allowsPlayback())
        timer.refresh()
        XCTAssertEqual(expirations, 1)
        XCTAssertEqual(timer.snapshot.phase, .expired)
        timer.prepareForManualPlayback()
        XCTAssertTrue(timer.allowsPlayback())
        XCTAssertEqual(timer.snapshot.phase, .inactive)
        XCTAssertEqual(expirations, 1)
    }

    func testExtendDuringFadeAndCancelKeepTimerAcrossManualPlay() {
        let clock = SleepTestClock()
        let timer = SleepTimerController(now: { clock.now() })
        timer.start(minutes: 1)
        clock.value.storeRelease(clock.now() + 55_000_000_000)
        timer.prepareForManualPlayback()
        XCTAssertEqual(timer.snapshot.remainingSeconds, 5)
        timer.extend()
        XCTAssertEqual(timer.snapshot.remainingSeconds, 905)
        XCTAssertEqual(timer.snapshot.phase, .countingDown)
        timer.cancel()
        clock.value.storeRelease(clock.now() + 1_000_000_000_000)
        timer.refresh()
        XCTAssertEqual(timer.snapshot.phase, .inactive)
        XCTAssertTrue(timer.allowsPlayback())
    }

    func testExpiredTimerCannotBeExtendedAndNewInstanceIsInactive() {
        let clock = SleepTestClock()
        let timer = SleepTimerController(now: { clock.now() })
        timer.start(minutes: 1)
        clock.value.storeRelease(clock.now() + 61_000_000_000)
        timer.extend()
        XCTAssertEqual(timer.snapshot.phase, .expired)
        XCTAssertFalse(timer.start(minutes: 0))
        XCTAssertFalse(timer.start(minutes: 721))
        let reopened = SleepTimerController(now: { clock.now() })
        XCTAssertEqual(reopened.snapshot.phase, .inactive)
        timer.cancel()
    }

    func testCancelOrRestartAfterDelayedExpiryStopsPreviousPlaybackFirst() {
        for restart in [false, true] {
            let clock = SleepTestClock()
            let timer = SleepTimerController(now: { clock.now() })
            var expirations = 0
            timer.onExpired = { expirations += 1 }
            timer.start(minutes: 1)
            clock.value.storeRelease(clock.now() + 61_000_000_000)
            if restart { timer.start(minutes: 15) } else { timer.cancel() }
            XCTAssertEqual(expirations, 1)
            XCTAssertEqual(timer.snapshot.phase, restart ? .countingDown : .inactive)
            timer.cancel()
        }
    }

    func testCoordinatorKeepsTimerThroughInternalStopAndBlocksExpiredPlayback() {
        let coordinator = ModPlayerCoordinator()
        coordinator.setMod(ModParser.generateDemoMod(), precomputedDuration: 1)
        coordinator.sleepTimer.start(minutes: 1)
        let deadline = coordinator.sleepTimer.signal.deadline
        coordinator.stop()
        XCTAssertEqual(coordinator.sleepTimer.signal.deadline, deadline)
        coordinator.sleepTimer.signal.start(seconds: 0.001, now: SleepTimerClock.now())
        Thread.sleep(forTimeInterval: 0.005)
        var stopped = 0
        coordinator.onSleepTimerExpired = { stopped += 1 }
        coordinator.play()
        XCTAssertFalse(coordinator.isPlaying)
        XCTAssertEqual(coordinator.sleepTimer.snapshot.phase, .expired)
        XCTAssertEqual(stopped, 1)
        coordinator.resume()
        XCTAssertFalse(coordinator.isPlaying)
        XCTAssertEqual(stopped, 1)
        coordinator.sleepTimer.prepareForManualPlayback()
        XCTAssertEqual(coordinator.sleepTimer.snapshot.phase, .inactive)
    }
}
#endif

#if canImport(AVFoundation) && canImport(Combine)
import AVFoundation

private final class SleepAudioResult: @unchecked Sendable {
    // Der importierte Blocktyp ist nicht Sendable annotiert. Diese Instanz
    // übergibt ihn einmal an einen einzelnen, durch Semaphoren begrenzten Worker.
    let render: AVAudioSourceNodeRenderBlock
    var samples: [Float] = []
    init(render: @escaping AVAudioSourceNodeRenderBlock) { self.render = render }
}

extension SleepTimerControllerTests {
    func testLiveAdapterSilencesWhileMainActorIsBlocked() {
        let timer = SleepTimerController()
        timer.start(minutes: 1)
        var expirations = 0
        timer.onExpired = { expirations += 1 }
        let adapter = ModPlayerCoordinator.makeSourceNodeRenderBlock({ frames, left, right in
            for i in 0..<Int(frames) { left[i] = 1; right[i] = -1 }
        }, sleepTimer: timer.signal, sampleRate: 1_000)
        let ready = DispatchSemaphore(value: 0)
        let start = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let result = SleepAudioResult(render: adapter)
        DispatchQueue.global().async {
            var left = [Float](repeating: 0, count: 64)
            var right = left
            let buffers = AudioBufferList.allocate(maximumBuffers: 2)
            defer { free(buffers.unsafeMutablePointer); done.signal() }
            buffers.unsafeMutablePointer.pointee.mNumberBuffers = 2
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 256, mData: l.baseAddress)
                    buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 256, mData: r.baseAddress)
                    ready.signal()
                    guard start.wait(timeout: .now() + 2) == .success else { return }
                    for _ in 0..<20 {
                        var silent = ObjCBool(false)
                        var timestamp = AudioTimeStamp()
                        _ = result.render(&silent, &timestamp, 64, buffers.unsafeMutablePointer)
                        result.samples.append(l[0])
                        Thread.sleep(forTimeInterval: 0.02)
                    }
                }
            }
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 2), .success)
        timer.signal.start(seconds: 0.2, now: SleepTimerClock.now())
        timer.refresh()
        start.signal()
        // Der UI-Ticker wäre nach einer Sekunde fällig, erhält hier aber
        // absichtlich keinen MainActor-Zeitschlitz. Nur der Adapter kann stoppen.
        Thread.sleep(forTimeInterval: 1.1)
        XCTAssertEqual(done.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(timer.snapshot.phase, .fading)
        XCTAssertEqual(expirations, 0)
        XCTAssertGreaterThan(result.samples.first!, 0)
        XCTAssertEqual(result.samples.last!, 0)
        timer.refresh()
        XCTAssertEqual(timer.snapshot.phase, .expired)
        XCTAssertEqual(expirations, 1)
    }
}
#endif

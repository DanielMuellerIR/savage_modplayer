import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum SleepTimerClock {
    @inline(__always)
    static func now() -> UInt64 {
        #if canImport(Darwin)
        return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        #else
        var value = timespec()
        guard clock_gettime(CLOCK_BOOTTIME, &value) == 0 else { return 0 }
        return UInt64(value.tv_sec) * 1_000_000_000 + UInt64(value.tv_nsec)
        #endif
    }
}

// Die Deadline zählt auch während Geräteschlaf weiter. Ein atomarer Wert
// genügt; der Audiothread benötigt weder den UI-Ticker noch mehrere Steuerwerte.
final class SleepTimerSignal: Sendable {
    static let fadeNanoseconds: UInt64 = 10_000_000_000
    static let maximumNanoseconds: UInt64 = 720 * 60 * 1_000_000_000
    private let storage = LockFreeAtomicUInt64(0)

    var deadline: UInt64 { storage.loadAcquire() }

    @discardableResult
    func start(seconds: Double, now: UInt64) -> Bool {
        guard seconds.isFinite, seconds > 0, seconds <= 720 * 60 else { return false }
        let duration = UInt64(max(1, (seconds * 1_000_000_000).rounded()))
        guard duration <= UInt64.max - now else { return false }
        storage.storeRelease(now + duration)
        return true
    }

    @discardableResult
    func extend(minutes: Int, now: UInt64) -> Bool {
        let current = deadline
        guard (1...720).contains(minutes), current > now else { return false }
        let remaining = min(current - now, Self.maximumNanoseconds)
        let duration = min(Self.maximumNanoseconds, remaining + UInt64(minutes) * 60 * 1_000_000_000)
        guard duration <= UInt64.max - now else { return false }
        storage.storeRelease(now + duration)
        return true
    }

    func cancel() { storage.storeRelease(0) }
}

// Genau ein Prozessor gehört zu genau einem serialisierten SourceNode-Callback.
// Song und Samplevorschau teilen die Deadline, aber keinen veränderlichen Gain.
final class SleepTimerGain: @unchecked Sendable {
    private let signal: SleepTimerSignal
    private let frameStep: Double
    private let recoveryStep: Float
    private var gain: Float

    convenience init(signal: SleepTimerSignal, sampleRate: Double) {
        self.init(signal: signal, sampleRate: sampleRate, now: SleepTimerClock.now())
    }

    init(signal: SleepTimerSignal, sampleRate: Double, now: UInt64) {
        precondition(sampleRate.isFinite && sampleRate > 0)
        self.signal = signal
        frameStep = 1_000_000_000 / (sampleRate * Double(SleepTimerSignal.fadeNanoseconds))
        recoveryStep = Float(1 / max(1, sampleRate * 0.05))
        gain = Self.target(deadline: signal.deadline, now: now, frameOffset: 0)
    }

    func process(frames: UInt32, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let deadline = signal.deadline
        if deadline == 0 && gain == 1 { return }
        apply(frames: frames, left: left, right: right, deadline: deadline,
              now: deadline == 0 ? 0 : SleepTimerClock.now())
    }

    func process(frames: UInt32, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, now: UInt64) {
        apply(frames: frames, left: left, right: right, deadline: signal.deadline, now: now)
    }

    private func apply(frames: UInt32, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                       deadline: UInt64, now: UInt64) {
        if deadline == 0 && gain == 1 { return }
        if deadline != 0 && (now == 0 || deadline <= now) {
            for frame in 0..<Int(frames) { left[frame] = 0; right[frame] = 0 }
            gain = 0
            return
        }
        if gain == 1, deadline > now {
            let lastRatio = Double(deadline - now) / Double(SleepTimerSignal.fadeNanoseconds)
                - Double(max(0, Int(frames) - 1)) * frameStep
            if lastRatio >= 1 { return }
        }
        var current = gain
        for frame in 0..<Int(frames) {
            let target = Self.target(deadline: deadline, now: now, frameOffset: Double(frame) * frameStep)
            current = target <= current ? target : min(target, current + recoveryStep)
            left[frame] *= current
            right[frame] *= current
        }
        gain = current
    }

    private static func target(deadline: UInt64, now: UInt64, frameOffset: Double) -> Float {
        if deadline == 0 { return 1 }
        guard now > 0, deadline > now else { return 0 }
        let remaining = Double(deadline - now) / Double(SleepTimerSignal.fadeNanoseconds)
        return Float(max(0, min(1, remaining - frameOffset)))
    }
}

public struct SleepTimerSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case inactive, countingDown, fading, expired }
    public let phase: Phase
    public let remainingSeconds: Int
    public var isActive: Bool { phase == .countingDown || phase == .fading }
}

#if canImport(Combine)
import Combine

@MainActor
public final class SleepTimerController: ObservableObject {
    @Published public private(set) var snapshot = SleepTimerSnapshot(phase: .inactive, remainingSeconds: 0)
    let signal = SleepTimerSignal()
    var onExpired: (@MainActor () -> Void)?
    private let now: @Sendable () -> UInt64
    private var notifiedDeadline: UInt64 = 0
    private var ticker: Task<Void, Never>?

    public convenience init() { self.init(now: { SleepTimerClock.now() }) }

    init(now: @escaping @Sendable () -> UInt64) {
        self.now = now
        _ = now()
    }

    deinit { ticker?.cancel() }

    @discardableResult
    public func start(minutes: Int) -> Bool {
        guard (1...720).contains(minutes) else { return false }
        refresh()
        guard signal.start(seconds: Double(minutes) * 60, now: now()) else { return false }
        notifiedDeadline = 0
        refresh()
        startTicker()
        return true
    }

    public func extend(minutes: Int = 15) {
        refresh()
        guard signal.extend(minutes: minutes, now: now()) else { return }
        notifiedDeadline = 0
        refresh()
    }

    public func cancel() {
        refresh()
        signal.cancel()
        ticker?.cancel()
        ticker = nil
        notifiedDeadline = 0
        update(.init(phase: .inactive, remainingSeconds: 0))
    }

    // Nur der bewusste Start quittiert den Ablauf. Automatischer Titelwechsel
    // und Interruption-Resume dürfen einen abgelaufenen Timer nicht freigeben.
    public func prepareForManualPlayback() {
        refresh()
        if snapshot.phase == .expired { cancel() }
    }

    public func allowsPlayback() -> Bool {
        refresh()
        return snapshot.phase != .expired
    }

    public func refresh() {
        let deadline = signal.deadline
        guard deadline != 0 else {
            update(.init(phase: .inactive, remainingSeconds: 0))
            return
        }
        let current = now()
        if current >= deadline {
            update(.init(phase: .expired, remainingSeconds: 0))
            ticker?.cancel()
            ticker = nil
            if notifiedDeadline != deadline {
                notifiedDeadline = deadline
                onExpired?()
            }
        } else {
            let remaining = deadline - current
            update(.init(phase: remaining <= SleepTimerSignal.fadeNanoseconds ? .fading : .countingDown,
                         remainingSeconds: Int((remaining + 999_999_999) / 1_000_000_000)))
        }
    }

    private func update(_ value: SleepTimerSnapshot) {
        if snapshot != value { snapshot = value }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                self?.refresh()
                if self?.snapshot.isActive != true { return }
            }
        }
    }
}
#endif

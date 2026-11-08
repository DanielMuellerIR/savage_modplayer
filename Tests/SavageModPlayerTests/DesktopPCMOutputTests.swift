#if os(Linux)
import Foundation
import XCTest
@testable import SavageModPlayerCore

private final class ControlledDesktopSink: PCMSink, @unchecked Sendable {
    let format = PCMFormat()
    var isRunning: Bool { true }
    private let condition = NSCondition()
    private var reason: PCMSinkFinishReason?
    func start(render: @escaping PCMRenderBlock) throws {}
    func pause() throws {}
    func resume() throws {}
    func stop() { finish(.stopped) }
    func finish(_ value: PCMSinkFinishReason) {
        condition.lock(); defer { condition.unlock() }
        if reason == nil { reason = value }
        condition.broadcast()
    }
    func waitUntilFinished() -> PCMSinkFinishReason {
        condition.lock(); defer { condition.unlock() }
        while reason == nil { condition.wait() }
        return reason!
    }
}

final class DesktopPCMOutputTests: XCTestCase {
    @MainActor func testUnexpectedSinkFailureIsDeliveredAndStoppedGenerationIsIgnored() async throws {
        for stopped in [false, true] {
            let sink = ControlledDesktopSink()
            let output = DesktopPCMOutput(makeSink: { _ in sink })
            var errors: [String] = []
            output.onFailure = { errors.append($0) }
            try output.start(block: { _, _, _ in }, sleepTimer: SleepTimerSignal(),
                             volume: 1, ledFilter: false, initiallyPaused: false)
            if stopped { output.stop() }
            sink.finish(.failed("synthetic device loss"))
            for _ in 0..<100 where errors.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
            XCTAssertEqual(errors, stopped ? [] : ["synthetic device loss"])
            output.stop()
        }
    }
}
#endif

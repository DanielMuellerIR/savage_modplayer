import XCTest
import SwiftUI
@testable import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class SleepTimerViewTests: XCTestCase {
    func testTimerSheetStatesRenderInBothLanguagesAndWithLargeText() async throws {
        let model = AppModel()
        let timer = model.player.coordinator.sleepTimer
        let defaults = UserDefaults.standard
        let key = "savage.sleepTimerMinutes"
        let original = defaults.object(forKey: key)
        defaults.set(1, forKey: key)
        defer {
            model.player.stop()
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        let cases: [(String, SleepTimerSnapshot.Phase, String, ColorScheme, DynamicTypeSize)] = [
            ("inactive-de-light", .inactive, "de", .light, .large),
            ("running-en-dark", .countingDown, "en", .dark, .large),
            ("fading-de-dark", .fading, "de", .dark, .large),
            ("expired-en-light", .expired, "en", .light, .large),
            ("running-en-large-text", .countingDown, "en", .light, .accessibility3),
            ("expired-de-large-text", .expired, "de", .dark, .accessibility3)
        ]
        for (name, phase, locale, scheme, size) in cases {
            timer.cancel()
            switch phase {
            case .inactive: break
            case .countingDown: timer.start(minutes: 15)
            case .fading:
                timer.start(minutes: 1)
                timer.signal.start(seconds: 5, now: SleepTimerClock.now())
            case .expired:
                timer.signal.start(seconds: 0.001, now: SleepTimerClock.now())
                try await Task.sleep(for: .milliseconds(20))
            }
            timer.refresh()
            XCTAssertEqual(timer.snapshot.phase, phase)
            try await snapshot(model: model, name: name, locale: locale, scheme: scheme, size: size)
        }
    }

    private func snapshot(model: AppModel, name: String, locale: String,
                          scheme: ColorScheme, size: DynamicTypeSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let timer = model.player.coordinator.sleepTimer
        let root = NowPlayingView(isSelected: true, onOpenLibrary: {})
            .environmentObject(model)
            .sheet(isPresented: .constant(true)) {
                SleepTimerView(timer: timer)
                    .environment(\.locale, Locale(identifier: locale))
                    .environment(\.dynamicTypeSize, size)
                    .presentationDetents(size.isAccessibilitySize ? [.large] : [.height(480), .large])
                    .presentationDragIndicator(.visible)
            }
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.dynamicTypeSize, size)
            .preferredColorScheme(scheme)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertNotNil(host.presentedViewController, "Die native Timeransicht muss beim ersten Öffnen tatsächlich präsentiert werden.")
        print("Timer sheet snapshot: \(name)")
        try await Task.sleep(for: .milliseconds(1200))
        var rendered = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered)
        let attachment = XCTAttachment(image: image)
        attachment.name = "sleep-timer-\(name)-\(Int(window.bounds.width))x\(Int(window.bounds.height))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

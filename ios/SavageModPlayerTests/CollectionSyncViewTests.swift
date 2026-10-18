import XCTest
import SwiftUI
@testable import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class CollectionSyncViewTests: XCTestCase {
    private let captureRun = UUID().uuidString
    func testNativeSyncStatesLanguagesMappingConflictsAndLargestText() async throws {
        let cases: [(String, String, ColorScheme, DynamicTypeSize, String)] = [
            ("unconfigured-de-light", "de", .light, .large, "unconfigured"),
            ("unconfigured-en-largest", "en", .dark, .accessibility5, "unconfigured"),
            ("setup-de-dark", "de", .dark, .large, "setup"),
            ("mapping-de-light", "de", .light, .large, "mapping"),
            ("mapping-en-largest", "en", .dark, .accessibility5, "mapping"),
            ("chooser-en-largest", "en", .light, .accessibility5, "chooser"),
            ("conflicts-de-dark", "de", .dark, .large, "conflicts"),
            ("conflicts-en-largest", "en", .light, .accessibility5, "conflicts"),
            ("current-en-light", "en", .light, .large, "current"),
            ("offline-de-dark", "de", .dark, .large, "offline"),
            ("quota-en-largest", "en", .light, .accessibility5, "quota")
        ]
        for (name, locale, scheme, size, kind) in cases {
            let f = try await CollectionSyncAppFixture(configured: kind != "unconfigured")
            do {
                if ["current", "conflicts", "offline", "quota"].contains(kind) { try await f.connect() }
                if kind == "conflicts" {
                    var remote = try await f.backend.snapshot()
                    let list = try remote.exchangeDocument().playlists[0]
                    remote.cells.removeAll { $0.id == .playlist(list.id) }
                    remote.cells.append(.init(.playlist(list.id), .playlist(.init(id: list.id, name: "Remote playlist with a very long descriptive title", trackIDs: list.trackIDs.reversed()))))
                    try await f.backend.put(remote)
                    f.model.playlists.rename(id: f.playlistID, name: "Local playlist with a very long descriptive title")
                    try await Task.sleep(for: .milliseconds(20)); f.sync.cancelReview()
                }
                if kind == "offline" { await f.backend.setFailure(.temporarilyUnavailable(retryAfter: nil)) }
                if kind == "quota" { await f.backend.setFailure(.quotaExceeded) }
                if kind == "mapping" || kind == "chooser" {
                    let tracks = (0..<2).map { _ in ExchangeTrack(descriptor: .init(fileName: f.longName)) }
                    let remote = CollectionSyncSnapshot(collectionID: UUID(), generation: UUID(), cells:
                        tracks.map { .init(.track($0.id), .track($0.descriptor)) } + [
                            .init(.playlist(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!),
                                  .playlist(.init(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, name: "Remote collection", trackIDs: tracks.map(\.id))))
                        ])
                    try await f.backend.put(remote)
                }
                if kind == "chooser" {
                    await f.sync.beginSetup()
                    let track = try XCTUnwrap(f.sync.tracks.first)
                    XCTAssertEqual(track.suggestions.count, 2)
                    try await snapshot(content: AnyView(CollectionSyncTrackChooser(model: f.sync, track: track)),
                        fixture: f, name: name, locale: locale, scheme: scheme, size: size, kind: kind)
                } else {
                    try await snapshot(content: AnyView(CollectionSyncView(model: f.sync)),
                        fixture: f, name: name, locale: locale, scheme: scheme, size: size, kind: kind)
                }
            } catch { try await f.close(); throw error }
            try await f.close()
        }
    }

    private func snapshot(content: AnyView, fixture f: CollectionSyncAppFixture, name: String, locale: String,
                          scheme: ColorScheme, size: DynamicTypeSize, kind: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let parent = Color.clear.sheet(isPresented: .constant(true)) {
            content.environment(\.locale, Locale(identifier: locale)).environment(\.dynamicTypeSize, size)
                .presentationDetents([.large])
        }.environment(\.locale, Locale(identifier: locale)).environment(\.dynamicTypeSize, size).preferredColorScheme(scheme)
        let host = UIHostingController(rootView: parent), window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds; window.rootViewController = host; window.makeKeyAndVisible()
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(500))
        if kind == "setup" || kind == "mapping" { await f.sync.beginSetup() }
        try await CollectionSyncAppFixture.wait { !f.sync.isBusy }
        let expected: CollectionSyncModel.Status = switch kind {
        case "unconfigured": .notConfigured
        case "setup", "mapping", "chooser", "conflicts": .review
        case "offline": .waiting
        case "quota": .failed
        default: .current
        }
        XCTAssertEqual(f.sync.status, expected, "\(String(describing: f.sync.error))")
        if kind == "conflicts" {
            XCTAssertFalse(f.sync.conflicts.isEmpty)
            for conflict in f.sync.conflicts { f.sync.resolve(conflict.id, with: .keepBoth(copyID: UUID())) }
            XCTAssertTrue(f.sync.canConfirm)
        }
        if kind == "mapping" {
            XCTAssertEqual(f.sync.tracks.count, 2)
            XCTAssertTrue(f.sync.tracks.allSatisfy { $0.suggestions.count == 2 })
            XCTAssertFalse(f.sync.canConfirm)
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(host.presentedViewController)
        func scrollViews(_ view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
        }
        if let view = host.presentedViewController?.view {
            for scroll in scrollViews(view) { scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false) }
            view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        try await capture(name)
        if size.isAccessibilitySize || kind == "mapping" || kind == "conflicts" {
            if let presented = host.presentedViewController?.view,
               let scroll = scrollViews(presented).last(where: { $0.contentSize.height > $0.bounds.height + 20 }) {
                scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
                try await Task.sleep(for: .milliseconds(150)); try await capture(name + "-scrolled")
            }
        }
    }
    private func capture(_ name: String) async throws {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CollectionSyncCapture")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #if !targetEnvironment(simulator)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let directory = root.appendingPathComponent("Device-" + captureRun)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat(); format.scale = scene.screen.scale
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(drawn)
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        print("Native device sync capture: Device-\(captureRun)/\(name).png")
        #else
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("enabled").path) else { return }
        let id = UUID().uuidString
        let request = try JSONSerialization.data(withJSONObject: ["id": id, "name": name])
        try request.write(to: root.appendingPathComponent("request.json"), options: .atomic)
        let ack = root.appendingPathComponent(id + ".ack"), deadline = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: ack.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ack.path), "Die angeforderte Simulator-Aufnahme fehlt.")
        #endif
    }
}

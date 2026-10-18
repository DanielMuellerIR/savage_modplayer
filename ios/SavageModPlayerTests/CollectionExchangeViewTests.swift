import XCTest
import SwiftUI
@testable import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class CollectionExchangeViewTests: XCTestCase {
    func testNativeTransferSheetsLanguagesErrorsAndLargeText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CollectionViews-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(String, String, ColorScheme, DynamicTypeSize, String)] = [
            ("export-de-light", "de", .light, .large, "export"),
            ("mapped-en-dark", "en", .dark, .large, "mapped"),
            ("conflicts-de-light", "de", .light, .large, "conflicts"),
            ("missing-en-light", "en", .light, .large, "missing"),
            ("corrupt-de-dark", "de", .dark, .large, "corrupt"),
            ("conflicts-en-large", "en", .light, .accessibility3, "conflicts"),
            ("chooser-de-dark", "de", .dark, .large, "chooser"),
            ("chooser-en-large", "en", .light, .accessibility3, "chooser")
        ]
        for (name, locale, scheme, size, kind) in cases {
            let (state, document) = try fixture(kind: kind)
            let model = CollectionExchangeModel(capture: { state }, apply: { _ in false })
            let file = root.appendingPathComponent(name + ".savagecollection")
            if kind == "corrupt" { try Data("invalid".utf8).write(to: file) }
            else { try CollectionExchangeCodec.encode(document).write(to: file) }
            let content: AnyView
            if kind == "chooser" {
                await model.load(); try await model.receive(document)
                try await wait { !model.isBusy && !model.isFiltering }
                content = AnyView(CollectionExchangeTrackChooser(model: model, track: document.tracks.last!))
            } else {
                let context = CollectionExchangeContext(model: model, fileURL: kind == "export" ? nil : file)
                content = AnyView(CollectionExchangeView(context: context))
            }
            try await snapshot(content: content, model: model, name: name, locale: locale, scheme: scheme, size: size,
                               scroll: size.isAccessibilitySize || kind == "conflicts")
            model.cancel()
        }
    }
    private func fixture(kind: String) throws -> (CollectionExchangeModel.State, CollectionExchangeDocument) {
        let long = "A long module filename with a shared prefix for both folders and a clearly preserved ending — synthetic-collection-song.mod"
        let paths = ["A/" + long, "B/" + long, "C/other.mod"]
        let sources = paths.map { path in
            CollectionExchangeLocalTrack(reference: .init(source: PlaylistTrackSource(libraryRelativePath: path)!, displayName: path.split(separator: "/").last.map(String.init)!),
                descriptor: .init(fileName: path.split(separator: "/").last.map(String.init)!, relativePath: path))
        }
        var local = CollectionExchangeSnapshot(playbackDefaults: .init())
        local.playlists.playlists = [.init(name: "Existing list", tracks: sources.prefix(2).map(\.reference))]
        local.playlists.favoriteIDs = [sources[0].reference.id]
        local.markers.markers = [.init(sourceID: sources[1].reference.id, name: "Existing marker", address: .init(position: 0, row: 8), createdAt: Date(timeIntervalSince1970: 1_700_000_000))]
        local.trackSettings.tracks[sources[0].reference.id] = .init(stereoSeparation: 0.8, useInterpolation: true)
        var incoming = local
        if kind == "conflicts" {
            incoming.playlists.playlists[0].name = "Incoming list"; incoming.playlists.playlists[0].tracks.reverse()
            incoming.markers.markers[0].name = "Incoming marker"; incoming.markers.markers[0].address = .init(position: 2, row: 17)
            incoming.trackSettings.tracks[sources[0].reference.id] = .init(palClock: false, stereoSeparation: 0.25, useInterpolation: false)
            incoming.playbackDefaults = .init(stereoSeparation: 0.4, ledFilterActive: true)
        }
        var document = try CollectionExchangeExporter.makeDocument(from: incoming, sources: sources)
        if kind == "missing" || kind == "chooser" {
            let missing = ExchangeTrack(descriptor: .init(fileName: "renamed-track.mod", relativePath: "Missing/renamed-track.mod"))
            document.tracks.append(missing); document.playlists[0].trackIDs.append(missing.id)
        }
        return (.init(snapshot: local, sources: sources), document)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(8)
        while !condition(), Date() < end { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
    private func snapshot(content: AnyView, model: CollectionExchangeModel, name: String, locale: String, scheme: ColorScheme,
                          size: DynamicTypeSize, scroll shouldScroll: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let parent = Color.clear.sheet(isPresented: .constant(true)) {
            content.environment(\.locale, Locale(identifier: locale)).environment(\.dynamicTypeSize, size)
                .presentationDetents([.large])
        }.environment(\.locale, Locale(identifier: locale)).environment(\.dynamicTypeSize, size).preferredColorScheme(scheme)
        let host = UIHostingController(rootView: parent), window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds; window.rootViewController = host; window.makeKeyAndVisible()
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(600))
        try await wait { model.state != nil && !model.isBusy && !model.isFiltering }
        XCTAssertNotNil(host.presentedViewController)
        try await capture(name)
        if shouldScroll {
            func views(_ view: UIView) -> [UIScrollView] { (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(views) }
            let presented = try XCTUnwrap(host.presentedViewController?.view)
            let scroll = try XCTUnwrap(views(presented).first { $0.contentSize.height > $0.bounds.height + 20 })
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            try await Task.sleep(for: .milliseconds(250))
            try await capture(name + "-scrolled")
        }
    }
    private func capture(_ name: String) async throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CollectionSnapshotCapture")
        print("Collection exchange snapshot: \(name)")
        fflush(stdout)
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("enabled").path) {
            try await wait { FileManager.default.fileExists(atPath: directory.appendingPathComponent(name + ".ack").path) }
        } else {
            try await Task.sleep(for: .milliseconds(200))
        }
    }
}

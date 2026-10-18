import XCTest
import SwiftUI
import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class LibraryFiltersViewTests: XCTestCase {
    private var work: URL!
    private var model: AppModel!
    private var suite: String!
    override func setUp() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryFilters-\(UUID())")
        let root = work.appendingPathComponent("Documents")
        for folder in ["One", "Two"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try module(title: "Zebra Theme", sample: "Lead Pulse").write(to: root.appendingPathComponent("One/shared.mod"))
        try module(title: "Alpha Theme", sample: "Clean Pad").write(to: root.appendingPathComponent("Two/shared.mod"))
        var long = module(title: "Long Cycle", sample: ""); long[950] = 128
        try long.write(to: root.appendingPathComponent("long.mod"))
        try Data("broken".utf8).write(to: root.appendingPathComponent("bad.mod"))
        let core = MusicLibrary(rootURL: root, indexURL: work.appendingPathComponent("index.json"))
        try core.load(); _ = try core.rescan()
        suite = "LibraryFilters-\(UUID())"
        let library = LibraryStore(defaults: UserDefaults(suiteName: suite)!, library: core)
        library.start()
        try await waitUntil { !library.isBusy && library.tracks.count == 4 }
        let catalog = LibraryCatalogModel(metadataURL: work.appendingPathComponent("metadata.json"),
                                          preferencesURL: work.appendingPathComponent("preferences.json"))
        let settings = PlayerSettings(); settings.volume = 0
        model = AppModel(settings: settings, library: library,
                         playlists: PlaylistCollectionStore(fileURL: work.appendingPathComponent("playlists.json")), catalog: catalog)
        try await waitUntil { catalog.progress == nil && catalog.summary.total == 4 && catalog.summary.indexed == 3 }
    }
    override func tearDown() async throws {
        model.player.stop(); model.catalog.cancelIndexing(); model = nil
        UserDefaults().removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: work)
    }
    private func module(title: String, sample: String) -> Data {
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        let name = Data(title.utf8.prefix(20)); data.replaceSubrange(0..<name.count, with: name)
        let instrument = Data(sample.utf8.prefix(22)); data.replaceSubrange(20..<(20 + instrument.count), with: instrument)
        data[43] = 2; data[45] = 64; data[950] = 1
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        return data
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Erwarteter Endzustand blieb aus")
    }

    func testInstrumentSearchSavedFilterAndSortedPlaybackUseRelativeIDs() async throws {
        model.catalog.query.search = "pulse"
        try await waitUntil { !self.model.catalog.isFiltering && self.model.catalog.filteredIDs == ["One/shared.mod"] }
        let saved = await model.catalog.saveFilter(name: "Pulse collection", query: model.catalog.query)
        XCTAssertTrue(saved)
        model.catalog.query = LibraryQuery()
        model.catalog.query.sort = .title
        try await waitUntil { !self.model.catalog.isFiltering && self.model.catalog.filteredIDs.first == "Two/shared.mod" }
        let tracks = model.catalog.filteredIDs.compactMap { model.library.track(forRelativePath: $0) }
        model.player.setExplicitQueue(tracks)
        model.player.select(tracks[0])
        try await waitUntil { self.model.player.currentTrack?.relativePath == "Two/shared.mod" }
        model.player.next()
        try await waitUntil { self.model.player.currentTrack?.relativePath == "long.mod" }
        XCTAssertFalse(model.player.coordinator.isPlaying)
        XCTAssertEqual(model.catalog.preferences.savedFilters.first?.query.search, "pulse")
        XCTAssertEqual(model.catalog.summary.duplicateNameGroups, 1)
        XCTAssertTrue(try XCTUnwrap(model.catalog.records["long.mod"]?.metadata).durationIsLimited)
    }

    func testFilterLibraryAndCollectionStatesRenderInBothThemes() async throws {
        model.catalog.query.sort = .title
        try await waitUntil { !self.model.catalog.isFiltering }
        for (width, height, locale, scheme) in [(393, 852, "de", ColorScheme.light), (1024, 768, "en", ColorScheme.dark)] {
            try await snapshot(LibraryView().environmentObject(model), name: "metadata-library-\(width)-\(locale)",
                               width: width, height: height, locale: locale, scheme: scheme, bottom: false)
            try await snapshot(LibraryFiltersView(catalog: model.catalog), name: "filters-top-\(width)-\(locale)",
                               width: width, height: height, locale: locale, scheme: scheme, bottom: false)
            try await snapshot(LibraryFiltersView(catalog: model.catalog), name: "filters-bottom-\(width)-\(locale)",
                               width: width, height: height, locale: locale, scheme: scheme, bottom: true)
        }
    }

    private func snapshot<V: View>(_ view: V, name: String, width: Int, height: Int, locale: String,
                                    scheme: ColorScheme, bottom: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: locale)).preferredColorScheme(scheme))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        if bottom {
            func scrollViews(_ view: UIView) -> [UIScrollView] {
                (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            let scroll = try XCTUnwrap(scrollViews(host.view).max { $0.contentSize.height < $1.contentSize.height })
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        var rendered = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

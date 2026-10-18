import XCTest
import SwiftUI
import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class SongMarkersViewTests: XCTestCase {
    func testMarkerEditorRangeMissingTargetAndReadOnlyStateRender() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MarkerUI-\(UUID())")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appendingPathComponent("markers.json"), store = SongMarkerStore(fileURL: work.appendingPathComponent("markers.json"))
        let entries = [SongMarker(sourceID: "One/shared.mod", name: "Intro", address: .init(position: 0,row: 1)),
                       SongMarker(sourceID: "One/shared.mod", name: "Second occurrence", address: .init(position: 1,row: 2)),
                       SongMarker(sourceID: "One/shared.mod", name: "Missing target", address: .init(position: 99,row: 0)),
                       SongMarker(sourceID: "Two/shared.mod", name: "Other file", address: .init(position: 0,row: 0))]
        _ = try await store.update { $0.markers = entries }
        let song = Mod(name: "Repeated patterns", length: 3, patternTable: [0,0,1], instruments: [nil],
                       patterns: [Pattern(rows: Array(repeating: Row(notes: []), count: 4)),
                                  Pattern(rows: Array(repeating: Row(notes: []), count: 12))])
        let model = SongMarkersModel(fileURL: file)
        model.setContext(sourceID: "One/shared.mod", module: song, moduleID: UUID())
        try await wait { model.isLoaded }
        model.setBoundary(.init(position: 1,row: 1), isStart: true); model.setBoundary(.init(position: 2,row: 8), isStart: false)
        XCTAssertEqual(model.markers.count, 3)
        let transport = TransportState(); transport.currentPosition = 1; transport.currentRow = 2
        let coordinator = ModPlayerCoordinator(); coordinator.setMod(song)
        defer { coordinator.stop() }
        let badFile = work.appendingPathComponent("bad.json"); try Data("broken".utf8).write(to: badFile)
        let broken = SongMarkersModel(fileURL: badFile)
        broken.setContext(sourceID: "One/shared.mod", module: song, moduleID: UUID())
        try await wait { broken.isLoaded }
        XCTAssertFalse(broken.canSave)
        for (width,height,locale,scheme) in [(393,852,"de",ColorScheme.light),(1024,768,"en",ColorScheme.dark)] {
            let view = NavigationStack {
                SongMarkersView(model: model, transport: transport, coordinator: coordinator,
                    current: { .init(position: 1,row: 2) }, seek: { model.layout.contains($0) })
                    .navigationTitle("Songstellen und Auswahl").navigationBarTitleDisplayMode(.inline)
            }
            for bottom in [false,true] {
                try await snapshot(view, name: "markers-\(bottom ? "bottom" : "top")-\(width)-\(locale)",
                                   width: width,height: height,locale: locale,scheme: scheme,bottom: bottom)
            }
            try await snapshot(NavigationStack {
                SongMarkersView(model: broken,current: { .init(position: 0,row: 0) },seek: { _ in true })
                    .navigationTitle("Songstellen und Auswahl").navigationBarTitleDisplayMode(.inline)
            }, name: "markers-readonly-\(width)-\(locale)", width: width,height: height,locale: locale,scheme: scheme,bottom: false)
        }
    }

    func testRealPlayerRowJumpPreservesStoppedStateAndChangesLoadIdentity() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MarkerPlayer-\(UUID())")
        let root = work.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        var data = Data(repeating: 0,count: 1084+1024+4); data[43] = 2; data[950] = 2
        data.replaceSubrange(1080..<1084,with: Data("M.K.".utf8))
        for name in ["a.mod","b.mod"] { try data.write(to: root.appendingPathComponent(name)) }
        let core = MusicLibrary(rootURL: root,indexURL: work.appendingPathComponent("index.json")); try core.load(); _ = try core.rescan()
        let suite = "MarkerPlayer-\(UUID())"
        let library = LibraryStore(defaults: UserDefaults(suiteName: suite)!,library: core)
        let settings = PlayerSettings(); settings.volume = 0
        let player = PlaybackEngine(settings: settings,library: library)
        defer { player.stop(); UserDefaults().removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: work) }
        library.start(); try await wait { library.tracks.count == 2 }
        player.select(library.tracks[0]); try await wait { player.currentTrack?.relativePath == "a.mod" }
        let identity = player.loadedModuleID
        player.seek(to: .init(position: 1,row: 8))
        XCTAssertEqual(player.coordinator.currentPosition,1); XCTAssertEqual(player.coordinator.currentRow,8)
        XCTAssertFalse(player.coordinator.isPlaying); XCTAssertFalse(player.isPlaying)
        let section = try XCTUnwrap(SongSection(start: .init(position: 1,row: 8), end: .init(position: 1,row: 9)))
        player.startSectionLoop(section)
        try await wait { player.coordinator.sectionLoopIsActive && player.isPlaying }
        player.pause()
        XCTAssertTrue(player.coordinator.isPaused)
        player.startSectionLoop(section)
        try await wait { player.coordinator.sectionLoopIsActive }
        XCTAssertTrue(player.coordinator.isPaused)
        XCTAssertEqual(player.coordinator.currentPosition, 1)
        XCTAssertEqual(player.coordinator.currentRow, 8)
        player.coordinator.cancelSectionLoop()
        player.play()
        try await wait { player.coordinator.currentPosition == 1 && player.coordinator.currentRow >= 8 }
        player.select(library.tracks[1]); try await wait { player.currentTrack?.relativePath == "b.mod" }
        XCTAssertNotEqual(player.loadedModuleID,identity)
        XCTAssertFalse(player.coordinator.sectionLoopIsActive)
    }

    func testSectionLoopErrorActiveControlsAndCancellationRender() async throws {
        let coordinator = ModPlayerCoordinator()
        coordinator.setVolume(0)
        let song = Mod(name: "A/B states", length: 1, patternTable: [0], instruments: [nil],
            patterns: [Pattern(rows: Array(repeating: Row(notes: []), count: 12))], initialSpeed: 1)
        coordinator.setMod(song)
        defer { coordinator.stop() }
        let section = try XCTUnwrap(SongSection(start: .init(position: 0,row: 3), end: .init(position: 0,row: 4)))
        coordinator.startSectionLoop(section)
        coordinator.stop()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(coordinator.sectionLoopIsPreparing)
        XCTAssertFalse(coordinator.sectionLoopIsActive)
        XCTAssertFalse(coordinator.isPlaying)
        coordinator.startSectionLoop(section)
        try await wait { coordinator.sectionLoopIsActive }
        for (width,height,locale,scheme) in [(393,220,"de",ColorScheme.light),(1024,220,"en",ColorScheme.dark)] {
            try await snapshot(SectionLoopControls(coordinator: coordinator, section: section).padding(20),
                name: "section-loop-active-\(width)-\(locale)",width: width,height: height,locale: locale,scheme: scheme,bottom: false)
        }
        coordinator.startSectionLoop(try XCTUnwrap(SongSection(start: .init(position: 99,row: 0), end: .init(position: 99,row: 1))))
        try await wait { coordinator.sectionLoopError != nil }
        XCTAssertFalse(coordinator.sectionLoopIsActive)
        for (width,height,locale,scheme) in [(393,300,"en",ColorScheme.dark),(1024,220,"de",ColorScheme.light)] {
            try await snapshot(SectionLoopControls(coordinator: coordinator, section: section).padding(20),
                name: "section-loop-error-\(width)-\(locale)",width: width,height: height,locale: locale,scheme: scheme,bottom: false)
        }
        coordinator.cancelSectionLoop()
        XCTAssertNil(coordinator.sectionLoopError)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }
    private func snapshot<V: View>(_ view: V,name: String,width: Int,height: Int,locale: String,scheme: ColorScheme,bottom: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: view.environment(\.locale,Locale(identifier: locale)).preferredColorScheme(scheme))
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0,y: 0,width: width,height: height)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(350))
        if bottom {
            func scrolls(_ view: UIView) -> [UIScrollView] { (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls) }
            let scroll = try XCTUnwrap(scrolls(host.view).max { $0.contentSize.height < $1.contentSize.height })
            scroll.setContentOffset(CGPoint(x: 0,y: max(0,scroll.contentSize.height-scroll.bounds.height+scroll.adjustedContentInset.bottom)),animated: false)
            host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(100))
        }
        var rendered = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in rendered = window.drawHierarchy(in: window.bounds,afterScreenUpdates: true) }
        XCTAssertTrue(rendered)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

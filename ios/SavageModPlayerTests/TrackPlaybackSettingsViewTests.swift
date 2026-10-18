import XCTest
import SwiftUI
@testable import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class TrackPlaybackSettingsViewTests: XCTestCase {
    func testNativeSheetContextsLanguagesAndLargeText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TrackSettingsViews-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(String,ModuleFormat,String,ColorScheme,DynamicTypeSize,Bool,Bool)] = [
            ("inherited-mod-de-light",.protracker,"de",.light,.large,false,false),
            ("overrides-mod-en-dark",.protracker,"en",.dark,.large,true,false),
            ("fixed-xm-de-dark",.xm,"de",.dark,.large,true,false),
            ("fixed-it-en-light",.it,"en",.light,.large,true,false),
            ("readonly-de-light",.protracker,"de",.light,.large,false,true),
            ("overrides-en-large-text",.protracker,"en",.light,.accessibility3,true,false),
            ("fixed-de-large-text",.xm,"de",.dark,.accessibility3,true,false)
        ]
        for (name,format,locale,scheme,size,overridden,corrupt) in cases {
            let file = root.appendingPathComponent(name+".json")
            if corrupt { try Data("broken".utf8).write(to:file) }
            let settings = PlayerSettings()
            let preferences = TrackPlaybackSettingsModel(fileURL:file,defaults:settings.playbackOptions)
            let sourceID = "album/same.mod"
            if overridden {
                XCTAssertTrue(preferences.updateTitle(sourceID) {
                    $0.palClock = false; $0.stereoSeparation = 0.25; $0.useInterpolation = false; $0.ledFilterActive = true
                })
            }
            let model = AppModel(playbackSettings:preferences)
            let demo = ModParser.generateDemoMod()
            let module = Mod(name:demo.name,length:demo.length,patternTable:demo.patternTable,
                instruments:demo.instruments,patterns:demo.patterns,format:format)
            model.player.coordinator.setMod(module,precomputedDuration:8)
            preferences.setContext(sourceID:sourceID,format:format)
            let context = TrackPlaybackSettingsContext(sourceID:sourceID,title:"A rather long track title · Beispiel für Titel-Einstellungen",format:format,sourceDescription:"Albums / Demo collection / same.mod")
            try await snapshot(model:model,preferences:preferences,context:context,name:name,locale:locale,scheme:scheme,size:size)
            model.player.stop()
            if corrupt { XCTAssertEqual(try Data(contentsOf:file),Data("broken".utf8)) }
        }
    }

    private func snapshot(model:AppModel,preferences:TrackPlaybackSettingsModel,context:TrackPlaybackSettingsContext,
                          name:String,locale:String,scheme:ColorScheme,size:DynamicTypeSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let content = NowPlayingView(isSelected:true,onOpenLibrary:{})
            .environmentObject(model)
            .sheet(isPresented:.constant(true)) {
                TrackPlaybackSettingsView(model:preferences,context:context)
                    .environment(\.locale,Locale(identifier:locale))
                    .environment(\.dynamicTypeSize,size)
                    .presentationDetents(size.isAccessibilitySize ? [.large] : [.height(600),.large])
                    .presentationDragIndicator(.visible)
            }
            .environment(\.locale,Locale(identifier:locale))
            .environment(\.dynamicTypeSize,size)
            .preferredColorScheme(scheme)
        let host = UIHostingController(rootView:content)
        let window = UIWindow(windowScene:scene)
        window.frame = scene.coordinateSpace.bounds; window.rootViewController = host
        window.makeKeyAndVisible()
        defer { host.dismiss(animated:false); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for:.milliseconds(550))
        XCTAssertNotNil(host.presentedViewController)
        print("Track settings snapshot: \(name)")
        try await Task.sleep(for:.milliseconds(1200))
        var rendered = false
        let image = UIGraphicsImageRenderer(size:window.bounds.size).image { _ in
            rendered = window.drawHierarchy(in:window.bounds,afterScreenUpdates:true)
        }
        XCTAssertTrue(rendered)
        if size.isAccessibilitySize || name.hasPrefix("readonly") {
            func scrollViews(_ view:UIView) -> [UIScrollView] {
                (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            let presented = try XCTUnwrap(host.presentedViewController?.view)
            let scroll = try XCTUnwrap(scrollViews(presented).first { $0.contentSize.height > $0.bounds.height+20 })
            scroll.setContentOffset(CGPoint(x:0,y:max(0,scroll.contentSize.height-scroll.bounds.height+scroll.adjustedContentInset.bottom)),animated:false)
            try await Task.sleep(for:.milliseconds(250))
            print("Track settings snapshot: \(name)-scrolled")
            try await Task.sleep(for:.milliseconds(1200))
        }
        let attachment = XCTAttachment(image:image)
        attachment.name = "track-settings-\(name)-\(Int(window.bounds.width))x\(Int(window.bounds.height))"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}

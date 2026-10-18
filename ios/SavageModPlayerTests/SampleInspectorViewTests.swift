import XCTest
import SwiftUI
import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class SampleInspectorViewTests: XCTestCase {
    func testMultiSampleStereoSustainAndEmptyStatesRenderOnPhoneAndPad() async throws {
        let pcm = (0..<4096).map { Float(sin(Double($0) * .pi / 40) * 0.45) }
        let sound = Sample(pcm: pcm, loopStart: 1024, loopLength: 1024, loopType: .pingpong,
                           volume: 48, finetune: -12, relativeNote: 2, name: "Stereo sustain",
                           rightPCM: pcm.map { -$0 }, sustainLoop: SampleLoop(start: 512, length: 512, type: .forward),
                           itProperties: ITSampleProperties(c5Speed: 16726, globalVolume: 64, defaultPanning: nil))
        let empty = Sample(pcm: [], loopStart: 0, loopLength: 0, loopType: .none, volume: 0, finetune: 0, name: "Empty")
        let xmInstrument = Instrument(index: 1, name: "Keyboard Layers", samples: [sound, empty],
                                      keymap: (0..<96).map { $0 < 60 ? 0 : 1 })
        let mapping = try NoteSampleMapping(entries: (0..<120).map { note in
            try .init(targetNote: min(119, note + 12), sampleID: note < 24 ? 0 : 2)
        })
        let itInstrument = Instrument(index: 1, name: "Mapped stereo", samples: [], noteSampleMapping: mapping)
        let xm = Mod(name: "XM", length: 0, patternTable: [], instruments: [nil, xmInstrument], patterns: [], format: .xm)
        let it = Mod(name: "IT", length: 0, patternTable: [], instruments: [nil, itInstrument],
                     samplePool: [nil, empty, sound], patterns: [], format: .it)
        let noSamples = Mod(name: "Empty", length: 0, patternTable: [], instruments: [nil], patterns: [])
        let emptySlot = Mod(name: "Empty slot", length: 0, patternTable: [],
                            instruments: [nil, Instrument(index: 1, name: "Empty", samples: [empty])], patterns: [])
        for (width, height, locale, scheme) in [(393, 852, "de", ColorScheme.light), (1024, 768, "en", ColorScheme.dark)] {
            for (name, module, index) in [("xm-multi", xm, Optional(1)), ("it-stereo-sustain", it, Optional(1)),
                                           ("empty", noSamples, nil), ("empty-slot", emptySlot, Optional(1))] {
                let view = NavigationStack {
                    SampleInspectorView(module: module, instrumentIndex: index)
                        .navigationTitle("Sample-Inspektor").navigationBarTitleDisplayMode(.inline)
                }
                try await snapshot(view, name: "samples-\(name)-\(width)-\(locale)", width: width, height: height,
                                   locale: locale, scheme: scheme, bottom: false)
                if name == "xm-multi" || name == "it-stereo-sustain" {
                    try await snapshot(view, name: "samples-\(name)-bottom-\(width)-\(locale)", width: width, height: height,
                                       locale: locale, scheme: scheme, bottom: true)
                }
            }
        }
    }

    private func snapshot<V: View>(_ view: V, name: String, width: Int, height: Int, locale: String, scheme: ColorScheme, bottom: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: locale)).preferredColorScheme(scheme))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
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

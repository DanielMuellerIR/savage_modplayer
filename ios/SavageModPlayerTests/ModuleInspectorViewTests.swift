import XCTest
import SwiftUI
import SavageModPlayerCore
@testable import SavageModPlayer

@MainActor
final class ModuleInspectorViewTests: XCTestCase {
    private func fixture() -> Mod {
        let points = [EnvelopePoint(frame: 0, value: 64), .init(frame: 10, value: 40), .init(frame: 35, value: 0)]
        let volume = Envelope(points: points, sustainStart: 1, sustainEnd: 1, loopStart: 0, loopEnd: 1,
                              sustainEnabled: true, loopEnabled: true, carryEnabled: true)
        let pan = Envelope(points: [.init(frame: 0, value: 0), .init(frame: 20, value: 64), .init(frame: 40, value: 32)],
                           sustainPoint: 2, loopStart: 0, loopEnd: 2, sustainEnabled: false, loopEnabled: true)
        let filter = Envelope(points: points, sustainStart: 1, sustainEnd: 2, loopStart: 0, loopEnd: 2,
                              sustainEnabled: true, loopEnabled: false, valueMode: .filter)
        let instrumentProperties = ITInstrumentProperties(newNoteAction: .continuePlaying, duplicateCheckType: .note,
            duplicateCheckAction: .noteFade, globalVolume: 96, defaultPanning: 32, pitchPanSeparation: 2, pitchPanCenter: 60,
            randomVolumeVariation: 12, randomPanningVariation: 8, initialFilterCutoff: 80, initialFilterResonance: 40,
            midiChannel: 0, midiProgram: 0, midiBank: 0, pluginSlot: 7)
        let instrument = Instrument(index: 1, name: "Envelope layers", samples: [], volumeEnvelope: volume,
                                    panningEnvelope: pan, fadeout: 1024, pitchEnvelope: filter, itProperties: instrumentProperties)
        let finding = ITCapabilityFinding(feature: .pluginInstrument, identifier: "plugin-7", detected: true, used: true,
            support: .unsupported, detail: "Instrument 1 uses an external plugin.", warning: "External plugin output is unavailable; PCM remains playable.")
        let properties = ITModuleProperties(createdWithVersion: 0x5131, compatibleWithVersion: 0x214,
            usesInstruments: true, stereo: true, volumeZeroMixOptimization: false, linearSlides: true,
            patternHighlight: 0, mixVolume: 128, panSeparation: 128, pitchWheelDepth: 0,
            hasSongMessage: false, songMessageLength: 0, songMessageOffset: 0,
            usesMIDIPitchController: false, hasEmbeddedMIDIConfiguration: false, unknownHeaderFlags: 0, unknownSpecialFlags: 0,
            trackerIdentity: ITTrackerIdentity(family: .openMPT, rawCreatedWith: 0x5131, displayName: "OpenMPT fixture"),
            openMPTExtensions: ITOpenMPTExtensions(artist: "Fixture composer"), capabilityReport: ITCapabilityReport(findings: [finding]))
        let pattern = Pattern(rows: (1...6).map { command in
            Row(notes: [Note(instrument: 1, period: 0, effectId: ModuleEffect.impulseTrackerCommand(command),
                             effectData: command == 4 ? 0 : command, key: 48, volume: 64, effectPresent: true)])
        })
        return Mod(name: "Inspector fixture", length: 2, patternTable: [0, 0], instruments: [nil, instrument],
                   patterns: [pattern], format: .it, linearFrequency: true, itProperties: properties)
    }

    func testOverviewEnvelopesAndEffectGuideRenderOnPhoneAndPad() async throws {
        for (width, height, locale, scheme) in [(393, 852, "de", ColorScheme.light), (1024, 768, "en", ColorScheme.dark)] {
            for section in ModuleInspectorSection.allCases {
                let view = NavigationStack {
                    ModuleInspectorView(module: fixture(), section: section)
                        .navigationTitle("Modul-Inspektor").navigationBarTitleDisplayMode(.inline)
                }
                for fraction in [0.0, 0.5, 1.0] {
                    try await snapshot(view, name: "module-\(section.rawValue)-\(fraction)-\(width)-\(locale)",
                                       width: width, height: height, locale: locale, scheme: scheme, fraction: fraction)
                }
            }
        }
    }

    func testPlayerShowsInspectorMenuWithARealLoadedModule() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("InspectorPlayer-\(UUID())")
        let documents = work.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        var data = Data(repeating: 0, count: 1084 + 1024 + 4)
        let name = Data("Player fixture".utf8); data.replaceSubrange(0..<name.count, with: name)
        data[43] = 2; data[950] = 1
        data.replaceSubrange(1080..<1084, with: Data("M.K.".utf8))
        try data.write(to: documents.appendingPathComponent("player.mod"))
        let core = MusicLibrary(rootURL: documents, indexURL: work.appendingPathComponent("index.json"))
        try core.load(); _ = try core.rescan()
        let suite = "InspectorPlayer-\(UUID())"
        let library = LibraryStore(defaults: UserDefaults(suiteName: suite)!, library: core)
        let settings = PlayerSettings(); settings.volume = 0
        let catalog = LibraryCatalogModel(metadataURL: work.appendingPathComponent("metadata.json"),
                                          preferencesURL: work.appendingPathComponent("preferences.json"))
        let model = AppModel(settings: settings, library: library,
            playlists: PlaylistCollectionStore(fileURL: work.appendingPathComponent("playlists.json")), catalog: catalog)
        defer {
            model.player.stop(); catalog.cancelIndexing()
            UserDefaults().removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: work)
        }
        library.start()
        let deadline = Date().addingTimeInterval(10)
        while library.tracks.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        model.player.select(try XCTUnwrap(library.tracks.first))
        while model.player.coordinator.activeMod == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.player.coordinator.activeMod?.name, "Player fixture")
        for (width, height, locale, scheme) in [(393, 852, "de", ColorScheme.light), (1024, 768, "en", ColorScheme.dark)] {
            try await snapshot(NowPlayingView(isSelected: true, onOpenLibrary: {}).environmentObject(model),
                name: "player-inspector-menu-\(width)-\(locale)", width: width, height: height,
                locale: locale, scheme: scheme, fraction: 0)
        }
    }

    private func snapshot<V: View>(_ view: V, name: String, width: Int, height: Int, locale: String,
                                   scheme: ColorScheme, fraction: Double) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: locale)).preferredColorScheme(scheme))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        if fraction > 0 {
            func scrollViews(_ view: UIView) -> [UIScrollView] {
                (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            let scroll = try XCTUnwrap(scrollViews(host.view).max { $0.contentSize.height < $1.contentSize.height })
            let end = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: end * fraction), animated: false)
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        var rendered = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

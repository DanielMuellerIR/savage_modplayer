import SavageModPlayerCore
import SwiftUI

// Der Wiedergabe-Tab.
//
// Grundsatz dieser Ansicht: Visualisierungen duerfen nur Arbeit verursachen,
// solange der Nutzer sie wirklich sieht. Titelbild, Transport, Positionsregler
// und Statuszeile stehen oben; scrollt der Visualizer-Abschnitt in den Viewport,
// werden Canvas und Wellenformen erzeugt. Beim Herausscrollen verschwinden beide
// wieder und die Audio-Wiedergabe laeuft unveraendert weiter.
struct NowPlayingView: View {
    @EnvironmentObject private var model: AppModel

    let isSelected: Bool
    let onOpenLibrary: () -> Void

    var body: some View {
        Content(
            player: model.player,
            settings: model.settings,
            library: model.library,
            isSelected: isSelected,
            sceneIsActive: model.isSceneActive,
            onOpenLibrary: onOpenLibrary)
    }

    static let contentMaximumWidth: CGFloat = 900

    static func visualizerWidth(viewportWidth: CGFloat) -> CGFloat {
        max(1, min(contentMaximumWidth, viewportWidth) - 40)
    }

    private struct Content: View {
        @ObservedObject var player: PlaybackEngine
        @ObservedObject var settings: PlayerSettings
        // Die Bibliothek wird hier NICHT beobachtet, sie wird nur an den
        // Favoriten-Schalter weitergereicht — der beobachtet sie selbst.
        let library: LibraryStore
        let isSelected: Bool
        let sceneIsActive: Bool
        let onOpenLibrary: () -> Void
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @State private var controlsHeight: CGFloat = 0
        @State private var visualizerIsInViewport = false

        var body: some View {
            NavigationStack {
                Group {
                    if let track = player.currentTrack, let mod = player.coordinator.activeMod {
                        trackContent(track: track, mod: mod)
                    } else {
                        emptyState
                    }
                }
                .navigationTitle("tab.player")
                .navigationBarTitleDisplayMode(.inline)
            }
            // TabView behaelt nicht ausgewaehlte Tabs im Speicher. Der
            // Auswahlzustand kommt deshalb ausdruecklich von RootView; auf
            // onAppear/onDisappear allein ist hier kein Verlass.
            .onAppear { applyVisualizerVisibility() }
            .onChange(of: isSelected) { _, _ in applyVisualizerVisibility() }
            .onDisappear { player.setVisualizerSectionVisible(false) }
        }

        // MARK: - Kein Titel gewaehlt

        private var emptyState: some View {
            ContentUnavailableView {
                Label("player.empty.title", systemImage: "opticaldisc")
            } description: {
                Text("player.empty.hint")
            } actions: {
                Button("player.empty.action", action: onOpenLibrary)
                    .buttonStyle(.borderedProminent)
            }
        }

        // MARK: - Gewaehlter Titel

        private func trackContent(track: TrackRef, mod: Mod) -> some View {
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        VStack(spacing: 20) {
                            artwork(mod: mod)
                            titleBlock(track: track, mod: mod)
                            positionBlock(mod: mod)
                            transportRow
                            secondaryRow(track: track)
                            PlaybackStatusRow(
                                coordinator: player.coordinator,
                                positionCount: mod.length,
                                channelCount: mod.usedChannelCount)
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                        visualizers(
                            mod: mod,
                            viewportHeight: viewport.size.height,
                            availableWidth: NowPlayingView.visualizerWidth(viewportWidth: viewport.size.width))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: NowPlayingView.contentMaximumWidth)
                    // Die begrenzte Spalte bleibt auch auf breiten iPads mittig.
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: VisualizerViewport.coordinateSpace)
                .background(Color.playerBackground)
            }
        }

        // Ein Modul hat kein Titelbild. Statt einer leeren Flaeche steht hier
        // das Format gross und lesbar — es ist die Information, die einen
        // Tracker-Titel wirklich einordnet.
        private func artwork(mod: Mod) -> some View {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.accentColor.opacity(0.30), Color.playerSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                    }
                VStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(.tint)
                    Text(verbatim: moduleFormatLabel(mod.format))
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 260, maxHeight: 260)
            .accessibilityLabel(Text(verbatim: moduleFormatLabel(mod.format)))
        }

        private func titleBlock(track: TrackRef, mod: Mod) -> some View {
            VStack(spacing: 4) {
                Text(verbatim: track.displayName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                folderPathText(track.folderPath)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                // Der im Modul gespeicherte Name weicht oft vom Dateinamen ab —
                // fuer Tracker-Musik gehoert er dazu.
                if !mod.name.isEmpty, mod.name != track.displayName {
                    Text(verbatim: mod.name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }

        private func positionBlock(mod: Mod) -> some View {
            VStack(spacing: 2) {
                PositionSliderView(
                    transport: player.coordinator.transport,
                    positionCount: mod.length,
                    onSeek: { player.seek(toPosition: $0) })
                PlaybackTimeRow(visualizer: player.coordinator.visualizerState)
            }
        }

        // MARK: - Transport

        private var isRunning: Bool {
            player.isPlaying && !player.isPaused
        }

        private var transportRow: some View {
            HStack(spacing: 0) {
                transportButton("backward.fill", label: "transport.previous", action: player.previous)
                transportButton("gobackward.15", label: "transport.back15") {
                    player.skip(bySeconds: -15)
                }

                let playPauseLabel: LocalizedStringKey = isRunning ? "transport.pause" : "transport.play"
                Button(action: player.togglePlayPause) {
                    Image(systemName: isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(playPauseLabel)
                .frame(maxWidth: .infinity)

                transportButton("goforward.30", label: "transport.forward30") {
                    player.skip(bySeconds: 30)
                }
                transportButton("forward.fill", label: "transport.next", action: player.next)
            }
            .font(.title2)
        }

        private func transportButton(
            _ symbol: String,
            label: LocalizedStringKey,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Image(systemName: symbol)
                    // Grosse Trefferflaeche: auf einem Telefon wird mit dem
                    // Daumen gezielt, nicht mit einem Mauszeiger.
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(label)
            .frame(maxWidth: .infinity)
        }

        // Zufallswiedergabe, Wiederholmodus, Favorit.
        //
        // Die Beschriftung des Wiederholmodus steht als eigene Zeile UNTER den
        // Knoepfen, nicht daneben. Bei grosser Schrift (Dynamic Type) braucht
        // "Liste wiederholen" mehr Platz, als ein Drittel der Zeilenbreite
        // hergibt — daneben wuerde der Text in drei Stuecke brechen und
        // abgeschnitten.
        private func secondaryRow(track: TrackRef) -> some View {
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Button {
                        settings.set(\.shuffleEnabled, to: !settings.shuffleEnabled)
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(settings.shuffleEnabled ? Color.accentColor : Color.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("transport.shuffle")
                    .accessibilityAddTraits(settings.shuffleEnabled ? .isSelected : [])
                    .frame(maxWidth: .infinity)

                    Button {
                        settings.set(\.loopMode, to: nextLoopMode)
                    } label: {
                        Image(systemName: settings.loopMode.iconName)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("transport.loop")
                    .accessibilityValue(Text(settings.loopMode.localizedName))
                    .frame(maxWidth: .infinity)

                    FavoriteToggleButton(library: library, relativePath: track.relativePath)
                        .frame(minWidth: 44, minHeight: 44)
                        .frame(maxWidth: .infinity)
                }
                // Sagt, was das Wiederholungs-Symbol gerade bedeutet.
                Text(settings.loopMode.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }

        // Reihum durch die drei Wiederholmodi.
        private var nextLoopMode: LoopMode {
            let modes = LoopMode.allCases
            let index = modes.firstIndex(of: settings.loopMode) ?? 0
            return modes[(index + 1) % modes.count]
        }

        // MARK: - Visualisierungen (nur im sichtbaren Scrollbereich)

        private func visualizers(
            mod: Mod,
            viewportHeight: CGFloat,
            availableWidth: CGFloat
        ) -> some View {
            VisualizerSection(
                visualizer: player.coordinator.visualizerState,
                channelIndices: visibleChannelIndices(mod: mod),
                totalChannels: mod.usedChannelCount,
                frameRate: settings.visualizerFrameRate,
                tabSelected: isSelected,
                sceneIsActive: sceneIsActive,
                viewportHeight: viewportHeight,
                availableWidth: availableWidth,
                minimumHeight: horizontalSizeClass == .regular
                    ? max(0, viewportHeight - controlsHeight - 52) : 0,
                onVisibilityChanged: { visible in
                    visualizerIsInViewport = visible
                    applyVisualizerVisibility()
                })
        }

        private func applyVisualizerVisibility() {
            player.setVisualizerSectionVisible(
                VisualizerActivation.shouldRun(
                    tabSelected: isSelected,
                    sectionVisible: visualizerIsInViewport))
        }

        // Welche Kanaele gezeichnet werden. Ein IT-Modul haelt bis zu 64 Kanaele
        // vor, benutzt aber oft nur einen Teil davon; gezeigt werden die
        // benutzten, und davon hoechstens so viele, wie in den Einstellungen
        // erlaubt sind.
        private func visibleChannelIndices(mod: Mod) -> [Int] {
            let limit = max(1, settings.maxVisibleChannelScopes)
            let used = mod.usedChannelIndices
            if used.isEmpty {
                return Array(0..<min(mod.channelCount, limit))
            }
            return Array(used.prefix(limit))
        }
    }
}

// Der Block mit den Visualisierungen. Eigene Ansicht, damit er sich merken
// kann, ob er ueberhaupt sichtbar ist: In einer TabView bleiben die anderen Tabs
// am Leben, und ein weiterlaufender Zeichentakt in einem unsichtbaren Tab waere
// genau die Rechenzeit, die diese App nicht verbrauchen will.
private struct VisualizerSection: View {
    let visualizer: VisualizerState
    let channelIndices: [Int]
    let totalChannels: Int
    let frameRate: Int
    let tabSelected: Bool
    let sceneIsActive: Bool
    let viewportHeight: CGFloat
    let availableWidth: CGFloat
    let minimumHeight: CGFloat
    let onVisibilityChanged: (Bool) -> Void

    @State private var isVisible = false

    var body: some View {
        Group {
            if VisualizerActivation.shouldRender(
                tabSelected: tabSelected,
                sceneActive: sceneIsActive,
                sectionVisible: isVisible
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    MasterScopeView(
                        visualizer: visualizer, frameRate: frameRate,
                        height: 64 + extraHeight / 3)
                    ChannelScopesView(
                        visualizer: visualizer,
                        channelIndices: channelIndices,
                        frameRate: frameRate,
                        availableWidth: availableWidth,
                        minimumHeight: channelHeight + extraHeight * 2 / 3)
                    if channelIndices.count < totalChannels {
                        Text("player.scopes.limited \(channelIndices.count) \(totalChannels)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Gleiche Hoehe wie der echte Inhalt: beim Ein-/Ausblenden darf
                // der Scrollbereich nicht springen.
                Color.clear
            }
        }
        .frame(height: reservedHeight, alignment: .top)
        .modifier(ScrollVisibilityObserver(
            viewportHeight: viewportHeight,
            onVisibilityChanged: setVisible))
        .onDisappear { setVisible(false) }
    }

    private var channelHeight: CGFloat {
        ChannelScopesView.height(
            channelCount: channelIndices.count,
            availableWidth: availableWidth)
    }

    private var extraHeight: CGFloat {
        // Nur freie iPad-Hoehe verteilen; viele Kanaele behalten ihren Scrollbereich.
        max(0, minimumHeight - naturalHeight)
    }

    private var reservedHeight: CGFloat { max(naturalHeight, minimumHeight) }

    private var naturalHeight: CGFloat {
        let limitHeight: CGFloat = channelIndices.count < totalChannels ? 22 : 0
        return 64 + 8 + channelHeight + limitHeight
    }

    private func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        onVisibilityChanged(visible)
    }
}

private enum VisualizerViewport {
    static let coordinateSpace = "now-playing-scroll"
}

// Die App unterstuetzt iOS 17, waehrend SwiftUI erst ab iOS 18 eine eigene
// Scroll-Sichtbarkeits-API anbietet. Auf aktuellen Geraeten verwenden wir diese
// direkte Quelle; iOS 17 bekommt dieselbe Aussage ueber onGeometryChange. Der
// fruehere PreferenceKey aus einem LazyVStack lieferte auf echten Geraeten
// nicht verlaesslich ein erstes sichtbares Rechteck und liess alle Scopes leer.
private struct ScrollVisibilityObserver: ViewModifier {
    let viewportHeight: CGFloat
    let onVisibilityChanged: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.01) { visible in
                onVisibilityChanged(visible)
            }
        } else {
            content.onGeometryChange(for: Bool.self) { proxy in
                let frame = proxy.frame(in: .named(VisualizerViewport.coordinateSpace))
                return frame.maxY > 0 && frame.minY < viewportHeight
            } action: { visible in
                onVisibilityChanged(visible)
            }
        }
    }
}

// Kleine, separat testbare Wahrheitstabellen fuer Tab, Viewport und
// Szenenzustand. Das verhindert sowohl tote Anzeigen im aktiven Tab als auch
// weiterlaufende Wellenform-Caches oder Canvas-Views im Hintergrund.
enum VisualizerActivation {
    static func shouldRun(tabSelected: Bool, sectionVisible: Bool) -> Bool {
        tabSelected && sectionVisible
    }

    static func shouldRender(
        tabSelected: Bool,
        sceneActive: Bool,
        sectionVisible: Bool
    ) -> Bool {
        tabSelected && sceneActive && sectionVisible
    }
}

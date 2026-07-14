import SwiftUI
import SavageModPlayerCore

// Eigenstaendiges Layout fuer kleine Fenster. Es zeigt die fuer reines Hoeren
// wichtigen Informationen, haengt aber bewusst weder Pattern-Canvas noch
// Oszilloskope oder Marker-Map ein. So bleibt der CPU-Vorteil des Kompaktmodus
// erhalten, ohne dass der Hauptbereich wie eine unfertige Leeransicht wirkt.
extension MainView {
    var compactHeaderView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(formatBadgeText)
                    .scaledFont(8, weight: .black)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(theme == .workbench ? Color.lightAccent : Color.spaceAccent)
                    .foregroundColor(theme == .workbench ? .white : .black)
                    .cornerRadius(theme == .workbench ? 3 : 5)

                // Im schmalen Header bekommt der Titel den verbleibenden Platz;
                // die beiden Aktionen rechts behalten ihre feste, klickbare Groesse.
                MarqueeText(
                    text: coordinator.trackName,
                    font: .system(size: 16 * uiFontScale, weight: .bold),
                    color: theme == .workbench ? .lightAccent : .white
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: {
                    theme = theme == .workbench ? .cyber : .workbench
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: theme == .workbench ? "moon.fill" : "sun.max.fill")
                        Text(theme == .workbench ? "DARK" : "LIGHT")
                    }
                    .scaledFont(9, weight: .bold)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceSurface)
                    .foregroundColor(theme == .workbench ? .lightTextPrimary : .spaceTextPrimary)
                    .cornerRadius(theme == .workbench ? 4 : 6)
                }
                .buttonStyle(PlainButtonStyle())
                .help(theme == .workbench ? "Zum dunklen Theme wechseln." : "Zum hellen Theme wechseln.")

                Button(action: { showFileImporter = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.badge.plus")
                        Text("ÖFFNEN")
                    }
                    .scaledFont(9, weight: .bold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accent(theme))
                    .foregroundColor(.white)
                    .cornerRadius(theme == .workbench ? 4 : 6)
                }
                .buttonStyle(PremiumHoverButtonStyle(theme: theme))
                .help("Modul-Dateien oder einen Ordner zum Abspielen auswählen.")
            }

            // Nur lesbare Kerndaten: Die selten benoetigten BPM-/Speed-Stepper
            // bleiben im vollen Arbeitsplatz und koennen den Kompakt-Header nicht
            // aus dem Fenster druecken.
            HStack(spacing: 14) {
                if let mod = coordinator.activeMod {
                    compactMetadata(icon: "slider.horizontal.3", text: "CH \(mod.usedChannelCount)")
                }
                compactMetadata(icon: "metronome", text: "BPM \(coordinator.bpm)")
                compactMetadata(icon: "speedometer", text: "SPD \(coordinator.speed)")
                if let mod = coordinator.activeMod {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.list")
                        PatPositionText(transport: coordinator.transport, length: mod.length)
                    }
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
            .scaledFont(10, weight: .semibold)
            .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
        }
    }

    @ViewBuilder
    var compactDashboardView: some View {
        if let mod = coordinator.activeMod {
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: geometry.size.height < 360) {
                    VStack(spacing: 16) {
                        compactNowPlayingHeader

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 105), spacing: 10)],
                            spacing: 10
                        ) {
                            compactStat(value: "\(mod.usedChannelCount)", label: "KANÄLE")
                            compactStat(
                                value: "\(mod.instruments.dropFirst().compactMap { $0 }.count)",
                                label: "INSTRUMENTE"
                            )
                            compactStat(value: "\(mod.patterns.count)", label: "PATTERN")
                            compactStat(value: "\(mod.length)", label: "POSITIONEN")
                        }

                        compactChannelSection(mod: mod)
                        compactPlaybackOptions
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .background(theme == .workbench ? Color.lightSurface : Color.spaceSurface)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                theme == .workbench
                                    ? Color.lightTextSecondary.opacity(0.18)
                                    : Color.spaceTextSecondary.opacity(0.16),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: theme == .workbench
                            ? Color.black.opacity(0.08)
                            : Color.spaceAccent.opacity(0.08),
                        radius: 14,
                        y: 5
                    )
                    .padding(16)
                    // Die Karte selbst bleibt inhaltsnah. Der aeussere Rahmen
                    // zentriert sie vertikal; so entsteht ruhige Aussenluft statt
                    // kuenstlich aufgeblasener, leerer Untersektionen.
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
                }
            }
            .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceBackground)
        } else {
            dropZonePrompt
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceBackground)
        }
    }

    private var compactNowPlayingHeader: some View {
        HStack(spacing: 18) {
            // Statisches Emblem statt eines weiteren 30-Hz-Animations-Timers.
            // Der kleine Play-Button im Transport darf sich weiterhin drehen.
            ZStack {
                Circle()
                    .fill(Color.accent(theme).opacity(theme == .workbench ? 0.10 : 0.15))
                Circle()
                    .stroke(Color.accent(theme).opacity(0.32), lineWidth: 1)
                    .padding(7)
                Image(systemName: "opticaldisc.fill")
                    .scaledFont(52)
                    .foregroundColor(Color.accent(theme))
                Circle()
                    .fill(theme == .workbench ? Color.lightSurface : Color.spaceSurface)
                    .frame(width: 11, height: 11)
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                Text("JETZT LÄUFT")
                    .scaledFont(9, weight: .black)
                    .tracking(1.2)
                    .foregroundColor(Color.accent(theme))

                Text(coordinator.trackName)
                    .scaledFont(18, weight: .bold)
                    .foregroundColor(theme == .workbench ? .lightTextPrimary : .spaceTextPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(compactSourceFilename)
                    .scaledFont(10)
                    .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                    Text("CPU-SPARMODUS")
                        .scaledFont(8, weight: .bold)
                    Text("Pattern und Oszilloskope pausiert")
                        .scaledFont(8)
                }
                .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func compactStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .scaledFont(16, weight: .bold)
                .foregroundColor(theme == .workbench ? .lightTextPrimary : .spaceTextPrimary)
            Text(label)
                .scaledFont(8, weight: .bold)
                .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceBackground.opacity(0.65))
        .cornerRadius(8)
    }

    private func compactChannelSection(mod: Mod) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("KANALSTEUERUNG")
                .scaledFont(8, weight: .bold)
                .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)

            ScrollView(.vertical, showsIndicators: mod.displayChannelCount > 16) {
                CompactChannelStrip(
                    coordinator: coordinator,
                    channelIndices: mod.displayChannelIndices,
                    theme: theme
                )
            }
            // Wenige Kanaele brauchen keine hohe leere Scrollflaeche. Erst grosse
            // S3M/XM/IT-Module erhalten mehrere Zeilen und schliesslich Scrollen.
            .frame(height: mod.displayChannelCount <= 8
                   ? 18
                   : (mod.displayChannelCount <= 24 ? 40 : 76))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme == .workbench ? Color.lightSurfaceAlt.opacity(0.72) : Color.spaceBackground.opacity(0.48))
        .cornerRadius(10)
    }

    private var compactPlaybackOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                compactAudioToggles
                Spacer(minLength: 8)
                compactLoopPicker
            }

            VStack(alignment: .leading, spacing: 10) {
                compactAudioToggles
                compactLoopPicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaledFont(9, weight: .semibold)
    }

    private var compactAudioToggles: some View {
        HStack(spacing: 14) {
            Toggle("LED FILTER", isOn: $coordinator.ledFilterActive)
                .toggleStyle(CheckboxToggleStyle(theme: theme))
                .help("Amiga-LED-Filter: Tiefpass für den dumpferen Originalklang.")

            Toggle("HI-FI INT.", isOn: $coordinator.useInterpolation)
                .toggleStyle(CheckboxToggleStyle(theme: theme))
                .help("Sample-Interpolation für einen weicheren Klang.")
        }
        .fixedSize()
    }

    private var compactLoopPicker: some View {
        HStack(spacing: 6) {
            Text("LOOP:")
                .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
            Picker("", selection: $loopMode) {
                ForEach(LoopMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(DefaultPickerStyle())
            .labelsHidden()
            .fixedSize()
            .colorScheme(theme == .workbench ? .light : .dark)
            .help("Verhalten nach dem Songende wählen.")
        }
    }

    private func compactMetadata(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text).fixedSize()
        }
        .fixedSize()
    }

    private var compactSourceFilename: String {
        guard playlist.indices.contains(currentPlaylistIndex) else {
            return coordinator.trackName
        }
        return cleanFilename(playlist[currentPlaylistIndex])
    }
}

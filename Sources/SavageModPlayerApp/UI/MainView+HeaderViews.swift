import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// Kopfbereich der MainView: Format-Badge, Header, Kanal-VU/Oszilloskope,
// Drop-Hinweis, Master-Oszilloskop und PAL/NTSC-Umschalter.
extension MainView {
    var formatBadgeText: String {
        switch coordinator.activeMod?.format {
        case .s3m: return "S3M"
        case .xm: return "FASTTRACKER II"
        case .it: return "IMPULSE TRACKER"
        case .multichannel: return "MULTICHANNEL"
        case .soundtracker: return "SOUNDTRACKER"
        default: return "PROTRACKER"
        }
    }

    var headerView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Titel-Font skaliert mit dem globalen UI-Zoom (CMD +/-/0).
                    // .title2 wird dafuer auf seine explizite Groesse (~17 pt)
                    // gebracht, weil ein semantischer Font nicht multiplizierbar ist.
                    let titleFont: Font = theme == .workbench
                        ? .system(size: 20 * uiFontScale, weight: .bold)
                        : .system(size: 17 * uiFontScale)
                    let titleColor: Color = theme == .workbench ? .lightAccent : .white

                    // Format-Badge LINKS vor dem Titel (feste Groesse). Bewusst vor
                    // dem Titel, damit der (bei Ueberlaenge scrollende) Titel den
                    // restlichen Platz fuellen kann, ohne das Badge zu verdraengen —
                    // und ohne bei kurzen Titeln eine grosse Luecke zum Badge zu lassen.
                    // In BEIDEN Themes sichtbar; Farben themen-abhaengig (Dark:
                    // Space-Akzent auf Schwarz, Light: dunkelblauer lightAccent auf
                    // Weiss, eckig wie die uebrigen Light-Controls).
                    Text(formatBadgeText)
                        .scaledFont(8, weight: .black)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(theme == .workbench ? Color.lightAccent : Color.spaceAccent)
                        .foregroundColor(theme == .workbench ? .white : .black)
                        .cornerRadius(theme == .workbench ? 0 : 3)

                    // Titel als Laufschrift: scrollt, wenn er breiter als der Platz
                    // ist, sonst steht er einfach links.
                    MarqueeText(text: coordinator.trackName, font: titleFont, color: titleColor)
                }

                HStack(spacing: 16) {
                    if let mod = coordinator.activeMod {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text(String(format: "CH: %d", mod.usedChannelCount))
                                .fixedSize()
                        }
                        .fixedSize()
                        .help("Genutzte Kanäle: zählt die Pattern-Kanäle, die im Song tatsächlich Noten, Instrumente, Lautstärke- oder Effektbefehle enthalten. Reservierte, komplett leere Kanäle werden nicht mitgezählt.")
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "metronome")
                        // fixedSize: verhindert, dass "BPM: 125" bei knappem Platz
                        // (langer Songtitel darueber) auf zwei Zeilen umbricht.
                        Text(String(format: "BPM: %d", coordinator.bpm))
                            .fixedSize()

                        // Steppers
                        Button(action: {
                            if coordinator.bpm > 32 { coordinator.bpm -= 1 }
                        }) {
                            Image(systemName: "minus.square")
                        }.buttonStyle(PlainButtonStyle())
                        .help("BPM verringern.")

                        Button(action: {
                            if coordinator.bpm < 300 { coordinator.bpm += 1 }
                        }) {
                            Image(systemName: "plus.square")
                        }.buttonStyle(PlainButtonStyle())
                        .help("BPM erhöhen.")
                    }
                    .fixedSize()
                    .help("BPM (Beats per Minute): Wiedergabe-Tempo. Amiga-Standard ist 125. Mit −/+ veraenderbar; ein Song kann sein Tempo per Effekt auch selbst umstellen. Bei Songwechsel wird der Header-Wert des neuen Moduls gesetzt.")
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                        Text(String(format: "SPD: %d", coordinator.speed))
                            .fixedSize()

                        Button(action: {
                            if coordinator.speed > 1 { coordinator.speed -= 1 }
                        }) {
                            Image(systemName: "minus.square")
                        }.buttonStyle(PlainButtonStyle())
                        .help("Speed verringern.")

                        Button(action: {
                            if coordinator.speed < 31 { coordinator.speed += 1 }
                        }) {
                            Image(systemName: "plus.square")
                        }.buttonStyle(PlainButtonStyle())
                        .help("Speed erhöhen.")
                    }
                    .fixedSize()
                    .help("Speed: Ticks pro Pattern-Zeile (Amiga-Standard 6). Kleiner = die Zeilen laufen schneller durch, groesser = langsamer. Zusammen mit BPM bestimmt das die effektive Geschwindigkeit.")
                    if let mod = coordinator.activeMod {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note.list")
                            PatPositionText(transport: coordinator.transport, length: mod.length)
                        }
                        .fixedSize()
                        .help("Pattern-Position: aktuelles Pattern und Gesamtzahl in der Abspielliste des Songs. Ein Pattern ist ein Notenblock (meist 64 Zeilen); der Song spielt sie in dieser Reihenfolge ab.")
                    }
                }
                .scaledFont(11, weight: .semibold)
                .foregroundColor(theme == .workbench ? .lightTextPrimary.opacity(0.8) : .spaceTextSecondary)
            }
            // Der Titelblock ist das EINE flexible Element in der Kopfzeile und
            // fuellt den Platz bis zu den rechten Bedienelementen (ersetzt den
            // frueheren Spacer). So bekommt ein langer Songtitel viel mehr Breite,
            // bevor er gekuerzt wird. WICHTIG: kein layoutPriority hier — das wuerde
            // den fixen rechten Buttons die Breite entziehen (0 pt -> vertikal
            // umgebrochener Text). Als flexibles Element mit Prioritaet 0 nimmt der
            // Block nur den Rest, den die intrinsisch breiten Buttons uebriglassen.
            .frame(maxWidth: .infinity, alignment: .leading)

            // Theme Selector
            HStack(spacing: 4) {
                ForEach(PlayerTheme.allCases) { t in
                    Button(action: { theme = t }) {
                        Text(t == .workbench ? "LIGHT" : "DARK")
                            .scaledFont(10, weight: .bold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                theme == t
                                ? (Color.accent(t))
                                : (theme == .workbench ? Color.lightSurfaceAlt : Color.spaceSurface.opacity(0.5))
                            )
                            .foregroundColor(theme == t ? Color.white : (theme == .workbench ? Color.lightTextPrimary : Color.spaceTextSecondary))
                            .cornerRadius(theme == .workbench ? 0 : 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(3)
            .background(theme == .workbench ? Color.lightSurface : Color.spaceBackground.opacity(0.6))
            .cornerRadius(theme == .workbench ? 0 : 6)
            
            // File Open Button
            Button(action: { showFileImporter = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                    Text("ÖFFNEN")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accent(theme))
                .foregroundColor(.white)
                .scaledFont(11, weight: .bold)
            }
            .buttonStyle(PremiumHoverButtonStyle(theme: theme))
            .cornerRadius(theme == .workbench ? 0 : 6)
            .help("Modul-Datei(en) oder einen Ordner zum Abspielen auswählen.")
        }
    }
    
    func vuVisualizersView(isCompact: Bool) -> some View {
        let channelIndices = coordinator.activeMod?.displayChannelIndices
            ?? Array(0..<coordinator.channelCount)
        return VStack(spacing: 8) {
            // Obere Zeile: im Full-Modus die adaptiven Kanal-Oszilloskope über die
            // VOLLE Breite (30-Hz-Canvas, SCHWER). Im Kompaktmodus stattdessen NUR
            // die leichte, umbrechende M/S-Leiste (kein Oszi, keine 30-Hz-Wellen) —
            // so bleibt die Kanalsteuerung erreichbar, ohne CPU zu kosten.
            // Kanal-Oszilloskope + VU: eigener 30-Hz-Beobachter (ChannelStripsView),
            // damit die Scope-Updates nicht die ganze MainView.body neu rendern.
            if isCompact {
                CompactChannelStrip(
                    coordinator: coordinator,
                    channelIndices: channelIndices,
                    theme: theme
                )
            } else {
                ChannelStripsView(
                    visualizer: coordinator.visualizerState,
                    coordinator: coordinator,
                    channelIndices: channelIndices,
                    theme: theme
                )
            }

            // Untere Zeile: kompakte Optionsleiste (aus der oberen Zeile
            // ausgelagert, damit die Oszis dort die volle Breite bekommen).
            HStack(spacing: 16) {
                Toggle("LED FILTER", isOn: $coordinator.ledFilterActive)
                    .toggleStyle(CheckboxToggleStyle(theme: theme))
                    .help("Amiga-LED-Filter: zuschaltbarer Tiefpass bei ~3,2 kHz, der die Höhen kappt — der dumpfere Originalklang, wie wenn am echten Amiga die Power-LED leuchtete.")

                Toggle("HI-FI INT.", isOn: $coordinator.useInterpolation)
                    .toggleStyle(CheckboxToggleStyle(theme: theme))
                    .help("Hi-Fi-Interpolation: glättet die Samples beim Resampling (weicherer Klang). Ausgeschaltet klingt es wie die Original-Hardware — roher 8-Bit-Sound mit hörbarem Aliasing.")

                HStack(spacing: 6) {
                    Text("LOOP:")
                        .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)

                    Picker("", selection: $loopMode) {
                        ForEach(LoopMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    .labelsHidden()
                    .fixedSize()
                    // Control-Optik ans App-Theme koppeln (sonst im Dark-Theme
                    // auf hellem System kaum lesbar).
                    .colorScheme(theme == .workbench ? .light : .dark)
                    .help("Was nach dem Songende passiert: Playlist fortsetzen, den Song wiederholen oder stoppen.")
                }

                Spacer()
            }
            .scaledFont(9, weight: .semibold)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(theme == .workbench ? Color.lightSurface.opacity(0.3) : Color.spaceSurface.opacity(0.5))
        .cornerRadius(theme == .workbench ? 0 : 8)
    }
    var dropZonePrompt: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 20) {
                // Glowing Icon
                ZStack {
                    if theme == .cyber {
                        Circle()
                            .fill(Color.spaceAccent.opacity(0.15))
                            .frame(width: 100, height: 100)
                            .blur(radius: 10)
                    }
                    
                    Image(systemName: dragOver ? "arrow.down.doc.fill" : "opticaldisc.fill")
                        .scaledFont(48)
                        .foregroundColor(Color.accent(theme))
                        .rotationEffect(.degrees(dragOver ? 180 : (isDiskAnimating ? 360 : 0)))
                        .scaleEffect(dragOver ? 1.2 : 1.0)
                        .shadow(color: theme == .workbench ? Color.clear : Color.spaceAccent.opacity(0.5), radius: 8)
                }
                
                VStack(spacing: 8) {
                    Text("PROTRACKER MOD PLAYER")
                        .font(theme == .workbench ? .system(size: 16, weight: .bold) : .system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(theme == .workbench ? .lightAccent : .white)
                        .tracking(theme == .cyber ? 2.0 : 0)
                    
                    Text("Ziehe .mod Dateien oder Ordner direkt in dieses Fenster")
                        .font(theme == .workbench ? .system(size: 12) : .system(size: 13, weight: .medium))
                        .foregroundColor(theme == .workbench ? .lightTextPrimary.opacity(0.8) : .spaceTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                
                HStack(spacing: 12) {
                    Button(action: { showFileImporter = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.rectangle.on.folder")
                            Text("DATEIEN AUSWÄHLEN")
                        }
                        .scaledFont(11, weight: .bold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.accent(theme))
                        .foregroundColor(.white)
                        .cornerRadius(theme == .workbench ? 0 : 8)
                    }
                    .buttonStyle(PremiumHoverButtonStyle(theme: theme))
                    .help("Modul-Datei(en) oder einen Ordner zum Abspielen auswählen.")

                    Button(action: { triggerDemoPlay() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle")
                            Text("DEMO ABSPIELEN")
                        }
                        .scaledFont(11, weight: .bold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(theme == .workbench ? 0 : 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Ein mitgeliefertes Demo-Modul abspielen.")
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 30)
            .background(
                Group {
                    if theme == .cyber {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.spaceSurface.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: dragOver ? [.spaceAccent, .spaceAccentGlow] : [.white.opacity(0.1), .white.opacity(0.02)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: dragOver ? 2 : 1
                                    )
                            )
                    } else {
                        Rectangle()
                            .fill(Color.lightSurface.opacity(0.2))
                            .border(dragOver ? Color.lightAccent : Color.lightTextPrimary, width: 2)
                    }
                }
            )
            .shadow(color: theme == .workbench ? Color.clear : Color.black.opacity(0.3), radius: 20)
            
            if let errorMsg = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMsg)
                        .foregroundColor(.red)
                }
                .scaledFont(11)
                .padding(.top, 4)
            }
            Spacer()
        }
        .background(theme == .workbench ? Color.lightSurfaceAlt : Color.clear)
    }
    
    // Master Oscilloscope visualizer showing master L/R mix output
    var masterOscilloscopeView: some View {
        HStack(spacing: 16) {
            Text("MASTER OSCILLOSCOPE")
                .scaledFont(10, weight: .bold)
                .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
                .frame(width: 140, alignment: .leading)
            
            // Master-Oszilloskop: eigener 30-Hz-Beobachter (siehe ChannelStripsView).
            MasterScopeCanvas(visualizer: coordinator.visualizerState, theme: theme)
            
            // Stereo Separation bleed adjustment slider
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right")
                    .scaledFont(11)
                    .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)

                Slider(value: $coordinator.stereoSeparation, in: 0.0...1.0)
                    .accentColor(Color.accent(theme))
                    .frame(width: 80)
                    // Tooltip auch direkt am Slider: ein Slider verschluckt die
                    // Hover-Events, sodass das .help() der umgebenden HStack beim
                    // Zeigen auf den Slider-Track allein nicht ausgeloest wird.
                    .help("Stereo-Separation: 100 % = hartes Amiga-Panning (Kanäle ganz links/rechts), 0 % = Mono. Dazwischen wird Übersprechen beigemischt, das Kopfhörer-Ermüdung vermeidet. Am deutlichsten mit Kopfhörern hörbar; über Laptop-Lautsprecher kaum.")

                Text(String(format: "%d%%", Int(coordinator.stereoSeparation * 100)))
                    .scaledFont(9)
                    .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
                    .frame(width: 32, alignment: .trailing)
            }
            .help("Stereo-Separation: 100 % = hartes Amiga-Panning (Kanäle ganz links/rechts), 0 % = Mono. Dazwischen wird Übersprechen beigemischt, das Kopfhörer-Ermüdung vermeidet. Am deutlichsten mit Kopfhörern hörbar; über Laptop-Lautsprecher kaum.")

            // PAL/NTSC verändert nur die Paula-basierten MOD-Formate. S3M, XM
            // und IT verwenden eigene, feste Frequenzmodelle; dort blenden wir
            // die wirkungslose Steuerung aus statt einen scheinbaren Schalter zu
            // zeigen.
            if usesAmigaClock {
                palClockSelector
            }
        }
    }

    var usesAmigaClock: Bool {
        switch coordinator.activeMod?.format {
        case .protracker, .soundtracker, .multichannel:
            return true
        default:
            return false
        }
    }

    var palClockSelector: some View {
        HStack(spacing: 4) {
            Button("PAL (3.546MHz)") {
                coordinator.palClock = true
            }
            .scaledFont(9, weight: .bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(coordinator.palClock ? Color.accent(theme) : Color.clear)
            .foregroundColor(coordinator.palClock ? .white : inactiveControlColor)
            .cornerRadius(4)
            .buttonStyle(PlainButtonStyle())
            .help("PAL-Paula-Takt (3,546 MHz) wie bei europäischen Amigas — die Referenz-Tonhöhe und -Geschwindigkeit der meisten Module.")

            Button("NTSC (3.580MHz)") {
                coordinator.palClock = false
            }
            .scaledFont(9, weight: .bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(!coordinator.palClock ? Color.accent(theme) : Color.clear)
            .foregroundColor(!coordinator.palClock ? .white : inactiveControlColor)
            .cornerRadius(4)
            .buttonStyle(PlainButtonStyle())
            .help("NTSC-Paula-Takt (3,580 MHz) wie bei US-Amigas — Module klingen minimal höher und laufen etwas schneller als mit PAL.")
        }
        .padding(2)
        .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceBackground.opacity(0.4))
        .cornerRadius(6)
    }

    var inactiveControlColor: Color {
        theme == .workbench ? .lightTextSecondary : .spaceTextSecondary
    }
    
    // Einheitliche Optik der kleinen Transport-Buttons (Stop, Positions- und
    // Titel-Spruenge) — rund im Dark-, eckig im Light-Theme.
    func transportButtonLabel(systemName: String) -> some View {
        ZStack {
            if theme == .cyber {
                Circle()
                    .fill(Color.spaceSurface)
                    .overlay(Circle().stroke(Color.spaceAccent.opacity(0.3), lineWidth: 1))
            } else {
                // Volle Akzentfarbe wie der Play-Button — das abgeschwaechte
                // Orange sah im Light-Mode wie "deaktiviert" aus.
                Rectangle()
                    .fill(Color.lightAccent)
            }
            Image(systemName: systemName)
                .scaledFont(11)
                .foregroundColor(.white)
        }
        .frame(width: 30, height: 30)
    }

}

import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// Transport-/Kontrollleiste der MainView (Play-Steuerung, Regler, LEDs).
extension MainView {
    var controlPanelView: some View {
        HStack(spacing: 24) {
            // Left block: Play controls
            HStack(spacing: 8) {
                // Play/Pause = rotierende Disk (eigener View mit lokalem Rotations-
                // State + Timer, damit die 30-Hz-Drehung NICHT die ganze MainView.body
                // neu rendert — das war die CPU-Hauptursache, 2026-07-09).
                SpinningDiskButton(
                    isPlaying: coordinator.isPlaying,
                    isPaused: coordinator.isPaused,
                    enabled: coordinator.activeMod != nil,
                    theme: theme,
                    onTap: { togglePlayback() }
                )

                // Stop button (setzt an den Songanfang zurueck)
                Button(action: {
                    stopPlayback()
                }) {
                    transportButtonLabel(systemName: "stop.fill")
                }
                .buttonStyle(PremiumHoverButtonStyle(theme: theme))
                .cornerRadius(theme == .workbench ? 0 : 15)
                .disabled(!coordinator.isPlaying)
                .help("Stopp: Wiedergabe beenden — der nächste Start beginnt wieder am Songanfang.")

                // −10s / +10s: schneller Sprung innerhalb des Songs (springt
                // zeilengenau über die aktuelle Zeilendauer). Praktisch, um ohne
                // langes Durchhören an eine Stelle zu gelangen.
                Button(action: { coordinator.seek(bySeconds: -10) }) {
                    transportButtonLabel(systemName: "gobackward.10")
                }
                .buttonStyle(PremiumHoverButtonStyle(theme: theme))
                .cornerRadius(theme == .workbench ? 0 : 15)
                .disabled(!coordinator.isPlaying)
                .help("10 Sekunden zurückspringen.")

                Button(action: { coordinator.seek(bySeconds: 10) }) {
                    transportButtonLabel(systemName: "goforward.10")
                }
                .buttonStyle(PremiumHoverButtonStyle(theme: theme))
                .cornerRadius(theme == .workbench ? 0 : 15)
                .disabled(!coordinator.isPlaying)
                .help("10 Sekunden vorspringen.")

                Divider()
                    .frame(height: 20)

                // Previous button (Playlist-Titel)
                Button(action: {
                    prevTrack()
                }) {
                    transportButtonLabel(systemName: "backward.end.fill")
                }
                .buttonStyle(PremiumHoverButtonStyle(theme: theme))
                .cornerRadius(theme == .workbench ? 0 : 15)
                .disabled(playlist.isEmpty)
                .help("Vorheriger Titel der Playlist (⌘← oder Pfeil links).")

                // Next button (Playlist-Titel)
                Button(action: {
                    nextTrack()
                }) {
                    transportButtonLabel(systemName: "forward.end.fill")
                }
                .buttonStyle(PremiumHoverButtonStyle(theme: theme))
                .cornerRadius(theme == .workbench ? 0 : 15)
                .disabled(playlist.isEmpty)
                .help("Nächster Titel der Playlist (⌘→ oder Pfeil rechts).")

                // Shuffle-Toggle (iTunes-Symbol): zufaellige statt sequenzielle
                // Titel-Wechsel. Aktiv = Akzentfarbe.
                Button(action: {
                    shuffleEnabled.toggle()
                }) {
                    ZStack {
                        if theme == .cyber {
                            Circle()
                                .fill(shuffleEnabled ? Color.spaceAccent : Color.spaceSurface)
                                .overlay(Circle().stroke(Color.spaceAccent.opacity(0.3), lineWidth: 1))
                        } else {
                            Rectangle()
                                .fill(shuffleEnabled ? Color.lightAccent : Color.lightSurfaceAlt)
                        }
                        Image(systemName: "shuffle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(shuffleEnabled ? (theme == .cyber ? .black : .white) : (theme == .workbench ? .lightTextSecondary : .spaceTextSecondary))
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(PremiumHoverButtonStyle(theme: theme))
                .cornerRadius(theme == .workbench ? 0 : 15)
                .disabled(playlist.isEmpty)
                .help(shuffleEnabled
                      ? "Zufallswiedergabe ist AN: Titel-Wechsel und Songende springen zufällig durch die Playlist."
                      : "Zufallswiedergabe ist AUS: die Playlist spielt der Reihe nach.")
            }
            
            // Middle block: Progress Timeline
            if let mod = coordinator.activeMod {
                HStack(spacing: 12) {
                    // Verstrichene Zeit: eigener 30-Hz-Beobachter (tickt ohne die
                    // MainView.body neu zu rendern).
                    ElapsedTimeText(visualizer: coordinator.visualizerState)

                    // Zeitsprung zurueck — bequeme Alternative zum Slider.
                    Button(action: { coordinator.seek(bySeconds: -15) }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 14))
                            .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!coordinator.isPlaying)
                    .help("15 Sekunden zurückspringen (zeilengenau; bei Tempo-Wechseln näherungsweise).")

                    // Der Slider springt pro Song-Position und funktioniert auch
                    // im gestoppten Zustand: Play startet dann ab der gewaehlten
                    // Stelle.
                    // WICHTIG: Der Range darf NIE leer sein. Bei Modulen mit nur
                    // EINER Song-Position (mod.length == 1) ergäbe 0...0 einen
                    // leeren Bereich — SwiftUIs Slider löst dann eine precondition
                    // aus und die App STÜRZT AB (2026-07-09, durch kurze XM
                    // aufgedeckt). Darum untere Grenze < obere garantieren
                    // (max(1, …)), den Wert in den Bereich klemmen und den Slider
                    // bei nur einer Position deaktivieren (es gibt nichts zu wählen).
                    // Positions-Slider beobachtet transport (row-rate), nicht coordinator.
                    PositionSlider(transport: coordinator.transport, mod: mod, theme: theme,
                                   onSeek: { coordinator.seek(toPosition: $0) })

                    // Zeitsprung vor.
                    Button(action: { coordinator.seek(bySeconds: 30) }) {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 14))
                            .foregroundColor(theme == .workbench ? .lightTextSecondary : .spaceTextSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!coordinator.isPlaying)
                    .help("30 Sekunden vorspringen (zeilengenau; bei Tempo-Wechseln näherungsweise).")

                    TotalTimeText(visualizer: coordinator.visualizerState)
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer()
                Text("Kein Song geladen")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme == .workbench ? .lightTextPrimary.opacity(0.4) : .spaceTextSecondary)
                Spacer()
            }
            
            // Right block: Volume Fader + WAV + Keyboard + Info
            HStack(spacing: 12) {
                // Keyboard short cuts HUD helper
                Button(action: { showKeyboardHUD = true }) {
                    Image(systemName: "keyboard")
                        .foregroundColor(.spaceTextSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Info Guru modal button
                Button(action: { showAboutModal = true }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.spaceTextSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                if coordinator.activeMod != nil {
                    // Exporter wav button
                    Button(action: { runWavExport() }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(isExporting ? .green : .spaceTextSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Volume slider with glow
                HStack(spacing: 6) {
                    Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundColor(theme == .workbench ? .lightTextPrimary : .spaceTextSecondary)
                    
                    Slider(value: Binding(
                        get: { volume },
                        set: { volume = $0; coordinator.setVolume(Float($0)) }
                    ), in: 0...1.0)
                    .accentColor(Color.accent(theme))
                    .frame(width: 90)
                    .shadow(color: theme == .cyber ? Color.spaceAccent.opacity(volume * 0.8) : Color.clear, radius: 4)
                }
            }
        }
    }

}

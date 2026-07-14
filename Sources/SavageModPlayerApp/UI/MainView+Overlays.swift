import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// Overlays der MainView: Guru-Meditation-About, Tastatur-HUD und
// Drag&Drop-Indikator.
extension MainView {
    // Custom Guru Meditation retro about modal view
    var guruMeditationAboutView: some View {
        ZStack {
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                Text("SOFTWARE FAILURE. Click button to continue.")
                    .font(.system(.body))
                    .foregroundColor(.red)
                    .bold()
                
                VStack(spacing: 4) {
                    Text("Guru Meditation #00000004.0000404C")
                        .font(.system(.title3))
                        .foregroundColor(.red)
                        .bold()
                }
                .padding()
                .border(Color.red, width: 3)
                .background(Color.black)
                .overlay(
                    Rectangle()
                        .stroke(Color.red, lineWidth: 1)
                        .padding(2)
                )
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("SAVAGE PROTRACKER PLAYER - NATIVE APPLE SWIFT")
                        .bold()
                        .foregroundColor(.spaceAccent)

                    Text("• Engine: AVAudioEngine + lock-free AVAudioSourceNode")
                    Text("• Formate: ProTracker MOD, Multichannel, Soundtracker, S3M")
                    Text("• Clock Rate: Configurable PAL (3.546MHz) / NTSC (3.580MHz)")
                    Text("• Mixing model: Authentic Nearest or linear Interpolated (Hifi)")
                    Text("• Design: Classic Light & Graphite Dark Themes")
                    Text("• Features: Quick-Look-Plugin, WAV-Export, Media-Tasten")

                    Divider().background(Color.spaceAccent.opacity(0.3))

                    Text("© 2026 Daniel Müller — Autor & Maintainer")
                        .foregroundColor(.spaceAccentGlow)
                    Text("WTFPL — Quellcode: github.com/DanielMuellerIR/savage_modplayer")
                }
                .scaledFont(11)
                .foregroundColor(.white)
                .padding()
                .background(Color.spaceSurface.opacity(0.4))
                .cornerRadius(6)
                
                Button("SCHLIESSEN") {
                    showAboutModal = false
                }
                .font(.system(.body))
                .foregroundColor(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.lightAccent)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(32)
            .background(Color.black)
            .border(Color.red, width: 4)
            .frame(width: 550)
        }
    }
    
    // Keyboard HUD Sheet View
    var keyboardHUDView: some View {
        ZStack {
            Color.black.opacity(0.6)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Text("TASTATUR-KURZBEFEHLE")
                    .scaledFont(14, weight: .bold)
                    .foregroundColor(Color.accent(theme))
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("LEERTASTE")
                            .bold()
                            .frame(width: 120, alignment: .leading)
                        Text("Abspielen / Pause")
                    }
                    HStack {
                        Text("⌘ .")
                            .bold()
                            .frame(width: 120, alignment: .leading)
                        Text("Stopp (zurück zum Anfang)")
                    }
                    HStack {
                        Text("PFEIL RECHTS")
                            .bold()
                            .frame(width: 120, alignment: .leading)
                        Text("Nächster Titel")
                    }
                    HStack {
                        Text("PFEIL LINKS")
                            .bold()
                            .frame(width: 120, alignment: .leading)
                        Text("Vorheriger Titel")
                    }
                    HStack {
                        Text("ESC")
                            .bold()
                            .frame(width: 120, alignment: .leading)
                        Text("Menüs schließen")
                    }
                }
                .scaledFont(11)
                .padding()
                
                Button("SCHLIESSEN") {
                    showKeyboardHUD = false
                }
                .font(.system(.body))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.accent(theme))
                .cornerRadius(theme == .workbench ? 0 : 6)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(24)
            .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceSurface)
            .border(theme == .workbench ? Color.lightTextPrimary : Color.spaceAccent.opacity(0.3), width: theme == .workbench ? 2 : 1)
            .cornerRadius(theme == .workbench ? 0 : 12)
            .frame(width: 380)
        }
    }
    
    
    // Blur drag-and-drop indicator
    var dragDropOverlayView: some View {
        ZStack {
            Color.black.opacity(0.4)
                .blur(radius: 20)
            
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.spaceAccent, lineWidth: 3)
                .padding(30)
            
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.doc.fill")
                    .scaledFont(48)
                    .foregroundColor(.spaceAccent)
                Text("MOD DATEIEN HIER ABLEGEN")
                    .scaledFont(16, weight: .bold)
                    .foregroundColor(.white)
            }
        }
        .allowsHitTesting(false)
    }

}

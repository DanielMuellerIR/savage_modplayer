import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// Eingabe-Anbindung der MainView: lokaler Tastatur-Monitor, Media-Tasten
// (F7/F8/F9, Touch Bar, AirPods) und System-Notifications.
extension MainView {
    // MARK: - Keyboard handling (Leertaste/Pfeile/ESC aus dem HUD)
    func installKeyMonitor() {
        #if os(macOS)
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Nicht in Textfelder (Suche/Export) eingreifen. Der Feld-Editor eines
            // fokussierten SwiftUI-TextField IST eine NSText-Subklasse (NSTextView),
            // daher greift dieser Guard tatsaechlich — kein toter Code.
            // codereview-ok: NSText-Guard ist funktional, kein toter Zweig (2026-07-02)
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            switch event.keyCode {
            case 49: // Leertaste
                togglePlayback()
                return nil
            case 124: // Pfeil rechts
                nextTrack()
                return nil
            case 123: // Pfeil links
                prevTrack()
                return nil
            case 53: // ESC
                if showAboutModal || showKeyboardHUD || showExportDialog {
                    showAboutModal = false
                    showKeyboardHUD = false
                    showExportDialog = false
                    return nil
                }
                return event
            default:
                return event
            }
        }
        #endif
    }

    func removeKeyMonitor() {
        #if os(macOS)
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        #endif
    }

    // MARK: - Media-Tasten (F7/F8/F9 bzw. Touch Bar / AirPods)
    // Registriert die App im System als "Now Playing"-App: Play/Pause- und
    // Titel-Sprung-Kommandos der Media-Tasten landen dann hier. Die Handler
    // posten dieselben Notifications wie die Menuepunkte — die onReceive-
    // Blöcke oben verarbeiten beide Quellen einheitlich auf dem Main-Thread.
    func setupMediaRemoteCommands() {
        guard !mediaCommandsConfigured else { return }
        mediaCommandsConfigured = true

        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { _ in
            NotificationCenter.default.post(name: NSNotification.Name("menuPlayStop"), object: nil)
            return .success
        }
        center.playCommand.addTarget { _ in
            NotificationCenter.default.post(name: NSNotification.Name("mediaPlay"), object: nil)
            return .success
        }
        center.pauseCommand.addTarget { _ in
            NotificationCenter.default.post(name: NSNotification.Name("mediaPause"), object: nil)
            return .success
        }
        center.stopCommand.addTarget { _ in
            NotificationCenter.default.post(name: NSNotification.Name("menuStop"), object: nil)
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            NotificationCenter.default.post(name: NSNotification.Name("menuNextTrack"), object: nil)
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            NotificationCenter.default.post(name: NSNotification.Name("menuPrevTrack"), object: nil)
            return .success
        }
    }

    // Haelt die "Now Playing"-Infos des Systems aktuell (Titel, Dauer,
    // Position, laeuft/pausiert) — Voraussetzung dafuer, dass die Media-Tasten
    // an diese App geroutet werden.
    func updateNowPlayingInfo() {
        let infoCenter = MPNowPlayingInfoCenter.default()
        guard coordinator.activeMod != nil else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            return
        }
        let activelyPlaying = coordinator.isPlaying && !coordinator.isPaused
        infoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: coordinator.trackName,
            MPMediaItemPropertyPlaybackDuration: coordinator.visualizerState.totalDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: coordinator.visualizerState.elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: activelyPlaying ? 1.0 : 0.0
        ]
        infoCenter.playbackState = coordinator.isPlaying
            ? (coordinator.isPaused ? .paused : .playing)
            : .stopped
    }

    // MARK: - Notification helper
    func setupNotifications() {
        #if os(macOS)
        // SwiftPM startet die App als nacktes Executable ohne .app-Bundle.
        // UserNotifications crasht in diesem Fall beim Zugriff auf
        // current(), deshalb werden Notifications dort übersprungen.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        #endif
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func fireNotification(for track: String) {
        #if os(macOS)
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        #endif
        let content = UNMutableNotificationContent()
        content.title = "Amiga ModPlayer spielt:"
        content.body = track
        let request = UNNotificationRequest(identifier: "modplayer.track", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

}

import SavageModPlayerCore
#if os(Linux)
import CMPRIS
#endif

enum PlaybackMode: String {
    case playing = "Playing", paused = "Paused", stopped = "Stopped"
}

enum MediaCommand {
    case play, pause, togglePause, stop, nextTrack, previousTrack, quit
}

/// Die Bus-Verbindung gehört ausschließlich dem CLI-Kontrollthread.
/// Der Renderblock greift nur auf die lockfreien Pegel-/Frame-Atomics zu.
final class DesktopMediaControls: @unchecked Sendable {
    #if os(Linux)
    private let service: OpaquePointer

    private init(service: OpaquePointer) { self.service = service }
    deinit { savage_mpris_destroy(service) }
    #endif

    static func make(format: PCMFormat) -> DesktopMediaControls? {
        #if os(Linux)
        guard let service = savage_mpris_create(format.sampleRate) else { return nil }
        return DesktopMediaControls(service: service)
        #else
        return nil
        #endif
    }

    func setTrack(title: String, url: String, index: Int, count: Int) {
        #if os(Linux)
        title.withCString { title in
            url.withCString { url in
                savage_mpris_track(service, title, url, UInt64(index + 1),
                                   index + 1 < count ? 1 : 0, index > 0 ? 1 : 0)
            }
        }
        #endif
    }

    func setStatus(_ mode: PlaybackMode) {
        #if os(Linux)
        mode.rawValue.withCString { savage_mpris_status(service, $0) }
        #endif
    }

    func poll() -> MediaCommand? {
        #if os(Linux)
        switch savage_mpris_poll(service) {
        case SAVAGE_MPRIS_PLAY: return .play
        case SAVAGE_MPRIS_PAUSE: return .pause
        case SAVAGE_MPRIS_TOGGLE: return .togglePause
        case SAVAGE_MPRIS_STOP: return .stop
        case SAVAGE_MPRIS_NEXT: return .nextTrack
        case SAVAGE_MPRIS_PREVIOUS: return .previousTrack
        case SAVAGE_MPRIS_QUIT: return .quit
        default: return nil
        }
        #else
        return nil
        #endif
    }

    func meter(_ render: @escaping PCMRenderBlock, channels: Int) -> PCMRenderBlock {
        #if os(Linux)
        return { [self] buffer, requested in
            let written = render(buffer, requested)
            let gain = Float(savage_mpris_gain(service))
            if gain != 1 {
                for index in 0..<(written * channels) { buffer[index] *= gain }
            }
            savage_mpris_add_frames(service, UInt64(written))
            return written
        }
        #else
        return render
        #endif
    }
}

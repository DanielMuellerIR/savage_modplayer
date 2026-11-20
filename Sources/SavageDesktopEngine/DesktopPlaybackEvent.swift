import Foundation
import SavageModPlayerCore

struct DesktopPlaybackEvent: Encodable {
    struct Sound: Encodable {
        let palClock: Bool
        let stereoSeparation: Float
        let useInterpolation: Bool
        let ledFilterActive: Bool
    }

    let event = DesktopEvent.state.rawValue
    let playing: Bool
    let paused: Bool
    let position: Int
    let row: Int
    let bpm: Int
    let speed: Int
    let sound: Sound
    let elapsed: Double
    let duration: Double
    let muted: [Bool]
    let solo: [Bool]
    let timerSeconds: Int
    let timerActive: Bool
    let timerPhase: String
    let markerSaving: Bool
    let sectionActive: Bool
    let sectionPreparing: Bool
    let sectionError: String
    let sectionProgress: Double

    @MainActor
    init(_ player: ModPlayerCoordinator, markerSaving: Bool) {
        playing = player.isPlaying
        paused = player.isPaused
        position = player.currentPosition
        row = player.currentRow
        bpm = player.bpm
        speed = player.speed
        sound = Sound(palClock: player.palClock, stereoSeparation: player.stereoSeparation,
                      useInterpolation: player.useInterpolation, ledFilterActive: player.ledFilterActive)
        elapsed = player.visualizerState.elapsedTime
        duration = player.visualizerState.totalDuration
        muted = (0..<player.channelCount).map { player.isMuted(channelIndex: $0) }
        solo = (0..<player.channelCount).map { player.isSoloed(channelIndex: $0) }
        let timer = player.sleepTimer.snapshot
        timerSeconds = timer.remainingSeconds
        timerActive = timer.isActive
        timerPhase = String(describing: timer.phase)
        self.markerSaving = markerSaving
        sectionActive = player.sectionLoopIsActive
        sectionPreparing = player.sectionLoopIsPreparing
        sectionError = player.sectionLoopError?.localizedDescription ?? ""
        sectionProgress = player.sectionLoopProgress
    }
}

struct DesktopVisualizerEvent: Encodable {
    let event = DesktopEvent.visualizer.rawValue
    var vu: [Float] = []
    var waves: [[Float]] = []
    var master: [Float] = []
}

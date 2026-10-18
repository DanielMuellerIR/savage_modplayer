import Foundation
import SavageModPlayerCore

@MainActor
enum PlaybackPreferences {
    static func makeModel() -> TrackPlaybackSettingsModel {
        let defaults = UserDefaults.standard
        let options = PlaybackOptions(
            palClock: defaults.object(forKey: "savage.palClock") as? Bool ?? true,
            stereoSeparation: defaults.object(forKey: "savage.stereoSeparation") as? Double ?? 0.8,
            useInterpolation: defaults.object(forKey: "savage.interpolation") as? Bool ?? true,
            ledFilterActive: defaults.object(forKey: "savage.ledFilter") as? Bool ?? false)
        return TrackPlaybackSettingsModel(
            fileURL: MainView.catalogURL("track-playback-settings.json", environment: "SAVAGE_TRACK_PLAYBACK_STORE"),
            defaults: options, saveDefaults: { options in
                defaults.set(options.palClock, forKey: "savage.palClock")
                defaults.set(options.stereoSeparation, forKey: "savage.stereoSeparation")
                defaults.set(options.useInterpolation, forKey: "savage.interpolation")
                defaults.set(options.ledFilterActive, forKey: "savage.ledFilter")
            })
    }
}

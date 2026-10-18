import SwiftUI
import SavageModPlayerCore

extension MainView {
    static func applyPlaybackOptions(_ options: PlaybackOptions, to coordinator: ModPlayerCoordinator) {
        if coordinator.palClock != options.palClock { coordinator.palClock = options.palClock }
        if coordinator.stereoSeparation != Float(options.stereoSeparation) { coordinator.stereoSeparation = Float(options.stereoSeparation) }
        if coordinator.useInterpolation != options.useInterpolation { coordinator.useInterpolation = options.useInterpolation }
        if coordinator.ledFilterActive != options.ledFilterActive { coordinator.ledFilterActive = options.ledFilterActive }
    }

    var interpolationBinding: Binding<Bool> {
        Binding(get: { coordinator.useInterpolation }, set: { playbackSettings.setInterpolation($0) })
    }
    var filterBinding: Binding<Bool> {
        Binding(get: { coordinator.ledFilterActive }, set: { playbackSettings.setFilter($0) })
    }
    var separationBinding: Binding<Float> {
        Binding(get: { coordinator.stereoSeparation }, set: { playbackSettings.setSeparation(Double($0)) })
    }
}

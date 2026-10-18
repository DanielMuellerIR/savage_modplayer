import SwiftUI
import SavageModPlayerCore

extension MainView {
    func openVideoExporter() {
        guard videoExportRequest == nil, !isExporting, !stemExport.isRunning,
              !showExportDialog, collectionContext == nil, batchExportRequest == nil,
              !showSavedPlaylists, !showQueue, !showLibraryFilters,
              let mod = coordinator.activeMod else { return }
        let audio = ChannelStemExportOptions(sampleRate: 48_000, maximumSeconds: 600,
            stereoSeparation: coordinator.stereoSeparation, useInterpolation: coordinator.useInterpolation,
            palClock: coordinator.palClock,
            mutedChannels: (0..<coordinator.channelCount).filter { coordinator.isMuted(channelIndex: $0) },
            soloChannels: (0..<coordinator.channelCount).filter { coordinator.isSoloed(channelIndex: $0) })
        videoExportRequest = .init(mod: mod, title: coordinator.trackName, audio: audio,
                                   appearance: theme == .workbench ? .light : .dark)
    }
}

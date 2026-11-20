import SwiftUI
import SavageModPlayerCore

struct TrackPlaybackSettingsButton: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settings: TrackPlaybackSettingsModel
    let title: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var request: TrackPlaybackSettingsContext?

    var body: some View {
        Button {
            request = settings.presentationContext(title: title)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }.accessibilityLabel(Text("Wiedergabeeinstellungen"))
            .accessibilityIdentifier("trackSettingsOpen")
            .accessibilityValue(settings.accessibilityStatus)
            .onChange(of: request?.id) { _, value in model.isLibraryPanelOpen = value != nil }
            .sheet(item: $request) { context in
                TrackPlaybackSettingsView(model: settings, context: context)
                    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(600), .large])
                    .presentationDragIndicator(.visible)
            }
    }
}

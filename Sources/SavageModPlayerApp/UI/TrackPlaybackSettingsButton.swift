import SwiftUI
import SavageModPlayerCore

struct TrackPlaybackSettingsButton: View {
    @ObservedObject var model: TrackPlaybackSettingsModel
    let title: String
    let theme: PlayerTheme
    var compact = false
    @State private var request: TrackPlaybackSettingsContext?

    var body: some View {
        Button {
            request = TrackPlaybackSettingsContext(sourceID: model.sourceID, title: title, format: model.format,
                sourceDescription: model.sourceDescription)
        } label: {
            Label("Klang", systemImage: "slider.horizontal.3")
                .scaledFont(compact ? 9 : 10, weight: .semibold)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceSurface)
                .foregroundColor(theme == .workbench ? .lightTextPrimary : .spaceTextPrimary)
                .cornerRadius(theme == .workbench ? (compact ? 4 : 0) : 6)
        }.buttonStyle(PremiumHoverButtonStyle(theme: theme))
            .help("Klang: globale Vorgaben und Einstellungen nur für diesen Titel.")
            .accessibilityIdentifier("trackSettingsOpen")
            .accessibilityValue(model.overrides(for: model.sourceID).isEmpty ? "Globale Vorgaben" : "Titel-Overrides")
            .sheet(item: $request) { context in
                TrackPlaybackSettingsView(model: model, context: context).frame(width: 440, height: 560)
                    .preferredColorScheme(theme == .workbench ? .light : .dark)
            }
    }
}

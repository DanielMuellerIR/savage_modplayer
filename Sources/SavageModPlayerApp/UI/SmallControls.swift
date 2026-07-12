import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// Kleine wiederverwendbare Controls: Tab-Button und Checkbox-Toggle-Style.

// Ein Segment des Sidebar-Umschalters (PLAYLIST/INSTRUMENTE). Optik nach Vorbild
// des Light/Dark-Switchers: aktives Segment = Akzent-Hintergrund + weisse Schrift,
// inaktiv = Flaechen-Hintergrund. Kein Unterstrich mehr (frueher VStack mit
// Rectangle-Underline) — der Wrapper (padding/background/cornerRadius) sitzt in
// MainView um die beiden Segmente.
struct TabButton: View {
    let title: String
    let tag: Int
    @Binding var selection: Int
    let theme: PlayerTheme

    var body: some View {
        let isSelected = selection == tag
        Button(action: { selection = tag }) {
            Text(title)
                .scaledFont(11, weight: .bold)
                .padding(.vertical, 5)
                // Volle Breite: die beiden Segmente teilen sich die Sidebar-Breite.
                .frame(maxWidth: .infinity)
                .background(
                    isSelected
                    ? (Color.accent(theme))
                    : (theme == .workbench ? Color.lightSurfaceAlt : Color.spaceSurface.opacity(0.5))
                )
                .foregroundColor(
                    isSelected
                    ? Color.white
                    : (theme == .workbench ? Color.lightTextPrimary : Color.spaceTextSecondary)
                )
                .cornerRadius(theme == .workbench ? 0 : 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    let theme: PlayerTheme
    
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? (Color.accent(theme)) : .spaceTextSecondary)
                configuration.label
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}


import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// Kleine wiederverwendbare Controls: Tab-Button und Checkbox-Toggle-Style.

struct TabButton: View {
    let title: String
    let tag: Int
    @Binding var selection: Int
    let theme: PlayerTheme
    
    var body: some View {
        let isSelected = selection == tag
        Button(action: { selection = tag }) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(
                        isSelected
                        ? (theme == .workbench ? Color.lightAccent : Color.white)
                        : (theme == .workbench ? Color.lightTextPrimary.opacity(0.5) : Color.spaceTextSecondary.opacity(0.7))
                    )
                
                Rectangle()
                    .fill(
                        isSelected
                        ? (Color.accent(theme))
                        : Color.clear
                    )
                    .frame(height: 2)
                    .shadow(color: isSelected && theme == .cyber ? Color.spaceAccent.opacity(0.8) : Color.clear, radius: 4)
            }
            // Volle Breite + vertikales Polster + contentShape: der ganze
            // Tab-Bereich (nicht nur der Text) schaltet um.
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
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


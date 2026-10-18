import SwiftUI
import SavageModPlayerCore

struct SleepTimerButton: View {
    @ObservedObject var timer: SleepTimerController
    let theme: PlayerTheme
    var compact = false
    @State private var showing = false

    var body: some View {
        Button { timer.refresh(); showing = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                if timer.snapshot.isActive {
                    let seconds = timer.snapshot.remainingSeconds
                    Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
                } else { Text("Timer") }
            }.scaledFont(compact ? 9 : 10, weight: .semibold)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceSurface)
                .foregroundColor(theme == .workbench ? .lightTextPrimary : .spaceTextPrimary)
                .cornerRadius(theme == .workbench ? (compact ? 4 : 0) : 6)
        }.buttonStyle(PremiumHoverButtonStyle(theme: theme))
            .help("Einschlaftimer: mit sanftem Ausblenden, Verlängerung und Abbruch.")
            .accessibilityLabel("Einschlaftimer").accessibilityIdentifier("sleepTimerOpen")
            .accessibilityValue(statusValue)
            .sheet(isPresented: $showing) {
                SleepTimerView(timer: timer).frame(width: 380, height: 480)
                    .preferredColorScheme(theme == .workbench ? .light : .dark)
            }
    }

    private var statusValue: Text {
        if timer.snapshot.isActive {
            let seconds = timer.snapshot.remainingSeconds
            return Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        return timer.snapshot.phase == .expired ? Text("Wiedergabe beendet") : Text("Ausgeschaltet")
    }
}

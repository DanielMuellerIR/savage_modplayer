import SwiftUI
import SavageModPlayerCore

struct SleepTimerButton: View {
    @ObservedObject var timer: SleepTimerController
    let theme: PlayerTheme
    var compact = false
    @State private var showing = false

    var body: some View {
        Button {
            timer.refresh()
            showing = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                if let countdown = timer.snapshot.toolbarCountdown {
                    Text(verbatim: countdown).monospacedDigit()
                } else { Text("Timer") }
            }.scaledFont(compact ? 9 : 10, weight: .semibold)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(theme == .workbench ? Color.lightSurfaceAlt : Color.spaceSurface)
                .foregroundColor(theme == .workbench ? .lightTextPrimary : .spaceTextPrimary)
                .cornerRadius(theme == .workbench ? (compact ? 4 : 0) : 6)
        }.buttonStyle(PremiumHoverButtonStyle(theme: theme))
            .help("Einschlaftimer: mit sanftem Ausblenden, Verlängerung und Abbruch.")
            .accessibilityLabel("Einschlaftimer").accessibilityIdentifier("sleepTimerOpen")
            .accessibilityValue(timer.snapshot.accessibilityStatus)
            .sheet(isPresented: $showing) {
                SleepTimerView(timer: timer).frame(width: 380, height: 480)
                    .preferredColorScheme(theme == .workbench ? .light : .dark)
            }
    }

}

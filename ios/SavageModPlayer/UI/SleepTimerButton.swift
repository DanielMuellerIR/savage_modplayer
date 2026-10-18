import SwiftUI
import SavageModPlayerCore

struct SleepTimerButton: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var timer: SleepTimerController
    @State private var showing = false

    var body: some View {
        Button { timer.refresh(); showing = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                if timer.snapshot.isActive {
                    let seconds = timer.snapshot.remainingSeconds
                    Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.caption.monospacedDigit())
                }
            }
        }.accessibilityLabel(Text("Einschlaftimer"))
            .accessibilityValue(statusValue)
            .accessibilityIdentifier("sleepTimerOpen")
            .onChange(of: showing) { _, open in model.isLibraryPanelOpen = open }
            .sheet(isPresented: $showing) {
                SleepTimerView(timer: timer)
                    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(480), .large])
                    .presentationDragIndicator(.visible)
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

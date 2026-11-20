import SwiftUI
import SavageModPlayerCore

struct SleepTimerButton: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var timer: SleepTimerController
    @State private var showing = false

    var body: some View {
        Button {
            timer.refresh()
            showing = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                if let countdown = timer.snapshot.toolbarCountdown {
                    Text(verbatim: countdown)
                        .font(.caption.monospacedDigit())
                }
            }
        }.accessibilityLabel(Text("Einschlaftimer"))
            .accessibilityValue(timer.snapshot.accessibilityStatus)
            .accessibilityIdentifier("sleepTimerOpen")
            .onChange(of: showing) { _, open in model.isLibraryPanelOpen = open }
            .sheet(isPresented: $showing) {
                SleepTimerView(timer: timer)
                    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(480), .large])
                    .presentationDragIndicator(.visible)
            }
    }

}

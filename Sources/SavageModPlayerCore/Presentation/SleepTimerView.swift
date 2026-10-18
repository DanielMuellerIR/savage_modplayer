#if canImport(SwiftUI) && canImport(Combine)
import SwiftUI

public struct SleepTimerView: View {
    @ObservedObject private var timer: SleepTimerController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("savage.sleepTimerMinutes") private var minutes = 15

    public init(timer: SleepTimerController) { self.timer = timer }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Einschlaftimer").font(.title2.bold()).accessibilityIdentifier("sleepTimerTitle")
                    Text("Die letzten zehn Sekunden blenden sanft aus. Der Lautstärkeregler bleibt unverändert.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Stepper(value: $minutes, in: 1...720) {
                        HStack {
                            Text("Dauer in Minuten")
                            Spacer()
                            Text(verbatim: String(minutes)).monospacedDigit()
                        }
                    }.accessibilityIdentifier("sleepTimerDuration")
                    buttonLayout {
                        Button("15 Min.") { minutes = 15 }.accessibilityIdentifier("sleepTimerPreset15")
                        Button("30 Min.") { minutes = 30 }.accessibilityIdentifier("sleepTimerPreset30")
                        Button("60 Min.") { minutes = 60 }.accessibilityIdentifier("sleepTimerPreset60")
                    }.buttonStyle(.bordered).controlSize(.large)
                    Text("Der Timer läuft auch bei Pause und Titelwechsel weiter. Nach Ablauf bleibt die Wiedergabe aus, bis du sie bewusst startest. Nach einem App-Neustart ist der Timer aus.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline) {
                phaseLabel.font(.headline).accessibilityIdentifier("sleepTimerPhase")
                Spacer()
                Text(verbatim: remainingText).font(.title.monospacedDigit())
                    .accessibilityIdentifier("sleepTimerRemaining")
            }
            if timer.snapshot.phase != .inactive {
                buttonLayout {
                    if timer.snapshot.isActive {
                        Button("+15 Minuten") { timer.extend() }.accessibilityIdentifier("sleepTimerExtend")
                    }
                    Button("Timer abbrechen") { timer.cancel() }.accessibilityIdentifier("sleepTimerCancel")
                }.buttonStyle(.bordered).controlSize(.large)
            }
            buttonLayout {
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("sleepTimerClose")
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button {
                    timer.start(minutes: minutes)
                } label: {
                    if timer.snapshot.isActive { Text("Neu starten") } else { Text("Timer starten") }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("sleepTimerStart")
            }.controlSize(.large)
        }.padding(20)
            .onAppear { minutes = max(1, min(720, minutes)); timer.refresh() }
    }

    @ViewBuilder private var phaseLabel: some View {
        switch timer.snapshot.phase {
        case .inactive: Text("Ausgeschaltet")
        case .countingDown: Text("Restzeit")
        case .fading: Text("Ausblenden …")
        case .expired: Text("Wiedergabe beendet")
        }
    }

    private var remainingText: String {
        let seconds = timer.snapshot.remainingSeconds
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var buttonLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }
}
#endif

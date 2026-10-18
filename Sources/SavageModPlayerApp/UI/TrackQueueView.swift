import SwiftUI
import SavageModPlayerCore

struct TrackQueueView: View {
    let items: [TrackQueue.Item]
    let onRemove: (UUID) -> Void
    let onMove: (UUID, Int) -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Als Nächstes").font(.title2.bold())
            Text("Weiter spielt zuerst diese Titel, danach geht die vorherige Liste weiter. Die Warteschlange gilt für diese Sitzung.")
                .font(.callout).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("Warteschlange leer. Rechtsklick auf einen Titel → Als Nächstes spielen.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 8) {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.track.displayName).lineLimit(1)
                                Text(item.track.source.archiveMembers.last
                                     ?? item.track.source.location.deletingLastPathComponent().lastPathComponent)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button { onMove(item.id, -1) } label: {
                                Image(systemName: "arrow.up").frame(width: 24, height: 24)
                            }.disabled(index == 0).help("Nach oben").accessibilityLabel("Titel nach oben")
                            Button { onMove(item.id, 1) } label: {
                                Image(systemName: "arrow.down").frame(width: 24, height: 24)
                            }.disabled(index == items.count - 1).help("Nach unten").accessibilityLabel("Titel nach unten")
                            Button { onRemove(item.id) } label: {
                                Image(systemName: "minus.circle").frame(width: 24, height: 24)
                            }.help("Aus Warteschlange entfernen").accessibilityLabel("Titel aus Warteschlange entfernen")
                        }.buttonStyle(.borderless).padding(.vertical, 3)
                    }
                }
            }
            HStack {
                Button("Warteschlange leeren", action: onClear).disabled(items.isEmpty)
                Spacer()
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 560, height: 400)
            .accessibilityIdentifier("track-queue-sheet")
    }
}

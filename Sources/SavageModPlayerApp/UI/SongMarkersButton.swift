import SwiftUI
import SavageModPlayerCore

struct SongMarkersButton: View {
    @EnvironmentObject private var model: SongMarkersModel
    @ObservedObject var coordinator: ModPlayerCoordinator
    let theme: PlayerTheme
    @State private var showing = false
    @State private var openedContextID: UUID?

    var body: some View {
        Button {
            openedContextID = model.contextID
            showing = true
        } label: {
            HStack(spacing: 6) {
                Label("Songstellen…", systemImage: "bookmark").scaledFont(11)
                SectionLoopBadge(coordinator: coordinator)
            }
        }
        .disabled(coordinator.activeMod == nil).accessibilityIdentifier("song-markers-open")
        .onChange(of: model.contextID) { _ in showing = false }
        .onChange(of: model.section) { section in
            if coordinator.sectionLoopTarget != nil, coordinator.sectionLoopTarget != section { coordinator.cancelSectionLoop() }
        }
        .sheet(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Songstellen und Auswahl").font(.title2.bold())
                    Spacer(); Button("Schließen") { showing = false }.buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                }.padding(20)
                Divider()
                SongMarkersView(model: model, transport: coordinator.transport, coordinator: coordinator,
                    current: { SongAddress(position: coordinator.currentPosition, row: coordinator.currentRow) },
                    seek: { address in
                        guard openedContextID == model.contextID, model.layout.contains(address) else { return false }
                        coordinator.seek(toPosition: address.position, row: address.row)
                        return true
                    })
            }
            .frame(minWidth: 650, idealWidth: 720, minHeight: 600, idealHeight: 720)
            .preferredColorScheme(theme == .workbench ? .light : .dark)
            .foregroundStyle(.primary)
        }
    }
}

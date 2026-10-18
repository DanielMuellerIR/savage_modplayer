import SwiftUI
import SavageModPlayerCore

struct PlayerInspectionMenu: View {
    @EnvironmentObject private var model: AppModel
    let module: Mod
    @State private var presentedModule: Mod?
    @State private var showing = false
    private enum Detail { case samples, module, markers }
    @State private var detail = Detail.samples
    @State private var openedModuleID: UUID?

    var body: some View {
        Menu {
            Button("Samples untersuchen…", systemImage: "waveform.path") { open(.samples) }
            Button("Modul untersuchen…", systemImage: "list.bullet.rectangle") { open(.module) }
            Button("Songstellen…", systemImage: "bookmark") { open(.markers) }
        } label: {
            HStack(spacing: 6) {
                Label("Moduldetails", systemImage: "info.circle")
                SectionLoopBadge(coordinator: model.player.coordinator)
            }
        }
        .accessibilityIdentifier("player-inspectors")
        .onChange(of: showing) { _, open in model.isLibraryPanelOpen = open }
        .onChange(of: model.player.loadedModuleID) { _, _ in if detail == .markers { showing = false } }
        .onChange(of: model.markers.section) { _, section in
            let coordinator = model.player.coordinator
            if coordinator.sectionLoopTarget != nil, coordinator.sectionLoopTarget != section { coordinator.cancelSectionLoop() }
        }
        .sheet(isPresented: $showing, onDismiss: { presentedModule = nil }) {
            if let presentedModule {
                NavigationStack {
                    Group {
                        switch detail {
                        case .samples: SampleInspectorView(module: presentedModule)
                        case .module: ModuleInspectorView(module: presentedModule)
                        case .markers:
                            SongMarkersView(model: model.markers, transport: model.player.coordinator.transport,
                                coordinator: model.player.coordinator,
                                startLoop: { model.player.startSectionLoop($0) },
                                current: { SongAddress(position: model.player.coordinator.currentPosition, row: model.player.coordinator.currentRow) },
                                seek: { address in
                                    guard openedModuleID == model.player.loadedModuleID,
                                          model.markers.sourceID == model.player.currentTrack?.relativePath,
                                          model.markers.layout.contains(address) else { return false }
                                    model.player.seek(to: address); return true
                                })
                        }
                    }
                    .navigationTitle(Text(LocalizedStringKey(detail == .samples ? "Sample-Inspektor" : detail == .module ? "Modul-Inspektor" : "Songstellen und Auswahl")))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("common.done") { showing = false }
                        }
                    }
                    .safeAreaInset(edge: .top) {
                        Text(verbatim: presentedModule.name).font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal).padding(.vertical, 6).frame(maxWidth: .infinity).background(.bar)
                    }
                }
            }
        }
    }
    private func open(_ detail: Detail) {
        self.detail = detail
        presentedModule = module
        openedModuleID = model.player.loadedModuleID
        if detail == .markers {
            model.markers.setContext(sourceID: model.player.currentTrack?.relativePath, module: module, moduleID: openedModuleID)
        }
        showing = true
    }
}

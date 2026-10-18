import SwiftUI
import SavageModPlayerCore

struct ModuleInspectorButton: View {
    let module: Mod
    let theme: PlayerTheme
    @State private var snapshot: InspectorModuleSnapshot?

    var body: some View {
        Button {
            snapshot = InspectorModuleSnapshot(module: module)
        } label: {
            Label("Modul untersuchen…", systemImage: "list.bullet.rectangle")
                .scaledFont(11)
        }
        .accessibilityIdentifier("module-inspector-open")
        .sheet(item: $snapshot) { presented in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Modul-Inspektor").font(.title2.bold())
                        Text(presented.module.name).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Schließen") { snapshot = nil }.keyboardShortcut(.cancelAction)
                }.padding(20)
                Divider()
                ModuleInspectorView(module: presented.module)
            }
            .frame(minWidth: 650, idealWidth: 760, minHeight: 620, idealHeight: 760)
            .preferredColorScheme(theme == .workbench ? .light : .dark)
        }
    }
}

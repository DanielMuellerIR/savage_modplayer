import SwiftUI

// Der Einstellungs-Tab: Klang, Darstellung, Bibliothek, Ueber.
//
// Alle Werte liegen in `PlayerSettings` und ueberleben damit Neustarts.
// Geschrieben wird ausschliesslich ueber `settings.binding(_:)` bzw.
// `settings.set(_:to:)` — die Begruendung steht in UISupport.swift.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Content(settings: model.settings, library: model.library)
    }

    private struct Content: View {
        @ObservedObject var settings: PlayerSettings
        @ObservedObject var library: LibraryStore

        @State private var showImport = false
        @State private var showReset = false

        var body: some View {
            NavigationStack {
                Form {
                    soundSection
                    appearanceSection
                    librarySection
                    aboutSection
                }
                .navigationTitle("tab.settings")
                .sheet(isPresented: $showImport) { LibraryImportSheet() }
                .sheet(isPresented: $showReset) { LibraryResetConfirmation(isPresented: $showReset) }
            }
        }

        // MARK: - Klang

        private var soundSection: some View {
            Section {
                Picker("settings.clock", selection: settings.binding(\.palClock)) {
                    Text("settings.clock.pal").tag(true)
                    Text("settings.clock.ntsc").tag(false)
                }
                .pickerStyle(.segmented)

                Toggle("settings.led", isOn: settings.binding(\.ledFilterActive))
                Toggle("settings.interpolation", isOn: settings.binding(\.useInterpolation))

                slider(
                    title: "settings.stereo",
                    value: settings.binding(\.stereoSeparation),
                    icon: "speaker.wave.2")
                slider(
                    title: "settings.volume",
                    value: settings.binding(\.volume),
                    icon: "speaker.wave.3")
            } header: {
                Text("settings.sound")
            } footer: {
                Text("settings.sound.hint")
            }
        }

        // Regler mit Beschriftung und Prozentwert. Der Wert steht daneben, weil
        // man einem Regler allein nicht ansieht, wo er steht.
        private func slider(title: LocalizedStringKey, value: Binding<Double>, icon: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(title, systemImage: icon)
                    Spacer()
                    Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: value, in: 0...1)
                    .accessibilityLabel(title)
            }
        }

        // MARK: - Darstellung

        private var appearanceSection: some View {
            Section {
                Picker("settings.theme", selection: settings.binding(\.theme)) {
                    ForEach(PlayerTheme.allCases) { theme in
                        Text(theme.localizedName).tag(theme)
                    }
                }

                Toggle("settings.visualizers", isOn: settings.binding(\.visualizersEnabled))

                // Bildrate und Kanalzahl haben nur Sinn, wenn ueberhaupt
                // gezeichnet wird.
                if settings.visualizersEnabled {
                    Picker("settings.framerate", selection: settings.binding(\.visualizerFrameRate)) {
                        ForEach([10, 20, 30], id: \.self) { rate in
                            Text("settings.framerate.value \(rate)").tag(rate)
                        }
                    }
                    Picker("settings.scopes", selection: settings.binding(\.maxVisibleChannelScopes)) {
                        ForEach([4, 8, 16, 32], id: \.self) { count in
                            Text(verbatim: "\(count)").tag(count)
                        }
                    }
                    Text("settings.scopes.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.appearance")
            } footer: {
                Text("settings.visualizers.hint")
            }
        }

        // MARK: - Bibliothek

        private var librarySection: some View {
            Section {
                Button {
                    showImport = true
                } label: {
                    Label("import.title", systemImage: "folder.badge.plus")
                }

                if !library.pendingArchives.isEmpty {
                    Button {
                        library.unpackPendingArchives()
                    } label: {
                        Label("import.pending.unpack", systemImage: "shippingbox")
                    }
                    .disabled(library.isBusy)
                }

                Button(role: .destructive) {
                    showReset = true
                } label: {
                    Label("library.reset.title", systemImage: "trash")
                }
            } header: {
                Text("settings.library")
            } footer: {
                Text("library.reset.count \(library.tracks.count)")
            }
        }

        // MARK: - Ueber

        private var aboutSection: some View {
            Section {
                Text(verbatim: "Savage Mod Player")
                    .font(.body.weight(.semibold))
                LabeledContent {
                    Text(verbatim: Self.appVersion)
                        .monospacedDigit()
                } label: {
                    Text("settings.about.version")
                }
                Text("settings.about.formats")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.about.license")
                        .font(.footnote.weight(.semibold))
                    Text("settings.about.license.text")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.about")
            }
        }

        // Version aus dem Bundle — nicht im Quelltext doppelt gepflegt.
        private static var appVersion: String {
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
        }
    }
}

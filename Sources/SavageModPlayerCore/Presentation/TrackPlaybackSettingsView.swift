#if canImport(SwiftUI) && canImport(Combine)
import SwiftUI

public struct TrackPlaybackSettingsContext: Identifiable, Sendable {
    public let id = UUID()
    public let sourceID: String?
    public let title: String
    public let format: ModuleFormat?
    public let sourceDescription: String
    public init(sourceID: String?, title: String, format: ModuleFormat?, sourceDescription: String = "") {
        self.sourceID = sourceID; self.title = title; self.format = format
        self.sourceDescription = sourceDescription
    }
}

public struct TrackPlaybackSettingsView: View {
    @ObservedObject private var model: TrackPlaybackSettingsModel
    private let context: TrackPlaybackSettingsContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editingDefaults = false

    public init(model: TrackPlaybackSettingsModel, context: TrackPlaybackSettingsContext) {
        self.model = model; self.context = context
    }

    private var overrides: TrackPlaybackOverrides { model.overrides(for: context.sourceID) }
    private var effective: PlaybackOptions { overrides.resolved(defaults: model.defaults, format: context.format) }
    private var writable: Bool { context.sourceID != nil && model.canWriteTitles }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wiedergabeeinstellungen").font(.title2.bold())
            Text(verbatim: context.title).font(.headline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("trackSettingsTitle")
            if !context.sourceDescription.isEmpty {
                Text(verbatim: context.sourceDescription).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).help(context.sourceDescription)
                    .accessibilityIdentifier("trackSettingsSource")
            }
            Picker("Geltungsbereich", selection: $editingDefaults) {
                Text("Dieser Titel").tag(false)
                Text("Globale Vorgaben").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("trackSettingsScope")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if editingDefaults { defaultsFields }
                    else {
                        Text("Nur ausdrücklich gewählte Werte überschreiben die globalen Vorgaben. Andere Titel behalten ihre eigenen Einstellungen.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        titleFields.disabled(!writable)
                        if context.sourceID == nil {
                            Text("Ohne dauerhafte Titelquelle können keine Overrides gespeichert werden.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let issue = model.issue {
                        if issue == .load {
                            Text("Titel-Einstellungen konnten nicht geladen werden. Die Datei bleibt erhalten; es gelten die globalen Vorgaben.")
                        } else {
                            Text("Titel-Einstellungen konnten nicht gespeichert werden. Der zuletzt gesicherte Stand bleibt erhalten.")
                        }
                    }
                    if model.isSaving { Text("Wird gespeichert …").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            footerLayout {
                if !editingDefaults {
                    Button("Titel zurücksetzen") {
                        if let sourceID = context.sourceID { model.resetTitle(sourceID) }
                    }.disabled(!writable || overrides.isEmpty).accessibilityIdentifier("trackSettingsReset")
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button("Schließen") { model.flush(); dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("trackSettingsClose")
            }.controlSize(.large)
        }.padding(20)
            .onDisappear { model.flush() }
    }

    private var defaultsFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diese Vorgaben gelten für alle Titel ohne passenden Override.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("MOD-Clock")
                Picker("MOD-Clock", selection: defaultBinding(\.palClock)) {
                    Text("PAL").tag(true); Text("NTSC").tag(false)
                }.labelsHidden().accessibilityIdentifier("trackSettingsDefaultClock")
            }
            separationSlider(defaultBinding(\.stereoSeparation), identifier: "trackSettingsDefaultSeparation")
            Toggle("Lineare Interpolation", isOn: defaultBinding(\.useInterpolation))
                .accessibilityIdentifier("trackSettingsDefaultInterpolation")
            Toggle("LED-Ausgabefilter", isOn: defaultBinding(\.ledFilterActive))
                .accessibilityIdentifier("trackSettingsDefaultFilter")
        }
    }

    private var titleFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            if PlaybackOptions.supportsAmigaClock(context.format) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MOD-Clock")
                    Picker("MOD-Clock", selection: titleBinding(\.palClock)) {
                        Text("Globale Vorgabe").tag(Bool?.none)
                        Text("PAL").tag(Bool?.some(true)); Text("NTSC").tag(Bool?.some(false))
                    }.labelsHidden().accessibilityIdentifier("trackSettingsClock")
                }
            } else {
                Text("Dieses Format verwendet ein festes Frequenzmodell; PAL/NTSC ist nicht anwendbar.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trackSettingsFixedClock")
            }
            Toggle("Stereo-Separation überschreiben", isOn: Binding(
                get: { overrides.stereoSeparation != nil },
                set: { enabled in update { $0.stereoSeparation = enabled ? effective.stereoSeparation : nil } }
            )).accessibilityIdentifier("trackSettingsSeparationOverride")
            separationSlider(Binding(
                get: { overrides.stereoSeparation ?? model.defaults.stereoSeparation },
                set: { value in if let sourceID = context.sourceID { model.previewSeparation(value, for: sourceID) } }
            ), identifier: "trackSettingsSeparation").disabled(overrides.stereoSeparation == nil)
            booleanPicker("Lineare Interpolation", field: \.useInterpolation, identifier: "trackSettingsInterpolation")
            booleanPicker("LED-Ausgabefilter", field: \.ledFilterActive, identifier: "trackSettingsFilter")
            Text("Wirksam für diesen Titel").font(.headline)
            footerLayout {
                if PlaybackOptions.supportsAmigaClock(context.format) { Text(verbatim: effective.palClock ? "PAL" : "NTSC") }
                Text(verbatim: "\(Int((effective.stereoSeparation * 100).rounded())) %")
                Text(effective.useInterpolation ? "Interpolation ein" : "Interpolation aus")
                Text(effective.ledFilterActive ? "Filter ein" : "Filter aus")
            }.font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("trackSettingsEffective")
            Text("Der LED-Ausgabefilter wirkt auf die Ausgabe. Änderungen an Klangwerten beenden eine aktive A/B-Schleife; der Einschlaftimer läuft weiter.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func booleanPicker(_ label: LocalizedStringKey, field: WritableKeyPath<TrackPlaybackOverrides, Bool?>,
                               identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
            Picker(label, selection: titleBinding(field)) {
                Text("Globale Vorgabe").tag(Bool?.none)
                Text("Ein").tag(Bool?.some(true)); Text("Aus").tag(Bool?.some(false))
            }.labelsHidden().accessibilityIdentifier(identifier)
        }
    }

    private func separationSlider(_ value: Binding<Double>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Stereo-Separation")
                Spacer()
                Text(verbatim: "\(Int((value.wrappedValue * 100).rounded())) %").monospacedDigit()
            }
            Slider(value: value, in: 0...1).accessibilityLabel(Text("Stereo-Separation"))
                .accessibilityIdentifier(identifier)
        }
    }

    private func defaultBinding<Value>(_ field: WritableKeyPath<PlaybackOptions, Value>) -> Binding<Value> {
        Binding(get: { model.defaults[keyPath: field] }, set: { value in
            var next = model.defaults; next[keyPath: field] = value; model.updateDefaults(next)
        })
    }
    private func titleBinding<Value>(_ field: WritableKeyPath<TrackPlaybackOverrides, Value>) -> Binding<Value> {
        Binding(get: { overrides[keyPath: field] }, set: { value in update { $0[keyPath: field] = value } })
    }
    private func update(_ change: (inout TrackPlaybackOverrides) -> Void) {
        if let sourceID = context.sourceID { model.updateTitle(sourceID, change: change) }
    }
    private var footerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }
}
#endif

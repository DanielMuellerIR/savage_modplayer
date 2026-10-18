#if canImport(SwiftUI) && canImport(Combine) && canImport(UniformTypeIdentifiers)
import SwiftUI
import UniformTypeIdentifiers

public struct CollectionExchangeContext: Identifiable {
    public let id = UUID()
    public let model: CollectionExchangeModel
    public let fileURL: URL?
    public init(model: CollectionExchangeModel, fileURL: URL? = nil) { self.model = model; self.fileURL = fileURL }
}

private struct CollectionExchangeFile: FileDocument {
    static let contentType = UTType(exportedAs: CollectionExchangeCodec.contentTypeIdentifier, conformingTo: .json)
    static var readableContentTypes: [UTType] { [contentType, .json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CollectionExchangeError.unreadable }
        _ = try CollectionExchangeCodec.decode(data); self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

public struct CollectionExchangeView: View {
    @ObservedObject private var model: CollectionExchangeModel
    private let initialFile: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportFile: CollectionExchangeFile?
    @State private var choice: Choice?
    @State private var confirmSkip = false
    private struct Choice: Identifiable { let id = UUID(); let track: ExchangeTrack }

    public init(context: CollectionExchangeContext) { model = context.model; initialFile = context.fileURL }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sammlung übertragen").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let name = model.sourceFileName {
                        Text(verbatim: name).font(.headline).lineLimit(2).truncationMode(.middle).help(name)
                    }
                    Text("Playlists, Favoriten, Songstellen und Klang-Einstellungen. Musikdateien bleiben auf ihrem Gerät.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let completion = model.completion, completion != .exported {
                        Label("Sammlung übernommen", systemImage: "checkmark.circle.fill").font(.headline)
                            .accessibilityIdentifier("collectionComplete")
                        if completion == .cleanupPending {
                            Text("Die Daten sind übernommen. Bitte vor einer weiteren Übertragung die App neu starten.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if let incoming = model.incoming {
                        importContent(incoming)
                    } else if let state = model.state {
                        summary(playlists: state.snapshot.playlists.playlists.count, favorites: state.snapshot.playlists.favoriteIDs.count,
                                markers: state.snapshot.markers.markers.count, settings: state.snapshot.trackSettings.tracks.count)
                        Text("Die globale Klang-Vorgabe wird ebenfalls übertragen. Lautstärke, laufende Timer und die Warteschlange bleiben lokal.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 12) {
                            Button("Sammlung exportieren…", systemImage: "square.and.arrow.up") {
                                Task {
                                    do {
                                        let data = try await model.exportData()
                                        guard !Task.isCancelled else { return }
                                        exportFile = CollectionExchangeFile(data: data); showExporter = true
                                    } catch is CancellationError { }
                                    catch { model.report(error) }
                                }
                            }.accessibilityIdentifier("collectionExport")
                            Button("Austauschdatei importieren…", systemImage: "square.and.arrow.down") { showImporter = true }
                                .accessibilityIdentifier("collectionChooseFile")
                        }.controlSize(.large).disabled(model.isBusy)
                        if model.completion == .exported { Text("Austauschdatei gespeichert.").accessibilityIdentifier("collectionExported") }
                    }
                    if model.isBusy { ProgressView("Wird vorbereitet …").accessibilityIdentifier("collectionProgress") }
                    if let error = model.error {
                        CollectionExchangeErrorText(error: error).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("collectionError")
                        if model.incoming == nil {
                            Button("Erneut prüfen") { Task { await model.load() } }.disabled(model.isBusy)
                                .accessibilityIdentifier("collectionRefresh")
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("collectionScroll")
            footer
        }.padding(20).buttonStyle(.bordered)
            .interactiveDismissDisabled(model.isApplying)
            .task {
                await model.load()
                if let initialFile, !Task.isCancelled { await model.loadFile(initialFile) }
            }
            .onDisappear { model.cancel() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [CollectionExchangeFile.contentType, .json, .data]) { result in
                switch result {
                case .success(let url): Task { await model.loadFile(url) }
                case .failure(let error): if !Self.isCancellation(error) { model.report(error) }
                }
            }
            .fileExporter(isPresented: $showExporter, document: exportFile, contentType: CollectionExchangeFile.contentType,
                          defaultFilename: "Savage-Collection") { result in
                switch result {
                case .success: model.exported()
                case .failure(let error): if !Self.isCancellation(error) { model.report(error) }
                }
            }
            .sheet(item: $choice) { choice in
                CollectionExchangeTrackChooser(model: model, track: choice.track)
                    #if os(macOS)
                    .frame(width: 600, height: 560)
                    #else
                    .presentationDetents([.large])
                    #endif
            }
            .confirmationDialog("Alle noch offenen Titel überspringen? Die betreffenden eingehenden Einträge werden nicht übernommen.",
                                isPresented: $confirmSkip, titleVisibility: .visible) {
                Button("Offene Titel überspringen", role: .destructive) { model.skipUnresolved() }
                Button("Abbrechen", role: .cancel) { }
            }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) { footerButtons }
            }
            VStack(alignment: .leading, spacing: 10) { footerButtons }
        }.controlSize(.large)
    }
    @ViewBuilder private var footerButtons: some View {
            if model.incoming != nil, model.completion == nil {
                Button("Andere Datei…") { showImporter = true }.disabled(model.isBusy)
                    .accessibilityIdentifier("collectionChooseFile")
            }
            #if os(macOS)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            #endif
            Button("Schließen") { model.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                .disabled(model.isApplying).accessibilityIdentifier("collectionClose")
            if model.incoming != nil, model.completion == nil {
                Button("Übernehmen") { Task { await model.applyImport() } }
                    .buttonStyle(.borderedProminent).disabled(!model.isReady)
                    .accessibilityIdentifier("collectionApply")
            }
    }
    private var footerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
    }
    private func summary(playlists: Int, favorites: Int, markers: Int, settings: Int) -> some View {
        GroupBox {
            VStack(spacing: 6) {
                count("Playlists", playlists); count("Favoriten", favorites)
                count("Songstellen", markers); count("Titel-Klang", settings)
            }.frame(maxWidth: .infinity)
        }
    }
    private func count(_ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(title); Spacer(); Text(verbatim: value.formatted()).monospacedDigit() }
    }
    private func importContent(_ incoming: CollectionExchangeDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vorschau der Austauschdatei").font(.headline)
            HStack { Text("Exportzeit"); Text(incoming.createdAt, format: .dateTime.year().month().day().hour().minute()) }
                .font(.caption).foregroundStyle(.secondary)
            Button("Vorschau neu erstellen") { Task { await model.load() } }.disabled(model.isBusy)
                .help("Setzt Titelzuordnungen und Konfliktentscheidungen zurück.").accessibilityIdentifier("collectionRefresh")
            summary(playlists: incoming.playlists.count, favorites: incoming.favoriteTrackIDs.count,
                    markers: incoming.markers.count, settings: incoming.trackSettings.count)
            if !incoming.playlists.isEmpty {
                DisclosureGroup("Playlists ansehen") {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(incoming.playlists) { playlist in
                            DisclosureGroup {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(playlist.trackIDs.enumerated()), id: \.offset) { index, id in
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(verbatim: "\(index + 1).").monospacedDigit()
                                            Text(verbatim: model.mapping[id].map(Self.localSourceDescription)
                                                ?? model.track(withID: id)?.descriptor.fileName ?? "")
                                                .lineLimit(3).truncationMode(.middle)
                                        }
                                    }
                                }.padding(.top, 8)
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(verbatim: playlist.name).fixedSize(horizontal: false, vertical: true)
                                    Spacer(); Text(verbatim: playlist.trackIDs.count.formatted()).monospacedDigit()
                                }
                            }
                        }
                    }.padding(.top, 8)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Titelzuordnung").font(.headline)
                count("Zugeordnet", model.mapping.count)
                count("Übersprungen", model.skipped.count)
                count("Offen", max(0, incoming.tracks.count - model.mapping.count - model.skipped.count))
                Text("Eindeutige Vorschläge sind vorausgewählt. Prüfen Sie die Zuordnung vor der Übernahme; Namen und Pfade sind Hinweise auf den lokalen Titel.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("Titel oder Pfad suchen", text: $model.query).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("collectionSearch")
                Toggle("Nur offene Zuordnungen", isOn: $model.unresolvedOnly).accessibilityIdentifier("collectionUnresolvedOnly")
                if model.matchingTrackCount > model.visibleTracks.count {
                    Text("Suche eingrenzen, um weitere Titel anzuzeigen.").font(.caption).foregroundStyle(.secondary)
                }
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.visibleTracks) { track in
                        Button { choice = Choice(track: track) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: track.descriptor.fileName).font(.headline).lineLimit(2).truncationMode(.middle).help(track.descriptor.fileName)
                                if let path = track.descriptor.relativePath {
                                    Text(verbatim: ([path] + track.descriptor.archiveMembers).joined(separator: " ▸ "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                                }
                                if let mapped = model.mapping[track.id] {
                                    Label { Text(verbatim: Self.localSourceDescription(mapped)) } icon: { Image(systemName: "checkmark.circle") }
                                        .font(.caption).lineLimit(2).truncationMode(.middle)
                                } else if model.skipped.contains(track.id) {
                                    Label("Wird übersprungen", systemImage: "minus.circle").font(.caption)
                                } else { Label("Zuordnung erforderlich", systemImage: "questionmark.circle").font(.caption) }
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(10)
                        }.collectionTrackRowStyle().disabled(model.isBusy)
                            .accessibilityIdentifier("collectionTrack-\(track.id.uuidString)")
                    }
                }
                if incoming.tracks.count > model.mapping.count + model.skipped.count {
                    Button("Alle offenen Titel überspringen…") { confirmSkip = true }.disabled(model.isBusy)
                        .accessibilityIdentifier("collectionSkipUnresolved")
                }
            }
            if let preview = model.preview, !preview.conflicts.isEmpty {
                Divider()
                Text("Konflikte entscheiden").font(.headline)
                Text("Vorhandene Daten werden nur nach Ihrer Entscheidung ersetzt. Favoriten werden ergänzt.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(preview.conflicts.enumerated()), id: \.element.id) { index, conflict in
                    VStack(alignment: .leading, spacing: 6) {
                        conflictTitle(conflict)
                        DisclosureGroup("Werte vergleichen") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Vorhanden").font(.caption.bold())
                                conflictValue(conflict.local)
                                Text("Eingehend").font(.caption.bold())
                                conflictValue(conflict.incoming)
                            }.padding(.top, 8)
                        }.accessibilityIdentifier("collectionCompare-\(index)")
                        Picker("Entscheidung", selection: Binding(get: { model.resolutions[conflict.id] }, set: { model.resolve(conflict.id, with: $0) })) {
                            Text("Bitte auswählen").tag(CollectionExchangeResolution?.none)
                            ForEach(conflict.allowedResolutions, id: \.self) { value in
                                resolutionTitle(value).tag(Optional.some(value))
                            }
                        }.disabled(model.isBusy).accessibilityIdentifier("collectionConflict-\(index)")
                    }
                }
                }
            }
        }
    }
    @ViewBuilder private func conflictTitle(_ conflict: CollectionExchangeConflict) -> some View {
        switch conflict.id {
        case .playbackDefaults: Text("Globale Klangwerte").font(.headline)
        default: Text(verbatim: conflict.name).font(.headline).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private func conflictValue(_ value: CollectionExchangeConflict.Value) -> some View {
        switch value {
        case .playlist(let playlist):
            Text(verbatim: playlist.name).font(.callout.bold())
            count("Titel", playlist.tracks.count)
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, reference in
                    Text(verbatim: "\(index + 1). " + Self.localSourceDescription(reference)).font(.caption).lineLimit(3).truncationMode(.middle)
                }
            }
        case .matchingPlaylistNames(let count):
            Text("Listen mit diesem Namen: \(count)")
        case .marker(let marker):
            Text(verbatim: marker.name).font(.callout.bold())
            Text("Position \(marker.address.position + 1), Zeile \(marker.address.row + 1)")
            if let source = model.source(withID: marker.sourceID) {
                Text(verbatim: Self.localSourceDescription(source.reference)).font(.caption).lineLimit(3).truncationMode(.middle)
            }
        case .overrides(let overrides): soundValues(overrides)
        case .defaults(let defaults):
            soundValues(.init(palClock: defaults.palClock, stereoSeparation: defaults.stereoSeparation,
                              useInterpolation: defaults.useInterpolation, ledFilterActive: defaults.ledFilterActive))
        }
    }
    private func soundValues(_ options: TrackPlaybackOverrides) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            soundRow("MOD-Clock") { if let value = options.palClock { Text(verbatim: value ? "PAL" : "NTSC") } else { Text("Globale Vorgabe") } }
            soundRow("Stereo-Separation") {
                if let value = options.stereoSeparation { Text(value, format: .percent.precision(.fractionLength(0))) }
                else { Text("Globale Vorgabe") }
            }
            soundRow("Lineare Interpolation") { boolValue(options.useInterpolation) }
            soundRow("LED-Ausgabefilter") { boolValue(options.ledFilterActive) }
        }
    }
    private func soundRow<Content: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Content) -> some View {
        footerLayout {
            Text(title).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            #if os(macOS)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            #endif
            value().fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private func boolValue(_ value: Bool?) -> some View {
        if let value { if value { Text("Ein") } else { Text("Aus") } }
        else { Text("Globale Vorgabe") }
    }
    @ViewBuilder private func resolutionTitle(_ resolution: CollectionExchangeResolution) -> some View {
        switch resolution {
        case .keepLocal: Text("Vorhandene Daten behalten")
        case .useIncoming: Text("Eingehende Daten übernehmen")
        case .keepBoth: Text("Beide behalten")
        }
    }
    nonisolated static func localSourceDescription(_ reference: PlaylistTrackReference) -> String {
        ([reference.source.libraryRelativePath ?? reference.source.location.path] + reference.source.archiveMembers).joined(separator: " ▸ ")
    }
    private static func isCancellation(_ error: Error) -> Bool { (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError }
}

struct CollectionExchangeTrackChooser: View {
    @ObservedObject var model: CollectionExchangeModel
    let track: ExchangeTrack
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @State private var sources: [CollectionExchangeLocalTrack] = []
    @State private var total = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lokalen Titel wählen").font(.title2.bold())
            Text(verbatim: track.descriptor.fileName).font(.headline).lineLimit(3).truncationMode(.middle).fixedSize(horizontal: false, vertical: true)
            TextField("Titel oder Pfad suchen", text: $query).textFieldStyle(.roundedBorder).accessibilityIdentifier("collectionTargetSearch")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if query.isEmpty, !model.suggestions(for: track.id).isEmpty {
                        Text("Vorschläge").font(.headline)
                        ForEach(Array(model.suggestions(for: track.id).enumerated()), id: \.element.reference.id) { index, source in
                            row(source, identifier: "collectionSuggestion-\(index)")
                        }
                        if model.suggestionCount(for: track.id) > model.suggestions(for: track.id).count {
                            Text("Weitere mögliche Titel sind in der lokalen Suche verfügbar.").font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                    Text("Lokale Titel").font(.headline)
                    ForEach(Array(sources.enumerated()), id: \.element.reference.id) { index, source in
                        row(source, identifier: "collectionTarget-\(index)")
                    }
                    if total > sources.count {
                        Text("Suche eingrenzen, um weitere Titel anzuzeigen.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("collectionTargetScroll")
            footerLayout {
                Button("Überspringen") { model.skip(track.id); dismiss() }.accessibilityIdentifier("collectionSkipTrack")
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button("Zurück") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("collectionChoiceClose")
            }.controlSize(.large)
        }.padding(20).buttonStyle(.bordered)
            .task(id: query) {
                let all = model.state?.sources ?? [], query = query
                let limit = CollectionExchangeModel.maximumVisibleRows
                do {
                    if !query.isEmpty { try await Task.sleep(for: .milliseconds(120)) }
                    let result = await Task.detached(priority: .userInitiated) {
                        let rows = all.map { ($0, CollectionExchangeView.localSourceDescription($0.reference)) }
                            .filter { query.isEmpty || ($0.0.reference.displayName + " " + $0.1).localizedCaseInsensitiveContains(query) }
                            .sorted { $0.1 < $1.1 }
                        return (rows.count, Array(rows.prefix(limit).map(\.0)))
                    }.value
                    guard !Task.isCancelled else { return }
                    total = result.0; sources = result.1
                } catch { }
            }
    }
    private var footerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
    }
    private func row(_ source: CollectionExchangeLocalTrack, identifier: String) -> some View {
        let used = model.isAssignedElsewhere(source.reference.id, than: track.id)
        return Button { model.assign(source, to: track.id); dismiss() } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: source.reference.displayName).font(.headline).lineLimit(2)
                Text(verbatim: CollectionExchangeView.localSourceDescription(source.reference)).font(.caption).lineLimit(2).truncationMode(.middle)
                if used { Text("Bereits einem anderen Titel zugeordnet").font(.caption) }
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(8)
        }.collectionTrackRowStyle().disabled(used || model.isBusy).accessibilityIdentifier(identifier)
    }
}

private extension View {
    @ViewBuilder func collectionTrackRowStyle() -> some View {
        #if os(macOS)
        buttonStyle(CollectionExchangeTrackRowButtonStyle())
        #else
        buttonStyle(.bordered).buttonBorderShape(.roundedRectangle)
        #endif
    }
}

#if os(macOS)
private struct CollectionExchangeTrackRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        // Der native macOS-Bezel begrenzt mehrzeilige Labels auf die Control-Höhe.
        configuration.label.fixedSize(horizontal: false, vertical: true)
            .background(.quaternary.opacity(configuration.isPressed ? 0.65 : 0.25), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.5)
    }
}
#endif

private struct CollectionExchangeErrorText: View {
    let error: Error
    var body: some View {
        if case CollectionExchangeError.unsupportedVersion(let version) = error {
            Text("Nicht unterstützte Dateiversion: \(version)")
        } else if error is CollectionExchangeError || error is CollectionExchangePersistenceError {
            Text(LocalizedStringKey(error.localizedDescription))
        } else { Text(verbatim: error.localizedDescription) }
    }
}

public struct CollectionExchangeRecoveryView: View {
    private let error: Error
    private let retry: () -> Void
    public init(error: Error, retry: @escaping () -> Void) { self.error = error; self.retry = retry }
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
            Label("Sammlung wiederherstellen", systemImage: "exclamationmark.triangle").font(.title2.bold())
            Text("Die letzte Sammlungsübernahme konnte nicht vollständig wiederhergestellt werden. Die vorhandenen Dateien bleiben erhalten. Bitte erneut versuchen oder die App neu starten.")
                .fixedSize(horizontal: false, vertical: true)
            CollectionExchangeErrorText(error: error).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Erneut versuchen", action: retry).buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("collectionRecoveryRetry")
        }.padding(24).frame(maxWidth: 640, alignment: .leading).accessibilityIdentifier("collectionRecoveryError")
    }
}
#endif

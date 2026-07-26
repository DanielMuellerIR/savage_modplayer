import SavageModPlayerCore
import SwiftUI
import UniformTypeIdentifiers

// Das Blatt fuer den Ordner-Import: Ordner waehlen, zusehen, abbrechen,
// Bericht lesen.
//
// Einbindung durch die spaetere Oberflaeche:
//
//     .sheet(isPresented: $showImport) { LibraryImportSheet() }
//
// Gebraucht wird nur `AppModel` in der Umgebung (`.environmentObject(model)`,
// wie in SavageModPlayerApp bereits gesetzt). Den Store holt sich das Blatt
// selbst aus dem Modell und beobachtet ihn im inneren `Content` — deshalb muss
// `LibraryStore` NICHT zusaetzlich injiziert werden.
//
// Geschlossen wird ueber `dismiss`, das Blatt braucht also keine eigene
// Bindung. Waehrend eines laufenden Vorgangs laesst es sich nicht wegwischen:
// sonst verschwaende der Nutzer die einzige Abbrechen-Taste und wuesste nicht
// mehr, was seine App gerade tut.
struct LibraryImportSheet: View {
    @EnvironmentObject var model: AppModel

    init() {}

    var body: some View {
        Content(library: model.library)
    }

    // Der eigentliche Inhalt. Er beobachtet den Store direkt — nur so zeichnet
    // SwiftUI bei jedem Fortschrittsschritt neu.
    private struct Content: View {
        @ObservedObject var library: LibraryStore
        @Environment(\.dismiss) private var dismiss
        @State private var isChoosingFolder = false

        // Wie viele Zeilen einer langen Liste hoechstens ausgeschrieben werden.
        // Bei 300 kaputten Dateien will niemand 300 Zeilen scrollen.
        private static let listLimit = 20

        var body: some View {
            NavigationStack {
                List {
                    if library.isBusy {
                        activitySection
                    } else if let report = library.lastReport {
                        reportSection(report)
                    } else {
                        sourceSection
                        pendingSection
                        fileSharingSection
                    }
                }
                .navigationTitle("import.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done") {
                            library.clearLastReport()
                            dismiss()
                        }
                        .disabled(library.isBusy)
                    }
                }
                .interactiveDismissDisabled(library.isBusy)
                .fileImporter(
                    isPresented: $isChoosingFolder,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        library.importFolders(urls)
                    case .failure(let error):
                        library.errorMessage = error.localizedDescription
                    }
                }
                .alert("library.error.title", isPresented: errorBinding) {
                    Button("common.ok", role: .cancel) { library.errorMessage = nil }
                } message: {
                    Text(verbatim: library.errorMessage ?? "")
                }
            }
        }

        // MARK: - Ordner waehlen

        private var sourceSection: some View {
            Section {
                Button {
                    isChoosingFolder = true
                } label: {
                    Label("import.choose.folder", systemImage: "folder.badge.plus")
                }
            } header: {
                Text("import.source.title")
            } footer: {
                Text("import.intro")
            }
        }

        // MARK: - Offene Archive (Weg B)

        @ViewBuilder
        private var pendingSection: some View {
            if !library.pendingArchives.isEmpty {
                Section {
                    Text("import.pending.count \(library.pendingArchives.count)")
                    ForEach(library.pendingArchives.prefix(Self.listLimit), id: \.self) { path in
                        Text(verbatim: path)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if library.pendingArchives.count > Self.listLimit {
                        Text("import.report.more \(library.pendingArchives.count - Self.listLimit)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        library.unpackPendingArchives()
                    } label: {
                        Label("import.pending.unpack", systemImage: "shippingbox")
                    }
                } header: {
                    Text("import.pending.title")
                } footer: {
                    Text("import.pending.hint")
                }
            }
        }

        private var fileSharingSection: some View {
            Section {
                Text("import.filesharing.hint")
            } header: {
                Text("import.filesharing.title")
            }
        }

        // MARK: - Waehrend der Arbeit

        private var activitySection: some View {
            Section {
                if let progress = library.progress, progress.totalFiles > 0 {
                    // Der Zaehler kann die Vorabzaehlung ueberholen: ein Archiv
                    // zaehlt vorher als eine Einheit und bringt hinterher
                    // hunderte Dateien mit. Deshalb wird der Balken gedeckelt.
                    ProgressView(
                        value: Double(min(progress.processedFiles, progress.totalFiles)),
                        total: Double(progress.totalFiles))
                    Text("import.progress.counted \(progress.processedFiles) \(progress.totalFiles)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let progress = library.progress {
                    ProgressView()
                    Text("import.progress.processed \(progress.processedFiles)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }

                if let progress = library.progress {
                    Text(verbatim: progress.currentName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if progress.importedBytes > 0 {
                        Text("import.progress.bytes \(progress.importedBytes.formatted(.byteCount(style: .file)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(role: .destructive) {
                    library.cancelCurrentOperation()
                } label: {
                    Label("common.cancel", systemImage: "xmark.circle")
                }
            } header: {
                Text(Self.activityTitle(library.activity))
            }
        }

        private static func activityTitle(_ activity: LibraryActivity?) -> LocalizedStringKey {
            switch activity {
            case .scanning: return "library.activity.scanning"
            case .importing: return "library.activity.importing"
            case .unpacking: return "library.activity.unpacking"
            case .resetting: return "library.activity.resetting"
            case nil: return "library.activity.importing"
            }
        }

        // MARK: - Bericht

        @ViewBuilder
        private func reportSection(_ report: ImportReport) -> some View {
            Section {
                if report.wasCancelled {
                    Label("import.report.cancelled", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }

                Label("import.report.imported \(report.imported.count)", systemImage: "tray.and.arrow.down")

                if !report.duplicates.isEmpty {
                    Label("import.report.duplicates \(report.duplicates.count)", systemImage: "doc.on.doc")
                }

                if !report.failures.isEmpty {
                    DisclosureGroup {
                        ForEach(Array(report.failures.prefix(Self.listLimit).enumerated()), id: \.offset) { _, failure in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: failure.path)
                                    .font(.footnote)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(verbatim: failure.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if report.failures.count > Self.listLimit {
                            Text("import.report.more \(report.failures.count - Self.listLimit)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label("import.report.failures \(report.failures.count)", systemImage: "exclamationmark.triangle")
                    }
                }

                if report.imported.isEmpty && report.duplicates.isEmpty && report.failures.isEmpty {
                    Text("import.report.empty")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("import.report.title")
            } footer: {
                if !report.duplicates.isEmpty {
                    Text("import.report.duplicates.hint")
                }
            }

            Section {
                Button {
                    library.clearLastReport()
                } label: {
                    Label("import.report.again", systemImage: "arrow.clockwise")
                }
            }
        }

        // MARK: - Fehlerdialog

        private var errorBinding: Binding<Bool> {
            Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } })
        }
    }
}

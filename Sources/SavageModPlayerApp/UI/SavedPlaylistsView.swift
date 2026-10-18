import SwiftUI
import SavageModPlayerCore

struct SavedPlaylistsView: View {
    let playlists: [SavedPlaylist]
    let currentTrackCount: Int
    let writable: Bool
    let errorMessage: String?
    let onCreate: (String) -> Bool
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onOpen: (SavedPlaylist) -> Void
    let onRemove: (UUID, String) -> Void
    let onMove: (UUID, String, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var name = ""
    @State private var deleteID: UUID?

    private var selected: SavedPlaylist? { playlists.first { $0.id == selectedID } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Gespeicherte Playlists").font(.title2.bold())
            Text("Die Listen verweisen auf Originaldateien und Archive. Musikdateien werden nicht dauerhaft kopiert.")
                .font(.callout).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(playlists) { saved in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(saved.name).lineLimit(1)
                            Text("\(saved.tracks.count) Titel").font(.caption).foregroundStyle(.secondary)
                        }.tag(saved.id).padding(.vertical, 3)
                    }
                }.frame(minWidth: 180, idealWidth: 210)
                VStack(alignment: .leading, spacing: 8) {
                    if let selected {
                        Text(selected.name).font(.headline)
                        List {
                            ForEach(Array(selected.tracks.enumerated()), id: \.element.id) { index, track in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.displayName).lineLimit(1)
                                        Text(track.source.archiveMembers.last
                                             ?? track.source.location.deletingLastPathComponent().lastPathComponent)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }.help(([track.source.location.path] + track.source.archiveMembers).joined(separator: " → "))
                                    Spacer()
                                    Button { onMove(selected.id, track.id, -1) } label: {
                                        Image(systemName: "arrow.up").frame(width: 20, height: 20)
                                    }.disabled(index == 0 || !writable).help("Titel nach oben")
                                        .accessibilityLabel("Titel nach oben")
                                    Button { onMove(selected.id, track.id, 1) } label: {
                                        Image(systemName: "arrow.down").frame(width: 20, height: 20)
                                    }.disabled(index == selected.tracks.count - 1 || !writable).help("Titel nach unten")
                                        .accessibilityLabel("Titel nach unten")
                                    Button { onRemove(selected.id, track.id) } label: {
                                        Image(systemName: "minus.circle").frame(width: 20, height: 20)
                                    }.disabled(!writable).help("Nur aus dieser Playlist entfernen")
                                        .accessibilityLabel("Titel aus Playlist entfernen")
                                }.buttonStyle(.borderless)
                            }
                        }
                        HStack {
                            Button("Playlist öffnen") { onOpen(selected) }.disabled(selected.tracks.isEmpty)
                            Spacer()
                            Button("Löschen…") { deleteID = selected.id }.disabled(!writable)
                        }
                    } else {
                        Text(playlists.isEmpty ? "Noch keine gespeicherte Playlist." : "Eine Playlist auswählen.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(minWidth: 350).padding(.leading, 8)
            }.frame(minHeight: 250)
            HStack {
                TextField("Name der Playlist", text: $name).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("saved-playlist-name")
                Button("Umbenennen") {
                    if let selectedID { onRename(selectedID, trimmedName) }
                }.disabled(selected == nil || trimmedName.isEmpty || !writable)
                Button("Aktuelle Titel speichern (\(currentTrackCount))") {
                    if onCreate(trimmedName) { name = "" }
                }.disabled(currentTrackCount == 0 || trimmedName.isEmpty || !writable)
            }
            HStack {
                Text("Weitere Titel: Rechtsklick auf einen Titel → Zu Playlist hinzufügen.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(minWidth: 680, idealWidth: 720, minHeight: 460)
        .onChange(of: selectedID) { _ in name = selected?.name ?? "" }
        .alert("Playlist löschen?", isPresented: Binding(
            get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Abbrechen", role: .cancel) { deleteID = nil }
            Button("Löschen", role: .destructive) {
                if let deleteID { onDelete(deleteID) }
                selectedID = nil; deleteID = nil; name = ""
            }
        } message: { Text("Nur die gespeicherte Liste wird entfernt. Musikdateien bleiben erhalten.") }
    }
}

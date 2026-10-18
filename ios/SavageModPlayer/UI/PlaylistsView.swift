import SavageModPlayerCore
import SwiftUI

struct PlaylistsView: View {
    @ObservedObject var store: PlaylistCollectionStore
    @ObservedObject var library: LibraryStore
    @ObservedObject var player: PlaybackEngine
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var deleteID: UUID?

    var body: some View {
        NavigationStack {
            List {
                if let key = store.errorMessageKey {
                    Label(LocalizedStringKey(key), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Section("playlists.create") {
                    TextField("playlists.name", text: $newName)
                        .accessibilityIdentifier("playlist-new-name")
                        .disabled(!store.canWrite)
                    Button("playlists.create", systemImage: "plus") {
                        if store.create(name: newName) != nil { newName = "" }
                    }
                    .disabled(!store.canWrite || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(store.canWrite ? Color.accentColor : Color.secondary)
                    .accessibilityIdentifier("playlist-create")
                }
                Section("playlists.title") {
                    ForEach(store.document.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(id: playlist.id, store: store, library: library, player: player)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: playlist.name)
                                Text("playlists.trackCount \(playlist.tracks.count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("playlists.delete", role: .destructive) { deleteID = playlist.id }
                                .disabled(!store.canWrite)
                        }
                    }
                    if store.document.playlists.isEmpty {
                        Text("playlists.empty").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("playlists.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
            .confirmationDialog("playlists.delete.confirm", isPresented: Binding(
                get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
                    Button("playlists.delete", role: .destructive) {
                        if let deleteID { store.delete(id: deleteID) }
                        deleteID = nil
                    }
            }
        }
    }
}

struct PlaylistDetailView: View {
    let id: UUID
    @ObservedObject var store: PlaylistCollectionStore
    @ObservedObject var library: LibraryStore
    @ObservedObject var player: PlaybackEngine
    @State private var showRename = false
    @State private var name = ""
    @State var editMode: EditMode = .inactive

    private var playlist: SavedPlaylist? { store.document.playlists.first { $0.id == id } }

    var body: some View {
        if let playlist {
            let available = PlaylistCollectionStore.resolve(playlist, in: library)
            List {
                if let key = store.errorMessageKey {
                    Label(LocalizedStringKey(key), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Section {
                    Button("playlists.play", systemImage: "play.fill") {
                        player.setExplicitQueue(available)
                        if let track = available.first { player.play(track) }
                    }
                    .disabled(available.isEmpty)
                    .accessibilityIdentifier("playlist-play")
                    if available.count < playlist.tracks.count {
                        Label("playlists.missing \(playlist.tracks.count - available.count)",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if playlist.tracks.isEmpty { Text("playlists.add.hint").foregroundStyle(.secondary) }
                }
                Section("playlists.tracks") {
                    ForEach(playlist.tracks) { reference in
                        let path = reference.source.libraryRelativePath ?? ""
                        let track = library.track(forRelativePath: path)
                        Button {
                            guard let track else { return }
                            player.setExplicitQueue(available)
                            player.play(track)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: reference.displayName)
                                    .foregroundStyle(track == nil ? .secondary : .primary)
                                Text(verbatim: path).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if let track {
                                Button("queue.next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                                    player.enqueue(track, next: true)
                                }
                                Button("queue.add", systemImage: "text.badge.plus") { player.enqueue(track) }
                            }
                        }
                    }
                    .onDelete { store.removeTracks(from: id, at: $0) }
                    .onMove { store.moveTracks(in: id, from: $0, to: $1) }
                    .deleteDisabled(!store.canWrite)
                    .moveDisabled(!store.canWrite)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(playlist.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if editMode.isEditing {
                        Button("common.done") { withAnimation { editMode = .inactive } }
                    } else {
                        Menu {
                            Button("playlists.rename", systemImage: "pencil") {
                                name = playlist.name; showRename = true
                            }
                            Button("playlists.edit", systemImage: "arrow.up.arrow.down") {
                                withAnimation { editMode = .active }
                            }
                        } label: { Label("playlists.options", systemImage: "ellipsis.circle") }
                        .disabled(!store.canWrite)
                    }
                }
            }
            .alert("playlists.rename", isPresented: $showRename) {
                TextField("playlists.name", text: $name)
                Button("common.cancel", role: .cancel) { }
                Button("common.save") { store.rename(id: id, name: name) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct PendingQueueView: View {
    @ObservedObject var player: PlaybackEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(player.pendingQueue.items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: item.track.displayName)
                                Text(verbatim: item.track.source.libraryRelativePath ?? "")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Button { player.moveQueued(id: item.id, by: -1) } label: {
                                Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("queue.up").disabled(index == 0)
                            Button { player.moveQueued(id: item.id, by: 1) } label: {
                                Image(systemName: "arrow.down").frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("queue.down")
                            .disabled(index == player.pendingQueue.items.count - 1)
                        }
                        .buttonStyle(.borderless)
                        .swipeActions {
                            Button("queue.remove", role: .destructive) { player.removeQueued(id: item.id) }
                        }
                    }
                    if player.pendingQueue.items.isEmpty { Text("queue.empty").foregroundStyle(.secondary) }
                } footer: { Text("queue.session.hint") }
            }
            .navigationTitle("queue.title")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("queue.clear", role: .destructive) { player.clearQueued() }
                        .disabled(player.pendingQueue.items.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() } }
            }
        }
    }
}

import Foundation
import SavageModPlayerCore

struct DesktopNotesEvent: Encodable {
    struct Note: Encodable {
        let key: Int
        let channel: Int
        let start: Double
        var end: Double
        let isOpen: Bool

        init(_ value: PreviewNote) {
            key = value.key
            channel = value.channel
            start = value.start
            end = value.end
            isOpen = value.isOpen
        }
    }

    let event = DesktopEvent.notes.rawValue
    let time: Double
    let notes: [Note]
    let overflow: Bool
    let preparing: Bool
}

@MainActor
final class DesktopNotePreview {
    var visible = false

    private var commandCount = 0
    private var revision = UUID()
    private var task: Task<Void, Never>?
    private var notes: [DesktopNotesEvent.Note] = []
    private var worker = NotePreviewWorker()
    private var sourceID: UUID?
    private var preparedThrough = 0.0
    private var nextSongEnd: Double?

    func cancel() {
        task?.cancel()
    }

    func update(source: NotePreviewSource?, loopingTrack: Bool) -> DesktopNotesEvent {
        guard let source else {
            resetTimeline()
            sourceID = nil
            return .init(time: 0, notes: [], overflow: false, preparing: false)
        }
        let time = Double(source.exchange.frame) / source.configuration.sampleRate
        if sourceID != source.id {
            resetTimeline()
            sourceID = source.id
            worker = NotePreviewWorker()
            commandCount = 0
        }
        let commands = source.collectCommands()
        if commands.count != commandCount {
            resetTimeline()
            commandCount = commands.count
        }

        let displayed: [DesktopNotesEvent.Note]
        if !loopingTrack, let end = nextSongEnd {
            displayed = notes.compactMap { note in
                guard note.start < end else { return nil }
                var clipped = note
                clipped.end = min(note.end, end)
                return clipped
            }
        } else {
            displayed = notes
        }
        let payload = DesktopNotesEvent(time: time, notes: displayed,
            overflow: source.exchange.hasOverflowed, preparing: task != nil)
        if task == nil, preparedThrough < time + 9 {
            prepare(source: source, commands: commands, time: time)
        }
        return payload
    }

    private func resetTimeline() {
        task?.cancel()
        task = nil
        revision = UUID()
        preparedThrough = 0
        notes = []
        nextSongEnd = nil
    }

    private func prepare(source: NotePreviewSource, commands: [NotePreviewCommand], time: Double) {
        let worker = self.worker
        let revision = self.revision
        task = Task { [weak self] in
            defer {
                if let self, self.revision == revision { task = nil }
            }
            guard let snapshot = try? await worker.preview(source: source, commands: commands,
                                                          currentTime: time, horizon: 10),
                  let self, !Task.isCancelled, sourceID == source.id, self.revision == revision else { return }
            notes = snapshot.notes.map(DesktopNotesEvent.Note.init)
            nextSongEnd = snapshot.nextSongEnd
            preparedThrough = snapshot.preparedThrough
        }
    }
}

import Foundation
import SavageModPlayerCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

@MainActor
final class DesktopExports {
    private let player: ModPlayerCoordinator
    private let temporary: URL
    private let emit: @MainActor (DesktopEvent, [String: Any]) -> Void
    private var exportTask: Task<Void, Never>?
    private var exportModule: Mod?
    private var exportOptions = ChannelStemExportOptions()

    var isRunning: Bool { exportTask != nil }

    init(player: ModPlayerCoordinator, temporary: URL,
         emit: @escaping @MainActor (DesktopEvent, [String: Any]) -> Void) {
        self.player = player
        self.temporary = temporary
        self.emit = emit
    }

    func capturePlayback() {
        exportModule = player.activeMod
        exportOptions = .init(
            stereoSeparation: player.stereoSeparation, useInterpolation: player.useInterpolation, palClock: player.palClock,
            mutedChannels: (0..<player.channelCount).filter { player.isMuted(channelIndex: $0) },
            soloChannels: (0..<player.channelCount).filter { player.isSoloed(channelIndex: $0) })
        emit(.exportPrepared, ["title": player.trackName])
    }

    func cancel() { exportTask?.cancel() }
    func finish() async { await exportTask?.value }

    func beginWAV(_ v: DesktopRequest) {
        guard !isRunning, let mod = exportModule ?? player.activeMod, let path = v[.path]?.string else { return }
        let output: ChannelStemRenderer.Output = (v[.kind]?.string == "stems") ? .channelStems : .stereoMix
        let duration = v[.seconds]?.number ?? 180
        guard (0...600).contains(duration) else {
            emit(.error, ["message": "Die Exportdauer muss zwischen 0 und 600 Sekunden liegen."])
            return
        }
        var options = exportOptions
        options.maximumSeconds = duration
        let capturedOptions = options
        let destination = URL(fileURLWithPath: path)
        let expected: WAVStamp?
        do { expected = try Self.wavStamp(destination, overwrite: output == .stereoMix && v[.overwrite]?.bool == true) }
        catch { emit(.error, ["message": error.localizedDescription]); return }
        let owner = self
        let coordinator = player
        exportTask = Task { [weak self] in
            let worker = Task.detached {
                if output == .stereoMix {
                    let staging = destination.deletingLastPathComponent().appendingPathComponent(".savage-mix-\(UUID()).wav")
                    defer { try? FileManager.default.removeItem(at: staging) }
                    try coordinator.exportActiveModToWav(mod: mod, stereoSeparation: capturedOptions.stereoSeparation,
                        useInterpolation: capturedOptions.useInterpolation, palClock: capturedOptions.palClock,
                        destinationURL: staging, durationSeconds: capturedOptions.maximumSeconds)
                    try Self.publishWAV(staging, to: destination, replacing: expected)
                    return ["path": path] as [String: String]
                }
                _ = try ChannelStemRenderer.export(mod: mod, to: destination, options: capturedOptions, output: output) { progress in
                    Task { @MainActor in owner.emit(.progress, ["value": progress]) }
                }
                return ["path": path]
            }
            do {
                let report = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                self?.emit(.complete, ["path": path, "report": report])
            } catch is CancellationError { self?.emit(.cancelled, [:]) }
            catch { self?.emit(.error, ["message": error.localizedDescription]) }
            self?.exportTask = nil
        }
    }
    struct WAVStamp: Sendable, Equatable {
        let inode: UInt64, size: UInt64
        let modified: Date
    }
    nonisolated static func wavStamp(_ url: URL, overwrite: Bool) throws -> WAVStamp? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard overwrite else { throw CocoaError(.fileWriteFileExists) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let inode = attributes[.systemFileNumber] as? NSNumber, let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { throw CocoaError(.fileWriteFileExists) }
        return WAVStamp(inode: inode.uint64Value, size: size.uint64Value, modified: modified)
    }
    nonisolated static func publishWAV(_ source: URL, to destination: URL, replacing expected: WAVStamp?) throws {
        try Task.checkCancellation()
        if let expected {
            guard try wavStamp(destination, overwrite: true) == expected else {
                throw NSError(domain: "SavageDesktop", code: 2, userInfo: [NSLocalizedDescriptionKey: "Das Ziel wurde während des Exports geändert und bleibt erhalten."])
            }
            let result = source.path.withCString { from in destination.path.withCString { to in rename(from, to) } }
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } else { try FileManager.default.linkItem(at: source, to: destination) }
    }
    func beginVideo(_ v: DesktopRequest, preview: Bool = false, light: Bool) {
        guard !isRunning, let mod = exportModule ?? player.activeMod else { return }
        guard let path = preview ? temporary.appendingPathComponent("preview-\(UUID()).mov").path : v[.path]?.string else { return }
        var audio = exportOptions; audio.sampleRate = 48_000; audio.maximumSeconds = preview ? 5 : (v[.seconds]?.number ?? 600)
        let options = NoteRainVideoOptions(width: v[.width]?.integer ?? 1280, height: v[.height]?.integer ?? 720,
            framesPerSecond: v[.fps]?.integer ?? 30, lookaheadSeconds: v[.horizon]?.integer ?? 4,
            keyRange: 0...119, appearance: (v[.light]?.bool ?? light) ? .light : .dark,
            quality: v[.compact]?.bool == true ? .compact : .high, audio: audio)
        let owner = self, destination = URL(fileURLWithPath: path)
        #if os(Linux)
        guard let renderer = ProcessInfo.processInfo.environment["SAVAGE_VIDEO_RENDERER"] else {
            emit(.error, ["message": "Der Qt-Videoencoder ist nicht konfiguriert."])
            return
        }
        #endif
        if preview { emit(.videoPreviewState, ["active": true]) }
        exportTask = Task { [weak self] in
            let worker = Task.detached {
                let progress: @Sendable (Double) -> Void = { value in
                    Task { @MainActor in owner.emit(.progress, ["value": value]) }
                }
                #if os(Linux)
                return try LinuxNoteRainVideoRenderer.export(mod: mod, to: destination, options: options,
                    renderer: URL(fileURLWithPath: renderer), progress: progress)
                #else
                return try NoteRainVideoRenderer.export(mod: mod, to: destination, options: options, progress: progress)
                #endif
            }
            do {
                let report = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                self?.emit(preview ? .videoPreview : .complete, ["path": path, "report": desktopJSONObject(report)])
            } catch is CancellationError { self?.emit(.cancelled, [:]) }
            catch { self?.emit(.error, ["message": error.localizedDescription]) }
            if preview { self?.emit(.videoPreviewState, ["active": false]) }
            self?.exportTask = nil
        }
    }
    func beginBatch(items: [BatchWAVExportItem], path: String, settings: BatchWAVExportSettings) {
        guard !isRunning else { return }
        let owner = self
        exportTask = Task { [weak self] in
            let worker = Task.detached {
                try BatchWAVExporter.export(items: items, to: URL(fileURLWithPath: path), settings: settings) { progress in
                    Task { @MainActor in owner.emit(.progress, ["value": progress.fraction, "title": progress.sourceName]) }
                }
            }
            do {
                let report = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                self?.emit(.complete, ["path": path, "report": desktopJSONObject(report)])
            } catch is CancellationError { self?.emit(.cancelled, [:]) }
            catch { self?.emit(.error, ["message": error.localizedDescription]) }
            self?.exportTask = nil
        }
    }
}

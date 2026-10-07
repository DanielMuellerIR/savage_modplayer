import Foundation
import SavageModPlayerCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// ============================================================================
// Echtzeit-Wiedergabe von einem oder mehreren Modulen, mit Tastatursteuerung.
//
// Ein Titel und eine ganze Playlist laufen bewusst durch denselben Code: Eine
// Playlist ist hier nur eine Liste mit mehr als einem Eintrag. Damit gibt es
// keinen zweiten Wiedergabepfad, der auseinanderlaufen koennte.
//
// Tastatursteuerung braucht ein Terminal. Unter Linux kann zusätzlich MPRIS
// über den Sitzungsbus steuern; ohne beides läuft der Titel bis zum Ende.
// ============================================================================

/// Wie ein einzelner Titel geendet hat.
private enum TrackOutcome {
    /// Song zu Ende (oder Zeitlimit erreicht).
    case finished
    case nextRequested
    case previousRequested
    case restartRequested
    case quitRequested
    case failed(String)
}

enum RegularInputError: Error, LocalizedError {
    case openFailed(String)
    case inspectFailed(String)
    case notRegular
    case configureFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let detail):
            return "Datei liess sich nicht oeffnen: \(detail)"
        case .inspectFailed(let detail):
            return "Dateityp liess sich nicht bestimmen: \(detail)"
        case .notRegular:
            return "Quelle ist keine reguläre Datei."
        case .configureFailed(let detail):
            return "Dateizugriff liess sich nicht vorbereiten: \(detail)"
        }
    }
}

/// Oeffnet direkte CLI-Eingaben zunaechst nichtblockierend und prueft danach
/// mit `fstat` GENAU den geoeffneten Deskriptor. Eine FIFO mit Modulendung darf
/// dadurch weder schon in `open` auf einen Schreiber warten noch zwischen einer
/// Pfadpruefung und dem eigentlichen Lesen untergeschoben werden.
func readRegularInput(at url: URL) throws -> Data {
    let descriptor = url.path.withCString { path in
        open(path, O_RDONLY | O_NONBLOCK)
    }
    guard descriptor >= 0 else {
        throw RegularInputError.openFailed(String(cString: strerror(errno)))
    }
    var descriptorNeedsClose = true
    defer {
        if descriptorNeedsClose { _ = close(descriptor) }
    }

    var info = stat()
    guard fstat(descriptor, &info) == 0 else {
        throw RegularInputError.inspectFailed(String(cString: strerror(errno)))
    }
    guard (info.st_mode & S_IFMT) == S_IFREG else {
        throw RegularInputError.notRegular
    }

    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
        throw RegularInputError.configureFailed(String(cString: strerror(errno)))
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    descriptorNeedsClose = false
    return try handle.readToEnd() ?? Data()
}

/// Sammelt alle spielbaren Module unterhalb eines Ordners, sortiert nach Pfad.
///
/// Bewusst direkt enumeriert statt ueber `PlaylistScanner.collectEntries`:
/// Dieser Weg packt nichts aus und legt kein Temp-Verzeichnis an — weder
/// `--list` noch die Wiedergabe sollen etwas auf die Platte schreiben.
func playableModules(in directory: URL) -> [URL]? {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }
    var found: [URL] = []
    while let fileURL = enumerator.nextObject() as? URL {
        // Die Endung allein reicht nicht: Ein Ordner `sammlung.mod` wurde
        // bislang aufgelistet, eine FIFO `stream.xm` bei --play sogar mit
        // Data(contentsOf:) geoeffnet und konnte dadurch unbegrenzt blockieren.
        // Symlinks sind ebenfalls keine regulaeren Dateien; Foundation meldet
        // sie ueber diesen Wert deshalb als false.
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        if values?.isRegularFile == true, PlaylistScanner.isModFile(fileURL) {
            found.append(fileURL)
        }
    }
    return found.sorted { $0.path < $1.path }
}

/// Spielt die Module der Reihe nach ueber die Audio-Ausgabe der Plattform.
///
/// - Returns: Der Exit-Code des Prozesses: 0, wenn mindestens ein Titel lief,
///   sonst 1.
func runRealtimePlayback(
    modules: [URL],
    seconds: Double,
    useInterpolation: Bool,
    quiet: Bool
) -> Int32 {
    let format = PCMSinkFactory.preferredFormat(channels: 2)
    let frameLimit: UInt64?
    do {
        // Derselbe dokumentierte Vertrag wie im Offline-Pfad: 0 = ganzer Song,
        // aber hoechstens 600 s. Bei einer Playlist gilt er je Titel.
        frameLimit = try ModuleRenderer.liveFrameLimit(
            sampleRate: format.sampleRate,
            maxDurationSeconds: seconds > 0 ? seconds : 600.0
        )
    } catch {
        reportError("Wiedergabe-Fehler: \(error.localizedDescription)")
        return 1
    }

    // Ctrl-C und `kill` sollen die Audio-Ausgabe schliessen, statt den Prozess
    // mittendrin abzuschneiden — und sie sollen ueberhaupt wirken, auch ohne
    // Terminal (siehe InterruptWatch).
    InterruptWatch.install()

    let keyboard = TerminalKeyboard.makeIfInteractive()
    defer { keyboard?.restore() }
    if keyboard != nil && !quiet {
        reportError("Tasten: [Leertaste/p] Pause  [n/→] nächster  [b/←] vorheriger  [q] Ende")
    }

    var index = 0
    var playedAnything = false
    var mode = PlaybackMode.playing
    let media = DesktopMediaControls.make(format: format)

    while index >= 0 && index < modules.count {
        let url = modules[index]
        guard let mod = loadModule(at: url) else {
            index += 1
            continue
        }
        let position = modules.count > 1 ? "[\(index + 1)/\(modules.count)] " : ""
        let title = mod.name.isEmpty ? url.lastPathComponent : mod.name
        media?.setTrack(title: title, url: url.absoluteString, index: index, count: modules.count)
        report(
            "\(position)Spiele '\(title)' (\(mod.format), \(mod.channelCount) ch) "
            + "@ \(Int(format.sampleRate)) Hz …",
            quiet: quiet
        )

        switch playSingleTrack(
            mod: mod, format: format, frameLimit: frameLimit,
            useInterpolation: useInterpolation, quiet: quiet, keyboard: keyboard,
            media: media, mode: &mode
        ) {
        case .finished:
            playedAnything = true
            index += 1
        case .nextRequested:
            playedAnything = true
            index += 1
        case .previousRequested:
            playedAnything = true
            // Am Anfang der Liste bleibt "zurueck" beim aktuellen Titel und
            // startet ihn neu — das ist das Verhalten jedes Players.
            index = max(0, index - 1)
        case .restartRequested:
            playedAnything = true
        case .quitRequested:
            report("Wiedergabe beendet.", quiet: quiet)
            // Ein per Taste beendeter Lauf ist ein Erfolg; ein abgebrochener
            // meldet den ueblichen Signal-Exit-Code, damit Skripte den
            // Unterschied sehen.
            return InterruptWatch.wasRequested ? 130 : 0
        case .failed(let detail):
            reportError("Wiedergabe abgebrochen: \(detail)")
            return 1
        }
    }

    if !playedAnything {
        // Die einzelnen Gruende stehen schon oben; hier bleibt nur das Fazit,
        // damit der Exit-Code 1 nicht unerklaert dasteht.
        reportError("Kein Modul konnte abgespielt werden.")
        return 1
    }
    report("Wiedergabe beendet.", quiet: quiet)
    return 0
}

// MARK: - Ein Titel

private func playSingleTrack(
    mod: Mod,
    format: PCMFormat,
    frameLimit: UInt64?,
    useInterpolation: Bool,
    quiet: Bool,
    keyboard: TerminalKeyboard?,
    media: DesktopMediaControls?,
    mode: inout PlaybackMode
) -> TrackOutcome {
    let source = ModulePCMSource(
        mod: mod, format: format, maxFrames: frameLimit, useInterpolation: useInterpolation
    )
    let sink = PCMSinkFactory.makeDefault(format: format)
    // Das Warten auf das Songende laeuft auf einem eigenen Thread, damit der
    // Haupt-Thread regelmaessig nach Tasten und nach Ctrl-C sehen kann. Der
    // Grund wird nicht weitergereicht: `waitUntilFinished()` liefert ihn laut
    // Vertrag bei jedem weiteren Aufruf erneut und blockiert dann nicht mehr.
    let finished = DispatchSemaphore(value: 0)
    var hasStarted = false
    func startPlayback() throws {
        let render = source.renderBlock()
        try sink.start(render: media?.meter(render, channels: format.channels) ?? render)
        Thread.detachNewThread {
            _ = sink.waitUntilFinished()
            finished.signal()
        }
    }
    if mode == .playing {
        do {
            try startPlayback()
            hasStarted = true
        } catch {
            return .failed(error.localizedDescription)
        }
    }
    media?.setStatus(mode)

    while true {
        // Ohne Tastatur wartet die Schleife hier kurz; mit Tastatur uebernimmt
        // das die Tastenabfrage weiter unten.
        let pollInterval: DispatchTime = keyboard == nil ? .now() + 0.1 : .now()
        if finished.wait(timeout: pollInterval) == .success {
            return outcome(for: sink.waitUntilFinished())
        }
        if InterruptWatch.wasRequested {
            return stopAndReport(sink, as: .quitRequested)
        }
        var command = media?.poll()
        if command == nil, let key = keyboard?.waitForCommand(timeoutMilliseconds: 100) {
            switch key {
            case .togglePause: command = .togglePause
            case .nextTrack: command = .nextTrack
            case .previousTrack: command = .previousTrack
            case .quit: command = .quit
            }
        }
        if case .togglePause = command { command = mode == .playing ? .pause : .play }
        switch command {
        case .play:
            guard mode != .playing else { continue }
            do {
                if hasStarted { try sink.resume() }
                else { try startPlayback(); hasStarted = true }
                mode = .playing
            } catch { return stopAndReport(sink, as: .failed(error.localizedDescription)) }
            media?.setStatus(mode)
            report("Weiter.", quiet: quiet)
        case .pause:
            guard mode == .playing else { continue }
            do { try sink.pause() }
            catch { return stopAndReport(sink, as: .failed(error.localizedDescription)) }
            mode = .paused
            media?.setStatus(mode)
            report("Pause.", quiet: quiet)
        case .stop:
            guard mode != .stopped else { continue }
            mode = .stopped
            media?.setStatus(mode)
            return stopAndReport(sink, as: .restartRequested)
        case .nextTrack:
            return stopAndReport(sink, as: .nextRequested)
        case .previousTrack:
            return stopAndReport(sink, as: .previousRequested)
        case .quit:
            return stopAndReport(sink, as: .quitRequested)
        case .togglePause, nil:
            continue
        }
    }
}

/// Haelt die Ausgabe an und wartet ab, bis sie wirklich steht — sonst griffe
/// der naechste Titel auf ein Geraet zu, das noch der alte Sink haelt.
private func stopAndReport(_ sink: PCMSink, as outcome: TrackOutcome) -> TrackOutcome {
    sink.stop()
    _ = sink.waitUntilFinished()
    return outcome
}

private func outcome(for reason: PCMSinkFinishReason) -> TrackOutcome {
    switch reason {
    case .sourceFinished, .stopped, .outputClosed:
        return .finished
    case .failed(let detail):
        return .failed(detail)
    case .notStarted:
        return .failed("Die Audio-Ausgabe startete nicht.")
    }
}

// MARK: - Laden und Ausgabe

/// Liest und parst ein Modul. Ein kaputter Titel ist kein Abbruchgrund: Er wird
/// gemeldet und uebersprungen. Bleibt am Ende kein einziger spielbarer Titel
/// uebrig, endet der Prozess mit 1 — die Meldung geht also nie verloren.
private func loadModule(at url: URL) -> Mod? {
    let data: Data
    do {
        data = try readRegularInput(at: url)
    } catch {
        reportError("Datei nicht lesbar: \(url.path): \(error.localizedDescription)")
        return nil
    }
    do {
        return try ModuleLoader.parse(data: data)
    } catch {
        reportError("Parse-Fehler bei '\(url.lastPathComponent)': \(error.localizedDescription)")
        return nil
    }
}

private func report(_ message: String, quiet: Bool) {
    guard !quiet else { return }
    reportError(message)
}

/// Alle Meldungen gehen nach stderr — stdout bleibt fuer Nutzdaten frei
/// (`--stdout`, `--list`).
private func reportError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

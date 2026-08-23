import Foundation
import SavageModPlayerCore

// ============================================================================
// Echtzeit-Wiedergabe von einem oder mehreren Modulen, mit Tastatursteuerung.
//
// Ein Titel und eine ganze Playlist laufen bewusst durch denselben Code: Eine
// Playlist ist hier nur eine Liste mit mehr als einem Eintrag. Damit gibt es
// keinen zweiten Wiedergabepfad, der auseinanderlaufen koennte.
//
// Die Steuerung ist optional. Ohne Terminal an stdin (Pipe, CI, Cron) gibt es
// nichts zu bedienen; dann wartet der Ablauf schlicht auf das Songende, genau
// wie vor der Tastatursteuerung.
// ============================================================================

/// Wie ein einzelner Titel geendet hat.
private enum TrackOutcome {
    /// Song zu Ende (oder Zeitlimit erreicht).
    case finished
    case nextRequested
    case previousRequested
    case quitRequested
    case failed(String)
}

/// Sammelt alle spielbaren Module unterhalb eines Ordners, sortiert nach Pfad.
///
/// Bewusst direkt enumeriert statt ueber `PlaylistScanner.collectEntries`:
/// Dieser Weg packt nichts aus und legt kein Temp-Verzeichnis an — weder
/// `--list` noch die Wiedergabe sollen etwas auf die Platte schreiben.
func playableModules(in directory: URL) -> [URL]? {
    guard let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    ) else {
        return nil
    }
    var found: [URL] = []
    while let fileURL = enumerator.nextObject() as? URL {
        if PlaylistScanner.isModFile(fileURL) { found.append(fileURL) }
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

    while index >= 0 && index < modules.count {
        let url = modules[index]
        guard let mod = loadModule(at: url) else {
            index += 1
            continue
        }
        let position = modules.count > 1 ? "[\(index + 1)/\(modules.count)] " : ""
        let title = mod.name.isEmpty ? url.lastPathComponent : mod.name
        report(
            "\(position)Spiele '\(title)' (\(mod.format), \(mod.channelCount) ch) "
            + "@ \(Int(format.sampleRate)) Hz …",
            quiet: quiet
        )

        switch playSingleTrack(
            mod: mod, format: format, frameLimit: frameLimit,
            useInterpolation: useInterpolation, quiet: quiet, keyboard: keyboard
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
    keyboard: TerminalKeyboard?
) -> TrackOutcome {
    let source = ModulePCMSource(
        mod: mod, format: format, maxFrames: frameLimit, useInterpolation: useInterpolation
    )
    let sink = PCMSinkFactory.makeDefault(format: format)
    do {
        try sink.start(render: source.renderBlock())
    } catch {
        return .failed(error.localizedDescription)
    }

    // Das Warten auf das Songende laeuft auf einem eigenen Thread, damit der
    // Haupt-Thread regelmaessig nach Tasten und nach Ctrl-C sehen kann. Der
    // Grund wird nicht weitergereicht: `waitUntilFinished()` liefert ihn laut
    // Vertrag bei jedem weiteren Aufruf erneut und blockiert dann nicht mehr.
    let finished = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        _ = sink.waitUntilFinished()
        finished.signal()
    }

    var isPaused = false
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
        guard let keyboard else { continue }
        switch keyboard.waitForCommand(timeoutMilliseconds: 100) {
        case .togglePause:
            isPaused.toggle()
            do {
                try isPaused ? sink.pause() : sink.resume()
            } catch {
                return .failed(error.localizedDescription)
            }
            report(isPaused ? "Pause." : "Weiter.", quiet: quiet)
        case .nextTrack:
            return stopAndReport(sink, as: .nextRequested)
        case .previousTrack:
            return stopAndReport(sink, as: .previousRequested)
        case .quit:
            return stopAndReport(sink, as: .quitRequested)
        case nil:
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
    guard let data = try? Data(contentsOf: url) else {
        reportError("Datei nicht lesbar: \(url.path)")
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

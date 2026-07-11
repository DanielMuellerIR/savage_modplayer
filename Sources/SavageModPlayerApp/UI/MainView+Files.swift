import SwiftUI
import SavageModPlayerCore
import UniformTypeIdentifiers
import UserNotifications
import MediaPlayer

// Datei- und Playlist-Handling der MainView: Drag&Drop, Laden von Modulen,
// Auto-Load des lokalen Audio-Ordners und Demo-Wiedergabe.
extension MainView {
    // MARK: - Playlists & File Handling
    
    // autoPlay=true startet die Wiedergabe direkt nach dem Laden — genutzt beim
    // App-Start (audio-Ordner), damit sofort etwas klingt. Echte Drag&Drops
    // rufen mit dem Default false auf und laden nur, ohne loszuspielen.
    func handleDroppedURLs(_ urls: [URL], autoPlay: Bool = false) {
        self.errorMessage = nil
        self.compatibilityMessage = nil
        // Dateisystem-Traversal + Kopieren laufen im Hintergrund — ein grosser
        // Ordner-Drop blockierte sonst den Main-Thread (Beachball). Nur die
        // @State-Mutation und das Laden der ersten Datei kehren auf den Main-Thread
        // zurueck.
        DispatchQueue.global(qos: .userInitiated).async {
            // Einsammeln (inkl. Ordner-Rekursion und unsichtbarem Entpacken von
            // Zip/7z-Archiven) uebernimmt der testbare Core-Scanner; hier bleibt
            // nur das Temp-Ziel und die UI-Anbindung.
            let entries = PlaylistScanner.collectEntries(from: urls, tempDir: MainView.newDropTempDir())
            let tree = PlaylistScanner.buildTree(entries)
            let flat = PlaylistScanner.flattenedFiles(tree)
            DispatchQueue.main.async {
                guard !flat.isEmpty else {
                    self.errorMessage = "Keine unterstützten Tracker-Dateien gefunden."
                    return
                }
                let sorted = flat.map(\.url)
                self.playlist = sorted
                self.playlistTree = tree
                self.folderPathByURL = Dictionary(uniqueKeysWithValues: flat.map { ($0.url, $0.folderPath) })
                // Standard: alle Ordner zugeklappt; nur der Pfad zum Start-Titel
                // wird unten via selectPlaylistSong/expandAncestors geoeffnet.
                self.expandedFolders = []
                self.selectedSidebarTab = 0 // Playlist fokussieren

                // Start-Titel bestimmen: ein expliziter "--autoplay <filter>"
                // gewinnt; sonst bei ausgeschaltetem Shuffle der zuletzt gespielte
                // Titel (falls noch in der Liste); sonst bei Shuffle ein Zufalls-
                // Titel, sonst der erste der (sortierten) Liste.
                let filterIndex = Self.autoplayFilterIndex(in: sorted)
                let lastPlayedIndex = self.shuffleEnabled
                    ? nil
                    : sorted.firstIndex(where: { self.cleanFilename($0) == self.lastPlayedSongName })
                let startIndex = filterIndex
                    ?? lastPlayedIndex
                    ?? (self.shuffleEnabled ? Int.random(in: 0..<sorted.count) : 0)

                // Sofort losspielen, wenn der Aufrufer es will (App-Start) oder die
                // Headless-/Agent-Steuerung "--autoplay [filter]" gesetzt ist —
                // Letzteres auch fuer Screenshots und Smoke-Tests ohne Klicks.
                if autoPlay || CommandLine.arguments.contains("--autoplay") {
                    self.selectPlaylistSong(at: startIndex, autoPlay: true)
                } else {
                    self.currentPlaylistIndex = startIndex
                    self.loadModFile(from: sorted[startIndex])
                    self.expandAncestors(of: sorted[startIndex])
                }
            }
        }
    }

    // Liefert den Playlist-Index des ersten Titels, dessen Name den optionalen
    // "--autoplay <filter>"-Parameter enthaelt (nil ohne Filter/Treffer).
    nonisolated private static func autoplayFilterIndex(in urls: [URL]) -> Int? {
        let args = CommandLine.arguments
        guard let flagIndex = args.firstIndex(of: "--autoplay") else { return nil }
        let next = flagIndex + 1
        if next < args.count, !args[next].hasPrefix("--") {
            let filter = args[next].lowercased()
            return urls.firstIndex(where: { $0.lastPathComponent.lowercased().contains(filter) })
        }
        return nil
    }

    // Pro Drop ein eigenes Temp-Unterverzeichnis statt das gemeinsame zu loeschen:
    // sonst entwertet ein neuer Drop die Temp-URLs frueherer Baetche. Das
    // eigentliche Einsammeln/Kopieren/Entpacken macht PlaylistScanner (Core).
    nonisolated private static func newDropTempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ModPlayerTemp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // Loescht die Temp-Kopien frueherer App-Laeufe (ModPlayerTemp/). Wird einmalig
    // beim App-Start gerufen (AppMain.init): die pro-Drop angelegten UUID-
    // Verzeichnisse bleiben innerhalb einer Sitzung bestehen (die Playlist
    // referenziert sie noch), wuerden sich sonst aber ueber Laeufe hinweg
    // unbegrenzt ansammeln.
    nonisolated static func cleanStaleTempRoot() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ModPlayerTemp", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
    }

    // Alle Ordner-Ebenen ueber dem Titel aufklappen, damit der laufende
    // Eintrag in der Baum-Ansicht sichtbar ist. Manuell geoeffnete Ordner
    // bleiben unangetastet (nur einfuegen, nie zuklappen).
    func expandAncestors(of url: URL) {
        guard let components = folderPathByURL[url], !components.isEmpty else { return }
        var path = ""
        for component in components {
            path = path.isEmpty ? component : "\(path)/\(component)"
            expandedFolders.insert(path)
        }
    }

    func selectPlaylistSong(at index: Int, autoPlay: Bool = true) {
        guard index >= 0 && index < playlist.count else { return }
        self.currentPlaylistIndex = index
        let songUrl = playlist[index]
        expandAncestors(of: songUrl)
        if loadModFile(from: songUrl) {
            // Nur abspielen, wenn gewuenscht — sonst startet z.B. Weiterblaettern
            // im pausierten Zustand ungewollt die Wiedergabe.
            if autoPlay { coordinator.play() }
        }
        // "Zuletzt gespielt" wird zentral in loadModFile gepflegt (alle Ladepfade).
    }
    
    @discardableResult
    func loadModFile(from url: URL) -> Bool {
        self.errorMessage = nil
        self.compatibilityMessage = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        
        do {
            let fileData = try Data(contentsOf: url)
            // ModuleLoader erkennt das Format am Inhalt (MOD, S3M, XM und IT).
            let mod = try ModuleLoader.parse(data: fileData)
            // Dateiname (ohne UUID-Praefix der Temp-Kopie und ohne Endung) als
            // Fallback-Titel, falls das Modul kein Titelfeld gesetzt hat.
            let fallbackName = (cleanFilename(url) as NSString).deletingPathExtension
            coordinator.setMod(mod, fallbackName: fallbackName)
            if !mod.compatibilityWarnings.isEmpty {
                self.compatibilityMessage = mod.compatibilityWarnings.joined(separator: "\n")
            }
            // Stabilen Namen fuer "zuletzt gespielt" merken (ueberlebt Neustart).
            self.lastPlayedSongName = cleanFilename(url)
            // "ZULETZT GESPIELT"-Liste hier zentral pflegen, damit JEDER Ladepfad
            // (Playlist-Klick, Weiter/Zurueck, Autostart, Drop, Recent-Klick) sie
            // aktualisiert — vorher nur selectPlaylistSong, weshalb sie oft
            // veraltet stehen blieb. Duplikat zuerst entfernen -> rueckt nach oben.
            recentSongs.removeAll { $0 == url }
            recentSongs.insert(url, at: 0)
            if recentSongs.count > 10 { recentSongs.removeLast() }
            return true
        } catch {
            self.errorMessage = "Parser-Fehler bei '\(cleanFilename(url))': \(error.localizedDescription)"
            print("Parser-Fehler: \(error)")
            return false
        }
    }
    
    func cleanFilename(_ url: URL) -> String {
        let name = url.lastPathComponent
        if name.count > 36 {
            let index = name.index(name.startIndex, offsetBy: 36)
            if name[index] == "_" {
                return String(name[name.index(after: index)...])
            }
        }
        return name
    }
    
    nonisolated private static func isModFile(_ url: URL) -> Bool {
        PlaylistScanner.isModFile(url)
    }

    func loadLocalAudioFolder() {
        let fm = FileManager.default
        var candidateDirs: [URL] = []
        // Primaere Quelle: der in den Einstellungen (Cmd+,) konfigurierte
        // Autoplay-Ordner. Nicht gesetzt = nur die Fallbacks unten.
        if !autoplayFolderPath.isEmpty {
            candidateDirs.append(URL(fileURLWithPath: (autoplayFolderPath as NSString).expandingTildeInPath, isDirectory: true))
        }
        // Fallbacks wie bisher: audio/-Ordner neben Arbeitsverzeichnis bzw. App.
        candidateDirs.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("audio"))
        // Bundle.main.bundlePath ist immer ein (non-optional) String.
        let appDir = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
        candidateDirs.append(appDir.appendingPathComponent("audio"))
        for dir in candidateDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            // Nur nehmen, wenn (rekursiv) wirklich Mods oder Archive drin sind —
            // sonst den naechsten Kandidaten probieren. Den eigentlichen Scan
            // (inkl. Hierarchie + Archive) macht dann handleDroppedURLs.
            guard PlaylistScanner.directoryContainsPlayableContent(dir) else { continue }
            handleDroppedURLs([dir], autoPlay: true)
            return
        }
    }
    
    func triggerDemoPlay() {
        let demoMod = ModParser.generateDemoMod()
        coordinator.setMod(demoMod)
        coordinator.play()
    }

    // Erstes Datei-/Ordner-Argument von der Kommandozeile (`SavageModPlayer <pfad>`).
    // Ignoriert Flags und die Prozess-Serial-Args (`-psn_…`, `-NSDocument…`), die
    // macOS beim Bundle-Start injiziert; nimmt den ersten existierenden Pfad mit
    // unterstützter Endung oder ein Verzeichnis. Ermöglicht headless Auto-Play
    // (Tests/CPU-Messung) ohne GUI-Bedienung.
    static func launchFileArgument() -> URL? {
        for arg in CommandLine.arguments.dropFirst() {
            guard !arg.hasPrefix("-") else { continue }
            let url = URL(fileURLWithPath: arg)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue || ModuleLoader.supportedExtensions.contains(url.pathExtension.lowercased()) {
                return url
            }
        }
        return nil
    }

}

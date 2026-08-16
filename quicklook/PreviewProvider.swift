import Foundation
import QuickLookUI
import UniformTypeIdentifiers

// Principal Class der Quick-Look-Extension (datenbasierte Preview,
// QLIsDataBasedPreview = true in der Info.plist des Appex).
//
// Funktionsweise: Die Extension parst das Tracker-Modul (alle MOD-Varianten
// + S3M/XM/IT über ModuleLoader) und rendert es mit der identischen DSP-Engine des
// Players offline zu WAV-Daten. Quick Look zeigt für die gelieferten
// WAV-Daten den nativen macOS-Audio-Player — damit ist das Modul direkt im
// Finder (Leertaste) abspielbar, inklusive Scrubbing und Lautstärke.
//
// Hinweis zum Build: Dieses File wird NICHT über SwiftPM gebaut, sondern von
// build_app.sh zusammen mit den SavageModPlayerCore-Quellen per swiftc
// in EIN Modul kompiliert (deshalb kein `import SavageModPlayerCore`).
class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    // Quick Look soll unmittelbar als Vorschau reagieren, nicht erst nach einem
    // minutenlangen Komplett-Render. Eine Minute enthält bei Trackern meist den
    // charakteristischen Einstieg und begrenzt CPU, RAM und WAV-Größe zuverlässig.
    private static let previewDurationSeconds = 60.0

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        do {
            let data = try Data(contentsOf: request.fileURL)
            let mod = try ModuleLoader.parse(data: data)
            // Cache-Identitaet aus GENAU den eingelesenen Bytes ableiten —
            // nicht danach erneut aus Pfad/Groesse/Aenderungszeit der URL.
            // Wird die Datei zwischen Lesen und Attributabfrage ersetzt (oder
            // mit gleicher Groesse/Zeit ueberschrieben), verband der alte
            // Schluessel sonst dauerhaft alte Audiodaten mit neuer Identitaet.
            let cacheKey = PreviewCacheIdentity.key(forContents: data)

            // WICHTIG: Die WAV als DATEI-URL liefern, nicht als Daten-Reply.
            // QLPreviewReply(dataOfContentType:) zeigt fuer Audio nur die
            // generische Info-Karte; erst initWithFileURL: (laut Header explizit
            // inkl. UTTypeAudio) bekommt den nativen Audio-Player mit
            // Play/Scrubbing. Die Datei liegt im Sandbox-Container der Extension.
            let wavURL = try Self.previewWav(for: mod, cacheKey: cacheKey)
            let reply = QLPreviewReply(fileURL: wavURL)

            // Titelzeile des Preview-Fensters: Songname + Format + Kanalzahl.
            let title = mod.name.isEmpty ? request.fileURL.lastPathComponent : mod.name
            reply.title = "\(title) — \(mod.format.displayName), \(mod.usedChannelCount) Kanäle (Vorschau bis 60 s)"
            return reply
        } catch {
            // Ein Parserfehler darf nicht wie ein nie endender Ladeindikator
            // aussehen. Eine kleine Textdatei liefert Quick Look sofort aus und
            // zeigt den konkreten Grund, ohne eine kaputte Audio-WAV vorzutäuschen.
            let errorURL = try Self.writeErrorPreview(error, sourceURL: request.fileURL)
            let reply = QLPreviewReply(fileURL: errorURL)
            reply.title = "\(request.fileURL.lastPathComponent) — keine Wiedergabe möglich"
            return reply
        }
    }

    // Rendert jeden Dateiinhalt nur einmal. Finder fordert dieselbe Vorschau
    // häufig mehrfach an; ohne diesen Cache sah der Nutzer bei jedem Öffnen
    // wieder lange den Ladeindikator. `cacheKey` kommt aus den eingelesenen
    // Bytes (PreviewCacheIdentity) und gehört damit zu exakt dem `mod`, das
    // hier gerendert wird.
    private static func previewWav(for mod: Mod, cacheKey: String) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("SavagePreviews", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let cachedURL = dir.appendingPathComponent("\(cacheKey).wav")
        if fm.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        let wav = try ModuleRenderer.renderWavData(
            mod: mod,
            maxDurationSeconds: previewDurationSeconds
        )

        pruneOldPreviews(in: dir)

        // Zuerst in eine private temporäre Datei schreiben und danach umbenennen:
        // parallele Finder-Anfragen können so nie eine halbfertige WAV erhalten.
        let temporaryURL = dir.appendingPathComponent("\(UUID().uuidString).wav")
        try wav.write(to: temporaryURL, options: .atomic)
        do {
            try fm.moveItem(at: temporaryURL, to: cachedURL)
            return cachedURL
        } catch {
            try? fm.removeItem(at: temporaryURL)
            if fm.fileExists(atPath: cachedURL.path) { return cachedURL }
            throw error
        }
    }

    // Aufraeumen: Der Schluessel haengt am Inhalt — WAVs ersetzter oder
    // geloeschter Dateien verwaisen und verschwinden ueber dieses
    // Alters-Aufraeumen, damit wiederholtes Leertasten schnell bleibt, ohne den
    // Extension-Container dauerhaft zu fuellen.
    //
    // Gilt ausdruecklich fuer BEIDE Vorschauarten. Frueher lief der Durchgang
    // nur beim erfolgreichen Rendern; die Fehlertexte tragen aber je einen
    // eigenen UUID-Namen, und wer nur defekte Dateien anschaut, hinterliess so
    // eine Datei je Leertastendruck, die nie jemand aufraeumte.
    private static func pruneOldPreviews(in directory: URL) {
        let fm = FileManager.default
        guard let existing = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-86_400)
        for url in existing {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if mtime < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func writeErrorPreview(_ error: Error, sourceURL: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavagePreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pruneOldPreviews(in: dir)

        let message = """
        Savage Mod Player konnte dieses Modul nicht wiedergeben.

        Datei: \(sourceURL.lastPathComponent)

        Grund: \(error.localizedDescription)

        Bei neueren OpenMPT-IT-Dateien können proprietäre Erweiterungen außerhalb der nativen Impulse-Tracker-2.14-/2.15-Unterstützung liegen.
        """
        let url = dir.appendingPathComponent("Fehler-\(UUID().uuidString).txt")
        try Data(message.utf8).write(to: url, options: .atomic)
        return url
    }
}

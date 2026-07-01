import Foundation
import QuickLookUI
import UniformTypeIdentifiers

// Principal Class der Quick-Look-Extension (datenbasierte Preview,
// QLIsDataBasedPreview = true in der Info.plist des Appex).
//
// Funktionsweise: Die Extension parst das Tracker-Modul (alle MOD-Varianten
// + S3M über ModuleLoader) und rendert es mit der identischen DSP-Engine des
// Players offline zu WAV-Daten. Quick Look zeigt für die gelieferten
// WAV-Daten den nativen macOS-Audio-Player — damit ist das Modul direkt im
// Finder (Leertaste) abspielbar, inklusive Scrubbing und Lautstärke.
//
// Hinweis zum Build: Dieses File wird NICHT über SwiftPM gebaut, sondern von
// build_app.sh zusammen mit den SavageProtrackerPlayerCore-Quellen per swiftc
// in EIN Modul kompiliert (deshalb kein `import SavageProtrackerPlayerCore`).
class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = try Data(contentsOf: request.fileURL)
        let mod = try ModuleLoader.parse(data: data)
        let wav = try ModuleRenderer.renderWavData(mod: mod)

        let reply = QLPreviewReply(
            dataOfContentType: .wav,
            contentSize: CGSize(width: 800, height: 400)
        ) { _ in
            wav
        }

        // Titelzeile des Preview-Fensters: Songname + Format + Kanalzahl.
        let title = mod.name.isEmpty ? request.fileURL.lastPathComponent : mod.name
        reply.title = "\(title) — \(mod.format.displayName), \(mod.channelCount) Kanäle"
        return reply
    }
}

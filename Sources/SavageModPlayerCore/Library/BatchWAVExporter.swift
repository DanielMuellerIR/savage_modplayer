import Foundation

public struct BatchWAVExportSettings: Codable, Equatable, Sendable {
    public enum ConflictPolicy: String, Codable, CaseIterable, Sendable {
        case skipExisting, keepBoth
    }
    public var output: ChannelStemRenderer.Output
    public var conflictPolicy: ConflictPolicy
    public var audio: ChannelStemExportOptions

    public init(output: ChannelStemRenderer.Output = .stereoMix,
                conflictPolicy: ConflictPolicy = .skipExisting,
                audio: ChannelStemExportOptions = .init()) {
        self.output = output
        self.conflictPolicy = conflictPolicy
        self.audio = audio
    }
}

public struct BatchWAVExportItem: Identifiable, Sendable {
    public let id: UUID
    public let source: URL
    public let displayName: String
    public let sourceDescription: String

    // Die Mac-Abspielliste liest aus Arbeitskopien mit wechselnden UUID-Namen.
    // Anzeige und Ausgabe müssen trotzdem den ursprünglichen Titel behalten.
    public init(source: URL, displayName: String? = nil, sourceDescription: String? = nil) {
        self.id = UUID()
        self.source = source
        let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = String((name.isEmpty ? source.lastPathComponent : name).prefix(512))
        self.sourceDescription = String((sourceDescription ?? source.deletingLastPathComponent().path).prefix(2048))
    }
}

public struct BatchWAVExportResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case exported, skipped, failed, cancelled, notStarted }
    public let sourceName: String
    public var folderName: String?
    public var status: Status
    public var detail: String?
    public var audio: ChannelStemExportReport?
}

public struct BatchWAVExportReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let settings: BatchWAVExportSettings
    public var results: [BatchWAVExportResult]
    public var wasCancelled: Bool
    public let reportFileName: String
    public var reportWriteError: String?
}

public struct BatchWAVExportProgress: Sendable {
    public let itemIndex: Int
    public let itemCount: Int
    public let sourceName: String
    public let itemProgress: Double
    public var fraction: Double { (Double(itemIndex) + itemProgress) / Double(max(1, itemCount)) }
}

public enum BatchWAVExportError: Error, LocalizedError {
    case invalidSelection, invalidDestination, invalidSettings, sourceUnavailable
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: "Bitte zwischen 1 und 10.000 Titel auswählen."
        case .invalidDestination: "Das Exportziel muss ein vorhandener Ordner sein."
        case .invalidSettings: "Die Stapel-Exporteinstellungen sind ungültig."
        case .sourceUnavailable: "Die Quelldatei fehlt, ist nicht regulär oder überschreitet 64 MiB."
        }
    }
}

public enum BatchWAVExporter {
    public static let maximumItems = 10_000
    public static let maximumSourceBytes = 64 * 1024 * 1024

    // Die Liste hält nur Referenzen und Beschriftungen. Modul und Renderblöcke
    // werden vollständig freigegeben, bevor der nächste Titel geladen wird.
    public static func export(items: [BatchWAVExportItem], to destination: URL,
                              settings: BatchWAVExportSettings,
                              progress: @Sendable (BatchWAVExportProgress) -> Void = { _ in }) throws -> BatchWAVExportReport {
        guard !items.isEmpty, items.count <= maximumItems else { throw BatchWAVExportError.invalidSelection }
        let options = settings.audio
        _ = try ModuleRenderer.validatedFrameLimit(sampleRate: options.sampleRate, maxDurationSeconds: options.maximumSeconds)
        guard options.sampleRate >= 8_000, options.sampleRate.rounded() == options.sampleRate,
              options.stereoSeparation.isFinite, (0...1).contains(options.stereoSeparation),
              options.mutedChannels == nil, options.soloChannels.isEmpty else { throw BatchWAVExportError.invalidSettings }
        var directory: ObjCBool = false
        guard destination.isFileURL, !destination.path.contains("\0"),
              FileManager.default.fileExists(atPath: destination.path, isDirectory: &directory), directory.boolValue else {
            throw BatchWAVExportError.invalidDestination
        }
        var report = BatchWAVExportReport(schemaVersion: 1, settings: settings,
            results: items.map { .init(sourceName: $0.displayName, status: .notStarted) },
            wasCancelled: false, reportFileName: "Savage-Export-\(UUID().uuidString).json")
        var reserved = Set<String>()
        for (index, item) in items.enumerated() {
            if Task.isCancelled { report.wasCancelled = true; break }
            let base = folderName(for: item.displayName)
            var suffix = 1
            var name = base
            while reserved.contains(name.lowercased()) {
                suffix += 1
                name = "\(base) (\(suffix))"
            }
            reserved.insert(name.lowercased())
            let preferredName = name
            report.results[index].folderName = name
            progress(.init(itemIndex: index, itemCount: items.count, sourceName: item.displayName, itemProgress: 0))
            do {
                // Konflikte vor dem Parsen prüfen; ein zweiter exklusiver Test
                // beim Veröffentlichen schützt spät angelegte Ziele ebenso.
                var exported = false
                while !exported {
                    try Task.checkCancellation()
                    let target = destination.appendingPathComponent(name, isDirectory: true)
                    do {
                        if (try? FileManager.default.attributesOfItem(atPath: target.path)) != nil {
                            throw ChannelStemExportError.destinationExists
                        }
                        let audio = try exportItem(item, to: target, settings: settings) { value in
                            progress(.init(itemIndex: index, itemCount: items.count,
                                           sourceName: item.displayName, itemProgress: value))
                        }
                        report.results[index].audio = audio
                        report.results[index].status = .exported
                        report.results[index].folderName = name
                        exported = true
                    } catch ChannelStemExportError.destinationExists {
                        if settings.conflictPolicy == .skipExisting {
                            report.results[index].status = .skipped
                            report.results[index].detail = "Ziel bereits vorhanden; unverändert übersprungen."
                            break
                        }
                        guard suffix < maximumItems else { throw ChannelStemExportError.destinationExists }
                        repeat {
                            suffix += 1
                            name = "\(base) (\(suffix))"
                        } while reserved.contains(name.lowercased()) && suffix < maximumItems
                        guard !reserved.contains(name.lowercased()) else { throw ChannelStemExportError.destinationExists }
                        reserved.insert(name.lowercased())
                    }
                }
            } catch is CancellationError {
                report.results[index].status = .cancelled
                report.wasCancelled = true
                break
            } catch {
                report.results[index].status = .failed
                report.results[index].detail = error.localizedDescription
            }
            // Der ursprünglich zugewiesene Name bleibt auch bei keepBoth belegt,
            // damit spätere gleichnamige Quellen eine eindeutige Zuordnung haben.
            reserved.insert(preferredName.lowercased())
            progress(.init(itemIndex: index, itemCount: items.count, sourceName: item.displayName, itemProgress: 1))
        }
        report.wasCancelled = report.wasCancelled || Task.isCancelled
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(report).write(to: destination.appendingPathComponent(report.reportFileName), options: .withoutOverwriting)
        } catch {
            report.reportWriteError = "Ausgaben bleiben erhalten. Der Stapelbericht konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
        return report
    }

    private static func exportItem(_ item: BatchWAVExportItem, to target: URL, settings: BatchWAVExportSettings,
                                   progress: @Sendable (Double) -> Void) throws -> ChannelStemExportReport {
        #if canImport(Darwin)
        let scoped = item.source.startAccessingSecurityScopedResource()
        defer { if scoped { item.source.stopAccessingSecurityScopedResource() } }
        #endif
        let data: Data
        do {
            let reader = try LibraryFileReader(item.source)
            defer { reader.close() }
            guard reader.stamp.size <= maximumSourceBytes else { throw BatchWAVExportError.sourceUnavailable }
            data = try reader.read(limit: maximumSourceBytes, isCancelled: { Task.isCancelled })
        } catch is CancellationError { throw CancellationError() }
        catch { throw BatchWAVExportError.sourceUnavailable }
        try Task.checkCancellation()
        let mod = try ModuleLoader.parse(data: data)
        try Task.checkCancellation()
        return try ChannelStemRenderer.export(mod: mod, to: target, options: settings.audio,
                                               output: settings.output, progress: progress)
    }

    private static func folderName(for sourceName: String) -> String {
        let cleaned = String(sourceName.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) || $0 == "/" || $0 == ":" ? "_" : String($0)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        var result = ""
        for character in cleaned {
            guard result.utf8.count + String(character).utf8.count <= 160 else { break }
            result.append(character)
        }
        return result.isEmpty || result == "." || result == ".." ? "Modul" : result
    }
}

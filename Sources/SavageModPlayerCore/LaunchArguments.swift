import Foundation

/// Auswertung der Startargumente der Mac-App — bewusst getrennt vom
/// App-Lebenszyklus, damit sie ohne laufende Oberflaeche pruefbar ist.
///
/// Hintergrund (2026-08-23): `SavageModPlayer <pfad>` zeigte ueberhaupt kein
/// Fenster. Ursache ist nicht diese Auswertung, sondern AppKit: ein positionales
/// Startargument gilt dort als "diese Datei oeffnen". Die App laeuft dann nicht
/// ueber den Weg, auf dem SwiftUI sein Standardfenster erzeugt — und weil kein
/// Fenster existierte, konnte auch `.onOpenURL` die Datei nicht entgegennehmen.
/// `SavageModPlayerApp.init()` schaltet diese Deutung ueber die Voreinstellung
/// `NSTreatUnknownArgumentsAsOpen` ab. Hier bleibt nur noch die reine
/// Argumentlogik, die `MainView` beim Start abfragt.
public enum LaunchArguments {

    /// Was an einem Pfad tatsaechlich liegt. Als Ergebnis einer einzigen Abfrage
    /// statt zweier Aufrufe (`exists` + `isDirectory`), damit Tests einen
    /// Dateibestand ohne echtes Dateisystem vorgeben koennen.
    public enum PathKind: Sendable, Equatable {
        case missing
        case file
        case directory
    }

    /// Das Flag, das die Wiedergabe direkt nach dem Laden startet.
    public static let autoplayFlag = "--autoplay"

    /// Erstes Datei- oder Ordnerargument (`SavageModPlayer <pfad>`), sonst `nil`.
    ///
    /// - Parameters:
    ///   - arguments: Die vollstaendige Argumentliste inklusive Programmpfad an
    ///     Position 0 — also genau das, was `CommandLine.arguments` liefert.
    ///   - probe: Liefert zu einem Pfad, was dort liegt. Der Standard fragt das
    ///     echte Dateisystem; Tests reichen eine eigene Zuordnung herein.
    ///
    /// Uebersprungen werden der Programmpfad, jedes mit `-` beginnende Argument
    /// **samt seinem Wert** und alles, was nicht existiert oder keine
    /// unterstuetzte Endung hat. Das Ueberspringen des Werts ist kein Detail:
    /// macOS haengt beim Start eigene Voreinstellungen als `-Schluessel Wert` an
    /// (etwa `-ApplePersistenceIgnoreState YES`), und ohne diese Regel wuerde ein
    /// Ordner namens `YES` im Arbeitsverzeichnis als Startordner durchgehen. Das
    /// eigene `--autoplay <filter>` hat dieselbe Form und wird damit ebenso
    /// korrekt als Paar gelesen.
    public static func fileArgument(
        _ arguments: [String],
        probe: (String) -> PathKind = LaunchArguments.filesystemProbe
    ) -> URL? {
        var index = 1 // Position 0 ist der Programmpfad selbst.
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("-") {
                index += valueFollows(arguments, after: index) ? 2 : 1
                continue
            }
            index += 1
            switch probe(argument) {
            case .directory:
                // Ein Ordner wird rekursiv zur Playlist — Endung spielt keine Rolle.
                return URL(fileURLWithPath: argument)
            case .file:
                let url = URL(fileURLWithPath: argument)
                if ModuleLoader.supportedExtensions.contains(url.pathExtension.lowercased()) {
                    return url
                }
            case .missing:
                continue
            }
        }
        return nil
    }

    /// Startet die Wiedergabe laut Argumentliste sofort nach dem Laden?
    public static func autoplayRequested(_ arguments: [String]) -> Bool {
        arguments.contains(autoplayFlag)
    }

    public static func collectionArgument(
        _ arguments: [String], probe: (String) -> PathKind = LaunchArguments.filesystemProbe
    ) -> URL? {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("-") { index += valueFollows(arguments, after: index) ? 2 : 1; continue }
            index += 1
            let url = URL(fileURLWithPath: argument)
            if url.pathExtension.lowercased() == CollectionExchangeCodec.fileExtension, probe(argument) == .file { return url }
        }
        return nil
    }

    /// Der optionale Filter hinter `--autoplay`: der erste Titel, dessen Name ihn
    /// enthaelt, wird zum Starttitel. Ohne Filter (Flag am Ende oder direkt vor
    /// einem weiteren Flag) `nil`.
    public static func autoplayFilter(_ arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: autoplayFlag) else { return nil }
        guard valueFollows(arguments, after: flagIndex) else { return nil }
        return arguments[flagIndex + 1].lowercased()
    }

    /// Standardabfrage gegen das echte Dateisystem.
    public static func filesystemProbe(_ path: String) -> PathKind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .missing
        }
        return isDirectory.boolValue ? .directory : .file
    }

    /// Folgt auf das Argument an `index` ein Wert (also ein weiteres Argument,
    /// das nicht selbst mit `-` beginnt)?
    private static func valueFollows(_ arguments: [String], after index: Int) -> Bool {
        let next = index + 1
        return next < arguments.count && !arguments[next].hasPrefix("-")
    }
}

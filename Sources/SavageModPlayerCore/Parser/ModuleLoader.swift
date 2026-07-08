import Foundation

// Zentraler Einstieg zum Laden von Tracker-Modulen: erkennt das Format am
// Dateiinhalt (nicht an der Endung) und delegiert an den passenden Parser.
// Wird von der App, dem Quick-Look-Plugin und den Tests gemeinsam genutzt.
public enum ModuleLoader {
    // Dateiendungen, die der Player abspielen kann (für Importer/Drop-Filter).
    public static let supportedExtensions: Set<String> = ["mod", "s3m", "xm"]

    public static func parse(data: Data) throws -> Mod {
        // XM zuerst prüfen ("Extended Module: "-Signatur ab Offset 0), dann S3M
        // (SCRM), sonst MOD (Signatur bei 1080 bzw. 15-Sample-Heuristik).
        if XMParser.canParse(data: data) {
            return try XMParser.parse(data: data)
        }
        if S3MParser.canParse(data: data) {
            return try S3MParser.parse(data: data)
        }
        return try ModParser.parse(data: data)
    }
}

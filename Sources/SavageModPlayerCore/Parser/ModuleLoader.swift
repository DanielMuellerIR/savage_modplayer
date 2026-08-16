import Foundation

// Zentraler Einstieg zum Laden von Tracker-Modulen: erkennt das Format am
// Dateiinhalt (nicht an der Endung) und delegiert an den passenden Parser.
// Wird von der App, dem Quick-Look-Plugin und den Tests gemeinsam genutzt.
public enum ModuleLoader {
    // Dateiendungen, die der Player abspielen kann (für Importer/Drop-Filter).
    public static let supportedExtensions: Set<String> = ["mod", "s3m", "xm", "it"]

    public static func parse(data: Data) throws -> Mod {
        // Ein `Data` aus einem groesseren Puffer (`puffer[100...]`) behaelt die
        // Indizes des Originals: sein startIndex ist dann nicht 0. XMParser und
        // ITParser rechnen deshalb konsequent relativ zu `startIndex`; ModParser
        // und S3MParser indizieren dagegen absolut und laesen bei einem Slice
        // die falschen Bytes — und beendeten den Prozess, sobald der startIndex
        // ueber ihren festen Offsets lag. Statt beide Parser umzurechnen wird
        // die Eingabe hier einmal auf startIndex 0 normalisiert. Der Normalfall
        // (`Data(contentsOf:)`) hat bereits startIndex 0 und wird nicht kopiert.
        let data = data.rebasedToZero
        // XM und IT zuerst an ihrer Signatur ab Offset 0 erkennen, dann S3M
        // (SCRM), sonst MOD (Signatur bei 1080 bzw. 15-Sample-Heuristik).
        if XMParser.canParse(data: data) {
            return try XMParser.parse(data: data)
        }
        if ITParser.canParse(data: data) {
            return try ITParser.parse(data: data)
        }
        if S3MParser.canParse(data: data) {
            return try S3MParser.parse(data: data)
        }
        return try ModParser.parse(data: data)
    }
}

extension Data {
    /// Dieselben Bytes, aber garantiert ab Index 0 adressierbar.
    ///
    /// Parser, die feste Dateioffsets direkt als Index verwenden, setzen
    /// stillschweigend `startIndex == 0` voraus. Bei einem Slice stimmt das
    /// nicht: `puffer[1200...]` hat den startIndex 1200, und ein Zugriff auf
    /// Index 470 liegt dann ausserhalb — Swift beendet den Prozess. Kopiert
    /// wird nur, wenn wirklich ein Slice vorliegt.
    var rebasedToZero: Data {
        startIndex == 0 ? self : Data(self)
    }
}

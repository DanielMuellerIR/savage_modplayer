import Foundation

/// Stabiler Cache-Schlüssel für Quick-Look-Vorschauen.
///
/// Der Schlüssel entsteht aus GENAU den Bytes, die auch geparst und gerendert
/// werden — nicht aus Pfad, Größe und Änderungszeit der Quelldatei. Eine
/// zwischen Einlesen und Attributabfrage ersetzte Datei (oder ein Ersatz mit
/// identischer Größe und Änderungszeit) kann so nie alte Audiodaten unter
/// neuer Identität aus dem Cache liefern; inhaltsgleiche Dateien teilen sich
/// schlicht dieselbe gerenderte WAV.
public enum PreviewCacheIdentity {
    public static func key(forContents data: Data) -> String {
        // Zwei unabhängig gestartete FNV-1a-Läufe (vorwärts und rückwärts,
        // jeweils mit der Länge im Startwert) ergeben einen kompakten,
        // stabilen 128-Bit-Dateinamen. Der Hash ist kein Sicherheitsmerkmal,
        // sondern macht den Inhalt nur dateinamenssicher.
        let length = UInt64(data.count)
        let first = fnv1a(data, seed: 0xcbf2_9ce4_8422_2325 ^ length)
        let second = fnv1a(data.reversed(), seed: 0x8422_2325_cbf2_9ce4 &+ length)
        return String(format: "%016llx%016llx", first, second)
    }

    private static func fnv1a<S: Sequence>(_ bytes: S, seed: UInt64) -> UInt64
    where S.Element == UInt8 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}

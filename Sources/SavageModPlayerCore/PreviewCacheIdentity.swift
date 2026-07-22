import Foundation

/// Stabiler, dateisystembezogener Schlüssel für Quick-Look-Vorschauen.
///
/// Der kanonische vollständige Pfad trennt gleichnamige Dateien aus verschiedenen
/// Ordnern. Die volle Double-Bitdarstellung des Änderungszeitpunkts bewahrt die
/// Subsekunden-Auflösung, die eine Rundung auf ganze Sekunden verloren hat.
public enum PreviewCacheIdentity {
    public static func key(
        sourceURL: URL,
        fileSize: Int,
        modificationDate: Date
    ) -> String {
        let path = sourceURL.standardizedFileURL.resolvingSymlinksInPath().path
        let identity = "\(path.utf8.count):\(path)|\(fileSize)|\(modificationDate.timeIntervalSinceReferenceDate.bitPattern)"
        let bytes = Array(identity.utf8)

        // Zwei unabhängig gestartete FNV-1a-Läufe ergeben einen kompakten,
        // stabilen 128-Bit-Dateinamen. Die eigentliche Identität steckt in Pfad,
        // Größe und hochaufgelöstem Zeitstempel; der Hash macht sie dateisicher.
        let first = fnv1a(bytes, seed: 0xcbf29ce484222325)
        let second = fnv1a(bytes.reversed(), seed: 0x84222325cbf29ce4)
        return String(format: "%016llx%016llx", first, second)
    }

    private static func fnv1a<S: Sequence>(_ bytes: S, seed: UInt64) -> UInt64
    where S.Element == UInt8 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x00000100000001B3
        }
        return hash
    }
}

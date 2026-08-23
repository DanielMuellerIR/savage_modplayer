import Foundation

/// Baut ein ZIP-Archiv im Speicher — unkomprimiert ("stored"), damit kein
/// Deflate-Encoder noetig ist.
///
/// Gemeinsam genutzt von den Importtests und den Tests fuer „Öffnen mit …".
/// Beide brauchen ein echtes Archiv: Der Import auf iOS laeuft ausschliesslich
/// ueber den eigenen `ZipArchiveReader`, und ein aus dem Repo geladenes
/// Beispielarchiv gibt es bewusst nicht.
enum ZipTestSupport {

    static func makeStoredZip(entries: [(String, Data)]) throws -> Data {
        var output = Data()
        var directory = Data()
        var offsets: [Int] = []

        func appendUInt16(_ value: UInt16, to data: inout Data) {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
        }
        func appendUInt32(_ value: UInt32, to data: inout Data) {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
        }

        for (name, payload) in entries {
            offsets.append(output.count)
            let nameBytes = Data(name.utf8)
            let crc = crc32(payload)

            appendUInt32(0x0403_4B50, to: &output)          // Local File Header
            appendUInt16(20, to: &output)                    // benoetigte Version
            appendUInt16(0x0800, to: &output)                // Flags: Bit 11 = Name ist UTF-8
            appendUInt16(0, to: &output)                     // Methode 0 = stored
            appendUInt16(0, to: &output)                     // Uhrzeit
            appendUInt16(0x21, to: &output)                  // Datum (1980-01-01)
            appendUInt32(crc, to: &output)
            appendUInt32(UInt32(payload.count), to: &output) // komprimiert
            appendUInt32(UInt32(payload.count), to: &output) // unkomprimiert
            appendUInt16(UInt16(nameBytes.count), to: &output)
            appendUInt16(0, to: &output)                     // kein Extra-Feld
            output.append(nameBytes)
            output.append(payload)
        }

        for (index, (name, payload)) in entries.enumerated() {
            let nameBytes = Data(name.utf8)
            let crc = crc32(payload)

            appendUInt32(0x0201_4B50, to: &directory)        // Central Directory Header
            appendUInt16(20, to: &directory)                 // erzeugt von Version
            appendUInt16(20, to: &directory)                 // benoetigte Version
            appendUInt16(0x0800, to: &directory)
            appendUInt16(0, to: &directory)
            appendUInt16(0, to: &directory)
            appendUInt16(0x21, to: &directory)
            appendUInt32(crc, to: &directory)
            appendUInt32(UInt32(payload.count), to: &directory)
            appendUInt32(UInt32(payload.count), to: &directory)
            appendUInt16(UInt16(nameBytes.count), to: &directory)
            appendUInt16(0, to: &directory)                  // Extra
            appendUInt16(0, to: &directory)                  // Kommentar
            appendUInt16(0, to: &directory)                  // Disk
            appendUInt16(0, to: &directory)                  // interne Attribute
            appendUInt32(0, to: &directory)                  // externe Attribute
            appendUInt32(UInt32(offsets[index]), to: &directory)
            directory.append(nameBytes)
        }

        let directoryOffset = output.count
        output.append(directory)

        appendUInt32(0x0605_4B50, to: &output)               // End of Central Directory
        appendUInt16(0, to: &output)                         // Disk-Nummer
        appendUInt16(0, to: &output)                         // Disk mit Central Directory
        appendUInt16(UInt16(entries.count), to: &output)
        appendUInt16(UInt16(entries.count), to: &output)
        appendUInt32(UInt32(directory.count), to: &output)
        appendUInt32(UInt32(directoryOffset), to: &output)
        appendUInt16(0, to: &output)                         // kein Kommentar

        return output
    }

    // CRC32 nach IEEE — dieselbe Pruefsumme, die im ZIP-Format steht.
    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var value = UInt32(i)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            table[i] = value
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

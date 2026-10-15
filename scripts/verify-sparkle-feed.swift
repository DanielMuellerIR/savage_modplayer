import CryptoKit
import Foundation

// Unabhängige Prüfung mit dem öffentlichen Schlüssel der ausgelieferten App.
// sign_update --verify würde mit demselben privaten Schlüssel gegenprüfen.
func verifySignature(_ signature: String, message: Data, key: Curve25519.Signing.PublicKey) throws {
    guard let bytes = Data(base64Encoded: signature), key.isValidSignature(bytes, for: message) else {
        throw NSError(domain: "SparkleFeed", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ungültige Ed25519-Signatur"])
    }
}

do {
    let args = CommandLine.arguments
    guard args.count == 4 else {
        throw NSError(domain: "SparkleFeed", code: 2, userInfo: [NSLocalizedDescriptionKey: "Aufruf: verify-sparkle-feed <appcast.xml> <Info.plist> <Update-Archiv>"])
    }
    let feed = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let plistData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    guard let publicKey = plist?["SUPublicEDKey"] as? String,
          let keyData = Data(base64Encoded: publicKey),
          let text = String(data: feed, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let pattern = #"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\s*$"#
    let regex = try NSRegularExpression(pattern: pattern)
    guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let signatureRange = Range(match.range(at: 1), in: text),
          let lengthRange = Range(match.range(at: 2), in: text),
          let blockRange = Range(match.range, in: text),
          let length = Int(text[lengthRange]), length > 0,
          length == text[..<blockRange.lowerBound].utf8.count else { throw CocoaError(.fileReadCorruptFile) }
    let signedFeed = Data(feed.prefix(length))
    try verifySignature(String(text[signatureRange]), message: signedFeed, key: key)
    let xml = try XMLDocument(data: signedFeed, options: [])
    let items = try xml.nodes(forXPath: "/rss/channel/item")
    guard items.count == 1, let item = items.first as? XMLElement,
          let enclosure = item.elements(forName: "enclosure").first,
          let archiveSignature = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
          let archiveLength = enclosure.attribute(forName: "length")?.stringValue else { throw CocoaError(.fileReadCorruptFile) }
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
    guard Int(archiveLength) == archive.count else { throw CocoaError(.fileReadCorruptFile) }
    try verifySignature(archiveSignature, message: archive, key: key)
    print("Feed und Update-Archiv gegen SUPublicEDKey verifiziert.")
} catch {
    FileHandle.standardError.write(Data("FEHLER: \(error.localizedDescription)\n".utf8))
    exit(1)
}

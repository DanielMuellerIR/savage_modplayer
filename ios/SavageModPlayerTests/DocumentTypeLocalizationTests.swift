import XCTest
@testable import SavageModPlayer

/// Die Namen der Dokumenttypen erscheinen auf Deutsch UND Englisch.
///
/// Hintergrund (Code-Review 2026-08-02): `UTTypeDescription` und
/// `CFBundleTypeName` standen nur deutsch in der `Info.plist`. iOS zeigt diese
/// Texte in der Dateien-App, im Teilen-Menue und unter „Öffnen mit …" — auf
/// einem englischen Telefon stand dort also Deutsch.
///
/// Beide Schluessel sind ueber `InfoPlist.strings` uebersetzbar: Der Wert aus
/// der `Info.plist` dient dabei als Schluessel. Genau diese Verbindung prueft
/// dieser Test — dass die Uebersetzungstabelle im gebauten Bundle liegt und
/// jeden in der `Info.plist` deklarierten Namen kennt.
final class DocumentTypeLocalizationTests: XCTestCase {

    /// Liest die kompilierte Uebersetzungstabelle einer Sprache aus dem Bundle.
    private func infoPlistStrings(language: String) throws -> [String: String] {
        let bundle = Bundle(for: NowPlayingController.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: "\(language).lproj"),
            "\(language).lproj/InfoPlist.strings fehlt im App-Bundle")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    /// Alle Namen, die die `Info.plist` als Dokumenttyp deklariert.
    private func declaredTypeNames() throws -> Set<String> {
        let info = try XCTUnwrap(Bundle(for: NowPlayingController.self).infoDictionary)
        var names: Set<String> = []

        let exported = info["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        for declaration in exported {
            if let description = declaration["UTTypeDescription"] as? String {
                names.insert(description)
            }
        }
        let documents = info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        for document in documents {
            if let name = document["CFBundleTypeName"] as? String {
                names.insert(name)
            }
        }
        return names
    }

    func testEveryDeclaredDocumentTypeNameIsTranslated() throws {
        let declared = try declaredTypeNames()
        XCTAssertEqual(declared.count, 6, "Erwartet: vier Formate plus zwei Dokumenttypen — \(declared.sorted())")

        for language in ["de", "en"] {
            let table = try infoPlistStrings(language: language)
            for name in declared {
                let translation = table[name]
                XCTAssertNotNil(translation, "\(language): Uebersetzung fuer '\(name)' fehlt")
                XCTAssertFalse(
                    (translation ?? "").isEmpty,
                    "\(language): Uebersetzung fuer '\(name)' ist leer")
            }
        }
    }

    /// Die englische Fassung muss sich von der deutschen unterscheiden — sonst
    /// steht die Tabelle zwar da, uebersetzt aber nichts.
    func testEnglishNamesDifferFromGerman() throws {
        let german = try infoPlistStrings(language: "de")
        let english = try infoPlistStrings(language: "en")

        for (key, germanValue) in german {
            let englishValue = try XCTUnwrap(english[key])
            XCTAssertNotEqual(
                englishValue, germanValue,
                "'\(key)' ist auf Englisch unveraendert geblieben")
        }
    }
}

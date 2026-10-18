import Foundation
import CoreFoundation

// Nur ausdrücklich benannte Schlüssel gehören zur Übernahme. Abwesende Werte
// bleiben abwesend; registrierte Standardwerte werden nicht als Original gespeichert.
@MainActor
public struct CollectionExchangePreferences {
    private let defaults: UserDefaults
    private let domain: String
    private let keys: Set<String>

    public init(defaults: UserDefaults, domain: String, keys: Set<String>) {
        self.defaults = defaults; self.domain = domain; self.keys = keys
    }

    public func capture() throws -> Data { try encode(current()) }
    public func values(in data: Data) throws -> [String: Any] { try decode(data) }

    public func assigning(_ values: [String: Any], to data: Data) throws -> Data {
        guard Set(values.keys).isSubset(of: keys) else { throw CollectionExchangePersistenceError.invalidJournal }
        var candidate = try decode(data)
        for (key, value) in values { candidate[key] = value }
        return try encode(candidate)
    }

    public func replace(expected: Data, replacement: Data) throws {
        let old = try decode(expected), next = try decode(replacement), actual = current()
        let actualValues = NSDictionary(dictionary: actual)
        guard actualValues.isEqual(to: old) || actualValues.isEqual(to: next) else { throw CollectionExchangePersistenceError.staleState }
        if !actualValues.isEqual(to: next) {
            for key in keys {
                if let value = next[key] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        // Der Abschlussmarker darf erst nach dem gesicherten Zusatzspeicher
        // entstehen; sonst wären Dateien und Defaults nach einem Abbruch getrennt.
        guard defaults.synchronize() else { throw CollectionExchangePersistenceError.unreadable }
    }

    private func current() -> [String: Any] {
        (defaults.persistentDomain(forName: domain) ?? [:]).filter { keys.contains($0.key) }
    }
    private func decode(_ data: Data) throws -> [String: Any] {
        guard data.count <= CollectionExchangePersistence.maximumAuxiliaryBytes,
              let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              Set(values.keys).isSubset(of: keys) else { throw CollectionExchangePersistenceError.invalidJournal }
        return values
    }
    private func encode(_ values: [String: Any]) throws -> Data {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        guard data.count <= CollectionExchangePersistence.maximumAuxiliaryBytes else { throw CollectionExchangePersistenceError.oversized }
        return data
    }
}

@MainActor
public enum CollectionExchangeSoundPreferences {
    public static func keys(prefix: String) -> Set<String> {
        Set(["palClock", "stereoSeparation", "interpolation", "ledFilter"].map { prefix + $0 })
    }
    public static func options(in values: [String: Any], prefix: String) -> PlaybackOptions {
        PlaybackOptions(palClock: values[prefix + "palClock"] as? Bool ?? true,
                        stereoSeparation: values[prefix + "stereoSeparation"] as? Double ?? 0.8,
                        useInterpolation: values[prefix + "interpolation"] as? Bool ?? true,
                        ledFilterActive: values[prefix + "ledFilter"] as? Bool ?? false)
    }
    public static func validatedOptions(in values: [String: Any], prefix: String) throws -> PlaybackOptions {
        func boolean(_ name: String, default fallback: Bool) throws -> Bool {
            guard let value = values[prefix + name] else { return fallback }
            guard let number = value as? NSNumber, number.doubleValue.isFinite,
                  number.doubleValue == 0 || number.doubleValue == 1 else { throw CollectionExchangeError.invalidLocalState }
            return number.boolValue
        }
        var separation = 0.8
        if let value = values[prefix + "stereoSeparation"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, (0...1).contains(number.doubleValue) else { throw CollectionExchangeError.invalidLocalState }
            separation = number.doubleValue
        }
        return try PlaybackOptions(palClock: boolean("palClock", default: true), stereoSeparation: separation,
                                   useInterpolation: boolean("interpolation", default: true),
                                   ledFilterActive: boolean("ledFilter", default: false))
    }
    public static func values(_ options: PlaybackOptions, prefix: String) -> [String: Any] {
        [prefix + "palClock": options.palClock, prefix + "stereoSeparation": options.stereoSeparation,
         prefix + "interpolation": options.useInterpolation, prefix + "ledFilter": options.ledFilterActive]
    }
}

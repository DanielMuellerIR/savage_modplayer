import Foundation

public struct TrackerNoteText: Sendable, Equatable {
    public let note: String
    public let instrument: String
    public let volume: String
    public let effect: String

    public init(_ value: Note) {
        note = Self.noteName(value)
        instrument = value.instrument > 0 ? String(format: "%02X", value.instrument) : "--"
        volume = value.volume >= 0 ? String(format: "v%02d", value.volume) : "..."
        effect = Self.effectText(value)
    }
    private static func noteName(_ note: Note) -> String {
        if note.key == Note.keyCut { return "^^^" }
        if note.key == Note.keyOff { return "===" }
        if note.key == Note.keyFade { return "~~~" }
        let names = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
        if note.key >= 0 { return "\(names[note.key % 12])\(note.key / 12)" }
        guard note.period >= 113, note.period <= 856 else { return "---" }
        let index = Int(round(24 + 12 * log2(428 / Double(note.period))))
        guard index >= 0 else { return "---" }
        return "\(names[index % 12])\(index / 12 + 1)"
    }
    private static func effectText(_ value: Note) -> String {
        guard value.hasEffect else { return "..." }
        if value.effectId > ModuleEffect.impulseTrackerCommandBase,
           value.effectId <= ModuleEffect.impulseTrackerCommandBase + 26,
           let scalar = UnicodeScalar(64 + value.effectId - ModuleEffect.impulseTrackerCommandBase) {
            return String(format: "%@%02X", String(Character(scalar)), value.effectData)
        }
        if value.effectId >= 0x100 {
            let letter: String
            switch value.effectId {
            case ModuleEffect.setSpeed: letter = "A"
            case ModuleEffect.setTempo: letter = "T"
            case ModuleEffect.globalVolume: letter = "V"
            case ModuleEffect.tremor: letter = "I"
            case ModuleEffect.fineVibrato: letter = "U"
            case ModuleEffect.volumeSlideS3M: letter = "D"
            case ModuleEffect.portaDownS3M: letter = "E"
            case ModuleEffect.portaUpS3M: letter = "F"
            default: letter = "?"
            }
            return String(format: "%@%02X", letter, value.effectData)
        }
        if value.effectId >= 0xE0 { return String(format: "E%X%X", value.effectId & 15, value.effectData) }
        return String(format: "%01X%02X", value.effectId, value.effectData)
    }
}

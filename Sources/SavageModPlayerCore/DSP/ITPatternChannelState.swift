// IT trennt den logischen Pattern-Kanal von der klingenden Stimme. In M5 ist
// beiden noch genau eine Vordergrundstimme zugeordnet; der eigene Zustand hält
// aber bereits Channel Volume und Effekt-Memory, damit M7 Hintergrundstimmen
// ergänzen kann, ohne diese kanalbezogenen Werte zu vervielfachen.
public final class ITPatternChannelState: Sendable {
    nonisolated(unsafe) public var channelVolume: Float

    // Index 1...26 entspricht A...Z. Das Array wird vor dem Audiostart einmal
    // angelegt; Zugriffe im Renderpfad ändern nur vorhandene Integerwerte.
    nonisolated(unsafe) private var effectMemory: [UInt8]

    public init(channelVolume: Int) {
        self.channelVolume = Float(max(0, min(64, channelVolume)))
        self.effectMemory = [UInt8](repeating: 0, count: 27)
    }

    @inline(__always)
    public func remembered(command: Int, parameter: Int, memoryCommand: Int? = nil) -> Int {
        let slot = memoryCommand ?? command
        guard (1...26).contains(slot) else { return parameter }
        if parameter != 0 {
            effectMemory[slot] = UInt8(truncatingIfNeeded: parameter)
            return parameter
        }
        return Int(effectMemory[slot])
    }
}

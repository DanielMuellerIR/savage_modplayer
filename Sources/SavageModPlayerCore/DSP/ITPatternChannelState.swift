// IT trennt den logischen Pattern-Kanal von der klingenden Stimme. In M5 ist
// beiden noch genau eine Vordergrundstimme zugeordnet; der eigene Zustand hält
// aber bereits Channel Volume und Effekt-Memory, damit M7 Hintergrundstimmen
// ergänzen kann, ohne diese kanalbezogenen Werte zu vervielfachen.
public final class ITPatternChannelState: Sendable {
    public let channelIndex: Int
    nonisolated(unsafe) public var channelVolume: Float
    nonisolated(unsafe) public var channelPanning: Float
    nonisolated(unsafe) public var foregroundVoiceIndex: Int
    nonisolated(unsafe) public var isMuted: Bool
    nonisolated(unsafe) public var isSoloed: Bool
    nonisolated(unsafe) public var isSurround: Bool
    nonisolated(unsafe) public var channelVolumeSlide: Float = 0
    // Panning-Schritt in normierten 0...1-Einheiten pro Tick.
    nonisolated(unsafe) public var panningSlide: Float = 0
    // Wxy wirkt pro IT-Patternkanal; mehrere aktive Slides addieren sich.
    nonisolated(unsafe) public var globalVolumeSlide: Int = 0
    nonisolated(unsafe) public var vibratoWaveform: Int = 0
    nonisolated(unsafe) public var tremoloWaveform: Int = 0
    nonisolated(unsafe) public var panbrelloWaveform: Int = 0
    nonisolated(unsafe) public var glissandoEnabled: Bool = false
    nonisolated(unsafe) public var highOffset: Int = 0
    nonisolated(unsafe) public var activeFilterMacro: Int = 0
    nonisolated(unsafe) public var patternLoopStartRow: Int = 0
    nonisolated(unsafe) public var patternLoopCount: Int = -1
    // 0 = erste Ausfuehrung der Zeile, >0 = Wiederholung durch SEx.
    nonisolated(unsafe) public var rowRepeatIndex: Int = 0

    // Index 1...26 entspricht A...Z. Das Array wird vor dem Audiostart einmal
    // angelegt; Zugriffe im Renderpfad ändern nur vorhandene Integerwerte.
    nonisolated(unsafe) private var effectMemory: [UInt8]
    nonisolated(unsafe) private var pitchSlideMemory: Int = 0
    nonisolated(unsafe) private var tonePortamentoMemory: Int = 0
    nonisolated(unsafe) private var volumeColumnSlideMemory: Int = 0

    public init(
        channelIndex: Int = 0,
        channelVolume: Int,
        channelPanning: Float = 0.5,
        foregroundVoiceIndex: Int? = nil,
        isMuted: Bool = false,
        isSoloed: Bool = false,
        isSurround: Bool = false
    ) {
        self.channelIndex = channelIndex
        self.channelVolume = Float(max(0, min(64, channelVolume)))
        self.channelPanning = max(0, min(1, channelPanning))
        self.foregroundVoiceIndex = foregroundVoiceIndex ?? channelIndex
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.isSurround = isSurround
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

    // IT teilt E/F-Memory. G besitzt bei Compatible-Gxx ein eigenes Memory;
    // ohne das Flag propagieren beide Speicher ihre neuen Werte gegenseitig.
    @inline(__always)
    public func rememberedPitchSlide(
        parameter: Int,
        tonePortamento: Bool,
        compatibleGxx: Bool
    ) -> Int {
        if tonePortamento {
            if parameter != 0 {
                tonePortamentoMemory = parameter
                if !compatibleGxx { pitchSlideMemory = parameter }
            } else if !compatibleGxx {
                tonePortamentoMemory = pitchSlideMemory
            }
            return tonePortamentoMemory
        }
        if parameter != 0 {
            pitchSlideMemory = parameter
            if !compatibleGxx { tonePortamentoMemory = parameter }
        }
        return pitchSlideMemory
    }

    // A/B/C/D der IT-Volume-Column teilen ein eigenes Memory, ausdrücklich
    // getrennt vom Dxx-Memory der Effektspalte.
    @inline(__always)
    public func rememberedVolumeColumnSlide(_ parameter: Int) -> Int {
        if parameter != 0 { volumeColumnSlideMemory = parameter }
        return volumeColumnSlideMemory
    }

    // Original-IT liest kombinierte Porta-Parameter beider Effektspalten in
    // einer festen Reihenfolge ein. Die eigentliche Effektauswertung verwendet
    // danach nur noch die hier vorbereiteten Speicherwerte.
    @inline(__always)
    public func primeDoublePortamentoMemory(
        effectCommand: Int,
        effectParameter: Int,
        volumeColumn: Int,
        compatibleGxx: Bool
    ) {
        if effectCommand == 7 || effectCommand == 12 {
            _ = rememberedPitchSlide(
                parameter: effectCommand == 7 ? effectParameter : 0,
                tonePortamento: true,
                compatibleGxx: compatibleGxx
            )
        }
        if (193...202).contains(volumeColumn) {
            _ = rememberedPitchSlide(
                parameter: Self.volumeColumnTonePortamentoSpeed(volumeColumn),
                tonePortamento: true,
                compatibleGxx: compatibleGxx
            )
        }
        if (105...114).contains(volumeColumn) {
            _ = rememberedPitchSlide(
                parameter: (volumeColumn - 105) * 4,
                tonePortamento: false,
                compatibleGxx: compatibleGxx
            )
        } else if (115...124).contains(volumeColumn) {
            _ = rememberedPitchSlide(
                parameter: (volumeColumn - 115) * 4,
                tonePortamento: false,
                compatibleGxx: compatibleGxx
            )
        }
        if effectCommand == 5 || effectCommand == 6 {
            _ = rememberedPitchSlide(
                parameter: effectParameter,
                tonePortamento: false,
                compatibleGxx: compatibleGxx
            )
        }
    }

    @inline(__always)
    public static func volumeColumnTonePortamentoSpeed(_ value: Int) -> Int {
        switch value - 193 {
        case 1: return 1
        case 2: return 4
        case 3: return 8
        case 4: return 16
        case 5: return 32
        case 6: return 64
        case 7: return 96
        case 8: return 128
        case 9: return 255
        default: return 0
        }
    }
}

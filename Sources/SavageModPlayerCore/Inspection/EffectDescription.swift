import Foundation

struct EffectDescription: Sendable {
    let id: String
    let code: String
    let title: InspectorText
    let detail: InspectorText
    var volumeColumn = false
    var implemented = true

    private static func make(_ id: String, _ code: String, _ meaning: Meaning, volume: Bool = false, implemented: Bool = true) -> Self {
        Self(id: id, code: code, title: meaning.title, detail: meaning.detail, volumeColumn: volume, implemented: implemented)
    }

    static func main(format: ModuleFormat, id: Int) -> Self {
        let key = "main-\(id)"
        if format == .it, (1...26).contains(id - ModuleEffect.impulseTrackerCommandBase) {
            let command = id - ModuleEffect.impulseTrackerCommandBase
            let meanings: [Meaning] = [.speed, .jump, .breakPattern, .volumeSlide, .pitchDown, .pitchUp, .tonePorta,
                .vibrato, .tremor, .arpeggio, .vibratoVolume, .portaVolume, .channelVolume, .channelVolumeSlide,
                .offset, .panSlide, .retrigger, .tremolo, .special, .tempo, .fineVibrato, .globalVolume,
                .globalVolumeSlide, .panning, .panbrello, .macro]
            let letter = String(UnicodeScalar(64 + command)!)
            return make(key, letter + "xx", meanings[command - 1])
        }
        let s3m = format == .s3m
        let standard: [Int: (String, Meaning)] = [
            0: (s3m ? "Jxy" : "0xy", .arpeggio), 1: ("1xx", .pitchUp), 2: ("2xx", .pitchDown),
            3: (s3m ? "Gxx" : "3xx", .tonePorta), 4: (s3m ? "Hxy" : "4xy", .vibrato),
            5: (s3m ? "Lxy" : "5xy", .portaVolume), 6: (s3m ? "Kxy" : "6xy", .vibratoVolume),
            7: (s3m ? "Rxy" : "7xy", .tremolo), 8: (s3m ? "Xxx" : "8xx", .panning),
            9: (s3m ? "Oxx" : "9xx", .offset), 10: ("Axy", .volumeSlide), 11: ("Bxx", .jump),
            12: ("Cxx", .volume), 13: (s3m ? "Cxx" : "Dxx", .breakPattern), 15: ("Fxx", .speedTempo),
            0xE0: ("E0x", .filterToggle), 0xE1: ("E1x", .finePitchUp), 0xE2: ("E2x", .finePitchDown),
            0xE3: ("E3x", .glissando), 0xE4: ("E4x", .vibratoWave), 0xE5: ("E5x", .finetune),
            0xE6: (s3m ? "SBx" : "E6x", .patternLoop), 0xE7: ("E7x", .tremoloWave),
            0xE8: (s3m ? "S8x" : "E8x", .panning), 0xE9: (s3m ? "Qxy" : "E9x", s3m ? .s3mRetrigger : .retrigger),
            0xEA: ("EAx", .fineVolumeUp), 0xEB: ("EBx", .fineVolumeDown),
            0xEC: (s3m ? "SCx" : "ECx", .noteCut), 0xED: (s3m ? "SDx" : "EDx", .noteDelay),
            0xEE: (s3m ? "SEx" : "EEx", .patternDelay), 0xEF: ("EFx", .invertLoop),
            ModuleEffect.setSpeed: ("Axx", .speed), ModuleEffect.setTempo: ("Txx", s3m ? .s3mTempo : .tempo),
            ModuleEffect.globalVolume: (s3m ? "Vxx" : "Gxx", .globalVolume),
            ModuleEffect.tremor: (s3m ? "Ixy" : "Txy", .tremor), ModuleEffect.fineVibrato: ("Uxy", .fineVibrato),
            ModuleEffect.volumeSlideS3M: ("Dxy", .volumeSlide), ModuleEffect.portaDownS3M: ("Exx", .pitchDown),
            ModuleEffect.portaUpS3M: ("Fxx", .pitchUp), ModuleEffect.globalVolumeSlide: ("Hxy", .globalVolumeSlide),
            ModuleEffect.keyOff: ("Kxx", .keyOff), ModuleEffect.setEnvelopePos: ("Lxx", .envelopePosition),
            ModuleEffect.panSlide: ("Pxy", .panSlide), ModuleEffect.multiRetrig: ("Rxy", .retrigger),
            ModuleEffect.extraFinePortaUp: ("X1x", .finePitchUp), ModuleEffect.extraFinePortaDown: ("X2x", .finePitchDown)
        ]
        guard let item = standard[id] else { return make(key, String(format: "0x%X", id), .unknown, implemented: false) }
        let ignored = [0xE0, 0xE3, 0xE4, 0xE5, 0xE7, 0xEF].contains(id)
        return make(key, item.0, item.1, implemented: !ignored)
    }

    static func volume(format: ModuleFormat, value: Int) -> Self {
        let item: (Int, String, Meaning)
        if format == .xm {
            switch value {
            case 0x10...0x50: item = (0x10, "10–50", .volume)
            case 0x60...0x6F: item = (0x60, "6x", .volumeDown)
            case 0x70...0x7F: item = (0x70, "7x", .volumeUp)
            case 0x80...0x8F: item = (0x80, "8x", .fineVolumeDown)
            case 0x90...0x9F: item = (0x90, "9x", .fineVolumeUp)
            case 0xA0...0xAF: item = (0xA0, "Ax", .vibratoSpeed)
            case 0xB0...0xBF: item = (0xB0, "Bx", .vibrato)
            case 0xC0...0xCF: item = (0xC0, "Cx", .panning)
            case 0xD0...0xDF: item = (0xD0, "Dx", .panLeft)
            case 0xE0...0xEF: item = (0xE0, "Ex", .panRight)
            case 0xF0...0xFF: item = (0xF0, "Fx", .tonePorta)
            default: item = (value, String(format: "%02X", value), .unknown)
            }
        } else {
            switch value {
            case 0...64: item = (0, "0–64", .volume)
            case 65...74: item = (65, "65–74", .fineVolumeUp)
            case 75...84: item = (75, "75–84", .fineVolumeDown)
            case 85...94: item = (85, "85–94", .volumeUp)
            case 95...104: item = (95, "95–104", .volumeDown)
            case 105...114: item = (105, "105–114", .pitchDown)
            case 115...124: item = (115, "115–124", .pitchUp)
            case 128...192: item = (128, "128–192", .panning)
            case 193...202: item = (193, "193–202", .tonePorta)
            case 203...212: item = (203, "203–212", .vibrato)
            case 223...232: item = (223, "223–232", .offset)
            default: item = (value, "\(value)", .unknown)
            }
        }
        return make("volume-\(item.0)", "v " + item.1, item.2, volume: true, implemented: item.2 != .unknown)
    }

    private enum Meaning {
        case arpeggio, pitchUp, pitchDown, tonePorta, vibrato, portaVolume, vibratoVolume, tremolo, panning, offset
        case volumeSlide, volume, jump, breakPattern, speedTempo, speed, tempo, s3mTempo, patternLoop, patternDelay
        case finePitchUp, finePitchDown, fineVolumeUp, fineVolumeDown, retrigger, s3mRetrigger, noteCut, noteDelay
        case tremor, fineVibrato, globalVolume, globalVolumeSlide, keyOff, envelopePosition, panSlide, channelVolume
        case channelVolumeSlide, special, panbrello, macro, filterToggle, glissando, vibratoWave, finetune, tremoloWave, invertLoop
        case volumeUp, volumeDown, panLeft, panRight, vibratoSpeed, unknown

        var title: InspectorText {
            switch self {
            case .arpeggio: return .init("Arpeggio", "Arpeggio")
            case .pitchUp, .finePitchUp: return .init("Tonhöhe aufwärts", "Pitch slide up")
            case .pitchDown, .finePitchDown: return .init("Tonhöhe abwärts", "Pitch slide down")
            case .tonePorta: return .init("Zielton gleiten", "Tone portamento")
            case .vibrato: return .init("Vibrato", "Vibrato")
            case .portaVolume: return .init("Portamento und Lautstärke", "Portamento and volume slide")
            case .vibratoVolume: return .init("Vibrato und Lautstärke", "Vibrato and volume slide")
            case .tremolo: return .init("Tremolo", "Tremolo")
            case .panning: return .init("Stereo-Position", "Panning")
            case .offset: return .init("Sample-Einstieg", "Sample offset")
            case .volumeSlide, .volumeUp, .volumeDown, .fineVolumeUp, .fineVolumeDown: return .init("Lautstärke ändern", "Volume slide")
            case .volume: return .init("Lautstärke setzen", "Set volume")
            case .jump: return .init("Songposition anspringen", "Position jump")
            case .breakPattern: return .init("Pattern verlassen", "Pattern break")
            case .speedTempo: return .init("Speed oder Tempo", "Speed or tempo")
            case .speed: return .init("Ticks pro Zeile", "Ticks per row")
            case .tempo, .s3mTempo: return .init("Tempo", "Tempo")
            case .patternLoop: return .init("Pattern-Schleife", "Pattern loop")
            case .patternDelay: return .init("Pattern-Verzögerung", "Pattern delay")
            case .retrigger, .s3mRetrigger: return .init("Note erneut starten", "Retrigger note")
            case .noteCut: return .init("Note abschneiden", "Note cut")
            case .noteDelay: return .init("Note verzögern", "Note delay")
            case .tremor: return .init("Tremor", "Tremor")
            case .fineVibrato: return .init("Feines Vibrato", "Fine vibrato")
            case .globalVolume: return .init("Gesamtlautstärke", "Global volume")
            case .globalVolumeSlide: return .init("Gesamtlautstärke ändern", "Global volume slide")
            case .keyOff: return .init("Taste loslassen", "Key off")
            case .envelopePosition: return .init("Hüllkurvenposition", "Envelope position")
            case .panSlide, .panLeft, .panRight: return .init("Stereo-Position ändern", "Panning slide")
            case .channelVolume: return .init("Kanal-Lautstärke", "Channel volume")
            case .channelVolumeSlide: return .init("Kanal-Lautstärke ändern", "Channel volume slide")
            case .special: return .init("IT-Spezialbefehl", "IT special command")
            case .panbrello: return .init("Panbrello", "Panbrello")
            case .macro: return .init("Filtermakro", "Filter macro")
            case .filterToggle: return .init("Filter schalten", "Filter toggle")
            case .glissando: return .init("Glissando", "Glissando")
            case .vibratoWave: return .init("Vibrato-Wellenform", "Vibrato waveform")
            case .finetune: return .init("Finetune setzen", "Set finetune")
            case .tremoloWave: return .init("Tremolo-Wellenform", "Tremolo waveform")
            case .invertLoop: return .init("Sample-Loop invertieren", "Invert sample loop")
            case .vibratoSpeed: return .init("Vibrato-Geschwindigkeit", "Vibrato speed")
            case .unknown: return .init("Unbekannter Befehl", "Unknown command")
            }
        }
        var detail: InspectorText {
            switch self {
            case .arpeggio: return .init("Wechselt im Tick-Raster zwischen Grundton und zwei Halbtonabständen.", "Cycles between the base note and two semitone offsets on ticks.")
            case .pitchUp: return .init("Erhöht die Tonhöhe schrittweise; Fine- und Memory-Regeln hängen vom Format ab.", "Raises pitch in steps; fine-slide and memory rules depend on the format.")
            case .pitchDown: return .init("Senkt die Tonhöhe schrittweise; Fine- und Memory-Regeln hängen vom Format ab.", "Lowers pitch in steps; fine-slide and memory rules depend on the format.")
            case .finePitchUp, .finePitchDown: return .init("Ein kleiner Tonhöhenschritt zu Beginn der Zeile statt eines laufenden Slides.", "A small pitch step at the start of the row rather than a continuous slide.")
            case .tonePorta: return .init("Gleitet zum Zielton, ohne das Sample bei jedem Schritt neu zu starten.", "Slides towards the target note without restarting the sample on every step.")
            case .vibrato, .fineVibrato, .vibratoSpeed: return .init("Moduliert die Tonhöhe; Geschwindigkeit, Tiefe und gespeicherte Parameter bestimmen den Verlauf.", "Modulates pitch; speed, depth and remembered parameters determine its movement.")
            case .portaVolume, .vibratoVolume: return .init("Kombiniert die laufende Tonhöhenbewegung mit einem Lautstärke-Slide.", "Combines the existing pitch movement with a volume slide.")
            case .tremolo: return .init("Moduliert die Lautstärke periodisch.", "Periodically modulates volume.")
            case .panning: return .init("Setzt die Stereo-Position; die Zahlenbereiche sind formatspezifisch.", "Sets the stereo position; numeric ranges depend on the format.")
            case .offset: return .init("Startet das Sample an einem versetzten Einstiegspunkt; Format und Effekt-Memory bestimmen die Einheit.", "Starts the sample at an offset; the format and effect memory determine its units.")
            case .volumeSlide, .volumeUp, .volumeDown: return .init("Ändert die Lautstärke in Tick-Schritten; Nullparameter können einen früheren Wert wiederverwenden.", "Changes volume on ticks; zero parameters may reuse an earlier value.")
            case .fineVolumeUp, .fineVolumeDown: return .init("Ändert die Lautstärke einmalig am Zeilenanfang.", "Changes volume once at the start of the row.")
            case .volume, .channelVolume, .globalVolume: return .init("Setzt den gespeicherten Pegel der Note, des Kanals oder des gesamten Moduls.", "Sets the stored level of a note, channel or the whole module.")
            case .jump: return .init("Springt zu einer Songposition. Übernommene Ziele beziehen sich auf die Abspielliste des Players.", "Jumps to a song position. Imported targets refer to the player's order list.")
            case .breakPattern: return .init("Wechselt zur angegebenen Zeile des folgenden Patterns; die Parameterkodierung hängt vom Format ab.", "Continues at the specified row of the next pattern; parameter encoding depends on the format.")
            case .speedTempo: return .init("F01–F1F setzt Ticks pro Zeile, ab F20 das Tempo in BPM. Null hat eigene Tracker-Regeln.", "F01–F1F sets ticks per row; F20 and above set BPM. Zero has its own tracker rules.")
            case .speed: return .init("Bestimmt, wie viele Tracker-Ticks eine Pattern-Zeile dauert.", "Determines the number of tracker ticks in a pattern row.")
            case .tempo: return .init("Setzt das Tempo in BPM oder führt formatspezifische Tempo-Slides aus.", "Sets BPM or applies format-specific tempo slides.")
            case .s3mTempo: return .init("Setzt BPM ab 0x20. S3M-Tempo-Slides darunter werden derzeit nicht ausgeführt.", "Sets BPM from 0x20. Lower S3M tempo-slide values are currently not executed.")
            case .patternLoop: return .init("Markiert den Schleifenanfang oder wiederholt den Pattern-Bereich.", "Marks the loop start or repeats a pattern section.")
            case .patternDelay: return .init("Verlängert die aktuelle Zeile um zusätzliche Zeilendauern.", "Extends the current row by additional row durations.")
            case .retrigger: return .init("Startet das Sample nach einer Tick-Anzahl erneut; kombinierte Lautstärkeregeln sind formatabhängig.", "Restarts the sample after a number of ticks; combined volume rules depend on the format.")
            case .s3mRetrigger: return .init("Wiederholt nach y Ticks. Der S3M-Lautstärkemodifikator x wird beim Import nicht übernommen.", "Retriggers after y ticks. The S3M volume modifier x is not retained during import.")
            case .noteCut: return .init("Schneidet die Note auf dem angegebenen Tick ab.", "Cuts the note on the specified tick.")
            case .noteDelay: return .init("Verschiebt den Notenstart innerhalb der Zeile.", "Delays the note start within the row.")
            case .tremor: return .init("Schaltet den Ton rhythmisch an und aus; IT-Old-Effects beeinflusst die Zählweise.", "Rhythmically gates the sound; IT Old Effects affects tick counting.")
            case .globalVolumeSlide, .channelVolumeSlide: return .init("Ändert den Gesamt- oder Kanalpegel schrittweise mit eigenem Effekt-Memory.", "Slides the global or channel level using its own effect memory.")
            case .keyOff: return .init("Löst die Taste; Sustain und Hüllkurven bestimmen das weitere Ausklingen.", "Releases the key; sustain and envelopes determine the subsequent decay.")
            case .envelopePosition: return .init("Versetzt die laufende Hüllkurve an einen gespeicherten Tick.", "Moves the active envelope to a stored tick position.")
            case .panSlide, .panLeft, .panRight: return .init("Verschiebt die Stereo-Position schrittweise.", "Moves the stereo position in steps.")
            case .special: return .init("Das obere Parameter-Nibble wählt etwa Loop, Delay, NNA, Panning oder Filter-Memory.", "The upper parameter nibble selects loop, delay, NNA, panning or filter memory, among other commands.")
            case .panbrello: return .init("Moduliert die Stereo-Position periodisch.", "Periodically modulates the stereo position.")
            case .macro: return .init("Führt unterstützte interne IT-Filtermakros aus; externe MIDI-/Plugin-Ausgabe bleibt deaktiviert.", "Runs supported internal IT filter macros; external MIDI/plugin output remains disabled.")
            case .filterToggle, .glissando, .vibratoWave, .finetune, .tremoloWave, .invertLoop, .unknown:
                return .init("Dieser übernommene Befehl wird vom Player derzeit nicht ausgeführt.", "This imported command is currently not executed by the player.")
            }
        }
    }
}

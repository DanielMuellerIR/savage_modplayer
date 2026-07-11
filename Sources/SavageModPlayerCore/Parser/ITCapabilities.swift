import Foundation

// Vollstaendige OpenMPT-Version aus CWV./LSWV beziehungsweise .VWC/VWSL.
// Die vier Bytes sind Major, Minor, Patch und Build (z. B. 0x01280400 = 1.28.04.00).
public struct OpenMPTVersion: Sendable, Codable, Equatable, Comparable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var components: [Int] {
        [
            (rawValue >> 24) & 0xFF,
            (rawValue >> 16) & 0xFF,
            (rawValue >> 8) & 0xFF,
            rawValue & 0xFF
        ]
    }

    public var displayName: String {
        let value = components
        return String(format: "%X.%02X.%02X.%02X", value[0], value[1], value[2], value[3])
    }

    public static func < (lhs: OpenMPTVersion, rhs: OpenMPTVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// cwtv identifiziert den Ersteller und ist ausdruecklich keine Formatversion.
public enum ITTrackerFamily: String, Sendable, Codable, Equatable {
    case impulseTracker
    case schismTracker
    case openMPT
    case pyIT
    case beRoTracker
    case itmck
    case tralala
    case chickDune
    case spc2it
    case itwriter
    case roseTracker
    case munch
    case unknown
}

public struct ITTrackerIdentity: Sendable, Codable, Equatable {
    public let family: ITTrackerFamily
    public let rawCreatedWith: Int
    public let displayName: String
    public let compatibilityExport: Bool
    public let createdWithOpenMPT: OpenMPTVersion?
    public let lastSavedWithOpenMPT: OpenMPTVersion?

    public init(
        family: ITTrackerFamily,
        rawCreatedWith: Int,
        displayName: String,
        compatibilityExport: Bool = false,
        createdWithOpenMPT: OpenMPTVersion? = nil,
        lastSavedWithOpenMPT: OpenMPTVersion? = nil
    ) {
        self.family = family
        self.rawCreatedWith = rawCreatedWith
        self.displayName = displayName
        self.compatibilityExport = compatibilityExport
        self.createdWithOpenMPT = createdWithOpenMPT
        self.lastSavedWithOpenMPT = lastSavedWithOpenMPT
    }
}

public enum ITTempoMode: Int, Sendable, Codable, Equatable {
    case classic = 0
    case alternative = 1
    case modern = 2
}

public enum ITMixLevel: Int, Sendable, Codable, Equatable {
    case original = 0
    case openMPT117RC1 = 1
    case openMPT117RC2 = 2
    case openMPT117RC3 = 3
    case compatible = 4
    case compatibleFT2Panning = 5
}

public enum ITExtensionContext: String, Sendable, Codable, Equatable {
    case legacyModPlug
    case instrument
    case song
    case mptm
}

public enum ITExtensionClassification: String, Sendable, Codable, Equatable {
    case playback
    case routing
    case metadata
    case compatibility
    case unknownPlayback
}

// Jeder gelesene Chunk bleibt mit ID, Kontext und Groesse diagnostizierbar.
public struct ITExtensionChunk: Sendable, Codable, Equatable {
    public let id: String
    public let context: ITExtensionContext
    public let size: Int
    public let classification: ITExtensionClassification
    public let summary: String

    public init(
        id: String,
        context: ITExtensionContext,
        size: Int,
        classification: ITExtensionClassification,
        summary: String
    ) {
        self.id = id
        self.context = context
        self.size = size
        self.classification = classification
        self.summary = summary
    }
}

// Ein XTPM-Feld speichert einen Wert pro Instrument. Die typisierte Property-ID
// verhindert, dass der Capability-Audit erneut mit unklaren FOURCCs arbeiten muss.
public enum ITInstrumentExtensionProperty: String, Sendable, Codable, Equatable {
    case fadeout
    case panning
    case midiBank
    case midiProgram
    case midiChannel
    case pluginSlot
    case volumeRamp
    case resamplingMode
    case cutoffSwing
    case resonanceSwing
    case filterMode
    case pluginVelocityHandling
    case pluginVolumeHandling
    case volumeEnvelopeReleaseNode
    case panningEnvelopeReleaseNode
    case pitchEnvelopeReleaseNode
    case midiPitchWheelDepth
    case pitchTempoLockInteger
    case pitchTempoLockFraction
    case extendedSampleMap
    case otherKnown
}

public struct ITInstrumentExtensionField: Sendable, Codable, Equatable {
    public let id: String
    public let property: ITInstrumentExtensionProperty
    public let entrySize: Int
    public let values: [Int]

    public init(
        id: String,
        property: ITInstrumentExtensionProperty,
        entrySize: Int,
        values: [Int]
    ) {
        self.id = id
        self.property = property
        self.entrySize = entrySize
        self.values = values
    }
}

public struct ITPluginDefinition: Sendable, Codable, Equatable {
    public let slot: Int
    public let typeID: Int
    public let uniqueID: Int
    public let routingFlags: Int

    public init(slot: Int, typeID: Int, uniqueID: Int, routingFlags: Int) {
        self.slot = slot
        self.typeID = typeID
        self.uniqueID = uniqueID
        self.routingFlags = routingFlags
    }
}

public struct ITMIDIConfiguration: Sendable, Codable, Equatable {
    public let globalMacros: [String]
    public let parameterizedMacros: [String]
    public let fixedMacros: [String]
    public let usesDefaultFilterSetup: Bool

    public init(
        globalMacros: [String],
        parameterizedMacros: [String],
        fixedMacros: [String],
        usesDefaultFilterSetup: Bool
    ) {
        self.globalMacros = globalMacros
        self.parameterizedMacros = parameterizedMacros
        self.fixedMacros = fixedMacros
        self.usesDefaultFilterSetup = usesDefaultFilterSetup
    }
}

public struct ITChannelSetting: Sendable, Codable, Equatable {
    public let panning: Int
    public let volume: Int
    public let muted: Bool
    public let surround: Bool

    public init(panning: Int, volume: Int, muted: Bool, surround: Bool) {
        self.panning = panning
        self.volume = volume
        self.muted = muted
        self.surround = surround
    }
}

// Die Bitpositionen entsprechen dauerhaft OpenMPTs PlayBehaviour-Enum. Alte
// Positionen duerfen upstream nie entfernt werden; unbekannte neuere Bits werden
// zusaetzlich roh erhalten.
public enum ITPlayBehaviour: Int, CaseIterable, Sendable, Codable {
    case compatiblePlay = 0
    case mptOldSwingBehaviour
    case midiCCBugEmulation
    case oldMIDIPitchBends
    case ft2VolumeRamping
    case modVBlankTiming
    case slidesAtSpeed1
    case periodsAreHertz
    case tempoClamp
    case perChannelGlobalVolumeSlide
    case panOverride
    case itInstrumentWithoutNote
    case itVolumeColumnFinePortamento
    case itArpeggio
    case itOutOfRangeDelay
    case itPortamentoMemoryShare
    case itPatternLoopTargetReset
    case itFT2PatternLoop
    case itPingPongNoReset
    case itEnvelopeReset
    case itClearOldNoteAfterCut
    case itVibratoTremoloPanbrello
    case itTremor
    case itRetrigger
    case itMultiSampleBehaviour
    case itPortamentoTargetReached
    case itPatternLoopBreak
    case itOffset
    case itSwingBehaviour
    case itNNAReset
    case itSCxStopsSample
    case itEnvelopePositionHandling
    case itPortamentoInstrument
    case itPingPongMode
    case itRealNoteMapping
    case itHighOffsetNoRetrigger
    case itFilterBehaviour
    case itNoSurroundPan
    case itShortSampleRetrigger
    case itPortamentoNoNote
    case itFT2DontResetNoteOffOnPortamento
    case itVolumeColumnMemory
    case itPortamentoSwapResetsPosition
    case itEmptyNoteMapSlot
    case itFirstTickHandling
    case itSampleAndHoldPanbrello
    case itClearPortamentoTarget
    case itPanbrelloHold
    case itPanningReset
    case itPatternLoopWithJumpsOld
    case itInstrumentWithNoteOff
    case ft2Arpeggio
    case ft2Retrigger
    case ft2VolumeColumnVibrato
    case ft2PortamentoNoNote
    case ft2KeyOff
    case ft2PanSlide
    case ft2ST3OffsetOutOfRange
    case ft2RestrictXCommand
    case ft2RetriggerWithNoteDelay
    case ft2SetPanEnvelopePosition
    case ft2PortamentoIgnoreInstrument
    case ft2VolumeColumnMemory
    case ft2LoopE60Restart
    case ft2ProcessSilentChannels
    case ft2ReloadSampleSettings
    case ft2PortamentoDelay
    case ft2Transpose
    case ft2PatternLoopWithJumps
    case ft2PortamentoTargetNoReset
    case ft2EnvelopeEscape
    case ft2Tremor
    case ft2OutOfRangeDelay
    case ft2Periods
    case ft2PanWithDelayedNoteOff
    case ft2VolumeColumnDelay
    case ft2FinetunePrecision
    case st3NoMutedChannels
    case st3EffectMemory
    case st3PortamentoSampleChange
    case st3VibratoMemory
    case st3LimitPeriod
    case st3PortamentoAfterArpeggio
    case modOneShotLoops
    case modIgnorePanning
    case modSampleSwap
    case ft2NoteOffFlags
    case itMultiSampleInstrumentNumber
    case rowDelayWithNoteDelay
    case ft2ModTremoloRampWaveform
    case ft2PortamentoUpDownMemory
    case modOutOfRangeNoteDelay
    case modTempoOnSecondTick
    case ft2PanSustainRelease
    case legacyReleaseNode
    case oplBeatingOscillators
    case st3OffsetWithoutInstrument
    case releaseNodePastSustainBug
    case ft2NoteDelayWithoutInstrument
    case oplFlexibleNoteOff
    case itInstrumentWithNoteOffOldEffects
    case midiVolumeOnNoteOffBug
    case itDoNotOverrideChannelPan
    case itPatternLoopWithJumps
    case itDCTBehaviour
    case oplWithNNA
    case st3RetriggerAfterNoteCut
    case st3SampleSwap
    case oplRealRetrigger
    case oplNoResetAtEnvelopeEnd
    case oplNoteStopWithZeroHertz
    case oplNoteOffOnNoteChange
    case ft2PortamentoResetDirection
    case applyUpperPeriodLimit
    case applyOffsetWithoutNote
    case itPitchPanSeparation
    case imprecisePingPongLoops
    case pluginIgnoreTonePortamento
    case st3TonePortamentoWithAdlibNote
    case itResetFilterOnPortamentoSampleChange
    case itInitialNoteMemory
    case pluginDefaultProgramAndBankOne
    case itNoSustainOnPortamento
    case itEmptyNoteMapSlotIgnoreCell
    case itOffsetWithInstrumentNumber
    case continueSampleWithoutInstrument
    case midiNotesFromChannelPlugin
    case itDoublePortamentoSlides
    case s3mIgnoreCombinedFineSlides
    case ft2AutoVibratoAbortSweep
    case legacyPPQPosition
    case legacyPluginNNABehaviour
    case itCarryAfterNoteOff
    case ft2OffsetMemoryRequiresNote
    case itNoteCutWithPortamento
    case itVolumeColumnNoSlidePropagation
    case itStoppedFilterEnvelopeAtStart

    public var displayName: String {
        String(describing: self)
    }
}

public struct ITPlayBehaviourState: Sendable, Codable, Equatable {
    public let bit: Int
    public let behaviour: ITPlayBehaviour?

    public init(bit: Int, behaviour: ITPlayBehaviour?) {
        self.bit = bit
        self.behaviour = behaviour
    }
}

public struct ITOpenMPTExtensions: Sendable, Codable, Equatable {
    public let chunks: [ITExtensionChunk]
    public let instrumentFields: [ITInstrumentExtensionField]
    public let defaultTempo: Int?
    public let rowsPerBeat: Int?
    public let rowsPerMeasure: Int?
    public let channelCount: Int?
    public let extraChannelSettings: [ITChannelSetting]
    public let tempoMode: ITTempoMode
    public let rawTempoMode: Int?
    public let mixLevel: ITMixLevel?
    public let rawMixLevel: Int?
    public let createdWithVersion: OpenMPTVersion?
    public let lastSavedWithVersion: OpenMPTVersion?
    public let samplePreamp: Int?
    public let synthPreamp: Int?
    public let restartPosition: Int?
    public let playBehaviours: [ITPlayBehaviourState]
    public let artist: String?
    public let channelColors: [Int?]
    public let hasMIDIMapping: Bool
    public let midiConfiguration: ITMIDIConfiguration?
    public let channelPluginAssignments: [Int]
    public let plugins: [ITPluginDefinition]
    public let isMPTM: Bool

    public init(
        chunks: [ITExtensionChunk] = [],
        instrumentFields: [ITInstrumentExtensionField] = [],
        defaultTempo: Int? = nil,
        rowsPerBeat: Int? = nil,
        rowsPerMeasure: Int? = nil,
        channelCount: Int? = nil,
        extraChannelSettings: [ITChannelSetting] = [],
        tempoMode: ITTempoMode = .classic,
        rawTempoMode: Int? = nil,
        mixLevel: ITMixLevel? = nil,
        rawMixLevel: Int? = nil,
        createdWithVersion: OpenMPTVersion? = nil,
        lastSavedWithVersion: OpenMPTVersion? = nil,
        samplePreamp: Int? = nil,
        synthPreamp: Int? = nil,
        restartPosition: Int? = nil,
        playBehaviours: [ITPlayBehaviourState] = [],
        artist: String? = nil,
        channelColors: [Int?] = [],
        hasMIDIMapping: Bool = false,
        midiConfiguration: ITMIDIConfiguration? = nil,
        channelPluginAssignments: [Int] = [],
        plugins: [ITPluginDefinition] = [],
        isMPTM: Bool = false
    ) {
        self.chunks = chunks
        self.instrumentFields = instrumentFields
        self.defaultTempo = defaultTempo
        self.rowsPerBeat = rowsPerBeat
        self.rowsPerMeasure = rowsPerMeasure
        self.channelCount = channelCount
        self.extraChannelSettings = extraChannelSettings
        self.tempoMode = tempoMode
        self.rawTempoMode = rawTempoMode
        self.mixLevel = mixLevel
        self.rawMixLevel = rawMixLevel
        self.createdWithVersion = createdWithVersion
        self.lastSavedWithVersion = lastSavedWithVersion
        self.samplePreamp = samplePreamp
        self.synthPreamp = synthPreamp
        self.restartPosition = restartPosition
        self.playBehaviours = playBehaviours
        self.artist = artist
        self.channelColors = channelColors
        self.hasMIDIMapping = hasMIDIMapping
        self.midiConfiguration = midiConfiguration
        self.channelPluginAssignments = channelPluginAssignments
        self.plugins = plugins
        self.isMPTM = isMPTM
    }
}

public enum ITCapabilitySupport: String, Sendable, Codable, Equatable {
    case supported
    case irrelevantForPCM
    case metadataOnly
    case midiOrPluginOnly
    case unsupported
    case differentPlayback
}

public enum ITCapabilityFeature: String, Sendable, Codable, Equatable {
    case formatCompatibility
    case tempoMode
    case mixLevel
    case samplePreamp
    case restartPosition
    case channelLayout
    case instrumentProperty
    case playBehaviour
    case midiInstrument
    case pluginInstrument
    case channelPlugin
    case masterPlugin
    case midiMacro
    case unknownExtension
    case mptmContainer
}

public struct ITCapabilityFinding: Sendable, Codable, Equatable {
    public let feature: ITCapabilityFeature
    public let identifier: String
    public let detected: Bool
    public let used: Bool
    public let support: ITCapabilitySupport
    public let detail: String
    public let warning: String?

    public init(
        feature: ITCapabilityFeature,
        identifier: String,
        detected: Bool,
        used: Bool,
        support: ITCapabilitySupport,
        detail: String,
        warning: String? = nil
    ) {
        self.feature = feature
        self.identifier = identifier
        self.detected = detected
        self.used = used
        self.support = support
        self.detail = detail
        self.warning = warning
    }
}

public struct ITCapabilityReport: Sendable, Codable, Equatable {
    public let findings: [ITCapabilityFinding]

    public init(findings: [ITCapabilityFinding] = []) {
        self.findings = findings
    }

    public var warnings: [String] {
        var seen = Set<String>()
        return findings.compactMap { finding in
            guard finding.detected, finding.used,
                  finding.support == .unsupported || finding.support == .differentPlayback else {
                return nil
            }
            guard let warning = finding.warning, seen.insert(warning).inserted else { return nil }
            return warning
        }
    }
}

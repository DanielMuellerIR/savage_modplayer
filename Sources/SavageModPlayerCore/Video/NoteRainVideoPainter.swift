#if canImport(CoreGraphics) && canImport(CoreText)
import Foundation
import CoreGraphics
import CoreText

struct NoteRainVideoPainter {
    let options: NoteRainVideoOptions
    let title: String
    let format: String
    let channelCount: Int
    private let keys: [Int]
    private let centers: [Double]
    private let keyWidth: Double
    private let keyboardHeight: Double
    private let strike: Double
    private let scale: Double
    private let left: Double
    private let right: Double
    private let top = 64.0
    private let colors: [CGColor]
    private let visible: [Bool]

    init(options: NoteRainVideoOptions, title: String, format: String, channelCount: Int) {
        self.options = options; self.title = title; self.format = format; self.channelCount = channelCount
        var lower = options.keyRange.lowerBound, upper = options.keyRange.upperBound
        if Self.isBlack(lower) { lower -= 1 }
        if Self.isBlack(upper) { upper += 1 }
        keys = Array(lower...upper)
        let whites = keys.filter { !Self.isBlack($0) }
        let availableWidth = Double(options.width) - 60
        let canvasHeight = Double(options.height) - 76
        keyWidth = max(1, min(availableWidth / Double(whites.count), min(144, canvasHeight * 0.28) / 4.8))
        keyboardHeight = keyWidth * 4.8
        left = 42 + (availableWidth - keyWidth * Double(whites.count)) / 2
        right = Double(options.width) - left - keyWidth * Double(whites.count)
        strike = Double(options.height) - 22 - keyboardHeight
        scale = max(1, strike - top) / Double(options.lookaheadSeconds)
        var centers = [Double](repeating: 0, count: 120), whiteIndex = 0
        for key in keys {
            centers[key] = left + Double(whiteIndex) * keyWidth + (Self.isBlack(key) ? 0 : keyWidth / 2)
            if !Self.isBlack(key) { whiteIndex += 1 }
        }
        self.centers = centers
        colors = (0..<64).map(Self.channelColor)
        let mutes = Set(options.audio.mutedChannels ?? []), solos = Set(options.audio.soloChannels)
        visible = (0..<64).map { !mutes.contains($0) && (solos.isEmpty || solos.contains($0)) }
    }

    func draw(_ context: CGContext, notes sourceNotes: [PreviewNote], sampleFrame: UInt64) {
        let time = Double(sampleFrame) / Double(NoteRainVideoOptions.sampleRate)
        let notes = sourceNotes.filter { ($0.key >= keys[0] && $0.key <= keys[keys.count - 1]) && visible.indices.contains($0.channel) && visible[$0.channel] }
            .sorted { a, b in
                if a.start != b.start { return a.start < b.start }
                if a.channel != b.channel { return a.channel < b.channel }
                if a.key != b.key { return a.key < b.key }
                return a.id < b.id
            }
        let light = options.appearance == .light
        let background = Self.rgb(light ? [0.965, 0.970, 0.980] : [0.020, 0.024, 0.030])
        let foreground = Self.rgb(light ? [0.075, 0.090, 0.115] : [0.925, 0.930, 0.940])
        let faint = CGColor(gray: light ? 0 : 1, alpha: 0.08)
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: 0, y: Double(options.height)); context.scaleBy(x: 1, y: -1)
        context.setFillColor(background); context.fill(CGRect(x: 0, y: 0, width: options.width, height: options.height))
        text(title.isEmpty ? format : title, at: CGPoint(x: 20, y: 26), size: 16, color: foreground, context: context,
             maximumWidth: Double(options.width - 186))
        let milliseconds = sampleFrame * 1000 / UInt64(NoteRainVideoOptions.sampleRate)
        let timeText = String(format: "%02llu:%02llu.%03llu", milliseconds / 60000, milliseconds / 1000 % 60, milliseconds % 1000)
        text(timeText, at: CGPoint(x: options.width - 150, y: 26), size: 13, color: foreground, context: context)
        text("\(format) · \(channelCount) ch", at: CGPoint(x: 20, y: 45), size: 10, color: foreground, context: context)
        for key in keys {
            if Self.isBlack(key) {
                context.setFillColor(CGColor(gray: light ? 0 : 1, alpha: light ? 0.035 : 0.025))
                context.fill(CGRect(x: centers[key] - keyWidth * 0.31, y: top, width: keyWidth * 0.62, height: strike - top))
            }
            if key % 12 == 0 { line(from: CGPoint(x: centers[key] - keyWidth / 2, y: top), to: CGPoint(x: centers[key] - keyWidth / 2, y: strike), color: faint, context: context) }
        }
        for second in 0...options.lookaheadSeconds {
            let y = strike - Double(second) * scale
            line(from: CGPoint(x: left, y: y), to: CGPoint(x: Double(options.width) - right, y: y), color: faint, context: context)
            text("+\(second)s", at: CGPoint(x: left - 32, y: y + 3), size: 9, color: foreground, context: context)
        }
        let rain = CGRect(x: left, y: top, width: Double(options.width) - left - right, height: strike - top)
        context.saveGState(); context.clip(to: rain)
        for note in notes where note.end > time && note.start < time + Double(options.lookaheadSeconds) {
            let width = max(3, keyWidth * (Self.isBlack(note.key) ? 0.52 : 0.68))
            let bottom = strike - (note.start - time) * scale
            let upper = strike - (note.end - time) * scale
            let rect = CGRect(x: centers[note.key] - width / 2, y: upper, width: width, height: max(2, bottom - upper))
            context.setFillColor(colors[note.channel]); context.addPath(CGPath(roundedRect: rect, cornerWidth: min(3, width * 0.15), cornerHeight: min(3, width * 0.15), transform: nil)); context.fillPath()
            let intersection = rect.intersection(rain)
            if width >= 18, intersection.height >= 18 {
                text(note.name, at: CGPoint(x: rect.minX + 2, y: intersection.maxY - 4), size: 9, color: CGColor(gray: 0, alpha: 0.85), context: context, maximumWidth: width - 4)
            }
        }
        context.restoreGState()
        var active = [[Int]](repeating: [], count: 120)
        for note in notes where note.start <= time && note.end > time { active[note.key].append(note.channel) }
        for black in [false, true] {
            for key in keys where Self.isBlack(key) == black {
                let width = keyWidth * (black ? 0.62 : 1)
                let rect = CGRect(x: centers[key] - width / 2, y: strike, width: width, height: keyboardHeight * (black ? 0.63 : 1))
                context.setFillColor(CGColor(gray: black ? 0.10 : 0.90, alpha: 1)); context.fill(rect)
                if let channel = active[key].first {
                    context.setFillColor(colors[channel].copy(alpha: black ? 0.32 : 0.22)!); context.fill(rect)
                    let segment = width / Double(active[key].count)
                    for (index, channel) in active[key].enumerated() {
                        context.setFillColor(colors[channel]); context.fill(CGRect(x: rect.minX + Double(index) * segment, y: strike, width: segment, height: 3))
                    }
                }
                context.setStrokeColor(CGColor(gray: 0, alpha: 0.5)); context.setLineWidth(0.6); context.stroke(rect)
                if key % 12 == 0 && width >= 15 {
                    text(PreviewNote.name(for: key), at: CGPoint(x: rect.minX + 2, y: rect.maxY - 8), size: 9,
                         color: CGColor(gray: black ? 1 : 0, alpha: 0.8), context: context, maximumWidth: width - 4)
                }
            }
        }
        line(from: CGPoint(x: left, y: strike), to: CGPoint(x: Double(options.width) - right, y: strike), color: colors[0], width: 2, context: context)
        let shown = min(channelCount, max(1, (options.width - 80) / 38))
        for channel in 0..<shown {
            let x = 20.0 + Double(channel) * 38
            context.setFillColor(colors[channel].copy(alpha: visible[channel] ? 1 : 0.25)!)
            context.fillEllipse(in: CGRect(x: x, y: Double(options.height) - 14, width: 6, height: 6))
            text("\(channel + 1)", at: CGPoint(x: x + 10, y: Double(options.height) - 7), size: 9,
                 color: foreground, context: context)
        }
        if shown < channelCount { text("…", at: CGPoint(x: 20 + shown * 38, y: options.height - 7), size: 10, color: foreground, context: context) }
    }

    private func line(from: CGPoint, to: CGPoint, color: CGColor, width: Double = 1, context: CGContext) {
        context.setStrokeColor(color); context.setLineWidth(width); context.move(to: from); context.addLine(to: to); context.strokePath()
    }
    private func text(_ text: String, at point: CGPoint, size: Double, color: CGColor, context: CGContext, maximumWidth: Double? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [.init(rawValue: kCTFontAttributeName as String): CTFontCreateWithName("Menlo" as CFString, size, nil),
            .init(rawValue: kCTForegroundColorAttributeName as String): color]
        var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        if let maximumWidth, CTLineGetTypographicBounds(line, nil, nil, nil) > maximumWidth {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            line = CTLineCreateTruncatedLine(line, maximumWidth, .middle, ellipsis) ?? ellipsis
        }
        context.saveGState(); context.translateBy(x: point.x, y: point.y); context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity; context.textPosition = .zero; CTLineDraw(line, context); context.restoreGState()
    }
    private static func isBlack(_ key: Int) -> Bool { [1, 3, 6, 8, 10].contains(key % 12) }
    private static func rgb(_ values: [Double]) -> CGColor { CGColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: 1) }
    private static func channelColor(_ channel: Int) -> CGColor {
        let hue = (Double(channel) * 0.381966 + 0.54).truncatingRemainder(dividingBy: 1) * 6
        let sector = Int(hue), fraction = hue - Double(sector), value = 0.88, saturation = 0.58
        let p = value * (1 - saturation), q = value * (1 - saturation * fraction), t = value * (1 - saturation * (1 - fraction))
        switch sector {
        case 0: return rgb([value,t,p])
        case 1: return rgb([q,value,p])
        case 2: return rgb([p,value,t])
        case 3: return rgb([p,q,value])
        case 4: return rgb([t,p,value])
        default: return rgb([value,p,q])
        }
    }
}
#endif

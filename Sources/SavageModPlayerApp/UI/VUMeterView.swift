import SwiftUI

struct VUMeterView: View {
    let value: Float // 0..1.0
    let theme: PlayerTheme
    
    var body: some View {
        // Segmentierter LED-Peak-Meter, gezeichnet in EINEM Canvas statt als
        // VStack aus 12 schattierten Rechtecken. Bei vielen Kanälen (XM/S3M bis
        // 32) sparte der frühere View-Baum-Ansatz ~12 Layout-Knoten pro Kanal —
        // 32 Kanäle × 12 = ~380 Knoten, 30×/s neu gelayoutet (Haupt-CPU-Posten,
        // 2026-07-09). Canvas zeichnet immediate-mode: 1 Knoten pro Meter.
        // (Der frühere dezente LED-Schein/Shadow entfällt bewusst — er war teuer.)
        Canvas { ctx, size in
            let count = 12
            let gap: CGFloat = 2
            let segH = (size.height - 4 - gap * CGFloat(count - 1)) / CGFloat(count)
            guard segH > 0 else { return }
            for idx in 0..<count {
                let threshold = Float(idx) / Float(count)
                let isActive = value >= threshold
                // idx 0 = unterstes Segment.
                let y = size.height - 2 - CGFloat(idx + 1) * segH - CGFloat(idx) * gap
                let rect = CGRect(x: 0, y: y, width: size.width, height: segH)
                let color = isActive ? ledColor(for: threshold) : inactiveColor
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
            }
        }
    }

    private var inactiveColor: Color {
        theme == .workbench ? Color.black.opacity(0.07) : Color.white.opacity(0.04)
    }

    private func ledColor(for threshold: Float) -> Color {
        if threshold > 0.85 {
            return .red
        } else if threshold > 0.65 {
            return .orange
        } else if threshold > 0.4 {
            // Light: kraeftiger Blau-Akzent; Dark: helles Glow-Cyan
            return theme == .workbench ? .lightAccent : .spaceAccentGlow
        } else {
            return theme == .workbench ? Color.lightAccent.opacity(0.65) : .spaceAccent
        }
    }
}

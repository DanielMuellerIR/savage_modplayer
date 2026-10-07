import AppKit
import Combine
import SwiftUI

@MainActor
final class NoteRainWindowState: ObservableObject {
    static let defaultWidth: CGFloat = 1100
    static let minimumKeyboardWidth: CGFloat = 720
    static let minimumFocusedWidth: CGFloat = 420
    static let minimumHeight: CGFloat = 440

    @Published private(set) var keyWidth: CGFloat?
    private weak var window: NSWindow?
    private var normalWidth = defaultWidth
    private var normalCanvasHeight: CGFloat = 600
    private var zoomed: Bool?
    private var fullKeyRange = 9...96
    private var keyRange = 9...96
    private var canvasSize = CGSize.zero

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        apply(reattached: true)
    }

    func configure(zoomed: Bool, fullKeyRange: ClosedRange<Int>,
                   keyRange: ClosedRange<Int>, canvasSize: CGSize) {
        let modeChanged = self.zoomed != zoomed
        let rangeChanged = self.keyRange != keyRange
        let fullRangeChanged = self.fullKeyRange != fullKeyRange
        self.zoomed = zoomed
        self.fullKeyRange = fullKeyRange
        self.keyRange = keyRange
        self.canvasSize = canvasSize
        apply(modeChanged: modeChanged, rangeChanged: rangeChanged, fullRangeChanged: fullRangeChanged)
    }

    private func apply(modeChanged: Bool = false, rangeChanged: Bool = false,
                       fullRangeChanged: Bool = false, reattached: Bool = false) {
        guard let window, let zoomed, canvasSize.width > 0, canvasSize.height > 0 else { return }
        if !zoomed {
            setMinimumWidth(Self.minimumKeyboardWidth, in: window)
            if modeChanged || reattached {
                if keyWidth != nil { setWidth(normalWidth, in: window) }
            } else {
                normalWidth = window.contentRect(forFrameRect: window.frame).width
                normalCanvasHeight = canvasSize.height
            }
            if keyWidth != nil { keyWidth = nil }
        } else {
            if modeChanged && keyWidth == nil && !reattached {
                normalWidth = window.contentRect(forFrameRect: window.frame).width
                normalCanvasHeight = canvasSize.height
            }
            if modeChanged || fullRangeChanged || keyWidth == nil {
                keyWidth = NoteRainLayout(size: CGSize(width: normalWidth, height: normalCanvasHeight),
                    keyRange: fullKeyRange, horizon: 4).keyWidth
            }
            let whiteCount = keyRange.filter { !NoteRainLayout.isBlack($0) }.count
            let width = max(Self.minimumFocusedWidth, NoteRainLayout.horizontalMargins + CGFloat(whiteCount) * (keyWidth ?? 20))
            setMinimumWidth(width, in: window)
            if modeChanged || rangeChanged || fullRangeChanged || reattached { setWidth(width, in: window) }
        }
    }

    private func setMinimumWidth(_ width: CGFloat, in window: NSWindow) {
        let size = NSSize(width: width, height: Self.minimumHeight)
        if window.contentMinSize != size { window.contentMinSize = size }
    }

    private func setWidth(_ width: CGFloat, in window: NSWindow) {
        let contentWidth = window.contentRect(forFrameRect: window.frame).width
        guard abs(contentWidth - width) > 0.5 else { return }
        var frame = window.frame
        frame.origin.x += (contentWidth - width) / 2
        frame.size.width += width - contentWidth
        window.setFrame(frame, display: true)
    }
}

struct NoteRainWindowAccess: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: WindowProbe, context: Context) { view.onWindow = onWindow }

    final class WindowProbe: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else { return }
                onWindow?(window)
            }
        }
    }
}

// Fokusfreier WebKit-Smoke mit echter AudioWorklet-Laufzeit und sichtbarem Status.
import AppKit
import WebKit
final class Runner: NSObject, WKNavigationDelegate {
    var web: WKWebView!
    var window: NSWindow!
    var tick = 0
    func start() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1080, height: 850), configuration: config)
        web.navigationDelegate = self
        window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web
        web.load(URLRequest(url: URL(string: "\(CommandLine.arguments[1])")!))
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] timer in
            tick += 1
            if tick > 50 { print("TIMEOUT"); timer.invalidate(); exit(1) }
            web.evaluateJavaScript("document.getElementById('drop-autoplay-test-result')?.textContent") { value, error in
                if let string = value as? String, string.contains("\"ok\": true") {
                    print(string)
                    self.web.evaluateJavaScript("document.getElementById('play-btn')?.click(); window.__savageDebug.getState()") { state, error in
                        guard error == nil, let state = state as? [String: Any],
                              state["playerPlaying"] as? Bool == false else {
                            print("STOP fehlgeschlagen:", state as Any, error as Any); exit(1)
                        }
                        print("STOP:", state)
                        self.web.takeSnapshot(with: nil) { image, error in
                            if let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                                do { try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
                                catch { print(error); exit(1) }
                            } else {
                                print("WebKit-Screenshot fehlgeschlagen:", error as Any); exit(1)
                            }
                            exit(0)
                        }
                    }
                } else if let string = value as? String, string == "idle" {
                    self.web.evaluateJavaScript("document.getElementById('volume').value = '0'; document.getElementById('volume').dispatchEvent(new Event('input')); document.getElementById('run-drop-autoplay-test').click()", completionHandler: nil)
                } else if let string = value as? String, string.contains("FAILED") {
                    print(string); exit(1)
                }
            }
        }
    }
}
guard CommandLine.arguments.count == 3 else {
    print("Aufruf: swift Tests/webkit_smoke.swift <Player-URL mit ?testDropAutoplay=1> <PNG-Pfad>"); exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let runner = Runner()
runner.start()
app.run()

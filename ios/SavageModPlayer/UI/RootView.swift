import SwiftUI

// PLATZHALTER — wird in Phase 6 durch die echte TabView-Oberflaeche ersetzt.
// Existiert vorerst nur, damit das Projektgeruest baut und im Simulator startet.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
            Text("Savage Mod Player")
                .font(.title2.bold())
        }
    }
}

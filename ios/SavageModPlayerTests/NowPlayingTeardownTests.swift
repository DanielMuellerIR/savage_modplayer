import XCTest
@testable import SavageModPlayer

/// Die Fernsteuerungs-Empfaenger im Sperrbildschirm werden garantiert wieder
/// abgemeldet.
///
/// Hintergrund (Code-Review 2026-08-02): `MPRemoteCommandCenter` ist global und
/// gehoert dem System. `deactivate()` wurde ausserhalb von `activate()` nie
/// gerufen — eine freigegebene Instanz liess ihre Empfaenger also fuer immer
/// angemeldet. Sie liefen ins Leere (`[weak self]`), meldeten dem System aber
/// weiterhin Erfolg, und in Tests mit mehreren Instanzen sammelte sich das an.
///
/// Das System gibt keine Auskunft darueber, wie viele Empfaenger angemeldet
/// sind. Geprueft wird deshalb die eigene Buchfuehrung des Halters — genau die
/// Groesse, die vorher nie wieder auf null ging.
@MainActor
final class NowPlayingTeardownTests: XCTestCase {

    override func setUp() async throws {
        // Frueher erzeugte Instanzen anderer Suiten koennen noch in der
        // Freigabe stecken; ihr Abmelden laeuft ueber den Hauptthread.
        await settle()
    }

    /// Laesst anstehende Abmeldungen auf dem Hauptthread durchlaufen.
    private func settle() async {
        for _ in 0..<10 {
            if NowPlayingController.registeredCommandCount == 0 { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testActivateRegistersAndDeactivateRemovesEveryHandler() async {
        let before = NowPlayingController.registeredCommandCount
        let controller = NowPlayingController()

        controller.activate()
        XCTAssertGreaterThan(
            NowPlayingController.registeredCommandCount, before,
            "activate() muss Empfaenger anmelden")

        controller.deactivate()
        await settle()
        XCTAssertEqual(
            NowPlayingController.registeredCommandCount, before,
            "deactivate() muss jeden Empfaenger wieder abmelden")
    }

    /// Zweimal anmelden darf nicht doppelt zaehlen — `activate()` meldet vorher
    /// ab.
    func testRepeatedActivateDoesNotAccumulate() async {
        let controller = NowPlayingController()
        controller.activate()
        let afterFirst = NowPlayingController.registeredCommandCount

        controller.activate()
        await settle()
        XCTAssertEqual(NowPlayingController.registeredCommandCount, afterFirst)

        controller.deactivate()
    }

    /// Der eigentliche Punkt des Reviews: Auch ohne `deactivate()` bleibt nach
    /// dem Freigeben kein Empfaenger zurueck.
    func testReleasingWithoutDeactivateStillRemovesEveryHandler() async {
        let before = NowPlayingController.registeredCommandCount

        do {
            let controller = NowPlayingController()
            controller.activate()
            XCTAssertGreaterThan(NowPlayingController.registeredCommandCount, before)
            // Hier endet der Gueltigkeitsbereich — niemand ruft deactivate().
        }

        await settle()
        XCTAssertEqual(
            NowPlayingController.registeredCommandCount, before,
            "Eine freigegebene Instanz darf keine Empfaenger hinterlassen")
    }
}

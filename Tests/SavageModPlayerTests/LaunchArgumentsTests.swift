import XCTest
@testable import SavageModPlayerCore

/// Tests der Startargument-Auswertung der Mac-App (`SavageModPlayer <pfad>`).
///
/// Hintergrund (2026-08-23): Ein positionales Startargument liess die App ohne
/// Fenster starten. Die Ursache lag in AppKit (siehe `LaunchArguments` und
/// `SavageModPlayerApp.init()`), nicht in dieser Auswertung — der Fensterbeleg
/// bleibt deshalb der Startlauf mit `Tests/launch_argument_smoke.sh`. Hier ist
/// abgesichert, dass die Argumentlogik selbst ohne laufende Oberflaeche stimmt:
/// welcher Pfad gewinnt, welche Argumente uebersprungen werden und wie
/// `--autoplay` gelesen wird.
final class LaunchArgumentsTests: XCTestCase {
    func testCollectionArgumentIsSeparateFromAudioAndSkipsFlagValues() {
        let file = "/synthetic/a.savagecollection", second = "/synthetic/b.SAVAGECOLLECTION"
        let probe: (String) -> LaunchArguments.PathKind = { [file, second].contains($0) ? .file : .missing }
        XCTAssertEqual(LaunchArguments.collectionArgument(["App", file], probe: probe)?.path, file)
        XCTAssertNil(LaunchArguments.fileArgument(["App", file], probe: probe))
        XCTAssertEqual(LaunchArguments.collectionArgument(["App", "-ApplePersistenceIgnoreState", file, second], probe: probe)?.path, second)
        XCTAssertNil(LaunchArguments.collectionArgument(["App", "--autoplay", file], probe: probe))
    }

    func testCollectionArgumentRejectsMissingFilesAndFoldersWithMatchingExtension() {
        XCTAssertNil(LaunchArguments.collectionArgument(["App", "/synthetic/a.savagecollection"], probe: { _ in .missing }))
        XCTAssertNil(LaunchArguments.collectionArgument(["App", "/synthetic/a.savagecollection"], probe: { _ in .directory }))
        XCTAssertNil(LaunchArguments.collectionArgument(["App", "/synthetic/a.json"], probe: { _ in .file }))
    }

    /// Ein vorgegebener Dateibestand statt eines echten Dateisystems.
    private func probe(files: Set<String> = [], directories: Set<String> = [])
        -> (String) -> LaunchArguments.PathKind {
        { path in
            if directories.contains(path) { return .directory }
            if files.contains(path) { return .file }
            return .missing
        }
    }

    private let program = "/Applications/Savage Mod Player.app/Contents/MacOS/SavageModPlayerApp"

    // MARK: - Der gesuchte Pfad

    func testFindsSupportedFileArgument() {
        let url = LaunchArguments.fileArgument(
            [program, "/tmp/song.mod"],
            probe: probe(files: ["/tmp/song.mod"])
        )
        XCTAssertEqual(url?.path, "/tmp/song.mod")
    }

    /// Alle vier unterstuetzten Endungen zaehlen, Gross-/Kleinschreibung egal.
    func testAcceptsEverySupportedExtensionCaseInsensitively() {
        for ext in ["mod", "MOD", "s3m", "S3m", "xm", "Xm", "it", "IT"] {
            let path = "/tmp/song.\(ext)"
            let url = LaunchArguments.fileArgument([program, path], probe: probe(files: [path]))
            XCTAssertEqual(url?.path, path, "Endung .\(ext) muss akzeptiert werden")
        }
    }

    /// Ein Ordner wird rekursiv zur Playlist — seine Endung ist bedeutungslos.
    func testAcceptsDirectoryRegardlessOfExtension() {
        let url = LaunchArguments.fileArgument(
            [program, "/tmp/Modules"],
            probe: probe(directories: ["/tmp/Modules"])
        )
        XCTAssertEqual(url?.path, "/tmp/Modules")
    }

    func testIgnoresMissingPath() {
        XCTAssertNil(LaunchArguments.fileArgument([program, "/tmp/weg.mod"], probe: probe()))
    }

    func testIgnoresUnsupportedExtension() {
        XCTAssertNil(LaunchArguments.fileArgument(
            [program, "/tmp/notiz.txt"],
            probe: probe(files: ["/tmp/notiz.txt"])
        ))
    }

    /// Nicht passende Argumente duerfen den Suchlauf nicht abbrechen.
    func testSkipsUnusablePathsAndTakesTheFirstUsableOne() {
        let url = LaunchArguments.fileArgument(
            [program, "/tmp/weg.mod", "/tmp/notiz.txt", "/tmp/zweiter.xm", "/tmp/dritter.it"],
            probe: probe(files: ["/tmp/notiz.txt", "/tmp/zweiter.xm", "/tmp/dritter.it"])
        )
        XCTAssertEqual(url?.path, "/tmp/zweiter.xm", "Der erste brauchbare Pfad gewinnt")
    }

    func testProgramPathAtIndexZeroIsNeverTaken() {
        // Der Programmpfad selbst existiert und koennte formal passen — er darf
        // trotzdem nie als zu ladende Datei durchgehen.
        let url = LaunchArguments.fileArgument(
            ["/tmp/player.mod"],
            probe: probe(files: ["/tmp/player.mod"])
        )
        XCTAssertNil(url)
    }

    // MARK: - Von macOS angehaengte Voreinstellungen

    /// macOS haengt beim Start `-Schluessel Wert`-Paare an. Weder der Schluessel
    /// noch sein Wert darf als Pfad gelesen werden — sonst wuerde ein Ordner
    /// namens `YES` im Arbeitsverzeichnis zum Startordner.
    func testSkipsDefaultsKeyAndItsValue() {
        let url = LaunchArguments.fileArgument(
            [program, "-ApplePersistenceIgnoreState", "YES", "/tmp/song.it"],
            probe: probe(files: ["/tmp/song.it"], directories: ["YES"])
        )
        XCTAssertEqual(url?.path, "/tmp/song.it")
    }

    func testDefaultsValueAloneYieldsNoFile() {
        let url = LaunchArguments.fileArgument(
            [program, "-ApplePersistenceIgnoreState", "YES"],
            probe: probe(directories: ["YES"])
        )
        XCTAssertNil(url, "`YES` ist der Wert der Voreinstellung, kein Startordner")
    }

    /// Der Prozess-Serial-Parameter des Bundle-Starts steht allein und darf den
    /// Pfad davor oder dahinter nicht verdecken.
    func testProcessSerialArgumentDoesNotHideThePath() {
        let url = LaunchArguments.fileArgument(
            [program, "/tmp/song.s3m", "-psn_0_12345"],
            probe: probe(files: ["/tmp/song.s3m"])
        )
        XCTAssertEqual(url?.path, "/tmp/song.s3m")
    }

    /// Bewusste Grenze: Was direkt hinter einem `-Schluessel` steht, ist dessen
    /// Wert — macOS legt es genau so in die Argument-Domain von `UserDefaults`.
    /// Ein Pfad gehoert deshalb nicht hinter ein Flag. Der Test haelt diese
    /// Entscheidung fest, damit sie nicht versehentlich zurueckgedreht wird.
    func testPathDirectlyAfterAFlagCountsAsThatFlagsValue() {
        let url = LaunchArguments.fileArgument(
            [program, "-eigenerSchalter", "/tmp/song.s3m"],
            probe: probe(files: ["/tmp/song.s3m"])
        )
        XCTAssertNil(url)
    }

    /// Zwei Flags hintereinander: das erste hat keinen Wert.
    func testFlagFollowedByFlagConsumesOnlyItself() {
        let url = LaunchArguments.fileArgument(
            [program, "--autoplay", "-ApplePersistenceIgnoreState", "YES", "/tmp/song.mod"],
            probe: probe(files: ["/tmp/song.mod"])
        )
        XCTAssertEqual(url?.path, "/tmp/song.mod")
    }

    // MARK: - --autoplay

    func testAutoplayFlagDetected() {
        XCTAssertTrue(LaunchArguments.autoplayRequested([program, "--autoplay"]))
        XCTAssertFalse(LaunchArguments.autoplayRequested([program, "/tmp/song.mod"]))
    }

    func testAutoplayFilterIsLowercased() {
        XCTAssertEqual(LaunchArguments.autoplayFilter([program, "--autoplay", "Enigma"]), "enigma")
    }

    func testAutoplayWithoutFilter() {
        XCTAssertNil(LaunchArguments.autoplayFilter([program, "--autoplay"]))
        XCTAssertNil(LaunchArguments.autoplayFilter([program, "--autoplay", "-psn_0_1"]))
        XCTAssertNil(LaunchArguments.autoplayFilter([program]))
    }

    /// Der Filter ist ein Namensteil, kein Pfad — er darf nicht zusaetzlich als
    /// Startdatei gelesen werden, auch wenn zufaellig eine Datei so heisst.
    func testAutoplayFilterIsNotTakenAsFileArgument() {
        let url = LaunchArguments.fileArgument(
            [program, "--autoplay", "song.mod"],
            probe: probe(files: ["song.mod"])
        )
        XCTAssertNil(url)
    }

    // MARK: - Standardabfrage gegen das echte Dateisystem

    func testFilesystemProbeDistinguishesFileDirectoryAndMissing() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LaunchArgumentsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appendingPathComponent("song.mod")
        try Data([0x00]).write(to: file)

        XCTAssertEqual(LaunchArguments.filesystemProbe(base.path), .directory)
        XCTAssertEqual(LaunchArguments.filesystemProbe(file.path), .file)
        XCTAssertEqual(LaunchArguments.filesystemProbe(base.appendingPathComponent("x").path), .missing)
    }
}

# Savage Mod Player — Projektregeln

## Typ und Zweck

- **Typ:** native macOS-GUI-App mit SwiftUI/AVAudioEngine, Quick-Look-Extension,
  native iPhone-App (SwiftUI, `ios/`), plattformübergreifendes headless CLI
  (`savage-cli`, macOS + Linux) und kompakte HTML5-Variante.
- **Zweck:** Tracker-Modul-Player für MOD, S3M, XM und IT. Die native Variante
  unterstützt alle vier Formate; der Single-File-Browserplayer bleibt bewusst
  auf klassische 4-Kanal-ProTracker-MODs begrenzt.
- **Linux ist Ist-Zustand, nicht Option** (seit 1.5.44/1.5.45): `SavageModPlayerCore`
  und `savage-cli` bauen, testen und spielen unter Linux; App und Quick Look sind
  macOS-only und werden dort per `#if os(macOS)` aus `Package.swift` ausgeblendet.
  Details und Grenzen: [Linux-Plan](tasks/2026-07-05-linux-port/plan.md).
- **iOS ist Ist-Zustand, nicht Option** (seit 1.6.0): `ios/` enthält die native
  iPhone-App mit Hintergrundwiedergabe, Sperrbildschirm-Steuerung, Bibliothek und
  rekursivem Import. Sideload-Team-ID und Bundle-Signatur sind öffentlich;
  privater Schlüssel und Notary-Profil bleiben geheim. WAV-Export fehlt bewusst.
  Details: [iOS-Plan](tasks/2026-07-26-ios-app/plan.md).
- Die aktuelle Produktversion steht ausschließlich in [VERSION](VERSION).

## Architektur und harte Invarianten

- `Sources/SavageModPlayerCore/Parser/`: strikte, längengeführte Parser und
  `ModuleLoader` als inhaltsbasierter Dispatch. Formatfremde Daten und strukturelle
  Korruption ablehnen; nur dokumentierte, sicher clamp-/ignorierbare Realweltwerte
  tolerant behandeln. Keine pauschale „OpenMPT akzeptiert es“-Toleranz.
- `Sources/SavageModPlayerCore/DSP/`: gemeinsamer Live-/Probe-/Offline-Renderpfad.
  Im Echtzeit-Renderblock niemals Heap-Allokationen, Locks oder dynamische
  Objective-C-Aufrufe einführen. Kanal-/Voice-Puffer bleiben voralloziert; IT
  trennt bis zu 64 Pattern-Kanäle von 256 Voices.
- **`RenderEngine.swift` bleibt plattformneutral:** kein AVFoundation, Combine
  oder CoreAudio. `ModuleRenderBlock` ist die neutrale Schnittstelle; CoreAudio
  lebt nur in `ModPlayerCoordinator.makeSourceNodeRenderBlock`. Plattformcode
  bleibt mit `canImport` geschützt.
- `Sources/SavageModPlayerCore/Audio/`: formatfreie Ausgabeschicht (`PCMSink`,
  `ModulePCMSource`). Änderungen mit `vicious_sidplayer` abgleichen; ein
  gemeinsames Paket lohnt erst nach Bewährung in beiden Projekten.
- **Eine Engine, mehrere Ausgaben.** Offline-Renderer, Echtzeit-CLI und App
  verwenden `RenderEngine.createRenderBlock`; `ModulePCMSourceTests` vergleicht
  Echtzeit- und Offlinepfad sample-genau.
- `modplayer.js`, `mod-player-worklet.js` und `src/` sind Webquellen; `build.py`
  erzeugt `savage-mod-player.html`. Nach Web-/Versionsänderungen neu bauen und
  den Diff prüfen.
- Der gemeinsame 4-Kanal-MOD-DSP in Swift und JavaScript muss mathematisch
  konsistent bleiben. Nach einem Fix in einer Variante die andere prüfen und bei
  ausstehender Parität einen Eintrag in [tasks/backlog.md](tasks/backlog.md)
  anlegen, nicht in dieser Dauerdatei.
- Quick Look rendert höchstens 60 Sekunden WAV. Appex zuerst mit Entitlements,
  danach die App ohne `--deep` signieren. Parserfehler liefern eine endliche
  Textvorschau.
- `ZipArchiveReader` liest `.zip` auf **allen** Plattformen (seit 1.6.10);
  `bsdtar` ist nur noch für `.7z` auf macOS und Linux zuständig und damit
  optional. Der Reader streamt blockweise; Speicherbedarf darf nicht mit der
  Archivgröße wachsen. Zip-Slip, Symlinks, Verschlüsselung, Zip64 und
  unplausible Kompressionsverhältnisse machen das **ganze Archiv** ungültig —
  abgelehnt, nicht bereinigt. Den DEFLATE-Strom liefert auf Apple das Framework
  `Compression`, unter Linux die zlib (`Sources/CZlib`).
- `Sources/SavageModPlayerCore/Library/` bleibt plattformneutral. **Stabile IDs
  sind relative Pfade.** Der Index ist nur Cache; Wahrheit ist `Documents/`, das
  auch über Finder-Dateifreigabe verändert werden kann.
- Das iOS-Projekt nutzt `PBXFileSystemSynchronizedRootGroup`; neue Swift-Dateien
  brauchen keinen pbxproj-Edit. `Info.plist` bleibt über
  `membershipExceptions` aus der Ressourcen-Phase ausgenommen.
- **Swift-6-Isolation auf iOS kann SIGTRAP auslösen.** Combine-Sinks auf
  Systembenachrichtigungen und `MPRemoteCommand`-Handler bleiben deshalb
  ausdrücklich entkoppelt (`.receive(on:)` beziehungsweise `@Sendable`).

## Sicherheit, Assets und Öffentlichkeit

- Das Repo ist veröffentlichbar. Keine privaten Hosts, Remotes, Kontakte,
  Assistentenformulierungen, lokalen Home-Pfade oder persönliche Fleet-Notizen in
  öffentliche Dateien übernehmen.
- Moduldateien unter `audio/`, lokale Referenz-WAVs und A/B-Berichte sind
  ungebundene Testdaten und bleiben aus Git. Für Regressionen synthetische,
  rechtlich unbedenkliche Fixtures bevorzugen. Vor GitHub den getrackten Stand
  erneut auf Audio-/Release-Artefakte und private Daten prüfen.
- Tests dürfen fehlende lokale Korpora sauber überspringen; ein grüner Skip ist
  kein Beleg für Realwelt-Kompatibilität. Bei Parser-/DSP-Änderungen vorhandene
  lokale Korpora zusätzlich prüfen, ohne sie zu committen.
- Veröffentlichung und Release-Erstellung sind externe Wirkungen. GitHub,
  Notarisierung oder `publish_github.sh` nur nach Daniels konkretem Auftrag;
  vorher den Workflow `github-publish` laden.
- `build_app.sh` baut nur, `install.sh` installiert notarisiert, `release.sh`
  packt das DMG und installiert nie. Notary-Profil nur über `NOTARY_PROFILE`
  oder die projektlokale Git-Konfiguration referenzieren.

## Git, Version und Parallelität

- Vor Änderungen den privaten kanonischen Fleet-Remote fetchen. Automatische
  Commits/Pushes gehen nur dorthin; GitHub bleibt ohne Auftrag unangetastet.
- Nur Scope-Pfade stagen. Fremdes WIP erhalten; keine destruktiven Git- oder
  Dateibefehle. Reine AGENTS-/CLAUDE-/Doku-Reorganisation erhöht die
  Produktversion nicht.
- Produktänderungen aktualisieren `VERSION`, Nutzer-/Release-Doku und
  eingebettete Versionsartefakte. Danach testen, committen und zum privaten
  kanonischen Remote pushen. Expected-Ausgaben nie still regenerieren.
- Gemeinsame Hotspots (`ModuleModels.swift`, `DSPChannel.swift`,
  `AudioCoordinator.swift`, Parser-/Sequencer-Kern, `ContentView.swift`,
  `build_app.sh`) nur seriell editieren. Nie zwei Writer im selben logischen Repo
  oder Worktree-Verbund; die abgeschlossene IT-Roadmap ist kein aktiver
  Parallelarbeitsvertrag.

## Änderung → Pflichtprüfung

Die vollständigen Befehle, Fixture-Regeln und Quick-Look-Fallen stehen in
[docs/testing.md](docs/testing.md). Mindestmatrix:

| Änderung | Pflichtprüfung |
|---|---|
| Swift allgemein | gezielter Test, vollständiges `swift test`, `git diff --check` |
| `savage-cli` | `swift build -c release --product savage-cli`, danach `python3 Tests/cli_contract_tests.py` und `python3 Tests/cli_playback_tests.py` |
| App/Core/Quick Look | zusätzlich `bash build_app.sh` |
| App-Start (`AppMain`, `onAppear`, `onOpenURL`, `LaunchArguments`) | zusätzlich `bash Tests/launch_argument_smoke.sh` |
| `RenderEngine`, `Audio/`, `Package.swift`, Parser-Kern | zusätzlich Linux-Lauf (Docker, siehe Linux-Plan) — der Build dort ist der einzige Beleg für Plattformneutralität |
| Audio-Renderpfad angefasst | `savage-cli`-WAVs über den lokalen MOD-Korpus byteidentisch zu vorher (Baseline vor der Änderung erzeugen) |
| gemeinsamer MOD-DSP | `DSPChannelTimingTests`, Sequencer-Tests und `node Tests/js/worklet-timing.mjs` |
| MOD/S3M/XM/IT-Parser oder -DSP | passende Format-Suite plus lokale Realweltdateien, falls vorhanden |
| `Archive/`, `Library/`, `PlaylistScanner` | zusätzlich `ZipArchiveReaderTests`, `MusicLibraryTests`, `LibraryImporterTests` und Linux-Lauf |
| iOS-App (`ios/`) | `bash ios/scripts/build-simulator.sh` und `bash ios/scripts/run-tests.sh`; Hintergrundwiedergabe und Sperrbildschirm sind **nur am Gerät** belegbar, nie aus dem Simulator behaupten |
| Webquelle/Version | `python3 build.py`, `node Tests/js/pattern-bounds.mjs`, generierten HTML-Diff prüfen, Browser-Smoke bei UI-Verhalten |
| Quick Look | Build/Signatur/PluginKit headless; Finder-Leertaste als manueller Endtest |
| Release | volle Suite, App-/Appex-Signatur, DMG/Notary nur bei Auftrag, EN/DE-Doku konsistent |

GUI-Fokus erst nach Zustimmung. Ein App- oder Finder-Handtest ersetzt nie die
headless Gates; nach einem sichtbaren Test die Test-App wieder ausblenden.

## Progressive Detailregeln und bestätigte Fallen

Vor betroffenen Änderungen [docs/testing.md](docs/testing.md) lesen. Dort stehen
Notary-, Quick-Look-, Release- und Gerätetestdetails. Dauerhafte iOS-Semantik:

- Finder-ZIPs werden beim Dateisystemabgleich automatisch streamend ausgepackt.
- Visualisierungen laufen nur im sichtbaren Abschnitt. Beim Herausscrollen,
  Tabwechsel oder Sperren verschwinden Views und Caches; der Core sinkt auf
  etwa 5 Hz. Höchstens 32 Kanal-Oszilloskope erscheinen im 4-/8-spaltigen Raster.

Aus realen Fehlern bestätigte Fallen:

- **Deklarierte Längen vollständig erzwingen.** Ein Binärparser darf ein
  deklariertes Datenfenster nicht still am Dateiende kürzen; `min(…, data.count)`
  ist kein Ersatz für eine Prüfung. Vor dem Parsen muss der vollständige Bereich
  in der Eingabe liegen, sonst gilt das sauber endende Präfix einer
  abgeschnittenen Datei — etwa eines XM — fälschlich als gültig.
- **`Data`-Slices nie als nullbasiert behandeln.** Ein `Data`-Ausschnitt kann einen
  `startIndex` ungleich null haben; dieselben Bytes werden dann fehlinterpretiert
  oder der Prozess stürzt ab. Eingaben an öffentlichen Parser-Grenzen entweder auf
  nullbasierte Daten umbasieren oder durchgehend relativ zu `startIndex`
  adressieren; Tests müssen auch echte Slices übergeben.
- **Ein fehlgeschlagener Dateisystem-Scan leert keinen Index.** Liefert ein
  Verzeichnis-Enumerator `nil` oder unvollständige Ergebnisse, ist das kein
  leerer Bestand. Den alten Index bis zum vollständigen Neuaufbau behalten oder
  fehlgeschlagene Teilbäume mit dem bekannten Bestand zusammenführen.
- **Ein positionales Startargument kostet der Mac-App ihr Fenster.** AppKit
  deutet es als „diese Datei öffnen“; auf diesem Startweg erzeugt SwiftUI sein
  Fenster nicht, und ohne Fenster greift auch `.onOpenURL` nicht. Die App
  schaltet das in `SavageModPlayerApp.init()` über die Voreinstellung
  `NSTreatUnknownArgumentsAsOpen` ab. Eigene Schalter bleiben trotzdem besser
  `-Schlüssel Wert`-Argumente. Der Beleg ist ein Startlauf, kein Unittest:
  `bash Tests/launch_argument_smoke.sh`.
- **Ein Quellarchiv erst nach vollständiger Übernahme löschen.** Ein entpacktes
  Archiv darf erst verschwinden, wenn alle unterstützten Inhalte einschließlich
  verschachtelter Archive übernommen sind. Ein einzelner importierter
  Direkteintrag belegt nicht, dass das gesamte Staging verarbeitet wurde.

Die IT-Implementierung M0–M10 ist abgeschlossen. Dauerhafte Semantik und
Capability-Grenzen sind projektextern dokumentiert. Historische
Start-/Branch-Anweisungen aus dem IT-Support-Task sind
geschlossen und dürfen nicht reaktiviert werden.

## Aktive nächste Schritte

Nur [tasks/backlog.md](tasks/backlog.md) ist die aktive Projektliste. Erledigtes
liegt in Release Notes, Tasks und der ausgelagerten AGENTS-Historie.

## Verzeichnisstruktur

- `README*` und `RELEASE_NOTES*`: Produkt, Bedienung und Release-Historie.
- `docs/testing.md`: Test-/Build-Runbook; `tasks/backlog.md`: offene Arbeit;
  `docs/AGENTS-history-through-2026-07-12.md`: erledigte Regelchronik.
- `Sources/SavageModPlayerCore/`: Parser, DSP, Audio, Playlist, Archive und
  Library; `Sources/SavageCLI/`: CLI; `quicklook/`: Extension.
- `src/`, `modplayer*.js`, `savage-mod-player.html`: Webplayer.
- `ios/`: iPhone-App, Tests und Build-Skripte; `ios/build/` ist gitignoriert.

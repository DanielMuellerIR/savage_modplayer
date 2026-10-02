# Savage Mod Player — Projektregeln

## Typ und Zweck

- **Typ:** native macOS-GUI-App (SwiftUI/AVAudioEngine) mit Quick-Look-Extension,
  native iPhone-App (`ios/`), plattformübergreifendes headless CLI (`savage-cli`,
  macOS + Linux) und kompakte HTML5-Variante.
- **Zweck:** Tracker-Modul-Player für MOD, S3M, XM und IT. Die native Variante
  unterstützt alle vier Formate; der Single-File-Browserplayer bleibt bewusst
  auf klassische 4-Kanal-ProTracker-MODs begrenzt.
- **Linux ist Ist-Zustand:** Core und `savage-cli` bauen, testen und spielen dort;
  App und Quick Look blendet `Package.swift` als macOS-only aus.
  Grenzen: [Linux-Plan](tasks/2026-07-05-linux-port/plan.md).
- **iOS ist Ist-Zustand:** Hintergrundwiedergabe, Sperrbildschirm, Bibliothek,
  rekursiver Import; kein WAV-Export. Team-ID und Bundle-Signatur sind
  öffentlich, Schlüssel und Notary-Profil geheim.
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
  konsistent bleiben. Nach einem Fix in einer Variante die andere prüfen; bei
  ausstehender Parität einen Eintrag in [tasks/backlog.md](tasks/backlog.md).
- Quick Look rendert höchstens 60 Sekunden WAV. Appex zuerst mit Entitlements,
  danach die App ohne `--deep` signieren. Parserfehler liefern eine endliche
  Textvorschau.
- `ZipArchiveReader` liest `.zip` blockweise; Speicher darf nicht mit der
  Archivgröße wachsen. Zip-Slip, Symlinks, Verschlüsselung, Zip64 oder unplausible
  Kompression machen das ganze Archiv ungültig. DEFLATE liefert Apple
  `Compression`, unter Linux `Sources/CZlib`; `bsdtar` bleibt optional für `.7z`.
- `Sources/SavageModPlayerCore/Library/` bleibt plattformneutral. **Stabile IDs
  sind relative Pfade.** Der Index ist nur Cache; Wahrheit ist `Documents/`, das
  auch über Finder-Dateifreigabe verändert werden kann.
- Das iOS-Projekt nutzt `PBXFileSystemSynchronizedRootGroup`; neue Swift-Dateien
  brauchen keinen pbxproj-Edit. `Info.plist` bleibt über `membershipExceptions`
  aus der Ressourcen-Phase ausgenommen.

## Sicherheit, Assets und Öffentlichkeit

- Das Repo ist veröffentlichbar. Keine privaten Hosts, Remotes, Kontakte,
  Assistentenformulierungen, lokalen Home-Pfade oder Fleet-Notizen in
  öffentliche Dateien übernehmen.
- Moduldateien unter `audio/`, lokale Referenz-WAVs und A/B-Berichte sind
  ungebundene Testdaten und bleiben aus Git. Für Regressionen synthetische,
  rechtlich unbedenkliche Fixtures bevorzugen. Vor GitHub den getrackten Stand
  erneut auf Audio-/Release-Artefakte und private Daten prüfen.
- Tests dürfen fehlende lokale Korpora sauber überspringen; ein grüner Skip ist
  kein Beleg für Realwelt-Kompatibilität. Bei Parser-/DSP-Änderungen vorhandene
  lokale Korpora zusätzlich prüfen, ohne sie zu committen.
- GitHub, Notarisierung oder `publish_github.sh` nur nach ausdrücklichem
  Auftrag; vorher den Workflow `github-publish` laden.
- `build.sh` baut nur (Wrapper auf `build_app.sh`, Schlusszeile `BUILD OK: <pfad>`),
  `install.sh` installiert notarisiert, `release.sh` packt das DMG und installiert
  nie. Notary-Profil nur über `NOTARY_PROFILE` oder die projektlokale
  Git-Konfiguration referenzieren.

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
  oder Worktree-Verbund.

## Änderung → Pflichtprüfung

Vollständige Befehle, Fixture-Regeln und Quick-Look-Fallen stehen in
[docs/testing.md](docs/testing.md). Mindestmatrix:

| Änderung | Pflichtprüfung |
|---|---|
| Swift allgemein | gezielter Test, vollständiges `swift test`, `git diff --check` |
| `savage-cli` | `swift build -c release --product savage-cli`, dann `python3 Tests/cli_contract_tests.py` und `python3 Tests/cli_playback_tests.py` |
| App/Core/Quick Look | zusätzlich `bash build_app.sh` |
| App-Start (`AppMain`, `onAppear`, `onOpenURL`, `LaunchArguments`) | zusätzlich `bash Tests/launch_argument_smoke.sh` |
| `RenderEngine`, `Audio/`, `Package.swift`, Parser-Kern | zusätzlich Linux-Lauf (Docker, siehe Linux-Plan) als einziger Beleg für Plattformneutralität |
| Audio-Renderpfad | `savage-cli`-WAVs über den lokalen MOD-Korpus byteidentisch zur Baseline von vor der Änderung |
| gemeinsamer MOD-DSP | `DSPChannelTimingTests`, Sequencer-Tests und `node Tests/js/worklet-timing.mjs` |
| MOD/S3M/XM/IT-Parser oder -DSP | passende Format-Suite plus lokale Realweltdateien, falls vorhanden |
| `Archive/`, `Library/`, `PlaylistScanner` | zusätzlich `ZipArchiveReaderTests`, `MusicLibraryTests`, `LibraryImporterTests` und Linux-Lauf |
| iOS-App (`ios/`) | `bash ios/scripts/build-simulator.sh` und `bash ios/scripts/run-tests.sh`; Hintergrundwiedergabe und Sperrbildschirm sind **nur am Gerät** belegbar |
| Webquelle/Version | `python3 build.py`, `node Tests/js/pattern-bounds.mjs`, HTML-Diff prüfen, Browser-Smoke bei UI-Verhalten |
| Quick Look | Build/Signatur/PluginKit headless; Finder-Leertaste als manueller Endtest |
| Release | volle Suite, App-/Appex-Signatur, DMG/Notary nur bei Auftrag, EN/DE-Doku konsistent |

GUI-Fokus erst nach Zustimmung. Ein Handtest ersetzt nie die headless Gates;
nach einem sichtbaren Test die Test-App wieder ausblenden.

## Bestätigte Fallen

Aus realen Fehlern gelernte Regeln zu Parser-Längen, `Data`-Slices,
Index-Scans, Archivimport, Startargumenten, `@Published`, Swift-6-Isolation und
seq_cst im Dreifachpuffer stehen in [docs/fallen.md](docs/fallen.md). Vor
Änderungen an diesen Stellen dort nachlesen. Die IT-Implementierung M0–M10 ist
abgeschlossen; historische Start-/Branch-Anweisungen aus dem IT-Task dürfen
nicht reaktiviert werden.

## Offene Arbeit und Verzeichnisstruktur

Nur [tasks/backlog.md](tasks/backlog.md) ist die aktive Projektliste, auch für
offene Abnahmen (Gerätetest iPhone, DMG-Finder-Layout). Erledigtes liegt in
Release Notes, Tasks und [docs/AGENTS-history-through-2026-07-12.md](docs/AGENTS-history-through-2026-07-12.md).

- `README*` und `RELEASE_NOTES*`: Produkt, Bedienung und Release-Historie.
- `docs/testing.md`: Test-/Build-Runbook; `docs/fallen.md`: bestätigte Fallen.
- `Sources/SavageModPlayerCore/`: Parser, DSP, Audio, Playlist, Archive und
  Library; `Sources/SavageCLI/`: CLI; `quicklook/`: Extension.
- `src/`, `modplayer*.js`, `savage-mod-player.html`: Webplayer.
- `ios/`: iPhone-App, Tests und Build-Skripte; `ios/build/` ist gitignoriert.

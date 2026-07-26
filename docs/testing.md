# Test-, Build- und Quick-Look-Runbook

Stand: 2026-07-22. Diese Datei enthält die Details, die nur vor einer betroffenen
Änderung geladen werden müssen. Die kompakte Pflichtmatrix steht in `AGENTS.md`.

## Allgemeines Gate

1. Reproduktion oder prüfbare Invariante vor dem Fix festhalten.
2. Kleinste passende Tests während der Arbeit ausführen.
3. Vor Abschluss `swift test` und `git diff --check` ausführen, wenn Swift-Code
   betroffen ist. Bei App/Core/Quick Look zusätzlich `bash build_app.sh`.
4. Lokale Moduldateien und Referenz-WAVs bleiben ungetrackt. Übersprungene
   Korpustests ausdrücklich als Skip und nicht als Kompatibilitätsbeleg melden.

## Swift- und Format-Suiten

- Echtzeit-Crash mit realer lokaler MOD-Datei:
  `swift test --filter testRealtimePlaybackSurvivesFiveSeconds`.
- Langes RType-Sample:
  `swift test --filter ModParserTests/testRTypeFourthChannelSampleSurvivesPastRow16`.
- MOD-DSP-Timing, Amplitude und Effekt-Memory:
  `swift test --filter DSPChannelTimingTests`.
- Sprung-, Break-, Loop- und Delay-Sequenzierung:
  `swift test --filter CoordinatorSequencingTests`.
- Swift↔JavaScript-Parität des gemeinsamen 4-Kanal-MOD-Kerns:
  `node Tests/js/worklet-timing.mjs`.
- Multichannel-MOD, Soundtracker-15 und S3M:
  `swift test --filter MultiFormatTests`.
- XM-Parser und reale lokale XM-Dateien:
  `swift test --filter XMParserTests`; DSP-Semantik zusätzlich in
  `DSPChannelTimingTests`.
- Renderparameter, Streaming-Framebudget und Quick-Look-Cacheidentität:
  `swift test --filter 'ModuleRendererLimitTests|ModulePCMSourceTests|PreviewCacheIdentityTests'`.
- Impulse Tracker einschließlich IT214/IT215, Instrument-/Samplemodus,
  Voice-Pool, NNA/DCT/DCA, Effekte, Filter und Capability-Matrix:
  `swift test --filter IT`.
- Länge-1-Song und nichtleerer Slider-Bereich:
  `swift test --filter LengthOneModuleTests`.
- Referenzvergleich gegen `openmpt123`:
  `python3 Tests/reference_compare_tests.py`; Version, Samplerate,
  Interpolation und verwendete lokale Fixtures im Ergebnis festhalten.

Parseränderungen müssen synthetische Grenzfälle für Längen, Offsets und
Korruption enthalten. Eine Toleranz ist nur zulässig, wenn das ignorierte oder
geclampte Feld keine Bounds, Allokationsgröße oder Nutzdateninterpretation
beeinflusst. Planunterstützte Realweltdateien müssen hörbar rendern.

CLI-Zahlparameter zusätzlich mit `nan`, `inf`, negativen und oberhalb der
dokumentierten Grenze liegenden Werten prüfen: Der Prozess muss vor Parse/Render
mit Exit-Code 2 enden. Beim `--stdout`-Smoke nur wenige KiB aus einer langen
Anforderung lesen; die ersten Bytes müssen sofort kommen und ein geschlossener
Consumer muss sauber als `outputClosed` enden.

## HTML5-Player

- Nach Änderungen an `src/`, `modplayer.js`, `mod-player-worklet.js`, `VERSION`
  oder am Bundler: `python3 build.py` und den Diff von
  `savage-mod-player.html` semantisch prüfen.
- DSP-Änderungen immer mit `node Tests/js/worklet-timing.mjs` gegen Swift prüfen.
- Drop-Autoplay-Smoke: `python3 -m http.server 8765`, dann
  `http://127.0.0.1:8765/savage-mod-player.html?testDropAutoplay=1` laden und
  prüfen, dass der simulierte Ordner-Drop `PLAYING` meldet.
- Der Browserplayer bleibt absichtlich auf klassische 4-Kanal-MODs begrenzt;
  Swift-only-Formate nicht aus Symmetriegründen in das 40-KB-Produkt ziehen.

## Native App und Quick Look

`bash build_app.sh` baut die Release-App und die Quick-Look-Appex. Ein bloßes
`swift build` deckt Extension, Signatur und Bundle-Integration nicht ab.

Headless prüfen:

1. App und Appex bauen; Plists linten und Signaturen strikt verifizieren.
2. Nach einem Rebuild die Appex bei Bedarf mit
   `pluginkit -a "<app>/Contents/PlugIns/SavageModPlayerQuickLook.appex"`
   registrieren.
3. Mit `pluginkit -m -p com.apple.quicklook.preview` die Registrierung prüfen.
4. Für den Prozess-Spawn bevorzugt eine `.s3m` verwenden. VLC kann `.mod` als
   `org.videolan.mod` exportieren; macOS nimmt dann den System-Medienpfad und
   fragt Dritt-Extensions nicht an.

`qlmanage -p -o <dir>` nutzt moderne Preview-Extensions nicht zuverlässig. Ein
leeres Ergebnis beweist keinen Defekt. Der sichtbare Endtest ist Finder-Leertaste
auf einer lokalen `.mod`/`.s3m`/`.xm`/`.it`: nativer Audio-Player, Timeline,
Scrubbing und Wiedergabe müssen funktionieren. Vor GUI-Fokus Daniel fragen.

Der Provider muss eine temporäre WAV-Datei und `QLPreviewReply(fileURL:)`
verwenden. `dataOfContentType: .wav` zeigt nur die generische Info-Karte. Die
Appex zuerst sandboxed mit Entitlements signieren, danach die App ohne `--deep`.

## iOS-App

Die iPhone-App liegt unter `ios/` und benutzt dasselbe `SavageModPlayerCore` wie
Mac-App und CLI. Das Projekt ist eingecheckt und arbeitet mit
`PBXFileSystemSynchronizedRootGroup` (`objectVersion 77`, Xcode 16 oder neuer):
neue Swift-Dateien unter `ios/SavageModPlayer/` landen ohne pbxproj-Edit im
Target. Ein Zusammenführungskonflikt in `project.pbxproj` ist damit die Ausnahme,
nicht der Normalfall.

Headless prüfen:

```
bash ios/scripts/build-simulator.sh    # Build, bricht bei eigenen Warnungen ab
bash ios/scripts/run-tests.sh          # XCTest im Simulator
```

`build-simulator.sh` filtert Warnungen auf den eigenen Quellbaum (`ios/` und
`Sources/`) und endet mit Exit 3, wenn dort welche auftauchen. Ein grüner Lauf
heißt also wirklich warnungsfrei. Das vollständige Protokoll liegt unter
`ios/build/` und ist gitignoriert.

`run-tests.sh` sucht sich ohne `SIMULATOR_NAME` das erste verfügbare iPhone.
Einzelne Suiten über `TEST_FILTER=SavageModPlayerTests/<Klasse>`.

Der Kern (`ZipArchiveReader`, `MusicLibrary`, `LibraryImporter`,
`LibraryReset`) wird **nicht** dort geprüft, sondern in der normalen
SwiftPM-Suite mit `swift test` — plattformneutral und ohne Simulator. Im
Simulator läuft nur, was ohne iOS nicht prüfbar ist.

### Grenzen des Simulators

Der Simulator belegt **nicht**: Hintergrundwiedergabe bei gesperrtem Bildschirm,
Sperrbildschirm- und AirPods-Steuerung, Verhalten bei eingehendem Anruf, Route-
Change beim Abziehen der Kopfhörer und das Speicherverhalten beim Import eines
großen Archivs. Wer nur den Simulator gefahren hat, darf keines dieser Dinge als
verifiziert melden.

### Gerätetest (nur mit echtem iPhone)

Voraussetzung: `ios/.env` mit der eigenen Team-ID (Vorlage `ios/.env.example`,
die Datei selbst ist gitignoriert).

```
bash ios/scripts/build-device.sh --install
```

Prüfliste am Gerät:

1. **Sperrbildschirm.** Titel starten, Display sperren. Die Musik läuft weiter.
   Auf dem Sperrbildschirm erscheinen Titel, Format und Artwork; Play/Pause,
   Weiter/Zurück und der Positionsregler funktionieren; die verstrichene Zeit
   läuft mit und springt nicht.
2. **AirPods.** Doppeltipp beziehungsweise Stiel-Geste pausiert und setzt fort.
3. **Eingehender Anruf.** Wiedergabe pausiert beim Klingeln und setzt nach dem
   Auflegen selbständig wieder ein.
4. **Kopfhörer abziehen.** Wiedergabe pausiert und läuft nicht über den
   Lautsprecher weiter.
5. **Speicherverhalten beim Import.** Ein großes Archiv (dreistellige MB)
   importieren und dabei den Speicher beobachten. Der Verbrauch darf nicht mit
   der Archivgröße wachsen; die App darf nicht vom System beendet werden.
6. **Dauerlauf.** Ein anspruchsvolles IT-Modul mindestens zehn Minuten laufen
   lassen, davon einen Teil bei gesperrtem Bildschirm: keine Aussetzer.

## Release und Notarisierung

- Reine Doku-/AGENTS-Reorganisation: kein `VERSION`-Bump.
- Produktänderung: `VERSION`, betroffene EN/DE-Doku und eingebettete
  Versionsartefakte konsistent aktualisieren; Webbundle regenerieren.
- `RELEASE_NOTES.md` und `.de.md` beginnen direkt mit dem ersten Absatz, nicht
  mit einer H1. `publish_github.sh` setzt den Release-Titel separat.
- Notary-Keychain-Profile werden nicht zuverlässig zwischen Macs synchronisiert.
  Vor Nutzung ein vorhandenes Profil verifizieren und nur per
  `NOTARY_PROFILE=<profil> bash build_dmg.sh --notarize` referenzieren. Konkrete
  Profilnamen gehören in private Setup-Doku.
- `publish_github.sh`, Tags, GitHub-Releases und Notary-Uploads nur nach
  ausdrücklichem Auftrag. Vorher Dry-run und Public-Leak-Prüfung.

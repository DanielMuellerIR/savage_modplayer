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

## CLI-Suiten

- Exit-Codes, Zahlgrenzen und `--list`: `python3 Tests/cli_contract_tests.py`.
- Echtzeit-Wiedergabe, Playlist, Tastatursteuerung und Ctrl-C:
  `python3 Tests/cli_playback_tests.py`. Die Suite hängt ein Pseudoterminal an
  stdin und spielt ein synthetisches Modul, dessen Sample nur Nullbytes enthält
  — dadurch ist der Lauf lautlos. Ohne nutzbare Audio-Ausgabe überspringt sie
  sich; ein Skip belegt keine funktionierende Wiedergabe.

Die vier zeitabhängigen Tests (Tasten, Ctrl-C) brauchen eine Ausgabe, die im
Echtzeittakt läuft. Ein ALSA-Nullgerät erfüllt das **nicht** — es verschluckt
die Samples so schnell, wie der Renderer sie liefert, und die Playlist ist
vorbei, bevor eine Taste ankommt. Der Probelauf in `setUpClass` misst das und
überspringt sie dann. Für den vollen Linux-Beleg eine temporäre
PipeWire-Null-Senke nehmen (Rezept im [Linux-Plan](../tasks/2026-07-05-linux-port/plan.md)).

**Beide Suiten nehmen `.build/release` vor `.build/debug`.** Nach einer
CLI-Änderung deshalb `swift build -c release --product savage-cli` laufen
lassen, sonst prüfen sie stillschweigend das alte Binary.

## HTML5-Player

- Nach Änderungen an `src/`, `modplayer.js`, `mod-player-worklet.js`, `VERSION`
  oder am Bundler: `python3 build.py` und den Diff von
  `savage-mod-player.html` semantisch prüfen.
- Parser-Grenzen des Browserplayers mit
  `node Tests/js/pattern-bounds.mjs` prüfen.
- DSP-Änderungen immer mit `node Tests/js/worklet-timing.mjs` gegen Swift prüfen.
- Drop-Autoplay-Smoke: `python3 -m http.server 8765`, dann
  `http://127.0.0.1:8765/savage-mod-player.html?testDropAutoplay=1` laden und
  prüfen, dass der simulierte Ordner-Drop `PLAYING` meldet.
- Der Browserplayer bleibt absichtlich auf klassische 4-Kanal-MODs begrenzt;
  Swift-only-Formate nicht aus Symmetriegründen in das 40-KB-Produkt ziehen.

## Native App und Quick Look

`bash build_app.sh` baut die Release-App und die Quick-Look-Appex. Ein bloßes
`swift build` deckt Extension, Signatur und Bundle-Integration nicht ab.
`python3 Tests/ui_source_tests.py` schützt zusätzlich die Pflichtbedienelemente
des kompakten Footers; der sichtbare Fenster-Smoke bleibt trotzdem erforderlich.

### CPU der Visualisierungen messen

`bash Tests/measure_visualizer_cpu.sh <modul> [hz …]` misst die verbrauchte
CPU-Zeit der laufenden App über ein festes Fenster — stumm und ohne Fokus.
Pflicht vor und nach jeder Optimierung am 30-Hz-Pfad; ohne festes Vorgehen sind
zwei Messungen nicht vergleichbar.

**Momentanwerte von `%CPU` taugen dafür nicht.** In einem Versuch streuten sie
für denselben Zustand zwischen 11 % und 25 %, und eine Messreihe stellte die
Reihenfolge der Bildraten sogar auf den Kopf. Die über 30 Sekunden verbrauchte
CPU-Zeit war dagegen auf ein paar Zehntelprozent reproduzierbar.

### Startlauf-Smoke

`bash Tests/launch_argument_smoke.sh` prüft nach jedem App-Build, ob beim Start
überhaupt ein Fenster erscheint und ob ein übergebenes Modul im Player landet —
für Datei, Ordner, unbekanntes Argument, `--autoplay` und den Weg über
LaunchServices („Öffnen mit“). Das Skript braucht weder Bedienungshilfen- noch
Bildschirmaufnahme-Rechte: Es zählt Fenster über `CGWindowListCopyWindowInfo`
und liest das geladene Modul aus der Voreinstellung `savage.lastPlayed`. Der
Lauf bleibt stumm und stellt die Voreinstellungen danach wieder her.

Pflicht bei allem, was den App-Start betrifft: `AppMain.swift`,
`MainView.onAppear`, `.onOpenURL` und `LaunchArguments`. Ein reiner
`swift test`-Lauf sieht diesen Fehler nicht — die Argumentlogik war korrekt,
das Fenster fehlte trotzdem.

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

Im Simulator liegen unter anderem:

- `PlaybackLoadingTests` — der Ladepfad läuft asynchron, ein neuer Auftrag
  überholt den alten, kaputte Titel werden übersprungen. Der Nachweis, dass
  `select` sofort zurückkehrt, ist bewusst kein Zeittest: Ein frisch erzeugter
  Task kann nicht laufen, solange die Testmethode den MainActor synchron hält.
- `CoordinationWatchdogTests` — der Wächter über einem koordinierten
  Lesevorgang: abbrechen bei Nutzerabbruch, abbrechen bei Stillstand,
  durchlaufen lassen bei Fortschritt, und nach `finish()` kein Wächter mehr.
  Dass ein realer, hängender File Provider daraufhin loslässt, belegt nur ein
  Gerätetest mit einem solchen Anbieter.
- `OpenWithTests` — „Öffnen mit …" für Datei und Archiv, doppeltes Öffnen,
  unspielbare Datei und der Kaltstart-Fall (Datei trifft während des
  Bibliotheksabgleichs ein). Beide Suiten arbeiten auf einer Bibliothek mit
  eigener Wurzel im Temp-Verzeichnis, nicht im echten `Documents/`, und laden
  nur — der Simulator bleibt still.

Für einen hörbaren Smoke mit aufwendigen XM-/IT-Modulen den Simulator als
Release-Build starten:

```
CONFIGURATION=Release bash ios/scripts/build-simulator.sh
```

Ein Debug-Build kann bei einem 32-Kanal-XM oder einem alten 16-Kanal-IT mit
Speed 1 und 250 BPM langsamer als Echtzeit rendern. Dann meldet Core Audio
`IOWorkLoop: skipping cycle due to overload`, und die Ausgabe kratzt trotz
korrekter Samples. Debug- und Release-WAV müssen für denselben Input
byteidentisch bleiben; die Release-Reserve ersetzt nicht den Gerätetest.

Der Kern (`ZipArchiveReader`, `MusicLibrary`, `LibraryImporter`,
`LibraryReset`) wird **nicht** dort geprüft, sondern in der normalen
SwiftPM-Suite mit `swift test` — plattformneutral und ohne Simulator. Im
Simulator läuft nur, was ohne iOS nicht prüfbar ist.

### iPad-Layout ansehen

Das zweispaltige Layout hängt an der horizontalen Größenklasse, nicht am Gerät.
Prüfen lässt es sich ohne Bedienung:

```
xcrun simctl boot "iPad Pro 11-inch (M4)"
bash ios/scripts/build-simulator.sh
xcrun simctl install "iPad Pro 11-inch (M4)" ios/build/DerivedData/Build/Products/Debug-iphonesimulator/SavageModPlayer.app
xcrun simctl launch "iPad Pro 11-inch (M4)" com.viben.SavageModPlayer
xcrun simctl io "iPad Pro 11-inch (M4)" screenshot /tmp/ipad.png
```

Testinhalt kommt am einfachsten direkt in den Container:
`xcrun simctl get_app_container … data` liefert den Pfad, Module gehören nach
`Documents/`. **Nicht** über die Voreinstellungs-Datei im Container arbeiten —
`cfprefsd` des Simulators hält den Stand und überschreibt ihn wieder. Ein von
außen gesetzter „zuletzt gespielt"-Wert kommt so nicht in der App an; dass die
Wiederherstellung trotzdem stimmt, decken `PlaybackLoadingTests` ab.

### Grenzen des Simulators

Der Simulator belegt **nicht**: Hintergrundwiedergabe bei gesperrtem Bildschirm,
Sperrbildschirm- und AirPods-Steuerung, Verhalten bei eingehendem Anruf, Route-
Change beim Abziehen der Kopfhörer und das Speicherverhalten beim Import eines
großen Archivs. Wer nur den Simulator gefahren hat, darf keines dieser Dinge als
verifiziert melden.

### Gerätetest (nur mit echtem iPhone)

Das Signatur-Team steht im Projekt (`DEVELOPMENT_TEAM`), ein anderes Team über
`SAVAGE_DEVELOPMENT_TEAM`. Die Team-ID ist bewusst nicht versteckt: Apple bettet
sie in die Signatur jeder ausgelieferten App ein, und sie steht für die
macOS-Signatur ohnehin in `build_app.sh`. Geheim sind der private Schlüssel des
Signaturzertifikats und das Notary-Keychain-Profil — beides liegt nicht im Repo.

**Der erste Lauf auf einem neuen Gerät gehört in Xcode.** Gerät registrieren,
Provisioning-Profil anlegen und das Entwicklerzertifikat auf dem iPhone
bestätigen sind einmalige Schritte, durch die die Oberfläche führt. Die
eingecheckte Scheme verwendet für Run bewusst Release, weil der unoptimierte
Replay-Core bei anspruchsvollen Modulen nicht echtzeitfähig sein muss; Tests
bleiben Debug. Danach:

```
bash ios/scripts/build-device.sh --install
# Bei mehreren gekoppelten iPhones:
SAVAGE_DEVICE='<Name oder ID>' bash ios/scripts/build-device.sh --install
```

Das Skript übergibt `-allowProvisioningUpdates`, damit `xcodebuild` das Profil
selbst auffrischen darf; ohne diese Vorarbeit in Xcode scheitert es aber am
noch nicht registrierten Gerät.

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
7. **Visualisierungen.** Im Wiedergabe-Tab bis zu den Visualisierungen scrollen:
   Pegel, Master- und Kanal-Oszilloskope starten sofort. Wieder hochscrollen,
   kurz in einen anderen Tab wechseln und zurückkehren; beim erneuten
   Sichtbarwerden starten alle drei Anzeigen wieder.
8. **Ziehen aus der Dateien-App.** Eine Moduldatei in die Bibliothek ziehen.
   Der Titel wird importiert und lässt sich abspielen; ein erneutes Ziehen
   derselben Datei erzeugt kein Duplikat. Diesen Bedienweg am Gerät prüfen,
   weil der Simulator keine von außen auslösbare Ziehgeste bietet.
9. **Hängender File Provider (gesonderte Abnahme).** Falls ein Anbieter mit
   reproduzierbar hängendem koordiniertem Lesen verfügbar ist: Import starten,
   abbrechen und prüfen, dass die App wieder bedienbar ist. Zusätzlich ohne
   Nutzerabbruch den Stall-Timeout prüfen. Anbieter, Auslöser und Ergebnis
   festhalten. Ohne reproduzierbaren Hänger bleibt diese Abnahme offen;
   `CoordinationWatchdogTests` allein belegt das Verhalten des Anbieters nicht.

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

Web-Ladezustand und Songende: `node Tests/js/playback-state.mjs` prüft Titelwechsel,
Stop während Audio-Vorbereitung, endliche Pattern-Loops und kombinierte Sprungbefehle.

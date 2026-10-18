# Test-, Build- und Quick-Look-Runbook

Stand: 2026-10-18. Diese Datei enthält die Details, die nur vor einer betroffenen
Änderung geladen werden müssen. Die kompakte Pflichtmatrix steht in `AGENTS.md`.

## Allgemeines Gate

Das portable Sammlungsformat wird mit `swift test --filter CollectionExchangeTests`
auf Mac und Linux geprüft. Hin-/Rückübertragung mit unterschiedlichen lokalen
Quellen, Konflikte, fehlende Zuordnungen, Pfadschutz und Größenlimits müssen
bestehen; die Tests ersetzen keine native Dateitransfer-Abnahme. Details stehen
in [collection-exchange.md](collection-exchange.md).

Die native Übernahme ergänzt `CollectionExchangePersistenceTests`,
`CollectionExchangePreferencesTests`, `LibraryCollectionExchangeAdapterTests` und
`CollectionExchangeModelTests`: Abwesenheit und Rohbytes der Speicher,
Wiederherstellung an allen Schreibgrenzen, fremde Änderungen, unveränderte
Wiederholungsimporte, Abbruch und veraltete Vorschauen. Die iOS-Suite prüft die
wirklichen Bibliotheks-IDs, Übernahme/Neustart und während des Datendialogs
geöffnete Musik nach Stop. Ein echter Mac→iPhone→Mac-Dateirundweg braucht Dateien
aus den nativen Exportdialogen beziehungsweise der iOS-Anbindung; ein Skip ohne
bereitgestellte Datei zählt nicht als Transferbeleg. Zusätzlich die betroffenen
Sheets auf Mac, Telefon und Tablet in beiden Sprachen/Darstellungen und mit großer
Schrift visuell prüfen. Geräte-Dateien/AirDrop bleiben eine eigene Abnahme.

1. Reproduktion oder prüfbare Invariante vor dem Fix festhalten.
2. Kleinste passende Tests während der Arbeit ausführen.
3. Vor Abschluss `swift test` und `git diff --check` ausführen, wenn Swift-Code
   betroffen ist. Bei App/Core/Quick Look zusätzlich `bash build_app.sh`.
4. Lokale Moduldateien und Referenz-WAVs bleiben ungetrackt. Übersprungene
   Korpustests ausdrücklich als Skip und nicht als Kompatibilitätsbeleg melden.

## Lokale Metadaten-Abgleichgrundlage

Die App-Anbindung prüfen `CollectionSyncModelTests` und die iOS-
`CollectionSyncAppTests`: tatsächliche Speicheränderungen, explizite Titelzuordnung,
Konflikte, Abbruch, Neustart, Kontowechsel und beschädigte Einstellungen. Ein
fehlender oder beschädigter Speicher darf keine Löschungen veröffentlichen.
`CollectionSyncPersistenceTests` prüfen die atomare Übernahme aller vier Dateien
und ausgewählter Einstellungen einschließlich Abbruch und Wiederherstellung.
Die große synthetische Sammlung enthält 20.000 Titel; während der Verarbeitung
muss der Hauptthread weiter reagieren.

`CollectionSyncViewTests` zeigen Einrichtung, Zuordnung, Konflikte, Fehler und
Kontowechsel in DE/EN, Light/Dark sowie großer Bedienungshilfen-Schrift. Native
Aufnahmen visuell prüfen. Der iOS-XCTest-Host startet weder die normale Bibliothek
noch deren Wiederherstellung. Für physische Geräte ausschließlich diese neuen
Abgleichtests mit eigenen Dateien, Bibliotheken und Einstellungssuiten auswählen;
ältere Tests besitzen diese vollständige Isolation nicht durchgängig.

Der injizierte Testdienst belegt den App-Ablauf einschließlich Transportfehlern.
Ein echter CloudKit-Lauf mit zwei Geräten benötigt weiterhin die bestätigte
Containerkennung, Entitlements und Profile. Ohne diese Konfiguration bleibt der
Anbieter deaktiviert. Eine erfolgreiche lokale Abnahme belegt keinen Cloud-Dienst.

Prüfstand 1.6.51 (2026-10-18): macOS 753 Tests / zwei Skips / kein Fehler,
Linux 670 Tests / zehn Skips / kein Fehler und iOS 123 Tests ohne Skips oder
Fehler. Ein Linux-Zeitgrenzentest wurde nach gemessener Vollauslastung bei ruhiger
Last erfolgreich wiederholt; seine Grenze bleibt unverändert. App/Quick Look,
Signaturen, Simulator-Build und Geräte-Build mit vorhandenen Profilen bestehen.
Die native Mac-Abnahme prüft den ausgeschalteten Anbieter, beschädigten
Abgleichspeicher bei weiter nutzbarem Dateiaustausch, Zuordnung, stabile Kopien,
Offline-Wiederholung und bestätigten Kontowechsel. Die vier isolierten iPhone-
Tests bestätigen tatsächliche App-Speicheränderungen und native Ansichten;
Produktionseinstellungen und vorhandene Metadatenspeicher bleiben unverändert.
Telefon und Tablet sind in DE/EN, beiden Darstellungen und größter Schrift
visuell geprüft. Der tatsächliche 1.6.51-Dateirundweg Mac → iPhone-Simulator → Mac
erhält Playlists, Reihenfolge, Favoriten, Songstellen und Klangwerte. Die
ursprüngliche Mac-App und vollständigen Einstellungen sind nach den temporären
Tests unabhängig wiederhergestellt. Dateien-App, AirDrop und echter CloudKit-
Zwei-Geräte-Dienst bleiben eigene Abnahmen.

Die integrierte Abschlussprüfung mit 1.6.51 verbindet übernommene Metadaten,
lokale Änderungen, Neustart, Titelklang, Warteschlange, Timer und festgehaltenen
Videoexport. Sieben native Video-Prüfphasen bestehen: Vorschau, geänderte
Optionen, Abbruch, Zielschutz, laufende Wiedergabe, festgehaltener Titel sowie
IT-Export bei größter Schrift und schmalem Fenster. Beide tatsächlichen
MOD-/IT-Exporte enthalten bytegleiches Float32-Audio zur unabhängig gerenderten
WAV-Referenz. 60 Sekunden mit 1.800 Bildern bei 30 Bildern/s beziehungsweise
7,68 Sekunden mit 192 Bildern bei 25 Bildern/s enden exakt mit ihren Audiotracks.
Die vollständige Wiederherstellung der ursprünglichen Mac-App und Einstellungen
ist unabhängig bestätigt. Zusätzlich bestehen 14 CLI-Vertrags- und acht
Wiedergabetests. Diese Abläufe ersetzen den ausstehenden echten Cloud-Dienstlauf
nicht.

`python3 Tests/cloudkit_signing_tests.py` prüft die Ablehnung fremder, abgelaufener und unpassender CloudKit-Profile. Gültige Profile dürfen nur den einzelnen Container und CloudKit in die App-Berechtigungen übernehmen.

`swift test --filter 'CollectionSync|CloudKitCollection'` prüft typisierte Snapshots, Referenzen,
Tombstones, Vererbung, alle 64 Einzelwert-Kombinationen, explizite Konflikte,
stabile Kopien, veraltete Vorschauen und Konto-Epochen. Codec-Rundläufe auf Disk
müssen auch Datumsbruchteile und ausstehende Änderungen erhalten. Bekannte,
fehlende Metadaten dürfen nicht als Löschung gelten; Grenzen und beschädigte
Dateien liefern Fehler. Große synthetische Sammlungen auf Mac und Linux prüfen.
Die lokale Projektion muss ausdrückliche Löschungen von additivem Import unterscheiden,
fremde Einträge erhalten und bei fehlender oder geänderter Zuordnung stoppen. Ein
lokales Titelregister muss globale IDs über wiederholte Exports und Neustarts
erhalten, gleichnamige Dateien unterscheiden und Konto-/Generationswechsel sowie
mehrdeutige oder stille Neuzuordnungen ablehnen. Auch 20.000 Zuordnungen dürfen
beim erneuten Export nicht wachsen; lokale URLs dürfen den Export nie erreichen. Ein
gemeinsamer lokaler Neustartstand muss Checkpoint und Titelregister zusammen
erhalten. Ausdrückliche Offline-Änderungen, Konflikte nach Neustart, Klangreset,
verlorene Zuordnungen und veraltete Ausgangsstände prüfen; fehlende, beschädigte,
nicht reguläre oder übergroße Dateien dürfen nie eine leere Sammlung liefern. Ein
zusätzlicher iOS-Test liest optional einen tatsächlichen Mac-Core-Checkpoint aus
`Documents/SyncFoundationInterop/from-mac.json` und schreibt `to-mac.json` zurück; ohne
Datei überspringt er diesen Rundlauf ausdrücklich. Er verbindet lokale relative
Titelzuordnung, Neustartstand, synthetischen Transport, Projektion und echtes
Dateijournal; `to-mac-snapshot.json` hält den simulierten Versandstand fest. Ein
unbestätigter Versand bleibt im Checkpoint ausstehend. `SongMarkerPrecisionTests`
prüft zusätzlich genaue lokale Datumswerte, positive/negative Sekundenwechsel,
ältere Dateien/Leser, widersprüchliche
Zeitangaben und den wiederholten manuellen Import. Diese Tests rufen keinen Cloud-Dienst
auf; die echte Zwei-Geräte-Abnahme bleibt
ein eigener Nachweis. Details: [Abgleichentwurf](collection-sync.md).

Transporttests verwenden einen synthetischen Dienst für bedingtes Erstellen und
Ändern, Rennen zwischen Read/Write, Kontowechsel und ungültige Bestätigungen.
Ein fehlender Record oder eine gelöschte Zone darf keine leere Sammlung ergeben.
Eine alte Konto-Epoche muss auch nach abgeschlossener Anfrage abgewiesen werden.
Lokale SDK-Record-/Asset-Tests erzeugen keine Containerinstanz; sie prüfen Format,
Identität, Größenbegrenzung und Fehlerabbildung. Nach einem unklaren Schreibende
bleibt der lokale Checkpoint unbestätigt; Tests dürfen daraus keinen Cloud-Rollback
ableiten. Die eigentliche CloudKit-Verbindung ist nur mit passender Konfiguration
und echtem Dienstzugriff belegbar.

## Offline-Notenregen-Video

`swift test --filter NoteRainVideo` prüft die portable Zeit-/Audiobasis und am Mac
die echten MOV-Tracks. Bei Änderungen zusätzlich die volle Suite, App/Quick Look,
iOS-Build/-Tests und den Linux-Lauf ausführen. Audioadapter mit den bestehenden
Float-WAV-Ausgaben vergleichen; der lokale MOD-Korpus muss nach einem
Release-Build weiter byteidentisch zur Baseline rendern. Kurze letzte Bilder,
Tempoänderungen, IT-Hintergrundstimmen, Mute/Solo, Zielrennen und Abbruch prüfen.
Gerenderte Bilder in Hell/Dunkel visuell ansehen und bei längeren Exports den
Speicherverlauf messen. [Vertrag und Grenzen](note-rain-video.md).

Die native Exportoberfläche zusätzlich mit pausierter Vorschau, geänderten
Optionen, abgebrochener Vorschau, Speichern-Dialog, vorhandenen Zielen,
Fortschritt, Exportabbruch und Finder-Ergebnis prüfen. Titel-/Klang-Snapshot,
weiterlaufender Live-Transport, Warteschlange und Einschlaftimer müssen erhalten
bleiben. Hell/Dunkel, schmale Hauptansicht und größte UI-Schrift abnehmen;
die Scrollbereiche müssen alle Optionen und die Fußleiste erreichbar halten.
Beide H.264-Kompressionsstufen müssen identisches Audio und exakte Trackenden
liefern. Ein verdecktes oder gesperrtes Fenster liefert keinen visuellen Beleg.

Native Abnahme mit Version 1.6.50 am 2026-10-18 bestanden: sechs Startprüfungen,
pausierte Fünf-Sekunden-Vorschau, Optionswechsel mit verworfener Vorschau,
Vorschau-/Exportabbruch, deaktivierte Optionen während des Exports, Schutz eines
vorhandenen Ziels und fertiger Finder-Link. Lautstärke, laufende Wiedergabe,
Warteschlange und Timer bleiben erhalten; ein späterer Titelwechsel ändert den
festgehaltenen Exporttitel nicht. Hell/Dunkel, schmale Hauptansicht und größte
Schrift sind visuell geprüft; die Exportbuttons wachsen mit ihrer Beschriftung.
Original-App und vollständige Einstellungen sind unabhängig wiederhergestellt.

Die beiden tatsächlich über die Oberfläche erzeugten HD-Videos enthalten
1.800 Bilder bei 30 fps beziehungsweise 192 Bilder bei 25 fps. Ihre Audio- und
Videotracks enden exakt nach 2.880.000 beziehungsweise 368.640 Stereo-Frames bei
48 kHz. Das nicht stumme Float32-Audio ist nach Decodierung byteidentisch zur
jeweiligen WAV-Referenz. Die getrennte zweiminütige IT-Probe mit 60 fps,
Tempoänderungen, Hintergrundstimmen und Mutes besteht ebenfalls; der eigene
Rendererprozess erreicht 55,1 MiB Spitze, ohne den externen Encoderdienst.

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

- macOS-Ausgabetail und Stop mit mehreren Wartern:
  `swift test --filter AVAudioEnginePCMSinkTests`. Die endlichen Nullsamples
  sind lautlos. Der Test braucht eine echte Audioausgabe; ein Skip ist kein
  Ausgabebeleg.

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

**Beide Suiten nehmen Release vor Debug und pruefen jeweils das zuletzt gebaute
Binary.** Sie beruecksichtigen den klassischen `.build/release`-Pfad sowie
`.build/out/Products/Release` des neueren Swift-Buildsystems. Nach einer
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

### Sparkle-Updates

`python3 Tests/sparkle_contract_tests.py` prüft signierte Feeds und Archive,
Manipulationen, falsche Schlüssel und die Ablehnung alter Releases/Prereleases.
Nach dem App-Build zusätzlich Framework-rpath, Lizenz und verschachtelte
Signaturen prüfen. `scripts/verify-sparkle-release.sh` prüft ein notarisiertes
Release-DMG vor der Feed-Signatur; `scripts/verify-sparkle-feed.swift` prüft Feed
und Archiv gegen den öffentlichen Schlüssel aus dem ausgelieferten Bundle.
Abschließend Menü, Update-Einstellungen und einen echten App-Austausch auf einem
Test-Mac prüfen. Setup und Bootstrap-Grenze stehen in `docs/sparkle-release.md`.

### App-Bundle

`bash build_app.sh` baut die Release-App und die Quick-Look-Appex. Ein bloßes
`swift build` deckt Extension, Signatur und Bundle-Integration nicht ab.
`python3 Tests/ui_source_tests.py` schützt zusätzlich die Pflichtbedienelemente
des kompakten Footers; der sichtbare Fenster-Smoke bleibt trotzdem erforderlich.

### Notenregen-Fenster

Fensterabnahme am 2026-10-07 mit Version 1.6.20 (`f08d4de`) und einem
synthetischen, lautlosen Vierkanal-MOD im normalen App-Lauf bestanden:

- **Darstellung → Notenregen öffnen** öffnet das separate Fenster.
- Wiederholtes Öffnen erzeugt kein zweites Notenfenster.
- Der Pause-Button schaltet den angezeigten Zustand von **Spielt** auf **Pausiert**.
- Nach dem Schließen öffnet **Umschalt–Cmd–N** das Fenster erneut.
- Erneutes Schließen und Wiederöffnen über das Menü erhält die Fensterzahl.
- Die Test-App wurde anschließend ausgeblendet und beendet.

Die native Ansicht wurde außerdem in hell, dunkel und mit der Mindestgröße
720 × 440 Punkten visuell geprüft. Timing, Stimmenlaufzeit, Steuerungsbefehle
und IT-NNA-Überlagerungen deckt `swift test --filter NotePreviewTests` ab.

Ergänzende Abnahme am 2026-10-07 mit Version 1.6.21 bestanden: Standardbereich
**A0–C8 · 88 Tasten**, Umschaltung auf **Tonumfang** mit **C2–B4 · 36 Tasten**
beim synthetischen Teststück, Rückkehr zur Klaviatur und Erhalt beider Auswahlen
beim Schließen/Wiederöffnen. Singleton, Pause und Tastenkürzel bleiben bestätigt.
Die native Darstellung wurde in hell, dunkel und 720 × 440 Punkten geprüft;
synthetische S3M-Noten an beiden Grenzen zeigen **C0–B9 · 120 Tasten**.
Schwarze Noten außerhalb des 88-Tasten-Bereichs erweitern die Klaviatur bis zu
äußeren weißen Tasten, sodass Tasten und Balken vollständig sichtbar bleiben.

Ergänzende Abnahme am 2026-10-07 mit Version 1.6.22 bestanden: **Tonumfang**
verkleinert die Fensterbreite beim Teststück von **1100 auf 480 Punkte**;
die weißen Tasten bleiben in beiden Ansichten **20 Punkte** breit. Die native
Darstellung wurde in hell/dunkel und bis **420 × 440 Punkten** geprüft.
Im normalen App-Lauf sind außerdem **900 → 420** und **720 → 420 Punkte**,
die Rückkehr zu allen drei Ausgangsbreiten und das Schließen/Wiederöffnen
bestätigt. Singleton, Pause und Tastenkürzel bestehen weiterhin. Bei einem
Songwechsel passt sich die fokussierte Breite an; alle 120 Tracker-Noten und
schwarze Randnoten bleiben abgedeckt. Die Voreinstellungen wurden anschließend
vollständig wiederhergestellt, die Test-App ausgeblendet und beendet.

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

`python3 Tests/launch_smoke_contract_tests.py` prüft Backupfehler, erhaltene
Sicherungen nach Restorefehlern und das Beenden ausschließlich eigener Prozesse.
`python3 Tests/publish_contract_tests.py` prüft ohne Netzwerk-Schreibzugriff
GitHub-Ziel, vollständige Refs, zusätzliche Tags und umgebogene Push-URLs.
`swift test --filter PCMSinkConcurrencyTests` prüft parallele Start-/Stop-Aufrufe;
unter Linux kann eine ALSA-Nullausgabe den Hardwarebedarf für diesen Vertrag ersetzen.

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

Das Skript verwendet vorhandene Profile und übergibt keine automatischen
Provisioning-Updates. Geräte, App-Kennung und Profile müssen vorher eingerichtet
sein. Für optionale CloudKit-Builds prüft `tools/prepare-cloudkit.py` das Profil
und erzeugt die begrenzten Build-Einstellungen.

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

Native Drop-Aufträge: `python3 Tests/drop_request_tests.py` führt die tatsächlichen
Drop-/Revisionsfunktionen mit steuerbaren Provider-Callbacks aus. Das prüft Stop,
neuere Auswahl und die Identität bis zum Hintergrundscan; ein echter Finder-Provider
ist dabei nicht beteiligt.

Ein fokusfreier Browser-Smoke auf macOS ist mit WebKit möglich:
`swift Tests/webkit_smoke.swift 'http://127.0.0.1:8765/savage-mod-player.html?testDropAutoplay=1' /tmp/savage-webkit.png`.
Der Test setzt die Lautstärke auf null, lädt den echten AudioWorklet, prüft Drop-Autoplay
und Stop und sichert einen Screenshot. Die WebKit-Testkonfiguration erlaubt Autoplay;
die Freigabe nach einer echten Browser-Nutzergeste bleibt eine separate Prüfung.


## Linux-MPRIS2

Linux-Builds benötigen zusätzlich `libdbus-1-dev`; das ausgelieferte Binary
benötigt `libdbus-1.so.3`. Auf einem Linux-Testdesktop mit Audioausgabe:

```bash
python3 Tests/mpris_contract_tests.py -v
dbus-run-session -- python3 Tests/mpris_contract_tests.py -v
```

Die Suite spielt ausschließlich synthetische Nullsamples. Sie prüft Play/Pause,
Stop → Play, Titelwechsel unter Pause, Position, Metadaten, PropertiesChanged,
Introspection, Fehlerantworten, mehrere Instanzen und Wiedergabe ohne Bus.
Fehlender Bus/Audioausgabe ist ein Skip und belegt keine Desktopfunktion.
Der Audiocallback ruft keine D-Bus-Funktion auf; Pegel und Framezähler sind
lockfreie 64-Bit-Atomics in der C-Brücke.


## Linux-AppImage

Zuerst `bash linux/build-static.sh`, dann `bash linux/build-appimage.sh` auf
Linux x86_64. Das zweite Skript prüft Werkzeug und enthaltene Runtime per
SHA-256; ein aktueller Runtime-Download ist ausgeschlossen. Systembibliotheken
bleiben ALSA, D-Bus, zlib, libstdc++ und glibc; die tatsächliche glibc-Grenze
steht im eingebetteten `usr/share/doc/savage-cli/build-info.txt`.

```bash
SAVAGE_APPIMAGE="$PWD/build/Savage-Mod-Player-$(cat VERSION)-x86_64.AppImage" \
  python3 Tests/appimage_contract_tests.py -v
SAVAGE_CLI_TEST_BINARY="$PWD/build/Savage-Mod-Player-$(cat VERSION)-x86_64.AppImage" \
  python3 Tests/mpris_contract_tests.py -v
```

Die AppImage-Suite prüft echten FUSE-Start, Extraktionsfallback, relative
Dateipfade mit Leerzeichen, identisches WAV-Rendering, Ressourcen/Lizenzen,
Prüfsummen-Abbruch und Schutz des Eingabebinarys. Ein FUSE-Startfehler darf
nicht als erfolgreicher nativer Start gezählt werden.

## Gespeicherte Playlists und Warteschlange (macOS)

Gezielte Regressionen: `swift test --filter 'SavedPlaylistTests|TrackQueueTests|PlaylistScannerTests'`.
Quellen-IDs müssen gleichnamige Dateien unterscheiden und bei erneutem Entpacken
verschachtelter Archive stabil bleiben. Der Speicher lehnt beschädigte und neuere
Dateiformate ab, ohne sie als leere Sammlung zu überschreiben.

Für isolierte App-Tests setzt `SAVAGE_PLAYLIST_STORE` den Pfad einer separaten
Playlist-JSON-Datei. Das isoliert **nur diese Datei**, nicht die UserDefaults.
Der Startlauf-Smoke sichert die Preferences separat und setzt den Speicher auf
sein eigenes temporäres Verzeichnis. Anschließend entfernt er neu angelegte
Preferences-Schlüssel, spielt die Sicherung zurück und vergleicht alle Werte.
Regulär liegt der Playlist-Speicher unter
`$HOME/Library/Application Support/SavageModPlayer/playlists.json`.

In der echten App prüfen:

- Liste anlegen, umbenennen, Titel entfernen/verschieben und erneut öffnen;
  nach Neustart müssen Name, Reihenfolge und Quellen erhalten bleiben.
- Zwei gleichnamige Dateien aus verschiedenen Ordnern getrennt favorisieren.
  Alte mehrdeutige Namen bleiben unzugeordnet, noch ungesehene Namen vorgemerkt.
- Eine und danach alle Quellen vorübergehend unerreichbar machen. Die App muss
  dies melden und die gespeicherten Referenzen behalten. Nach Rückkehr der Quellen
  muss die vollständige Liste wieder öffnen.
- Zwei unterschiedliche Titel einreihen, verschieben/entfernen und über Weiter
  laden. Danach muss die vorherige Liste an der richtigen Stelle fortfahren;
  pausierte Wechsel bleiben pausiert. Die Warteschlange gilt für die Sitzung.
- Suchtreffer ausdrücklich abspielen: Weiter/Shuffle bleiben im gewählten Bereich,
  auch wenn sich die reine Suchanzeige ändert. „Alle“ gibt den Bereich wieder frei.
- Helles/dunkles Theme und die schmale Sidebar prüfen, einschließlich Suche,
  Hinweisen, Playlistdialog und Warteschlange. Bei beschädigtem Speicher muss der
  Dialog den Fehler zeigen und Schreibaktionen sperren.

### iPhone/iPad

`SavedCollectionTests` prüft Bearbeitung und Neustart, Containerwechsel,
fehlende Quellen, beschädigte Daten und die Rückkehr aus der Sitzungswarteschlange.
Der gemeinsame Speicher enthält für diese Titel `savage-library`-Referenzen mit
relativen Pfaden; absolute App-Containerpfade dürfen dort nicht auftauchen.

Nach `bash ios/scripts/build-simulator.sh` und `bash ios/scripts/run-tests.sh`
die neuen Bibliotheksmenüs, Playlistliste/-details und Warteschlange auf iPhone
und iPad in beiden Themes prüfen. Die Renderproben müssen einer echten
`UIWindowScene` zugeordnet sein; schwarze Offscreen-Bilder sind kein UI-Beleg.
Auf dem echten Gerät zusätzlich Weiter über Kopfhörer/Sperrbildschirm mit zwei
eingereihten Titeln und anschließender Rückkehr in die vorherige Liste prüfen.

## Metadatenindex

`swift test --filter ModuleMetadataIndexTests` prüft alle vier echten Parser,
Cache-Wiederverwendung/Neustart, geänderte Dateien, Größenlimits, Fehler, Abbruch
und FIFO-Schutz. Der FIFO-Test öffnet nach seiner begrenzten Wartefrist selbst
einen Schreiber, damit eine Regression rot endet und keinen Leser zurücklässt.
Die Gegenprobe ohne `O_NONBLOCK` muss scheitern. Der Index liegt im gemeinsamen
Library-Bereich und braucht zusätzlich die vollständige Linux-Suite.
Dauerwerte an der Grenze sind begrenzte Ergebnisse, keine exakten Gesamtdauern.

## Bibliotheksfilter und Hörstatus

Gemeinsame Regressionen: `LibraryQueryTests`, `LibraryPreferencesStoreTests` und
`LibraryCatalogModelTests`. Sie prüfen 10.000 synthetische Einträge, Namenskollisionen,
Kombinationen, natürliche Sortierung, fehlende Metadaten, Abbruch, Neustart,
Transaktionen und veraltete Aufträge. Die native Bindung wird nur mit Combine
gebaut; Linux prüft die plattformneutralen Query-/Speichertypen.

In der App Instrumentnamen suchen, nach internem Titel sortieren und ausdrücklich
die Treffer abspielen; Weiter/Zurück müssen dieser Reihenfolge folgen. Gespeicherten
Filter nach Neustart erneut anwenden. Ungehörte Auswahl darf beim bloßen Laden
nicht verschwinden, erst nach echtem Play; Kontextmenü setzt sie zurück.
Fehlerdetails, gleiche Dateinamen und begrenzte Dauerwerte in beiden Themes prüfen.

Für isolierte Mac-Tests setzen `SAVAGE_METADATA_STORE` und
`SAVAGE_LIBRARY_PREFERENCES_STORE` getrennte Dateien. Der Start-Smoke setzt beide
zusätzlich zu seinem Playlist-Speicher. iOS-Tests reichen `VERSION` wie der
Simulator-Build als `MARKETING_VERSION` durch; neue Renderproben liegen in
`LibraryFiltersViewTests`, der echte Wiedergabe-/Hörstatuspfad in `CatalogPlaybackTests`.

## Sample-Inspektor

`swift test --filter SampleInspectionTests` prüft alle XM-Samples einschließlich
ungenutzter Slots, den globalen IT-Pool, transponierte/unbelegte Tastenzuordnungen,
Stereo-Impulse, Zoom-Grenzen, leere Daten und Abbruch. Linux prüft dieselben Modelle;
die optionale SwiftUI-Ansicht bleibt über `canImport(SwiftUI)` ausgeblendet.

Im echten Mac-Lauf zwischen Instrumenten/Samples wechseln, bis 64× zoomen, beide
Ausschnittenden und die direkten Loop-/Sustain-Ansichten prüfen. Kleine Samples
müssen auch bei einem Frame je Zeichenpunkt sichtbar bleiben. Die Tastenzuordnung
muss Quelle, Ziel und Sample getrennt zeigen; MOD/S3M erhalten keine erfundene
Tabelle. Dialog-Pfeile/Leertaste dürfen keine Transportaktion auslösen.
`SampleInspectorViewTests` rendert XM-, IT-Stereo-/Sustain- und Leerzustände auf
Telefon und Tablet in DE/EN und beiden Themes. Die Ansicht verändert den Hörstatus
nicht und hält das beim Öffnen gewählte Modul fest.

## Modul-/Instrument-Inspektor

`ModuleInspectionTests` prüft wiederverwendete Orders, statische Effektzahlen,
explizite Nullparameter, Formatkollisionen, Volume-Spalten, Hüllkurven-Tickgrenzen,
Abbruch und Herkunft ausschließlich aus expliziten Feldern. `ModuleInspectorViewTests`
rendert Übersicht, Hüllkurven, IT-Regeln und Effekthilfe in DE/EN auf Telefon/Tablet
sowie das Info-Menü mit einem tatsächlich geladenen Modul. Im Mac-Lauf dieselben
Ansichten mit echten synthetischen XM-/IT-Dateien öffnen, Order-/Punktlisten
aufklappen und erkannte ignorierte Befehle prüfen. Die Auswertung bleibt lesend;
Parser und Audiopfad ändern sich durch die Inspektoren nicht.

## Songstellen und Bereichsauswahl

`SongMarkerTests` prüft wiederverwendete Patterns, Bereichsgrenzen, Quellen-IDs,
Neustart/ISO-Zeiten, beschädigte/neue/zu große Speicherdateien, atomare Fehler und
konkurrierende Actor-Aufträge. `SongMarkersModelTests` prüft Quellwechsel,
Bearbeiten/Neustart, Schreibsperre, unabhängige Auswahl und einen echten gestoppten
Zeilensprung. `SongMarkersViewTests` rendert Editor, Bereich, fehlende Ziele und
Schreibsperre auf Telefon/Tablet; der zweite Test lädt echte synthetische MODs und
prüft zeilengenauen Sprung und neue Lade-ID beim Titelwechsel.

Im Mac-Lauf eine Songstelle nach Neustart öffnen, pausiert und gestoppt springen,
Anfang/Ende über Blatt und Tracker-Zeilenmenü setzen, zwei Order-Positionen mit
identischem Pattern unterscheiden und die Positionsleiste im Notenregen prüfen.
Die Leiste folgt der Abspielliste, nicht einer vorausberechneten Zeitachse.
`SAVAGE_SONG_MARKER_STORE` isoliert den eigenen autoritativen Speicher; der
Start-Smoke setzt ihn ebenfalls. Simulatorläufe wählen konkrete IDs und laufen
ohne parallele Tests; fremde Simulatorgeräte/Prozesse bleiben unangetastet.

Queue-Navigation auf macOS: `python3 Tests/playlist_queue_navigation_tests.py` prüft den unveränderten nativen Navigationscode mit einer externen Queue-Quelle, Listenrückkehr, Stopzustand und gescheiterten Ladeversuchen. `python3 Tests/drop_request_tests.py` prüft verzögerte Drop-Callbacks und Transportabbrüche. `PlaylistScannerTests` deckt gespeicherte Listen mit 129 Archiven und getrennte Sicherheitslimit-Meldungen ab; iOS `SavedCollectionTests` unterbricht tatsächliche asynchrone Ladevorgänge und ergänzt einen Queue-Titel während eines Fehlversuchs.

## Zustandskorrekte A/B-Wiedergabe

`SectionLoopTests` vergleicht zehn Wiederholungen mit dem entsprechenden Abschnitt
der kontinuierlichen Float-Ausgabe, bei Blockgrößen 1/64/127/256/1024 und in allen
vier Formaten. Fixtures treffen vor A gestartete Stimmen, fractional Timing,
Effekt-Memory, IT-NNA/Filterhistorie/Zufallsvariation, neue Stimmen nach Restore,
inklusive MOD-/IT-Delays, Pattern-Loops, Sprünge, gleiche Patterns in mehreren
Orders, letzte Zeile, Budget/Abbruch, Mute und den synchronen Preview-Pfad.
`SectionLoopCoordinatorTests` startet eine stumme echte Audio-Engine und prüft
pausierte Aktivierung, Ausschalten vor dem ersten Callback, späte Ergebnisse
nach Stop/Optionen und den Erhalt laufender Wiedergabe bei einem ungültigen Ziel.
Auf iOS prüft `SongMarkersViewTests` den tatsächlichen PlaybackEngine-Aufruf,
Pause, Titelwechsel, Abbruch und die DE/EN-Ansichten für aktive Schleife/Fehler.

Im echten Mac-Lauf A/B in einer späteren Songposition setzen, mehrere Runden in
Tracker und Notenregen vergleichen, pausiert aktivieren und vor Fortsetzen
abschalten. Stop, Titel-/Bereichswechsel und Tempo/Clock/Interpolation/Separation/
LED-Filter prüfen. Unerreichbare Grenzen müssen einen Fehler zeigen; Abbruch darf
keinen verspäteten Start auslösen. Der LED-Ausgabefilter liegt außerhalb des
Replay-Snapshots und behält während der Schleifen seine Ausgabehistorie.


### A/B-Wiedergabe: Abnahme 1.6.42

Am 2026-10-16 bestanden: macOS 549 Tests (2 Skips), Linux 515 Tests (9 Skips),
22 byteidentische MOD-Baselines und 22 samplegenaue A/B-Korpusvergleiche.
Die Allokationssonde mit positiver Gegenprobe meldet bei je 1.000 MOD-/XM-/IT-
Callbacks keine Heap-Allokation. App und Quick Look sind gebaut und signiert.

Native Mac-Bedienung und Bilder wurden in Light/Dark geprüft: A/B-Wiederholungen
in zwei Orders desselben Patterns, weiterlaufende Stimmen im Notenregen,
Pause/pausierter Start/Stop, Änderungen von Clock, Tempo, Speed, Separation,
Interpolation und Filter, Bereich/Seek/Titelwechsel, begrenzte Rekonstruktion,
Abbruch sowie Wiederöffnung des Songstellenblatts nach dem Notenregen.
Die ergänzenden Sample-/Modulinspektor- und Marker-Detailprüfungen sind bestanden.
Der erste Inspektoraufruf zeigt sein festgehaltenes Modul ohne leeres Blatt.

Der echte iPhone-Simulatorlauf umfasst 96 Tests ohne Fehler oder Skips, die
gezielte iPad-Songstellen-Suite 3 Tests ohne Fehler oder Skips. Frische Bilder
belegen DE/EN, Light/Dark, aktive Schleife, Fehlerzustände und Scrollbereiche.
Hintergrundwiedergabe und Sperrbildschirm bleiben ausschließlich am Gerät belegbar.

## Stereo-Kanalspuren

`swift test --filter ChannelStemRendererTests` prüft Stereo-Gegenphase, die
Spurensumme gegen den Referenzmix, die Rekonstruktion der normalen Ausgabe,
Mute/Solo/Header-Defaults, IT-NNA mit 256 Stimmen/64 Besitzern, Panning/Surround,
Timing-Sonderfälle, Teilblöcke, Abbruch und frühe/späte Zielkonflikte.
Bei Änderungen am Capture weiterhin die lokalen MOD-WAVs byteweise mit der
Baseline vergleichen; der vorhandene Mono-Capture behält seinen bisherigen
Vertrag. Die [Exportbeschreibung](channel-stem-export.md) erklärt Gain und
Mastergrenzen.

Die Mac-Abnahme umfasst den gesamten Weg über die Export-Schaltfläche: beide
Ausgaben, Ordnername/Zielwahl, bestehendes Ziel, Fortschritt/Abbruch, Ergebnis
im Finder und anschließenden erneuten Export. Light/Dark und Tastaturbedienung
prüfen; Pfeiltasten und Leertaste im Exportdialog dürfen nicht den Titel wechseln.
Die Core-Tests ersetzen diese echte Bedienabnahme nicht.


Native Abnahme 1.6.43 am 2026-10-16 bestanden: Ausgabe-/Dauerwahl, ungültiger
Ordnername, Panelabbruch, Tastatur/Escape, Zielkonflikt mit unveränderter
Kontrolldatei, erneuter Export, Titel-Snapshot bei gleichzeitigem Titelwechsel,
Mute/Solo, Stereo-Mix und Abbruch während Analyse und Schreiben.
Fünf echte GUI-Exporte enthalten synchronisierte Stereo-Float32-WAVs mit je
338.688 Frames bei 44.100 Hz; ihre Spurensumme weicht höchstens 7,46e-9 vom
Referenzmix ab. Stumme und solo ausgeschlossene Kanäle sind exakt null.
Das Finder-Ergebnis wurde geöffnet und das eigene Testfenster wieder geschlossen.
Die finale native Darstellung ist in Light/Dark und900×620 Punkten geprüft;
native Controls erhalten das passende Farbschema. Preferences/App sind restauriert.
Vollsuiten: macOS558Tests/2Skips/0Fehler, Linux525Tests/10Skips/0Fehler,
22 identische MOD-Baselines und Allokationssonde mit positiver Gegenprobe.


## WAV-Stapelexport

`swift test -c release --filter 'BatchWAVExporterTests|ChannelStemRendererTests'`
prüft separate gleichnamige Quellen, beide Zielkonfliktregeln, späte Konflikte,
Einzelfehler, Quelldateischutz, Größen-/Dateityplimits, Abbruch im Titel und
zwischen Titeln, monotone Fortschrittswerte und wiederholbare Einstellungen.
Die Stereo-Float-Ausgabe wird in allen vier Formaten gegen die normale Engine
verglichen. Linux prüft dieselben Core-Tests.

Im echten Mac-Lauf die Liste aus Suche/Filter öffnen, einzelne Titel abwählen,
Player/Anzeige danach ändern und die festgehaltene Auswahl prüfen. Stereo-Mix
und Kanalspuren tatsächlich exportieren, WAVs und Berichte unabhängig lesen.
Überspringen/Beide behalten mit Kontrolldatei, defekte Quelle, Panelabbruch,
Abbruch bei laufendem Export und erneuten Start prüfen. Einstellungen nach
Neustart, Tastatur, Light/Dark und schmale Fenster visuell prüfen.


Native Abnahme mit Version 1.6.44 am 2026-10-18 bestanden: Suchtreffer,
Einzelwahl/Alle/Keine, festgehaltene Auswahl bei Playlistwechsel, Stereo-Mix,
Kanalspuren, Überspringen/Beide behalten, defekte Quelle, Panelabbruch und
Abbruch während des Renderns. Gespeicherte Einstellungen bleiben nach einem
App-Neustart erhalten. Leertaste und Pfeil rechts im Dialog verändern den Player
nicht; Escape bricht die Zielwahl ab. Light/Dark sowie 900 × 620 und 1000 × 740 Punkte sind visuell geprüft;
Fortschritt, Ergebnis und Schaltflächen liegen in einem festen sichtbaren Bereich.
Die ursprünglichen Dateinamen bleiben bei internen Arbeitskopien stabil.

Die unabhängige Gegenprobe liest sechs Ausgabeordner mit zehn Float32-WAVs
(44.100 Hz, Stereo, je 338.688 Frames). Kanalspuren summieren sich mit höchstens
7,46 × 10⁻⁹ Abweichung zum Referenzmix; die Stereo-Mixe weichen bei der
PCM16-Umrechnung höchstens um eine Quantisierungsstufe von der normalen Engine ab.
Wiederholtes Überspringen und neue Namen erhalten die vorhandenen WAVs unverändert;
Abbruch hinterlässt keine unvollständige Titelausgabe. Test-App und Einstellungen
wurden nach dem Lauf vollständig wiederhergestellt.
Vollsuiten: macOS 569 Tests / 2 Skips / 0 Fehler, Linux 536 Tests / 10 Skips /
0 Fehler; 22 MOD-WAVs byteidentisch zur Baseline. App-/Quick-Look-Build und
verschachtelte Signaturen bestehen.


## Einschlaftimer

`swift test -c release --filter 'SleepTimerTests|SleepTimerControllerTests|SectionLoopCoordinatorTests'`
prüft Fadegrenzen innerhalb eines Audioblocks, glatte Rückkehr bei Abbruch und
Verlängerung, gemeinsame Deadline für getrennte Ausgaben, ungültige Zeiten,
verspätete Aktualisierung und den Schutz gegen automatische Wiederaufnahme.
Der Live-Adapter liefert auch bei absichtlich blockiertem MainActor rechtzeitig
Nullsamples. Interner Stop und Titelwechsel erhalten die Deadline; ausdrückliches
Play quittiert den Ablauf. A/B-Vorbereitung darf nach dem Ablauf nicht aktivieren.

Die iOS-`PlaybackLoadingTests` prüfen Abbruch eines wartenden Ladevorgangs bei
Timerende, erhaltene Warteschlange und Lautstärke, Pause/Titelwechsel,
Unterbrechungsende, Vordergrund-Rückkehr und verspätete Songende-Signale.
`SleepTimerViewTests` rendern die native Ansicht in beiden Sprachen, beiden
Darstellungen und mit großer Schrift auf Telefon und Tablet. Die Bildbelege
müssen visuell geprüft werden.

Im echten Mac-Lauf einen Einminutentimer starten, während des Ausblendens die
Lautstärke ändern und verlängern; einen zweiten Lauf während des Ausblendens
abbrechen. Einen weiteren Lauf tatsächlich enden lassen und danach automatische
Wiederaufnahme, normalen manuellen Start und erhaltenen Lautstärkewert prüfen.
Einstellungen/Timerzustand nach Neustart, beide Darstellungen und kleine Fenster
abnehmen. Hintergrund, Sperrbildschirm und reale Audio-Unterbrechungen auf iOS
bleiben Geräteprüfungen; ein Simulatorlauf belegt diese Eigenschaften nicht.

Prüfstand 1.6.45 (2026-10-18): macOS 583 Tests mit zwei Skips wegen fehlender
lokaler IT-Referenzen, iOS 101 Tests ohne Fehler oder Skips, Linux 543 Tests mit
zehn Skips wegen fehlender lokaler Referenzen, Container-Dateirechten und fehlender
Audioausgabe. Die Linux-Suite lief mit CPU-Affinität, nachdem wechselnde Last auf
dem geteilten Testsystem die unveränderte Performancegrenze überschritten hatte.
App-/Quick-Look-Build, Signaturen, Startargument-Smoke, Web-Build und
Pattern-Bounds-Prüfung bestehen. 22 lokale MOD-Ausgaben sind byteidentisch zur
vorherigen Baseline. Bei vier Formaten und fünf Timerzuständen verursachen weder
der erste noch die folgenden 1000 Rendercallbacks Heap-Allokationen; eine
positive Kontrolle weist die aktive Messung nach.

Je sechs native Bildschirmaufnahmen von iPhone und iPad sind visuell geprüft:
DE/EN, hell/dunkel und große Bedienungshilfen-Schrift. Countdown und Aktionen
bleiben sichtbar; die Konfiguration scrollt bei großer Schrift. Die Bilder
belegen die Darstellung, keine iOS-Bediengesten oder Geräte-Hintergrundwiedergabe.

Die native Mac-Abnahme besteht in fünf Prüfphasen mit drei echten
Einminutentimern: Titelwechsel, Verlängern im Fade bei geändertem Lautstärkewert,
Abbruch im Fade, vollständiger Ablauf ohne automatischen Neustart sowie bewusster
Start, expliziter Stop und App-Neustart. Der Reglerwert wurde über seine native
Bedienungshilfen-Aktion von 0,37 auf 0,47 geändert und blieb auch nach Neustart
erhalten. Die gewählte Dauer blieb gespeichert, der aktive Timer wurde nicht
wiederhergestellt. Acht Bilder von Light/Dark bei 1000 × 740 und 900 × 620 Punkten
sind visuell geprüft. Original-App, vollständige Einstellungen und Prozessfreiheit
sind nach dem temporären Test unabhängig bestätigt.

## Klang-Einstellungen pro Titel

`swift test --filter 'TrackPlaybackSettingsTests|TrackPlaybackSettingsModelTests'`
prüft Vererbung gegenüber ausdrücklichem Aus, getrennte Quellen mit gleichem
Dateinamen, Archiv- und Bibliotheks-IDs, Neustart, Rücksetzen, Reglerbündelung,
festgehaltenen Dialogkontext sowie beschädigte, zukünftige und zu große Dateien.
Schreibfehler dürfen keinen ungesicherten Titelwert als gespeichert anzeigen.

Die iOS-`TrackPlaybackSettingsTests` prüfen Werte vor Wiedergabestart,
aktive/pausierte Titelwechsel, globale Änderungen, Timer-Verträglichkeit und
überholte Ladevorgänge. `TrackPlaybackSettingsViewTests` rendern MOD und feste
Formatmodelle, lange Titel, gesperrte Speicherung, DE/EN, Light/Dark und große
Schrift. Telefon- und Tablet-Aufnahmen einschließlich des Scrollendes visuell
prüfen; Bildaufnahmen belegen keine Bediengesten oder Geräte-Hintergrundwiedergabe.

Nativ auf dem Mac alle vier Overrides setzen und bei aktiven wie pausierten
Titelwechseln die Schnellregler gegenprüfen. Globale Vorgaben ändern, einen Titel
zurücksetzen und den unabhängigen zweiten Titel erhalten. Neustart, Archivquelle,
XM ohne PAL/NTSC, Wechsel bei offenem Titeldialog und laufenden Einschlaftimer
prüfen. Gleichnamige Quellen müssen im Dialog unterscheidbar bleiben.
Beschädigte Dateien müssen unverändert und Titelregler sichtbar gesperrt bleiben.
Beide Darstellungen und kleine Fenster prüfen; nach temporärer Installation
ursprüngliche App, vollständige Einstellungen und eigene Prozesse kontrollieren.


Prüfstand 1.6.46 (2026-10-18): macOS 597 Tests / zwei Skips / kein Fehler,
iOS 106 Tests ohne Skips oder Fehler und Linux 550 Tests / zehn Skips / kein
Fehler. Die Skips betreffen unveränderte lokale Referenz- und Hostgrenzen.
App-/Quick-Look-Build, verschachtelte Signaturen, Startargument-Smoke ohne
Fokusübernahme sowie Web-Build und Pattern-Bounds-Prüfung bestehen. 22 lokale
MOD-WAVs sind byteidentisch zur Ausgangsbasis.

Die native Mac-Abnahme umfasst alle vier Overrides, geänderte globale Vorgaben,
Rücksetzen eines einzelnen Titels, unabhängige gleichnamige Quellen, Neustart und
Archivmitglieder mit neuen internen Arbeitskopien. Ein offen gehaltener Dialog
bearbeitet nach automatischem Titelwechsel weiterhin seinen ursprünglichen Titel;
der Einschlaftimer zählt weiter. XM bietet keine PAL/NTSC-Auswahl. Eine beschädigte
Einstellungsdatei bleibt bytegleich und sperrt die Titelregler sichtbar.
Die Schnellregler zeigen tatsächliche Coordinatorwerte und ändern vorhandene
Overrides, während globale Vorgaben unverändert bleiben. Aktive und pausierte
Wechsel wenden die passenden Werte an. Die Hauptanzeige rundet die Separation
konsistent zum Titeldialog; gespeicherte 60 % werden als 60 % angezeigt.

Je zehn native Telefon-/Tablet-Aufnahmen und zwölf Mac-Aufnahmen sind visuell
geprüft: DE/EN, Light/Dark, lange Titel, große Schrift, Scrollende und feste
Aktionen; auf dem Mac zusätzlich 900 × 620, 1000 × 740 und 1200 × 900 Punkte.
Die mobilen Bilder belegen die Darstellung, keine Bediengesten oder physische
Hintergrund-/Sperrbildschirmwiedergabe. Ursprüngliche App samt Dateiidentität,
vollständige Einstellungen und Prozessfreiheit wurden nach der temporären
Mac-Abnahme unabhängig bestätigt.


## Performance-Abnahme und geteilte CI-Runner

Prüfstand 1.6.52, 2026-10-18: Die vollständige Release-Suite auf einem
kontrollierten Mac besteht mit 754 Tests, zwei Auslassungen und keinem Fehler;
Linux besteht mit 670 Tests, zehn umgebungsbedingten Auslassungen und keinem
Fehler. Die Performance-Grenzen sind in diesen Läufen aktiv.

Der Stresstest mit 64 Kanälen und 256 Stimmen misst den vorbereiteten
`ModulePCMSource`-Callback. Engine-Aufbau und WAV-Verpackung liegen außerhalb
der Messung; Framezahl und nicht stumme Ausgabe werden weiterhin gegen den
Offline-Pfad geprüft. Die strenge Grenze bleibt die Audiodauer von
1,960784 Sekunden bei 8 kHz. Gemessen wurden 0,63–0,69 Sekunden auf dem Mac
und 1,59–1,71 Sekunden auf dem kontrollierten Linux-Rechner. Geteilte
GitHub-Runner benötigen dagegen etwa 2,03 Sekunden und verfehlen dort die
Zeitgrenze. Diese Messung belegt keine Echtzeitfähigkeit unter beliebiger
CPU-Last oder auf jedem Rechner.

Die Einrichtung mit 20.000 Titeln benötigt auf dem kontrollierten Mac etwa
19 Sekunden; die längste Hauptthread-Pause bleibt unter 0,4 Sekunden.
GitHub-Runner benötigen in den bisherigen Läufen etwa 54–77 Sekunden bei
einer unveränderten Aufbaugrenze von 60 Sekunden. Ihre gemessenen
Hauptthread-Pausen bleiben unter der Zwei-Sekunden-Grenze. Die Aufbauzeit
wird direkt nach der Einrichtung erfasst und enthält keine spätere Prüfung
der gespeicherten Dateien.

Diese Abweichungen bleiben als offene CI-Einschränkung im Backlog. Weder
Grenzwerte noch Prüfungen werden für einen grünen Lauf abgeschaltet. Für eine
Release-Abnahme zählen die tatsächlich ausgeführten strengen Vollsuiten auf
kontrollierter Hardware; ein fehlgeschlagener CI-Zeitcheck wird zusätzlich
benannt. Neue funktionale Fehler bleiben Freigabeblocker.

# Linux-Port: Savage Mod Player

Stand: 2026-07-15 (Ausgangslage neu verifiziert) · Ziel: Repo läuft zusätzlich
unter Linux — zuerst als CLI-Player. Kein separates Repo: `SavageModPlayerCore`
ist der plattformübergreifende Teil, die macOS-App bleibt unverändert.

## Verhältnis zum vicious_sidplayer-Port

Der Plan vom 2026-07-05 wollte dem SID-Port folgen und dessen PCMSink-/ALSA-Code
kopieren. **Das ist überholt:** im SID-Repo liegt bis heute nur `plan.md`, kein
Portcode. Beide Ports laufen ab 2026-07-15 parallel — Daniel im SID-Repo, dieser
Plan hier. Damit entsteht die PCMSink-Abstraktion *hier zuerst* und ist die
Blaupause für den SID-Port, nicht umgekehrt. Bewusst Copy statt gemeinsames
Package; eine Extraktion erst nach Bewährung in beiden Repos.

## Ausgangslage (verifiziert 2026-07-15, Version 1.5.42)

Plattformneutral (nur Foundation): alle Parser inklusive XM, IT und
`ITSampleDecompressor`, dazu `DSPChannel`, `SequencerCore`, `ModuleModels`,
`PlaylistScanner`, `SongPositionScale`. Der XM-/IT-Zuwachs seit dem alten Plan hat
**keine** neue Plattformbindung eingeführt.

Plattformgebunden sind nur:

| Datei | Bindung | Umgang |
|---|---|---|
| `DSP/ModPlayerCoordinator.swift` | AVFoundation (28 Stellen) + Combine | aufteilen, siehe Phase 0 |
| `DSP/ModuleRenderer.swift` | AVFoundation (nur `AVAudioFormat`/`AVAudioPCMBuffer`) | Puffer ersetzen |
| `DSP/VisualizerState.swift` | Combine (`ObservableObject`) | guarden, nur App braucht es |
| 3 Testdateien | AVFoundation | entfällt mit neutralem Renderblock |

`Sources/SavageCLI/` existiert bereits (`savage-cli`, Foundation-only) und deckt
Datei laden, `--info`, `--pattern`, `--out`, `--seconds`, `--rate`, `--normalize`,
`--no-interp` und Exit-Codes ab. Phase 1 ist damit weitgehend erledigt; es fehlen
nur `--stdout` und `--list`. Der WAV-Container in `ModuleRenderer` wird bereits von
Hand geschrieben (RIFF + Int16) und ist portabel.

### Warum der alte Phase-0-Schritt nicht mehr funktioniert

Der alte Plan wollte `ModPlayerCoordinator.swift` **datei-weit** in
`#if canImport(AVFoundation)` hüllen. Das würde den Port unmöglich machen: die
Datei ist gemischt. Zeilen 8–186 enthalten plattformneutrale State-/Puffertypen
(`RealtimePlaybackState`, `RealtimeVUBuffer`, `RenderCapture`), und die statischen
Render-Helfer `createRenderBlock`, `makeRenderState`, `makeRenderChannels` liegen
bei 967–1350 — genau die, die `ModuleRenderer` und damit das CLI brauchen. Ein
Datei-Guard schaltete den Offline-Renderer auf Linux mit ab.

Der eigentliche Blocker ist die Signatur des gemeinsamen Renderblocks:

```
(UnsafeMutablePointer<ObjCBool>, UnsafePointer<AudioTimeStamp>, UInt32,
 UnsafeMutablePointer<AudioBufferList>) -> OSStatus
```

`ObjCBool`, `AudioTimeStamp`, `AudioBufferList` und `OSStatus` sind CoreAudio und
existieren unter Linux nicht. Die Verflechtung ist also tiefer als „nur WAV“.

**Der alte Ausweg ist verboten.** Der Plan bot an, den Linux-CLI-Renderpfad direkt
auf `DSPChannel`-Ebene neu zu bauen. Das erzeugte einen zweiten Renderpfad und
verletzt die AGENTS-Invariante, dass Live- und Offlinepfad nicht semantisch
auseinanderlaufen dürfen. Stattdessen: **eine** Engine, neutrale Blocksignatur,
CoreAudio nur noch im macOS-Adapter.

Günstig: `isSilence` und `timestamp` werden in **keinem** der beiden Blöcke
benutzt (`createPreviewRenderBlock` deklariert sie bereits als `_, _`). Der
neutrale Block braucht daher nur `(frameCount, left, right)`.

## Phasen

### Phase 0 — Core kompiliert und testet auf Linux (~1,5–2 PT)

Nicht 0,5 PT wie im alten Plan — der Datei-Split und die Blocksignatur sind echte
Arbeit an einem AGENTS-Hotspot.

- Neutralen Blocktyp einführen:
  `@Sendable (UInt32, UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>) -> Void`.
  Den CoreAudio-Adapter (`UnsafeMutableAudioBufferListPointer`, `noErr`) nur im
  macOS-`AVAudioSourceNode`-Pfad behalten.
- Neutralen Renderkern aus `ModPlayerCoordinator.swift` in eine neue Datei
  `DSP/RenderEngine.swift` lösen (`enum RenderEngine`): Render-Helfer,
  `renderChannelFrame`, `maxChannels`, `itVoiceCapacity`, neutrale State-Typen.
  `ModPlayerCoordinator` behält Live-Playback und wird geguarded.
- `ModuleRenderer`: `AVAudioFormat`/`AVAudioPCMBuffer` durch einen eigenen
  Float-Stereopuffer ersetzen. Der RIFF-Writer bleibt.
- `VisualizerState` (Combine) guarden; Aufrufer sind nur App und Coordinator.
- Testaufrufe von `ModPlayerCoordinator.*` auf `RenderEngine.*` umstellen — das ist
  semantisch ohnehin richtiger und macht die drei AVFoundation-Importe überflüssig.
- Im Echtzeit-Renderblock weiterhin **keine** Allokationen, Locks oder dynamischen
  Objective-C-Aufrufe.

**Erfolgskriterien:**
1. ✅ macOS bleibt bitgleich — `savage-cli`-WAVs über den lokalen MOD-Korpus
   byteidentisch zur Baseline vor dem Umbau. Das ist das Hauptgate; der Umbau
   fasst den heißesten Audiopfad an. *Erreicht 2026-07-15: 22 Module, 46,5 MB,
   Sammelhash `a004fb2cc52e1f41432511c6ad49288e7f57a1941ed2d8dd9c06652b7ac1f4a0`
   vor und nach dem Umbau identisch.*
2. ✅ `swift test` auf macOS unverändert grün. *Erreicht: 230 Tests, 2
   übersprungen, 0 Fehler — wie die Baseline. Zusätzlich `bash build_app.sh`
   grün inklusive Appex-Signatur.*
3. ✅ `swift build` + `swift test` grün im `swift:6.0`-Container. *Erreicht
   2026-07-15 auf dem Linux-Testrechner: **216 Tests, 0 Fehler, 2 übersprungen**. Die Differenz zu
   den 230 macOS-Tests sind exakt die 14 Testmethoden, die die AVAudioEngine-
   gebundene Live-Klasse instanziieren und deshalb geguardet sind.*
   *Erneut bestätigt 2026-08-15 für Version 1.6.7 nach der CodeQA-Kampagne
   (Swift 6.0.3, x86_64): `swift build -c release` und `swift test -c release`
   grün, **311 Tests, 0 Fehler, 7 übersprungen**. Die Differenz zu den 362
   macOS-Tests sind die AVFoundation-/Combine-gebundenen Suiten und der
   ZIP-Reader samt Tests, der hinter `canImport(Compression)` liegt; die 7
   Skips sind die Korpustests, weil `audio/` dort nicht existiert. Gezielt
   nachgewiesen: alle acht neuen Regressionstests der Kampagne laufen dort
   grün, darunter beide Slice-Tests und beide Archiv-Tiefentests.*

Der erste Linux-Lauf hat drei echte Fehler aufgedeckt, die auf macOS latent waren
— genau der Wert des Ports:

- `PlaylistScanner` rief `url.startAccessingSecurityScopedResource()`, eine reine
  Apple-Sandbox-API → jetzt hinter `#if canImport(Darwin)`.
- `MultiFormatTests` las die WAV-Chunk-Größe mit `load(as: UInt32.self)` aus
  einem `Data`-Slice, dessen Basis nicht 4-Byte-ausgerichtet sein muss. Darwin
  toleriert das, Linux bricht hart ab („misaligned raw pointer") → `loadUnaligned`.
- `extractArchive` lief komplett unter `#if os(macOS)` mit der Begründung, es gebe
  außerhalb kein `Process`/`bsdtar`. **Das war schlicht falsch:**
  swift-corelibs-foundation hat `Process`, und `bsdtar` liegt unter Linux an
  derselben Stelle. Der Guard prüft jetzt die tatsächliche Verfügbarkeit
  (`PlaylistScanner.bsdtarURL`) statt die Plattform — Archive werden damit auch
  unter Linux entpackt (im Container verifiziert). Fehlt bsdtar, überspringen die
  Tests sauber, statt rot zu melden.

Der `ObjCBool`-Verdacht aus der Vorab-Analyse war unbegründet: swift-corelibs-
foundation kennt den Typ, die Zeile kompiliert unverändert.

**Container-Anforderung (Stand 1.6.10):** `swift:6.0` bringt weder `bsdtar` noch
die ALSA-Header noch die zlib-Header mit. `zlib1g-dev` ist seit 1.6.10 nötig,
weil der eigene `ZipArchiveReader` dort `.zip` entpackt; `libarchive-tools` nur
noch für `.7z`. Der Satz unten stammt aus der Zeit davor:

**Container-Anforderung (bis 1.6.9):** `swift:6.0` bringt weder `bsdtar` noch die
ALSA-Header mit. Der Lauf braucht `apt-get install -y libasound2-dev
libarchive-tools`: ohne `libarchive-tools` überspringen zwei Archiv-Tests, ohne
`libasound2-dev` scheitert schon der Build, weil `SavageModPlayerCore` unter
Linux das Systemmodul `CALSA` einbindet. Beides steht so im CI-Job.

### Phase 1 — CLI vervollständigen (~0,25 PT)

- ✅ `--stdout`: PCM-s16le auf stdout (→ `aplay`), Metadaten weiterhin auf stderr.
  *Umgesetzt 2026-07-15; verifiziert: Ausgabe ist byteident zum WAV-Body ohne die
  44 Header-Bytes.*
- ✅ `--list`: Ordnerscan via `PlaylistScanner.isModFile`, ein Pfad je Zeile,
  Exit 1 wenn nichts gefunden. Bewusst ohne `collectEntries` — kein Entpacken,
  kein TempDir, `--list` schreibt nichts auf die Platte.
- Name bleibt `savage-cli` (nicht `savage-mod` wie im alten Plan) — das Target
  existiert und ist in Doku und Tests verankert.
- ✅ **Erfolgskriterium erreicht — aber in korrigierter Form.** Das alte
  Kriterium „`--out`-WAV byteident zwischen macOS- und Linux-Build" ist
  **prinzipiell unerfüllbar** und wurde ersetzt.

  Gemessen 2026-07-15 (identisches MOD, 12 s, Debug-Build beidseitig): Dateigröße
  gleich, **90 von 1.058.400 Samples (0,0085 %) weichen um exakt 1 LSB ab**, nie
  mehr. RMS-Fehler 0,0092 LSB — rund 115 dB unter dem Signal, also weit unterhalb
  jeder Hörschwelle und unterhalb des 16-Bit-Quantisierungsrauschens.

  Ursache belegt, nicht vermutet: `tanh` (Soft-Limiter im Renderblock) rundet in
  glibc und Darwin-libm unterschiedlich. Direkt gemessen mit identischem
  Swift-Code auf beiden Plattformen:

  | | `tanh(0.938268)` | Bitmuster |
  |---|---|---|
  | macOS/arm64 | `0.7344255` | `1060897615` |
  | Linux/x86_64 | `0.73442554` | `1060897616` |

  Beide Ergebnisse sind innerhalb 1 ULP korrekt — die Plattformen sind sich nur
  über das letzte Bit uneins. Byteidentität wäre nur über eine eigene
  tanh-Implementierung erreichbar; das würde den macOS-Klang (minimal) ändern,
  ohne hörbaren Gewinn, und ist deshalb **abgelehnt**.

  **Neues Kriterium:** gleiche Länge, maximale Sample-Abweichung ≤ 1 LSB,
  Fehler-RMS < 0,1 LSB. Für Regressionen innerhalb *einer* Plattform bleibt
  Byteidentität das Gate (macOS: erfüllt, siehe Phase 0).

### Phase 2 — Echtzeit-Playback (✅ Kern erledigt 2026-07-15)

Die Sink-Schicht **kam doch aus dem SID-Port** — Daniel hat sie am 2026-07-15
gebaut, damit war die ursprüngliche Reihenfolge des Plans (SID zuerst, savage
guckt ab) am Ende doch die richtige. Übernommen aus
`vicious_sidplayer/Sources/`, bewusst als Kopie:

- `Audio/PCMSink.swift` — Vertrag (Pull-Modell, interleaved Float, Sendable).
- `Audio/PCMSinkFactory.swift` — einzige Plattformweiche.
- `Audio/ALSAPCMSink.swift`, `Audio/AVAudioEnginePCMSink.swift`,
  `Audio/StdoutPCMSink.swift` — die drei Ausgaben.
- `Sources/CALSA/` — Systemmodul-Brücke zu libasound.

Der Code ist frei von Format-Wissen und ließ sich unverändert übernehmen; nur die
Kommentare zeigten auf SID-Interna und wurden auf den savage-Kontext umgeschrieben.
Eine Extraktion in ein gemeinsames Paket lohnt erst, wenn sich die Schicht in
beiden Repos bewährt hat — bis dahin: Änderungen hier und dort im Blick behalten.

Eigenanteil ist `Audio/ModulePCMSource.swift`: die Brücke vom `ModuleRenderBlock`
(getrennte L/R-Puffer, kein Endesignal) zum `PCMRenderBlock` (interleaved, Rückgabe
= gefüllte Frames). Voralloziierte Chunk-Puffer, damit der Audio-Thread nicht
alloziert; Songende über `endReachedFrame` als kurze Lieferung.

**Verifiziert:**

- `savage-cli --play` spielt auf macOS (AVAudioEngine) und Linux (ALSA).
- Linux-Laufzeit lautlos geprüft, ohne den Desktop des Testrechners zu beschallen: `.asoundrc`
  mit `pcm.!default { type null }` biegt `default` auf ALSAs null-Plugin um —
  echter `snd_pcm_open`/`writei`/`drain`-Pfad, Ergebnis `sourceFinished`, Exit 0.
- `ModulePCMSourceTests`: der Echtzeitpfad liefert **sample-identisch** dasselbe
  wie `ModuleRenderer` (Offline), trotz unterschiedlicher Blockgrößen (1024 vs.
  4096) — die „eine Engine"-Invariante ist damit testgedeckt, nicht nur behauptet.
  Zweiter Test: Songende kommt als kurze Lieferung an, sonst hinge der Sink.

**Dropout-Nachweis auf echter Hardware erbracht (2026-07-16).** Methode aus dem
SID-Port übernommen: statisches Binary (`swift build -c release
--static-swift-stdlib`, ~68 MB) im Container bauen, nativ auf dem Testhost gegen
eine temporäre PipeWire-Null-Senke spielen und per `parec` mitschneiden. Lautlos,
also ohne Störung des Desktops; die Senke wird danach wieder entladen.

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
MOD=$(pactl load-module module-null-sink sink_name=savage44 rate=44100 format=s16le channels=2)
parec -d savage44.monitor --file-format=wav --rate=44100 --channels=2 capture.wav &
PULSE_SINK=savage44 ./savage-cli-static test.mod --play
pactl unload-module $MOD          # aufräumen nicht vergessen
```

Ergebnis über 12 s eines realen 4-Kanal-MOD:

| Messung | Wert |
|---|---|
| Spitzenpegel | 15960/32767 (−6,2 dBFS) |
| Nicht-Null-Samples | 100 % |
| längste Null-Strecke | 1 Frame (0,02 ms) — im Offline-Render sind es 10 |
| RMS Kette / Offline | Faktor 1,0000 (0,00 dB) |
| Korrelation zum Offline-Render | **0,9994** bei 6 Frames Versatz |

**Keine Aussetzer**: die längste Stille in der Kette ist kürzer als die im
Offline-Render selbst. Die Kette ist pegelrichtig (RMS-Faktor exakt 1,0) und
spielt dasselbe Signal.

Falle für den nächsten Durchlauf: Der Mitschnitt ist gegen den Offline-Render
**nur mit Versatz in beide Richtungen** vergleichbar. Der Song beginnt leise, eine
Startsuche per Schwellwert überspringt die ersten Frames, und ein einseitiger
Suchbereich liefert dann ~0,77 statt 0,9994 — das sieht nach einem kaputten
Audiopfad aus, ist aber bloß eine schlechte Ausrichtung. Restliche
Sample-Differenzen (Mittel ~54 LSB) stammen aus dem Subsample-Timing der Kette,
nicht aus dem Replayer; sample-genaue Gleichheit deckt `ModulePCMSourceTests` ab.

**Tastatursteuerung und Playlist ergänzt (2026-08-23, Version 1.6.10) — Phase 2
ist damit abgeschlossen.**

- `savage-cli --list <ordner> --play` spielt den Ordner als Playlist, in
  Pfadreihenfolge. Ein unlesbares oder kaputtes Modul wird gemeldet und
  übersprungen; bleibt kein spielbares übrig, endet der Prozess mit 1.
- An einem Terminal steuern Leertaste/`p` (Pause), `n` und Pfeil rechts
  (nächster), `b` und Pfeil links (vorheriger) sowie `q` (Ende). Ohne Terminal
  läuft die Wiedergabe wie bisher durch — `isatty` entscheidet, nicht ein Flag.
- Einzeltitel und Playlist laufen durch denselben Code (`PlaylistPlayback.swift`);
  eine Playlist ist nur eine Liste mit mehr als einem Eintrag. Kein zweiter
  Wiedergabepfad, der auseinanderlaufen könnte.
- Nebenbefund und mitbehoben: **`--play` verschluckte SIGINT.** Mit dem Stand
  davor beendete `kill -INT` einen `--stdout`-Lauf sofort, während `--play` die
  ganze Playlist zu Ende spielte — die Meldung „Ctrl-C beendet" stimmte also
  nicht. Ein eigener Handler setzt jetzt nur ein Flag; die Wiedergabeschleife
  schließt die Audio-Ausgabe und endet mit dem üblichen Exit-Code 130.
- Beleg: `python3 Tests/cli_playback_tests.py` — acht Tests über ein
  Pseudoterminal (`pty`) mit einem synthetischen, klanglosen Modul. Ohne
  nutzbare Audio-Ausgabe überspringt sich die Suite sauber.

**ZIP-Leser auch unter Linux belegt (2026-08-23, Version 1.6.10).** `.zip`
entpackt dort jetzt der eigene `ZipArchiveReader` über die zlib statt über
`bsdtar`; `libarchive-tools` braucht nur noch `.7z`.

| Container | Ergebnis |
|---|---|
| nur `libasound2-dev` + `zlib1g-dev` | **387 Tests, 25 übersprungen, 0 Fehler**; `ZipArchiveReaderTests` läuft mit allen 38 Tests |
| zusätzlich `libarchive-tools` | **387 Tests, 7 übersprungen, 0 Fehler** |

Die 18 zusätzlichen Skips ohne `bsdtar` sind genau die `.7z`- und
Importtests, die das Werkzeug brauchen. Vor 1.6.10 lief die ZIP-Suite unter
Linux **gar nicht** (sie hing an `canImport(Compression)`) und meldete trotzdem
grün — der Testzähler stieg deshalb von 348 auf 387.

Zwei Fallen dabei, beide erst im Container aufgefallen:

- `autoreleasepool` gibt es nur auf Apple-Plattformen. Mit dem Umstieg wird der
  Stored-Kopierpfad des Lesers auch unter Linux übersetzt und der Bau brach ab.
- Die Testdatei hing noch am alten `canImport(Compression)`-Guard. Der Lauf
  führte 0 von 38 Tests aus und meldete trotzdem grün — ein Skip, der wie ein
  Erfolg aussieht.

**Linux-Lauf für 1.6.10 belegt (2026-08-23, Swift 6.0.3 im `swift:6.0`-Container).**

| Prüfung | Ergebnis |
|---|---|
| `swift build -c release` | grün |
| `swift test -c release` | **345 Tests, 7 übersprungen, 0 Fehler** |
| `python3 Tests/cli_contract_tests.py` | 10 Tests grün |
| `python3 Tests/cli_playback_tests.py` am ALSA-Nullgerät | 4 grün, 4 übersprungen |
| `python3 Tests/cli_playback_tests.py` an einer PipeWire-Null-Senke | **8 von 8 grün** |

Falle, die dabei auffiel: **Ein ALSA-Nullgerät (`pcm.!default { type null }`)
taugt nicht für die Tastensteuerung.** Es verschluckt die Samples so schnell,
wie der Renderer sie liefert — drei Titel sind in 0,1 s vorbei, lange bevor ein
Tastendruck ankommt. Zwei Tests fielen deshalb um, ohne dass etwas kaputt war.
Die Suite misst jetzt im Probelauf die Laufzeit und überspringt die vier
zeitabhängigen Tests, wenn die Ausgabe nicht im Echtzeittakt läuft.

Für den vollen Beleg dieselbe Methode wie beim Dropout-Nachweis: statisches
Binary im Container bauen, nativ gegen eine temporäre PipeWire-Null-Senke
laufen lassen — echtzeitgetaktet und trotzdem lautlos.

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
SINK=$(pactl load-module module-null-sink sink_name=savagekeys rate=44100 format=s16le channels=2)
PULSE_SINK=savagekeys python3 Tests/cli_playback_tests.py -v
pactl unload-module $SINK          # aufräumen nicht vergessen
```

### Phase 3 — Desktop-Integration (teilweise erledigt 2026-08-23, 1.6.10)

**Erledigt und auf dem Fleet-Linux-Host belegt:**

- `linux/savage-cli.desktop` meldet den Player für MOD, S3M, XM und IT an.
  `desktop-file-validate` sagt gültig; `Tests/desktop_entry_tests.py` hält
  Aufruf, Terminal-Pflicht und Typliste fest.
- `linux/install.sh` installiert ohne root nach `~/.local` (Präfix wählbar),
  `--uninstall` räumt auf. Geprüft in einem Wegwerf-Präfix: Binary und Eintrag
  landen richtig, `update-desktop-database` schreibt savage-cli in die
  `mimeinfo.cache`, und nach dem Deinstallieren steht es dort nicht mehr.
- `linux/build-static.sh` baut ein statisch gelinktes `savage-cli` im Container
  (69 MB), das ohne Swift-Laufzeit auf dem Zielrechner startet — im Präfix
  ausgeführt und mit `--help` belegt.

**Ergänzungen und Grenzen:**

- **AppImage ist seit 1.6.27 verfügbar.** `linux/build-appimage.sh` verpackt
  das statische CLI für Linux x86_64, mit per SHA-256 festem appimagetool 1.9.1
  und eingebetteter Runtime. Zielsystem bleibt ein Desktop mit ALSA/D-Bus.
- **MPRIS2 ist seit 1.6.26 umgesetzt.** Linux-CLI-Anbindung über libdbus-1;
  Play/Pause, Stop/Neustart, pausierter Titelwechsel, Statussignale, Fehler und
  mehrere Instanzen sind auf einem echten Desktopbus geprüft.
  `Tests/mpris_contract_tests.py` nutzt lautlose synthetische Module.
- Ein natives Linux-GUI bleibt ausgeschlossen.

## Rahmenbedingungen

- **Linux-Verifikation läuft** (seit 2026-07-15 freigeschaltet). Auf dem
  macOS-Entwicklungsrechner gibt
  es weder Docker noch Podman noch ein Linux-SDK; verifiziert wird auf dem
  Fleet-Linux-Host im `swift:6.0`-Container:

  ```bash
  # Der Host traegt das Bare-Repo der Fleet — dort genuegt ein lokaler Klon
  # des gepushten Stands, dann laeuft genau der geprueft, was gepusht wurde.
  ssh <host> 'git clone -q --branch main ~/git/savage_modplayer.git ~/savage-linux-check/repo && \
    cd ~/savage-linux-check/repo && \
    docker run --rm -v "$PWD":/src -w /src swift:6.0 bash -c \
    "apt-get update -qq && apt-get install -y -qq libasound2-dev libdbus-1-dev zlib1g-dev libarchive-tools; \
     swift build -c release && swift test -c release"'
  ```

  Der Container laeuft als root und hinterlaesst ein root-eigenes `.build`, das
  der naechste Lauf als normaler Nutzer nicht loeschen kann. Das Arbeitsverzeichnis
  deshalb ebenfalls per Container aufraeumen (`docker run --rm -v "$HOME":/h
  alpine rm -rf /h/savage-linux-check`).

  Der Host ist zugleich Backup-Host — Testlast moderat halten (ein Build/Testlauf
  am Stück, keine Dauerschleifen). Host-Details und die Etikette für GUI-/Audio-
  Zugriffe stehen in der privaten Fleet-Doku, nicht hier.
- CI: Ubuntu-Job in `.github/workflows/ci.yml`, erst wenn lokal grün. Push von
  `.github/workflows/*` nach GitHub nur auf Auftrag.
- README.md/README.de.md: Linux-Abschnitt nach Phase 1; RELEASE_NOTES pflegen,
  `VERSION`-Bump pro Phase.
- Chirurgisch: App-, Quick-Look- und JS/HTML5-Code nicht anfassen.
- `ModPlayerCoordinator.swift` ist ein AGENTS-Hotspot — nur ein Writer.

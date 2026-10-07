# Gezielte Audio-Gegenproben vom 2026-10-07

Ausgangsstand: `75afaf4`, Version 1.6.22. Korrekturen: Versionen 1.6.23 bis 1.6.25.

## Ende der macOS-CLI-Wiedergabe

Ein deterministischer PCM-Test lieferte ausschließlich Nullsamples und endete
mit einem Teilpuffer. Zehn Läufe mit 4.801 bis 4.991 Frames bei 48.000 und
44.100 Hz meldeten `sourceFinished` 14,19 bis 19,60 ms vor dem HAL-Zeitpunkt
am Ende des letzten gültigen Frames. Der CLI gab daraufhin den Sink frei und
konnte die noch ausstehende Ausgabe abschneiden. Die Messung belegt die
vorzeitige Freigabe; sie ist keine akustische Aufnahme des Lautsprechers.

`AVAudioEnginePCMSink` veröffentlicht nun den Zeitstempel am Ende des letzten
Teilpuffers zusammen mit dem Quellenende. Der wartende Kontrollthread wartet
zusätzlich die Pipeline-/Gerätelatenz ab; ein ausdrücklicher Stop weckt ihn.
Der Audiocallback allokiert dafür keinen Speicher und nimmt keinen Lock.
Die Rendererberechnung und die Klangvoreinstellungen ändern sich nicht.

Der neue Regressionstest scheitert am Ausgangscode: Die Rückkehr erfolgte nach
0,12 ms statt frühestens nach der gültigen Pufferdauer von 10,66 ms. Mit der
Korrektur besteht er. Ein weiterer Test prüft, dass Stop alle Warter freigibt.

Ausgeführte Prüfungen:

- macOS: vollständige Swift-Suite, 461 Tests, 2 Fixture-Skips, 0 Fehler;
  die beiden neuen Hardwaretests liefen ohne Skip.
- Linux, Swift 6.0.3: Release-CLI-Build und vollständige Release-Suite,
  437 Tests, 7 Skips, 0 Fehler. Die Apple-Ausgabeschicht ist dort ausgeschlossen.
- macOS-Release-CLI-Build, 13 Vertragstests und 8 Wiedergabetests bestanden.
- 22 lokale MOD-Dateien mit je acht Sekunden WAV-Ausgabe sind byteidentisch
  zur Baseline von Version 1.6.22.
- App und Quick-Look-Extension gebaut, Signaturen gültig.
- HTML neu erzeugt; der Diff enthält ausschließlich die Produktversion.
  JavaScript-Pattern-Bounds und `git diff --check` bestanden.

Es wurde kein akustischer Lautsprecher- oder Bluetooth-Tail aufgezeichnet.
Die Timingmessung belegt den korrigierten Lebenszyklus des Sinks. Die
verwandte Ausgabeschicht im SID-Player wurde gelesen; beim späteren Vergleich unterschieden sich Drain- und Lebenszyklusstrategie.
Die [getrennte Untersuchung](2026-10-07-audio-ideas.md) hält die Grenzen fest.


## Erste Initialisierung der ProTracker-Sinustabelle

Ein synthetisches, lautloses MOD beginnt auf Zeile 0 mit Vibrato `447` und
einem geloopten Nullsample. Ein Breakpoint auf die einmalige Initialisierung
von `DSPChannel.ptSineTable` trifft im unveränderten Debug-Build auf
`com.apple.audio.IOThread.client`, aus `DSPChannel.performTick` über
`SequencerCore`, `RenderEngine` und `ModulePCMSource`. Der Initialisierer ruft
`_allocateUninitializedArray` für 32 Float-Werte auf. Damit ist die
Speicherallokation im Echtzeitcallback für diese Buildkonfiguration bestätigt.
Ein hörbarer Aussetzer wurde nicht behauptet oder gemessen.

Die Release-Konfiguration optimiert diesen Zugriff bereits zu direkten
Lesezugriffen auf konstante Daten; dort existiert kein separater Initialisierer
für diese Tabelle. Der Debug-Befund wird daher nicht als Release-Klangfehler
verallgemeinert.

Seit 1.6.24 übernimmt jeder Kanal die unveränderliche, gemeinsam gespeicherte
Tabelle in seinem Konstruktor. Vibrato und Tremolo verwenden diese vorbereitete
Referenz. Der entsprechende Kaltstart-Breakpoint trifft danach auf dem
Hauptthread in `DSPChannel.init`, vor dem Start der Audioausgabe.
Tabellenwerte, Effekttiming und Klangvoreinstellungen bleiben gleich.

Ausgeführte Prüfungen für 1.6.24:

- Kaltstart im Debugger vor/nach der Änderung: Audio-IO-Thread → Hauptthread;
  der korrigierte CLI-Lauf endet anschließend regulär mit Exit-Code 0.
- 80 gezielte DSP-/Sequencer-/IT-Sounddetailtests, 0 Fehler.
- Vollständige macOS-Suite: 461 Tests, 2 Fixture-Skips, 0 Fehler.
- Release-CLI und App-/Quick-Look-Build einschließlich Signaturen bestanden.
- 22 MOD-WAVs mit je acht Sekunden sowie ein synthetisches, nichtstummes
  Vibrato-WAV sind byteidentisch zum jeweiligen Ausgangsstand.
- JavaScript-Worklet-Timing und Pattern-Bounds bestanden; HTML-Diff nur Version;
  `git diff --check` ohne Befund.

Es wurde kein subjektiver Hörvergleich als Beleg verwendet. Die lokale
Realweltprüfung enthält MODs; IT-/XM-/S3M-Korpusdateien lagen nicht vor.


## IT-Pingpong mit Originalreferenz

Referenz ist das historische [IT-2.14-Patch-3-Archiv](https://files.scene.org/view/resources/music/trackers/it214v3.zip)
(SHA-256 `ad1bf9dcc7db3d74f15e5d8576becd2dadaf0fbdefc8c9057d71f56416ce43de`).
`IT.EXE` und der enthaltene Mono-WAV-Treiber `ITWAV.DRV` liefen in DOSBox 0.74-3
mit `IT /s20 /m44100`; F9 lädt das Fixture, F5 rendert es nach WAV.
Der [Originalquellcode des Autors](https://github.com/jthlim/impulse-tracker/tree/58c44e48dfdf479b186db17df0f2fa494b8c9aa9)
belegt in `SoundDrivers/MIXWAV.INC`, `MixPingPongLoop`, die getrennte Reflexion
von Ganzzahlposition und 16-Bit-Bruchteil sowie die asymmetrischen Grenzen.
Die erhaltene historische Binärdatei wurde verwendet, kein moderner IT-Nachbau.

Das synthetische IT hat ein signiertes 8-Bit-Sample
`[0, 24, 48, 72, 96, 120, 0, -80]`, Loop `[1, 6)`, Pingpong-Flag, eine C-5-Note,
lineares Pitch-Flag, Tempo 125 und Speed 6. Der lineare Modus isoliert die
Loop-Grenzen von Rundungsfehlern der Amiga-Perioden. C5Speed 44.100 beziehungsweise 22.050 ergibt bei
44.100 Hz Schritte 1 beziehungsweise 0,5. Nach dem Einschwingen wiederholt
sich die Originalaufnahme nach 9 beziehungsweise 16 Ausgabeframes. Savage
1.6.24 brauchte 10 beziehungsweise 20 Frames. Die Änderung in 1.6.25 folgt
der belegten Originalkonvention ausschließlich für IT-Voices.

Original IT und Savage verwenden verschiedene Interpolatoren, Pegel und
Ausgabekennlinien. Vollständige Samplegleichheit wäre deshalb kein angemessenes
Kriterium. Verglichen wurden die exakte Wiederholungsperiode sowie die
Samplefolge bei ganzzahligen Phasen; ein neuer hardwarefreier Regressionstest
hält beide Folgen fest. Er scheitert am alten Renderer in beiden Fällen.
Die historische Bruchteilbehandlung wird ausdrücklich erhalten; sie entspricht
keiner kontinuierlichen geometrischen Dreiecksfaltung.

Gemessene Wiederholungsperioden der finalen linearen Fixtures:

| Sampleschritt | Original IT | Savage 1.6.24 | Savage 1.6.25 |
| --- | ---: | ---: | ---: |
| 1 | 9 Frames | 10 Frames | 9 Frames |
| 0,5 | 16 Frames | 20 Frames | 16 Frames |

Die ursprünglichen Versuche mit Amiga-Perioden sind kein exakter Halb-Schritt-
Vergleich: Savages Float-Perioden runden die Frequenz leicht. Darum nutzt
der abschließende Vergleich den linearen Modus; die Tonhöhenberechnung wurde
nicht geändert. Eine allgemeine Samplegleichheit zu IT wird nicht behauptet.

Ausgeführte Prüfungen für 1.6.25:

- Zwei Original-IT-WAVs und native Vorher-/Nachher-WAVs, Perioden und
  Samplefolgen numerisch geprüft; Regression am alten Code in beiden Fällen rot.
- macOS: 462 Swift-Tests, 2 Fixture-Skips, 0 Fehler.
- Linux: Release-CLI-Build, 438 Release-Tests, 7 Skips, 0 Fehler.
- CLI: 13 Vertragstests und 8 Wiedergabetests bestanden.
- App und Quick-Look-Extension gebaut, Signaturen gültig.
- 22 lokale MOD-WAVs mit je acht Sekunden byteidentisch zur Baseline 1.6.22.
- JavaScript-Timing und Pattern-Bounds bestanden; HTML-Diff nur Version;
  `git diff --check` ohne Befund. Keine lokalen IT-/XM-/S3M-Korpora verfügbar.

# Aktiver Projekt-Backlog

Stand: 2026-07-26 · Version 1.6.0.

Diese Datei ist die einzige aktive Projektliste. Erledigte Chronik liegt in
Release Notes, abgeschlossenen Tasks und `archive/`.

## Priorisiert

0. **Gerätetest der iPhone-App.** Der einzige noch offene Punkt aus dem
   iOS-Vorhaben, und der einzige, der sich nicht headless erledigen lässt.
   `bash ios/scripts/build-device.sh --install`, danach die Prüfliste in
   [docs/testing.md](../docs/testing.md) unter „Gerätetest" abarbeiten:
   Sperrbildschirm-Steuerung, AirPods, eingehender Anruf, Kopfhörer abziehen,
   Speicherverhalten beim Import eines großen Archivs, Dauerlauf mit einem
   anspruchsvollen IT-Modul. Bis dahin gilt keiner dieser Punkte als verifiziert.
   Fällt dabei der IO-Puffer auf: Startwert sind 10 ms in
   `AudioSessionController`, der Ist-Wert ist über `ioBufferDuration` auslesbar.
1. **GUI-Smoke für Dateiargument untersuchen.** Ein früherer Lauf mit
   `open --args <mod>` zeigte kein Hauptfenster, während der Autoplay-Ordnerpfad
   funktionierte. Mit einer rechtlich unbedenklichen lokalen Datei reproduzieren,
   App-Lifecycle und Argumentdispatch trennen, headless Tests ergänzen und danach
   einen freigegebenen GUI-Smoke durchführen. *Hinweis: intern
   `knowledge/swiftui-cli-args-fenster.md` beschreibt exakt dieses Symptom
   (AppKit deutet unbekannte positionale Argumente als Datei-Öffnen) — vor der
   Analyse lesen, das könnte die Ursache schon nennen.*
2. **Linux-Port Phase 2 abschließen.** Echtzeit-Wiedergabe läuft
   (`savage-cli --play`, ALSA); es fehlen Tastatursteuerung (Pause, nächster
   Titel, Quit) und Playlist-Wiedergabe über `--list`. Details:
   [Linux-Plan](2026-07-05-linux-port/plan.md).

## Optionaler Feinschliff

- **Visualizer-Bildrate als Opt-in-Einstellung.** Default bleibt 30 Hz und damit
  volle Optik. Optionen etwa 30/24/15/10 Hz speisen den Full-Mode-
  `vuUpdateInterval`; CPU-Gewinn auf demselben Host/Modul vor und nach der
  Änderung messen. Compact bleibt 5 Hz.
- **Full-Mode-`@Published`-Churn:** Erst messen, dann gegebenenfalls Uhr und
  Visualizer-Datenpfad trennen. Ziel 2–4 % Gewinn ohne reduzierte 30-Hz-Optik;
  keine spekulative Audio-DSP-Optimierung, weil diese nur etwa 3–4 % ausmachte.
- **Seltene XM-Semantik:** Pxy-Effekt-Memory ergänzen; lineare/Amiga-XM und die
  bestehenden Effect-Memory-Regeln dürfen dabei nicht regressieren.
- **Audioqualität:** optionale Anti-Click-Hüllkurve und JavaScript-
  Sampleinterpolation nur mit hörbarem A/B-, Timing- und Swift-Paritätsnachweis.
- **PCMSink-Extraktion:** Die Ausgabeschicht liegt als bewusste Kopie in
  savage_modplayer und vicious_sidplayer. Erst wenn sie sich in beiden bewährt
  hat, lohnt ein gemeinsames Paket — bis dahin Änderungen beidseitig abgleichen.
- **Linux-GUI / Phase 3:** MPRIS2, `.desktop`-Datei, statisches Binary/AppImage.
  Ein natives Linux-GUI ist ausdrücklich kein Ziel.
- **ZIP-Reader auch auf macOS und Linux nutzen.** Der eigene
  `ZipArchiveReader` läuft heute nur auf iOS; macOS und Linux entpacken weiter
  über `bsdtar`. Ein Umstieg würde die externe Abhängigkeit loswerden und den
  Vorfilter auch dort wirksam machen, kostet aber `.7z`-Unterstützung — deshalb
  nur mit einer bewussten Entscheidung dazu, was mit `.7z` passiert.
- **`.7z` auf iOS.** Aktuell nicht unterstützt und als solches gemeldet. Nur
  angehen, wenn im realen Bestand tatsächlich `.7z` auftaucht; ein eigener
  LZMA-Dekoder ist ein spürbarer Brocken.
- **Zip64.** Der ZIP-Reader lehnt Zip64-Archive mit klarer Meldung ab, statt
  falsche Offsets zu lesen. Erst umsetzen, wenn ein Archiv über 4 GB oder mit
  mehr als 65535 Einträgen real auftritt.
- **iPad-Layout.** Das Projekt baut universal (`TARGETED_DEVICE_FAMILY = 1,2`),
  die Oberfläche ist aber fürs iPhone-Hochformat entworfen. Ein eigenes
  iPad-Layout ist offen, aber kein Versprechen.

## Nicht offen

Compact-Header/Layout, UI-Plan 1–10, IT M0–M10, Capability-Härtung sowie
Linux-Port Phase 0 und 1 (Core + CLI bauen, testen und spielen unter Linux) sind
abgeschlossen. Die iOS-App aus
[2026-07-26-ios-app/plan.md](2026-07-26-ios-app/plan.md) ist gebaut (Phasen 0–7);
offen bleibt daraus nur der Gerätetest oben. WAV-Export auf iOS ist eine
bewusste Auslassung und kein offener Punkt. Der Ubuntu-CI-Job baut und testet Core/CLI mit ALSA- und
Archiv-Abhängigkeiten; XM unterstützt lineare und Amiga-Perioden gemäß Headerflag.
Auch der Dropout-Nachweis auf echter Audiohardware ist erbracht
(2026-07-16, `parec` über eine PipeWire-Null-Senke: keine Aussetzer, RMS-Faktor
1,0000, Korrelation 0,9994 zum Offline-Render — Details im Linux-Plan). Historische Start-/Branch-Anweisungen im IT-Task sind superseded
und kein Auftrag für eine neue Session.

# Aktiver Projekt-Backlog

Stand: 2026-07-16 · Basis: `main@abcf536`, Version 1.5.45.

Diese Datei ist die einzige aktive Projektliste. Erledigte Chronik liegt in
Release Notes, abgeschlossenen Tasks und `archive/`.

## Priorisiert

1. **Release Notes konsolidieren — Entscheidung offen.** `RELEASE_NOTES.md`/`.de.md`
   beschreiben noch 1.5.29, während Tags bis v1.5.45 existieren. Sie sind der Text
   des nächsten GitHub-Releases, also eine Veröffentlichungsentscheidung: Was aus
   1.5.30–1.5.45 gehört hinein? Ohne Daniels Vorgabe nicht anfassen.
2. **GUI-Smoke für Dateiargument untersuchen.** Ein früherer Lauf mit
   `open --args <mod>` zeigte kein Hauptfenster, während der Autoplay-Ordnerpfad
   funktionierte. Mit einer rechtlich unbedenklichen lokalen Datei reproduzieren,
   App-Lifecycle und Argumentdispatch trennen, headless Tests ergänzen und danach
   einen freigegebenen GUI-Smoke durchführen. *Hinweis: intern
   `knowledge/swiftui-cli-args-fenster.md` beschreibt exakt dieses Symptom
   (AppKit deutet unbekannte positionale Argumente als Datei-Öffnen) — vor der
   Analyse lesen, das könnte die Ursache schon nennen.*
3. **Linux-Port Phase 2 abschließen.** Echtzeit-Wiedergabe läuft
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
- **Ubuntu-Job in `.github/workflows/ci.yml`.** Baut und testet den Core unter
  Linux. Braucht `libasound2-dev` und `libarchive-tools` im Job, sonst fehlen
  ALSA und der Archiv-Test. Push von `.github/workflows/*` nach GitHub braucht
  `gh auth refresh -s workflow` und einen konkreten Auftrag.
- **Seltene XM-Semantik:** echte Amiga-Periodentabelle für XM mit `flags bit0=0`
  und Pxy-Effekt-Memory. Mit synthetischen Tests plus lokalem XM-Korpus absichern;
  lineare XM und bestehende Effect-Memory-Regeln dürfen nicht regressieren.
- **Audioqualität:** optionale Anti-Click-Hüllkurve und JavaScript-
  Sampleinterpolation nur mit hörbarem A/B-, Timing- und Swift-Paritätsnachweis.
- **PCMSink-Extraktion:** Die Ausgabeschicht liegt als bewusste Kopie in
  savage_modplayer und vicious_sidplayer. Erst wenn sie sich in beiden bewährt
  hat, lohnt ein gemeinsames Paket — bis dahin Änderungen beidseitig abgleichen.
- **Linux-GUI / Phase 3:** MPRIS2, `.desktop`-Datei, statisches Binary/AppImage.
  Ein natives Linux-GUI ist ausdrücklich kein Ziel.

## Nicht offen

Compact-Header/Layout, UI-Plan 1–10, IT M0–M10, Capability-Härtung sowie
Linux-Port Phase 0 und 1 (Core + CLI bauen, testen und spielen unter Linux) sind
abgeschlossen. Auch der Dropout-Nachweis auf echter Audiohardware ist erbracht
(2026-07-16, `parec` über eine PipeWire-Null-Senke: keine Aussetzer, RMS-Faktor
1,0000, Korrelation 0,9994 zum Offline-Render — Details im Linux-Plan). Historische Start-/Branch-Anweisungen im IT-Task sind superseded
und kein Auftrag für eine neue Session.

# Review-Korrekturen 1.6.30

Prüfdatum: 2026-10-10. Ausgangsstand: `8cc3308eef681a74d615668e1adf8fcd81ee8e2d`.

## Triage und Entscheidungen

| Fund | Entscheidung und Umsetzung |
|---|---|
| P2: überlappender Web-Audiograph | Bestätigt und behoben. Eine eigene Graphrevision entwertet den Aufbau nach `unload()`. Nach beiden asynchronen Grenzen wird die Revision geprüft; veraltete Aufbauten erzeugen keinen Node. Nur das noch aktuelle Setup-Promise darf sich löschen. Worklet und Gain werden beim Entladen getrennt. |
| P2: Datei-Auftrag nach Transportaktion im Notenfenster | Bestätigt und behoben. `PlaybackActions` hält die gemeinsame Datei-Auftrags-ID auf App-Ebene. Haupt- und Notenfenster rufen dieselben synchronen Play/Pause-/Stop-Aktionen auf. Die Entwertung erfolgt vor der Coordinator-Aktion und braucht keinen Benachrichtigungsempfänger im Hauptfenster. |
| P2: AppImage fehlt beim Release | Bestätigt und behoben. Das Publish-Skript verwendet wie Builder und Dokumentation `build/Savage-Mod-Player-<Version>-x86_64.AppImage` einschließlich der SHA-256-Datei. |
| P3: zweiter ALSA-Selbst-Stop-Zweig | Bestätigt und entfernt. Die frühe Prüfung übernimmt bereits jeden Selbst-Stop vor dem Lifecycle-Lock; der Kommentar beschreibt diesen Pfad. |
| P3: unnötige Vorschau-Neuberechnung | Für Stereo-/Interpolationsänderungen bestätigt und behoben. Der Audiothread veröffentlicht ein Vorschau-Optionskommando nur bei geänderter PAL-/NTSC-Taktrate. Dadurch bleiben Vorschau und Kommandoring bei wiederholten reinen Klangoptionen unverändert. Der zusätzlich vorgeschlagene allgemeine DSP-Checkpoint wurde als weitergehendes Refactoring verworfen: Ein konsistentes Duplikat müsste auch Samplepositionen, Effekt-Memory, Hüllkurven und IT-Voice-Verknüpfungen erfassen. Die belegte unnötige Arbeit lässt sich ohne diesen Eingriff beseitigen. Echte Tempo-, Seek- und Taktänderungen dürfen weiterhin aus der Historie neu simulieren; deren Aufwand wächst weiterhin mit der Laufzeit. |

## Prüfungen

- `swift test --filter NotePreviewTests`: 11 Tests bestanden. Die neue Regression
  verändert Stereo/Interpolation 100-mal bei einer Ringkapazität von zwei
  Kommandos: kein Vorschaukommando und kein Überlauf; eine echte Taktänderung
  liefert genau ein Kommando am richtigen Audioframe. Bestehende Tempo-/Seek-
  und IT-NNA-Prüfungen bleiben erfolgreich.
- Vollständiges `swift test`: 476 Tests, zwei Skips, keine Fehler. Die Skips
  betreffen fehlende lokale IT-Referenzen.
- Linux: Release-Build und vollständiges `swift test -c release` mit Swift 6.0
  bestanden; 450 Tests, neun Skips, keine Fehler. Skips: zwei fehlende lokale
  IT-Referenzen, sechs unter root nicht prüfbare Dateirechte und ein Test ohne
  nutzbare Audioausgabe. Der Lauf belegt daher keine ALSA-Hardwarewiedergabe.
- `node Tests/js/playback-state.mjs`: beide Abschlussreihenfolgen überlappender
  URL-Ladevorgänge bestanden. Der alte Start wird abgelehnt, nur ein Node
  entsteht, das neue Setup-Promise bleibt erhalten und Stop erreicht den
  gestarteten Node.
- `python3 Tests/drop_request_tests.py`: verzögerter Provider nach Stop/Pause
  über die konkreten Aktionen beider Fenster abgewiesen; neuere Auswahl und
  durchgehende Auftragsidentität bestanden. Der Test führt die unveränderten
  Aktions- und Drop-Funktionen mit einem hardwarefreien Coordinator-Ersatz aus;
  er ist kein nativer Klicktest.
- `python3 Tests/publish_contract_tests.py`: sechs Tests bestanden, darunter
  Upload von AppImage/Prüfsumme am Builder-Standardpfad und Abbruch vor jedem
  Push bei fehlender Prüfsumme. Git-/GitHub-Aufrufe sind kontrollierte Ersatzobjekte.
- `python3 build.py`, `node Tests/js/pattern-bounds.mjs`,
  `node Tests/js/worklet-timing.mjs`, `python3 Tests/ui_source_tests.py` und
  `git diff --check` bestanden. Der HTML-Diff enthält die Graphkorrektur und
  die neue Versionsnummer.
- Fokusfreier WebKit-Smoke mit echter AudioWorklet-Laufzeit: Drop-Autoplay
  erreicht `PLAYING`; Stop setzt `playerPlaying=false`. Screenshot geprüft.
  Die deterministische Überlappung des Graphaufbaus prüft die Node-Suite.

- `bash build_app.sh`: Release-App und Quick-Look-Extension gebaut und
  Signaturen erfolgreich geprüft. Keine Installation oder Notarisierung.
- `bash Tests/launch_argument_smoke.sh`: alle sechs Startfälle bestanden,
  einschließlich Datei, Ordner, unbekanntem Argument, Autoplay und LaunchServices.
  Der Lauf blieb im Hintergrund und stellte die Voreinstellungen wieder her.
- `swift build -c release --product savage-cli`, 14 CLI-Vertragsprüfungen und
  acht CLI-Wiedergabeprüfungen bestanden.
- WAV-Vergleich: 21 lokale MOD-Dateien mit jeweils drei Sekunden Ausgabe nach
  dem Fix byteidentisch zur vor den Änderungen erzeugten Baseline. Dies belegt
  diese Renderabschnitte, nicht den vollständigen Verlauf jeder Datei.
- `python3 Tests/context_hygiene_tests.py`: sechs Prüfungen bestanden.

Native Fensterklicks und ALSA-Hardwarewiedergabe sind nicht geprüft.

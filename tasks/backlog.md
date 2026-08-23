# Aktiver Projekt-Backlog

Stand: 2026-08-23 · Version 1.6.10.

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

## Optionaler Feinschliff

- **Wächter über dem koordinierten Lesen am Gerät gegenprüfen.** Der
  `FileProviderReader` bricht eine hängende `NSFileCoordinator`-Koordination
  seit 1.6.10 ab (Abbruchflag und Stall-Timeout, `CoordinationWatchdogTests`
  belegt die Entscheidungslogik). Dass ein realer, hängender fremder File
  Provider daraufhin wirklich loslässt, zeigt nur ein Gerätetest mit einem
  solchen Anbieter. Damit ist der iOS-Review-Nachschliff vom 2026-08-02
  vollständig umgesetzt.

- **Full-Mode-`@Published`-Churn: gemessen, Trennung von Uhr und Visualizer
  lohnt nicht.** Der Vorschlag war, Spielzeit und Oszilloskop-Puffer in
  getrennte `ObservableObject`s zu legen, damit die Zeitanzeige nicht 30-mal
  pro Sekunde neu zeichnet. Umgesetzt und gemessen (1.6.10, Mac mit M5-Chip, 4-Kanal-MOD,
  stumm, je 30 s CPU-Zeit): vorher 22,3 / 21,4 / 23,9 %, nachher 20,6 / 23,2 /
  23,3 / 21,8 % eines Kerns. Kein Gewinn über dem Rauschen; die Änderung ist
  deshalb wieder draußen, statt eine wirkungslose Umstellung quer durch Core,
  Mac und iOS stehen zu lassen.

  Was die Messung stattdessen zeigt: Die reine Wiedergabe kostet 3,6 %
  (`savage-cli --play`, derselbe Titel). Von den 22 % der App sind also rund
  18 Prozentpunkte Oberfläche, und davon hängen etwa 8 an der Bildrate allein
  (die Einstellung dazu kam mit 1.6.10). Der Rest verteilt sich über den
  übrigen SwiftUI-Baum — wer da weiter will, braucht ein Profil, keine
  Vermutung. Gemessen wird mit `Tests/measure_visualizer_cpu.sh`.
- **Audioqualität:** optionale Anti-Click-Hüllkurve und JavaScript-
  Sampleinterpolation nur mit hörbarem A/B-, Timing- und Swift-Paritätsnachweis.
- **PCMSink-Extraktion:** Die Ausgabeschicht liegt als bewusste Kopie in
  savage_modplayer und vicious_sidplayer. Erst wenn sie sich in beiden bewährt
  hat, lohnt ein gemeinsames Paket — bis dahin Änderungen beidseitig abgleichen.
- **MPRIS2 für Linux.** Der Desktop-Teil von Phase 3 ist mit 1.6.10 erledigt
  (`.desktop`-Eintrag, Installer, statisches Binary — siehe
  [Linux-Plan](2026-07-05-linux-port/plan.md)). Offen bleibt die Steuerung über
  den Desktop-Mediaplayer. Sie braucht eine D-Bus-Anbindung und damit ein
  weiteres `systemLibrary`-Ziel (libdbus oder sd-bus) — eine bewusste
  Entscheidung, und ohne laufende Desktop-Sitzung auf dem Testhost nicht
  ehrlich belegbar. Ein AppImage bleibt ebenfalls offen: `appimagetool` kommt
  nicht aus den Paketquellen. Ein natives Linux-GUI ist ausdrücklich kein Ziel.
- **`.7z` auf iOS.** Aktuell nicht unterstützt und als solches gemeldet — seit
  1.6.10 ist `.7z` auch auf Mac und Linux der einzige Grund, `bsdtar` überhaupt
  zu installieren. Nur
  angehen, wenn im realen Bestand tatsächlich `.7z` auftaucht; ein eigener
  LZMA-Dekoder ist ein spürbarer Brocken.
- **Zip64.** Der ZIP-Reader lehnt Zip64-Archive mit klarer Meldung ab, statt
  falsche Offsets zu lesen. Erst umsetzen, wenn ein Archiv über 4 GB oder mit
  mehr als 65535 Einträgen real auftritt.
- **iPad-Feinschliff.** Das zweispaltige Grundlayout steht seit 1.6.10
  (Bibliothek links, Wiedergabe rechts, umgeschaltet über die Größenklasse).
  Was darüber hinaus möglich wäre: Tastaturkürzel für die Wiedergabe, Drag &
  Drop von Modulen aus der Dateien-App in die Bibliothek, und ein Blick darauf,
  ob die Visualisierungen die zusätzliche Breite gut nutzen. Alles offen, nichts
  davon versprochen.

## Nicht offen

Compact-Header/Layout, UI-Plan 1–10, IT M0–M10, Capability-Härtung sowie
Linux-Port Phase 0 bis 2 (Core + CLI bauen, testen und spielen unter Linux;
Tastatursteuerung und Playlist über `--list --play`) sind abgeschlossen. Die iOS-App aus
[2026-07-26-ios-app/plan.md](2026-07-26-ios-app/plan.md) ist gebaut (Phasen 0–7);
offen bleibt daraus nur der Gerätetest oben. WAV-Export auf iOS ist eine
bewusste Auslassung und kein offener Punkt. Das Laden eines Titels läuft seit
1.6.10 abbrechbar im Hintergrund, und „Öffnen mit …" übernimmt die Datei in die
Bibliothek und spielt sie ab. Der Ubuntu-CI-Job baut und testet Core/CLI mit ALSA- und
Archiv-Abhängigkeiten; XM unterstützt lineare und Amiga-Perioden gemäß Headerflag.
Auch der Dropout-Nachweis auf echter Audiohardware ist erbracht
(2026-07-16, `parec` über eine PipeWire-Null-Senke: keine Aussetzer, RMS-Faktor
1,0000, Korrelation 0,9994 zum Offline-Render — Details im Linux-Plan). Historische Start-/Branch-Anweisungen im IT-Task sind superseded
und kein Auftrag für eine neue Session.

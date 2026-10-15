# Aktiver Projekt-Backlog

Stand: 2026-10-16 · Version 1.6.32.

Diese Datei ist die einzige aktive Projektliste. Erledigte Chronik liegt in
Release Notes, abgeschlossenen Tasks und `archive/`.

## Priorisiert

0. **Gerätetest der iPhone-App: verbleibende Abnahmen.** Auf einem echten iPhone stehen
   noch Dateiziehen aus der Dateien-App, Wiederanlauf der Visualisierungen nach
   Scrollen/Tabwechsel, Großarchivimport und ein zehnminütiger Dauerlauf mit
   anspruchsvollem IT-Modul aus. Die Prüfliste steht in
   [docs/testing.md](../docs/testing.md) unter „Gerätetest“.
   Sperrbildschirm-Steuerung, AirPods, eingehender Anruf und Kopfhörerabziehen
   sind mit Version 1.6.16 am iPhone 16 Pro Max bestanden (2026-10-01).
   Der File-Provider-Wächter braucht weiterhin einen realen reproduzierbaren
   Hänger; seine Unit-Tests ersetzen diese Abnahme nicht.

1. **Gezielte Audio-Gegenproben nach dem Review vom 2026-10-02.** Die originale
   IT-Pingpong-Endpunktkonvention wurde mit IT 2.14 Patch 3 / ITWAV.DRV
   numerisch verglichen und in 1.6.25 übernommen (ganze und halbe
   Sampleschritte). Der
   AVAudioEngine-Ausgabetail beim CLI-Ende wurde mit einem endlichen
   Nullsample-Fixture bestätigt und in 1.6.23 korrigiert: Das natürliche Ende
   wartet auf den letzten Framezeitpunkt einschließlich Ausgabelatenz. Seit 1.6.29
   begrenzt der Zeitpunkt des fertig gerenderten Puffers auch zurückliegende
   HAL-Zeitstempel; die GitHub-CI deckte diesen zusätzlichen Randfall auf. Zu prüfen
   war die erste Initialisierung der Vibratotabelle im Echtzeitpfad: im Debug-
   Build bestätigt, seit 1.6.24 beim Kanalaufbau vorbereitet. Der Release-
   Compiler las bereits direkt aus konstanten Daten. Belege stehen in der
   [Audio-Gegenprobe](../docs/reviews/2026-10-07-audio-checks.md).
   Für den iPhone-Gerätetest zusätzlich Unterbrechung → Kopfhörer entfernen →
   Ende der Unterbrechung prüfen; der Simulator belegt den Zustandswechsel,
   nicht das reale Audio-Routing.

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
  (die Einstellung dazu kam mit 1.6.10). Gemessen wird mit
  `Tests/measure_visualizer_cpu.sh`.

- **Tracker-Raster: begrenzt und gemessen — mehr ist hier nicht zu holen.**
  Der Canvas mit den Kanalzellen ist so hoch wie das ganze Pattern (64 Zeilen à
  18 Punkte = 1152), CoreAnimation fordert ihn aber kachelweise an. Eine Sonde
  im Zeichenblock zeigte Ausschnitte von 512 bis 519 Punkten — 29 der 64 Zeilen.
  Die übrigen 35 wurden jedes Mal vollständig gesetzt, ohne je sichtbar zu sein.
  Seit 1.6.11 zeichnet der Canvas nur noch die Zeilen des angeforderten
  Ausschnitts (`TrackerGridGeometry.visibleRowRange`, sieben Tests auf die
  Ränder). Ergebnis, derselbe 4-Kanal-MOD, stumm, je 30 s CPU-Zeit bei 30 Hz:
  26,2 / 26,4 % vorher, 25,8 / 25,8 % nachher — 0,5 Prozentpunkte, in beiden
  Läufen identisch.

  Warum nicht mehr: Ein Blattprofil (`sample`, 20 s, Abschnitt „Sort by top of
  stack") zeigt, dass die Oberflächenlast keinen großen Einzelposten mehr hat.
  Auf dem Hauptthread verteilt sie sich auf SwiftUIs eigene Maschinerie —
  `AG::Graph::UpdateStack::update` (189 Proben), `AG::Graph::propagate_dirty`
  (185), `AG::Subgraph::update` (94), dazu rund 380 Proben dynamischer
  Zugriffsprüfung (`swift_beginAccess` samt Umfeld) und die Vergleiche der
  Layout-Vorschläge. Das ist der Preis dafür, dass sich der View-Baum überhaupt
  aktualisiert; kein eigener View steht mehr oben. Der Audio-DSP liegt bei 80
  Proben und deckt sich mit den 3,6 % aus dem CLI-Vergleich.

  Damit ist die Frage aus dem vorigen Eintrag beantwortet: Die Bildrate bleibt
  der einzige wirksame Regler. Wer trotzdem weiter will, muss die Zahl der
  Aktualisierungen selbst senken, nicht einzelne Views verbilligen — und sollte
  die gescheiterte Trennung von Uhr und Visualizer als Warnung lesen.

- **Audioqualität untersucht (2026-10-07):** Ein isolierter JS-Interpolator
  stimmt in 1.536 Fällen mit Swift überein und verbessert ein synthetisches
  Sinussignal; Browser-Timing und hörbares A/B bleiben vor einer Umsetzung
  erforderlich. Anti-Click glättet Sprünge, kann aber kurze Anschläge stark
  schwächen; kein konkreter störender Titelübergang bestätigt. Deshalb kein
  Klangdefault geändert. [Versuch und Grenzen](../docs/reviews/2026-10-07-audio-ideas.md).
- **PCMSink-Extraktion:** Die Ausgabeschicht liegt als bewusste Kopie in
  savage_modplayer und vicious_sidplayer. Erst wenn sie sich in beiden bewährt
  hat, lohnt ein gemeinsames Paket — bis dahin Änderungen beidseitig abgleichen.
  Der Vergleich vom 2026-10-07 zeigt einen gemeinsamen Vertrag, aber noch
  Unterschiede bei Apple-Drain und Lebenszyklus. Extraktion erst nach deren
  Stabilisierung; Paket- und beide Migrationseigentümer vorher festlegen.
- **Linux-Lieferung abgeschlossen.** Seit 1.6.27 erzeugt das Bauskript ein
  x86_64-AppImage mit festem appimagetool und Runtime. MPRIS2 über libdbus-1
  ist seit 1.6.26 umgesetzt und auf einem echten Desktop-Sitzungsbus geprüft.
  Ein natives Linux-GUI bleibt ausgeschlossen.
- **`.7z` auf iOS.** Aktuell nicht unterstützt und als solches gemeldet — seit
  1.6.10 ist `.7z` auch auf Mac und Linux der einzige Grund, `bsdtar` überhaupt
  zu installieren. Nur
  angehen, wenn im realen Bestand tatsächlich `.7z` auftaucht; ein eigener
  LZMA-Dekoder ist ein spürbarer Brocken.
- **Zip64.** Der ZIP-Reader lehnt Zip64-Archive mit klarer Meldung ab, statt
  falsche Offsets zu lesen. Erst umsetzen, wenn ein Archiv über 4 GB oder mit
  mehr als 65535 Einträgen real auftritt.
- **iPad-Feinschliff:** Die Visualisierungen nutzen seit 1.6.16 auch die freie
  Höhe der Wiedergabespalte. Das Ziehen aus der Dateien-App bleibt Teil der
  echten Geräteabnahme oben.

## Nicht offen

Das [vollständige Quellcode-Review vom 2026-10-07](../docs/reviews/2026-10-07-full-code-review.md)
ist mit Version 1.6.28 umgesetzt; bestätigte Funde und Prüfgrenzen sind dort dokumentiert.

Das Finder-Layout des DMG ist seit 1.6.16 korrigiert: gespeicherte
Fenstergröße 600 × 600 Punkte und Icons in den vorgesehenen Plätzen.

Die Kontext-Auslagerung aus `AGENTS.md` ist seit Commit `99f3449` erledigt.
Bestätigte Fallen stehen in `docs/fallen.md`; offene Abnahmen stehen hier.

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

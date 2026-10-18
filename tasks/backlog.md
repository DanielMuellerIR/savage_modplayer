# Aktiver Projekt-Backlog

Stand: 2026-10-18 · Version 1.6.52.

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

0. **Einschlaftimer: iPhone-Geräteabnahme für 1.6.45.** Hintergrund-/
   Sperrbildschirmbetrieb und reale Audio-Unterbrechungen während des Countdowns
   beziehungsweise Ausblendens am Gerät prüfen. Mac-Abnahme und visuelle
   Simulatorprüfung ersetzen diese Geräteabnahme nicht.

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

## Geplante Erweiterungen

Die [Erweiterungsübersicht](../docs/roadmap.md) hält die vereinbarten Funktionen
und ihre Abhängigkeiten fest. Gespeicherte Playlists und Warteschlange sind auf macOS seit 1.6.34 vorhanden.
Auf iPhone/iPad seit 1.6.35 ebenfalls vorhanden. Der Hintergrund-Metadatenindex ist seit 1.6.36 vorhanden. Suche, Sortierung und gespeicherte Filter sind seit 1.6.37, der Sample-Inspektor seit 1.6.38, der Modul-/Instrument-Inspektor seit 1.6.39 und Songstellen/Bereichsauswahl seit 1.6.40 vorhanden. Die macOS-Grundprüfung ist bestanden: Suche nach Instrumentnamen, gespeicherter Filter nach Neustart, Titelreihenfolge und Zweier-Wiedergabe, Sample-Wellenform und leerer Slot, IT-Hüllkurve sowie Marker speichern/springen und Bereichsanzeige in Tracker/Notenregen. Die iPhone-Suite umfasst 96 bestandene Tests; die drei ergänzenden iPad-Songstellen-Tests bestehen ebenfalls. Auch die ergänzende Mac-Detailabnahme ist bestanden: festgehaltene Zweier-Wiedergabe nach Änderung der Metadatenanzeige, Sample-Zoom/Pan, Tastenzuordnung und IT-Stereo/Sustain, weitere Hüllkurven und XM-Effekttabelle sowie Marker nach Neustart bearbeiten/löschen und unterschiedliche Bereiche in zwei Orders desselben Patterns.

Native A/B-Audioschleifen sind seit 1.6.42 vorhanden und vollständig abgenommen.
Audio-Gegenproben, Linux-Suite, 22 identische MOD-Baselines und 22 samplegenaue
A/B-Korpusvergleiche bestehen. Die native Mac-Abnahme umfasst Light/Dark,
Notenregen mit fortlaufenden Stimmen, Pause/Stop, geänderte Audioeinstellungen,
Bereichs-/Titelwechsel, begrenzte Vorbereitung und Abbruch. Die iOS-Simulator-
Prüfung besteht auf iPhone und iPad in DE/EN und beiden Darstellungen.
Die Allokationssonde bestätigt mit positiver Gegenprobe je 1.000 MOD-/XM-/IT-
Callbacks ohne Heap-Allokation. Der Stapel-Export ist seit 1.6.44 vorhanden und vollständig am Mac abgenommen. Stereo-Kanalspuren sind seit 1.6.43 vorhanden und vollständig abgenommen: Zielwahl, Fortschritt, Abbruch in beiden Renderphasen, Zielkonflikte, festgehaltener Titel, Mute/Solo, Stereo-Mix, Finder-Ergebnis sowie Light/Dark einschließlich schmalem Fenster und größerer Schrift. Die neuen Listen-/Warteschlangenabläufe sind noch auf einem echten Gerät abzunehmen.

Das [portable Sammlungsformat](../docs/collection-exchange.md) ist seit 1.6.47 im gemeinsamen Core vorhanden. Seit 1.6.48 gibt es die nativen Export-/Import-Oberflächen mit Titelzuordnung, Vorschau und Konfliktentscheidungen. Der Transfer über Dateien und AirDrop ist noch auf einem echten iPhone zu prüfen; Simulator- und Mac-Dateirundwege ersetzen diese Geräteabnahme nicht. Die native Mac-Abnahme und der tatsächliche Dateirundweg Mac → iPhone-Simulator → Mac bestehen einschließlich Konfliktentscheidungen, Neustart und Erhalt lokaler Wiedergabeeinstellungen.

Der [Offline-Notenregen-Video-Renderer](../docs/note-rain-video.md) ist seit 1.6.49 im macOS-Core vorhanden. Seit 1.6.50 sind die native Exportoberfläche, Vorschau und Zielwahl implementiert. Die zusammenhängende native Abnahme mit Vorschau, Fortschritt, Abbruch, Zielschutz, festgehaltenem Titel und laufender Wiedergabe besteht. Hell/Dunkel, schmale Ansicht und größte Schrift sind visuell geprüft. Die tatsächlich exportierten MOD-/IT-Videos enthalten bytegleiches Float32-Audio zur WAV-Referenz und enden samplegenau mit ihrem Bildtrack.

## Automatischer Metadatenabgleich

Die [Abgleich-Anbindung](../docs/collection-sync.md) ist seit 1.6.51 auf Mac und iPhone/iPad implementiert: lokale Erfassung, atomare Speicheranbindung, dauerhafte Titelzuordnung, Einrichtung, Status, Wiederholung und Konfliktentscheidungen. Die lokale Abnahme mit simuliertem Dienst besteht einschließlich nativer Mac-Zuordnung, Konflikten, Offline-Wiederholung und Kontowechsel. Vier isolierte App-/Darstellungstests am echten iPhone bestehen bei unveränderten Produktionseinstellungen und Metadatenspeichern. Der tatsächliche Dateirundweg Mac → iPhone-Simulator → Mac besteht auch mit 1.6.51. Seit 1.6.52 sind der gemeinsame Container bestätigt und die optionalen Mac-/iOS-Builds mit geprüften Profilen, minimalen CloudKit-Berechtigungen und getrennter Entwicklungs-/Produktionsumgebung vorbereitet. Der echte Entwicklungs-Rundweg Mac → iPhone → Mac besteht für Playlists, Favoriten, Songstellen und Klang-Overrides einschließlich stabiler IDs, lokaler Lautstärke und Mac-Neustart. Das geprüfte Schema ist in Production bereitgestellt. Der konfigurierte und notarisierte Mac-Build besteht die native Abnahme ohne iCloud-Konto einschließlich Fehler/Wiederholung, Speicherschutz, Dateiübertragung und Songstellen nach Neustart. Der schreibende Production-Rundweg und echte parallele Playlistkonflikte mit Songstellen-Löschung bestehen. Development wurde nach Testablaufkorrekturen zusätzlich mit einem frischen iPhone-Client geprüft; Production besteht durchgehend. Der Mac-Endstand bleibt nach Neustart erhalten. Zusätzlich bestehen in Production der bytegleiche Asset-Rundweg einer 6,4-MB-Sammlung mit 20.000 synthetischen Titelbeschreibungen und die echte Ablehnung eines veralteten bedingten Schreibzugriffs. Die eigene temporäre Prüfzone ist gelöscht; der App-Snapshot bleibt unverändert. Reale Netztrennung, tatsächlicher Kontowechsel, Quota/Drosselung und große Sammlungen in der Oberfläche auf zwei Geräten bleiben zusätzliche Dienstabnahmen; die entsprechenden Schutz- und Grenzfälle sind lokal getestet. Standardbuilds lassen den Cloud-Zugriff ausgeschaltet; der manuelle Austausch bleibt nutzbar.

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

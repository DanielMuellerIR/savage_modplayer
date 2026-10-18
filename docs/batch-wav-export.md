# Stapel-Export auf macOS

Seit 1.6.44 öffnet **Stapel-Export …** in der Seitenleiste die aktuelle Anzeige
einschließlich Suche, Sortierung und Filter. Die beim Öffnen festgehaltene Liste
lässt sich über Kontrollkästchen einschränken. **Ziel wählen …** startet den Export
in einen vorhandenen oder neu angelegten Zielordner. Bis zu 10.000 Titel sind je
Stapel möglich; iPhone/iPad bieten weiterhin keinen Audioexport.

Ausgabe, Dauergrenze je Titel, MOD-Clock, Interpolation, Separation und
Konfliktbehandlung werden beim Start gespeichert und beim nächsten Öffnen wieder
angeboten. Der Stapel übernimmt keine laufende A/B-Schleife oder Abspielposition.
Die normale Wiedergabe bleibt unabhängig. Quelldateien werden erst beim jeweiligen
Titel gelesen; zwischenzeitlich entfernte oder veränderte Dateien können deshalb
zu anderen Ergebnissen oder einem ausdrücklich gemeldeten Ladefehler führen.

## Ausgaben und Konflikte

Jeder Titel erhält einen Ordner nach seinem ursprünglichen Dateinamen. Gleiche Namen innerhalb
der Auswahl bekommen fortlaufende Zusätze wie `Track.mod (2)`. Unzulässige Zeichen
werden ersetzt, lange Namen gekürzt. Vorhandene Dateien, Ordner und Symlinks werden
niemals überschrieben. **Überspringen** erhält das vorhandene Ziel unverändert.
**Beide behalten** sucht einen freien Namen mit nummeriertem Zusatz. Ein exklusives
Umbenennen schützt auch Ziele, die erst während des Renderns angelegt werden.

- **Stereo-Mix:** `Mix.wav`, Stereo-Float32 bei 44.100 Hz, ohne Normalisierung.
  Der Mix enthält den normalen `tanh`-Limiter.
- **Kanalspuren und Referenzmix:** eine Stereo-Float32-WAV je logischem Kanal,
  `Reference-Mix.wav` und derselbe gemeinsame Pegelfaktor je Titel wie beim
  [einzelnen Kanalspuren-Export](channel-stem-export.md). Die Spuren liegen vor
  dem Limiter. Pegel werden nicht zwischen verschiedenen Titeln vereinheitlicht.
- **Je Titel:** `manifest.json` hält Audiooptionen, Framezahl, Dauergrenze und
  Pegelregeln fest.
- **Je Stapel:** `Savage-Export-<ID>.json` hält die Einstellungen und für jeden
  Titel Dateiname, Zielordner, Ergebnis und gegebenenfalls Fehler fest. Der Bericht
  kopiert keine Quelldateien und enthält keine separate Liste absoluter Quellpfade.

Mute/Solo aus dem aktuell laufenden Player wird nicht auf andere Titel übertragen;
die Header-Defaults des jeweiligen Moduls bleiben erhalten. Mixerlautstärke und
externer LED-Ausgabefilter sind in beiden Ausgaben ausgeschlossen.

## Fortschritt, Abbruch und Grenzen

Die Oberfläche zeigt den aktuellen Titel und dessen Fortschritt sowie den
Fortschritt über die Titelzahl. Titel sind gleich gewichtet; Prozentangaben sind
keine verbleibende Zeitschätzung. Dauergrenzen schützen gegen endlose Module.
Quellen müssen reguläre Dateien bis 64 MiB sein; FIFOs blockieren den Leser nicht.
Archivtitel aus einer geöffneten Liste werden über ihre bereits entpackte Quelle
gelesen, ohne beim Export ganze Archive erneut in den Speicher zu laden.

Der Export arbeitet seriell. Jeweils ein Modul und feste Audioblöcke liegen im
Speicher; die gesamte WAV-Ausgabe wird nicht gepuffert. Abbruch beendet den aktuellen
Titel zwischen Blöcken und entfernt dessen eigene temporäre Ausgabe. Bereits
fertige Titel bleiben erhalten. Defekte Quellen verhindern folgende Titel nicht.
Der Abschluss unterscheidet exportiert, übersprungen, fehlgeschlagen, abgebrochen
und nicht begonnen. Ein nicht speicherbarer Stapelbericht wird gesondert gemeldet;
bereits veröffentlichte Ausgaben bleiben erhalten.

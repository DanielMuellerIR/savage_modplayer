# Offline-Notenregen-Video

Seit 1.6.49 enthält der macOS-Core `NoteRainVideoRenderer`. Er schreibt eine neue
MOV-Datei mit H.264-Bild und verlustfreiem Stereo-Float32-Audio. Seit 1.6.50 bietet die App dafür eine native Exportoberfläche.

## Bedienung

Einen Titel laden und **Export → Notenregen als Video…** oder das Film-Symbol
neben dem WAV-Export öffnen. Der Dialog hält Modul und Mute/Solo-, Clock-,
Interpolations- und Separationswerte fest. Ein anschließender Titelwechsel oder
eine Änderung der Live-Wiedergabe verändert diesen Export nicht.

Die optionale **Vorschau erstellen** rendert bis zu fünf Sekunden ab Songanfang
mit denselben Bild- und Klangoptionen. Sie startet pausiert; Play und Zeitleiste
gehören nur zur Vorschau. Geänderte Optionen verwerfen die alte Vorschau.

Auflösung (640 × 360, 1280 × 720, 1920 × 1080), Bildrate, Bildqualität,
Hell/Dunkel, Vorlauf und Dauergrenze wählen. **Hoch** verwendet ungefähr doppelt
so viele angeforderte Videobits wie **Kompakt**, abhängig von Auflösung und
Bildrate und begrenzt auf 0,6–24 Mbit/s. Die tatsächliche Dateigröße hängt vom
Bildinhalt und Encoder ab. Das verlustfreie Audio ist in beiden Stufen gleich.
Die Dauergrenze reicht von einer bis 60 Minuten; ein natürliches Songende
beendet den Export früher.

**Ziel wählen und exportieren …** öffnet den nativen Speichern-Dialog. Ein neuer
MOV-Name ist erforderlich. **Export abbrechen** wartet auf die Bereinigung;
ein fertiges Video bleibt erhalten, wenn der Abschluss bereits erfolgt ist.
Die Oberfläche meldet Erfolg oder Fehler und bietet **Im Finder zeigen** an.
Live-Wiedergabe, Warteschlange und Einschlaftimer laufen unabhängig weiter.

## Ausgabe und Zeitbasis

Audio und Bild beginnen am Modulanfang. Header-Tempo, Pattern-Effekte und
Songende kommen aus derselben Replay-Engine wie bei Wiedergabe und WAV-Export.
Die Notenvorschau verwendet die bestehende Sequenzersimulation mit eigener,
ausschließlich vom Export genutzter DSP-Instanz. IT-Hintergrundstimmen behalten
ihren logischen Pattern-Kanal und damit ihre Farbe und Mute-/Solo-Zuordnung.

Die Audiorate beträgt 48.000 Hz. Videobilder liegen bei ganzzahligen Sampleframes:
24, 25, 30 beziehungsweise 60 Bilder pro Sekunde entsprechen Abständen von
2.000, 1.920, 1.600 beziehungsweise 800 Samples. Container und Videotrack verwenden
ebenfalls die Zeitskala 48.000. Das letzte Bild endet am tatsächlichen Audioende,
auch wenn ihm nur ein Teil seines normalen Bildintervalls bleibt. Die Bildzahl
ist die aufgerundete Anzahl dieser Intervalle; es wird kein Audio angehängt.

Die Balken zeigen die berechnete Stimmenlaufzeit, die Farben den Kanal. Ein
Vorlauf von zwei, vier oder acht Sekunden ist möglich. Noten hinter dem
natürlichen Ende oder der gewählten Dauergrenze werden ausgeblendet. Standardmäßig
umfasst die Klaviatur alle 120 möglichen Noten; ein ausdrücklich gesetzter
Tonbereich kann die Darstellung eingrenzen. Hell und Dunkel folgen der Gestaltung
des vorhandenen Notenregens.

Rastergeometrie, Sample-Zeitpunkte und unkomprimiertes Audio sind deterministisch.
Die Bytefolge des gesamten MOV ist kein Reproduzierbarkeitsvertrag: Der native
Videoencoder und seine Metadaten können sich zwischen Systemversionen ändern.

## Optionen und Klang

Standard sind 1280 × 720 Pixel, 30 Bilder pro Sekunde, vier Sekunden Vorlauf und
höchstens 600 Sekunden Laufzeit. Erlaubt sind gerade Abmessungen zwischen
320 × 180 und 1920 × 1080 Pixeln und eine positive Dauer bis 3600 Sekunden. Die
Dauergrenze wird vor dem Rendern auf ganze Audioframes abgerundet. Ungültige oder
nicht endliche Werte werden vor der Pufferallokation abgelehnt.

`ChannelStemExportOptions` liefert MOD-Clock, Stereo-Separation, Interpolation
sowie Mute und Solo. Ohne ausdrücklich übergebene Mutes bleiben die
Modul-Voreinstellungen erhalten. Audio wird nach dem bestehenden tanh-Limiter
und ohne Peaknormalisierung gespeichert. Mixerlautstärke und der externe
LED-Ausgabefilter sind wie beim Float-WAV-Export nicht enthalten. Laufende
Wiedergabe, Timer, Warteschlange, manuelles Seek und manuelle Tempoänderungen
werden nicht in den Export übernommen.

## Aufruf und Abschluss

Der Export läuft synchron und gehört in eine Hintergrund-Task. Modul und Optionen
vorher festhalten. Die Ziel-URL muss eine neue `.mov`-Datei in einem vorhandenen
Ordner bezeichnen; erforderlichen Security-Scope verwaltet der Aufrufer.

```swift
let options = NoteRainVideoOptions(width: 1280, height: 720, framesPerSecond: 30)
let report = try await Task.detached(priority: .userInitiated) {
    try NoteRainVideoRenderer.export(mod: capturedModule, to: newMovieURL,
                                    options: options)
}.value
```

`progress` wird auf dem ausführenden Thread aufgerufen. Während des Renderns
bezieht sich der Fortschritt auf das gesetzte Dauerbudget; ein früheres
natürliches Ende schließt den Vorgang entsprechend früher ab. Eine abgebrochene
Task wirft `CancellationError` und entfernt ihren Arbeitsstand. Nach erfolgreicher
Veröffentlichung ist die Datei fertig; ein danach eintreffender Abbruch entfernt
sie nicht.

Der Renderer schreibt zuerst in ein eigenes verstecktes Arbeitsverzeichnis im
Zielordner. Erst nach abgeschlossenem Medien-Writer und letzter Abbruchprüfung
wird die Datei exklusiv umbenannt. Vorhandene Dateien, Verzeichnisse und Symlinks
werden geschützt, auch wenn sie erst während des Exports am Ziel erscheinen.
Der Rückgabewert enthält Optionen, Audio-/Videoframezahl und den Endgrund.

## Begrenzter Speicher und Prüfung

Der Export hält feste Audioblöcke und höchstens sechs eigene Bildpuffer vor.
Audio wird gestreamt; weder der ganze Song noch alle Videobilder liegen im RAM.
Die Notensimulation verwirft ältere Ereignisse. Ihre Menge wird alle 256
simulierten Frames geprüft; mehr als 60.000 Noten im aktuellen Fenster führen
zu einem erklärbaren Abbruch. Ein Medien-Writer ohne Fortschritt wird nach einem
begrenzten Warteintervall beendet. Die Datei auf Disk wächst mit der Laufzeit.

`NoteRainVideoTests` prüft Zeitbasis, Grenzen, Überlauf und den samplegenauen
Audioadapter auf allen Plattformen. `NoteRainVideoRendererTests` liest am Mac die
wirklichen MOV-Tracks mit AVFoundation und prüft Samplezahlen, Zeitstempel,
verlustfreies Audio, natürliches Ende, Zielkonflikte, Abbruch und Rasterreihenfolge.
Die Prüfung längerer Exporte, Speicherentwicklung und gerenderter Ansichten
gehört zusätzlich zur Abnahme; ein grüner Daten-Test ersetzt diese Bildprüfung
nicht. Linux und iOS bauen die neutrale Konfiguration und Audiobasis; der
Medien-Writer ist macOS-spezifisch.

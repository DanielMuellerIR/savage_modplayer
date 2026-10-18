# Modul- und Instrument-Inspektor

Auf dem Mac öffnet **Modul untersuchen…** im Instrumente-Tab die Ansicht.
Auf iPhone/iPad liegt der Punkt zusammen mit dem Sample-Inspektor im Info-Menü
**Moduldetails** oben im Wiedergabe-Tab. Die Ansicht hält das beim Öffnen gewählte
Modul fest und verändert seine Daten nicht.

**Übersicht** zeigt Titel, Format, Starttempo, Kanal-/Instrument-/Sampleplätze und
die Abspielliste mit Pattern- und Zeilenzahlen. Wiederverwendete Patterns bleiben
als verschiedene Songpositionen sichtbar. Die Positionen entsprechen der
Abspielliste des Players; entfernte Datei-Skip-/Endmarker werden nicht erfunden.
Die statische Patternstruktur ist keine Berechnung der tatsächlichen Spieldauer.

Herkunftsangaben stammen ausschließlich aus erhaltenen Feldern: insbesondere
IT-Trackeridentität, Erstellerversion `cwtv`, erforderliche IT-Version `cmwt` und
ein explizites OpenMPT-Künstlerfeld. Fehlende Angaben werden nicht aus Dateinamen
oder Instrumenttexten geschätzt. Der vollständige Songtext gehört derzeit nicht
zum geladenen Modell und wird hier nicht rekonstruiert.

Die Kompatibilitätsansicht übernimmt die vorhandene Capability-Analyse mit
Merkmal-ID, Unterstützungsstatus und Verwendung. Gespeicherte Metadaten sind
von tatsächlich verwendeten klangrelevanten Merkmalen getrennt. Vorhandene
Diagnosetexte bleiben im Wortlaut des Parsers erhalten. „Keine erfassten
Kompatibilitätswarnungen“ verspricht keine identische Wiedergabe in jedem Tracker.

**Instrumente** zeigt aktivierte Lautstärke-, Panning- und Tonhöhen-/Filter-
Hüllkurven. Die horizontale Achse zählt Ticks seit Notenbeginn, die vertikale
gespeicherte Werte von 0 bis 64. Bei Pitch ist 32 neutral. Sustain und Loop
verweisen auf die Tickpositionen der gespeicherten Punkte; Carry bleibt separat
sichtbar. Das sind Hüllkurvendaten, keine gemessenen Audiopegel. Fadeout,
Auto-Vibrato und vorhandene IT-NNA-/Duplikat-/Filter-/Routingwerte ergänzen die
Ansicht; externe MIDI- oder Pluginsynthese wird dadurch nicht aktiviert.

**Effekte** zählt übernommene Befehle in allen gespeicherten Patterns einmal pro
Zelle. Wiederholte Songpositionen vervielfachen die Zahl nicht; unbenutzte Patterns
können enthalten sein. Effektspalte und Volume-Spalte bleiben getrennt, ebenso
formatspezifische Codes wie S3M `Ixy` und XM `Txy`. Vorhandene Nullparameter bleiben
sichtbar, auch wenn sie Effekt-Memory verwenden. Zahlenbasis und normalisierte
Parameter sind beschriftet; beim Einlesen verworfene Originalbefehle können nicht
nachträglich rekonstruiert werden. Erkannte, derzeit ignorierte Befehle erhalten
einen Hinweis.

Die gemeinsame Auswertung läuft abbrechbar außerhalb des UI- und Audiothreads.
Reine Modelle bleiben unter Linux verfügbar; die optionale SwiftUI-Ansicht wird
nur auf Apple-Plattformen gebaut.

# Begrenzte Untersuchung der Audioideen

Stand: 2026-10-07 · Ausgangsstand 1.6.27. Drei getrennte Untersuchungen;
keine Änderung eines Klangdefaults und keine Paketmigration.

## JavaScript-Sampleinterpolation

Der Browserkanal liest bisher den ganzzahligen Sampleindex. Ein isolierter
Prototyp ersetzt ausschließlich diesen Lesezugriff durch lineare Interpolation,
einschließlich des Nachbarwerts am Vorwärtsloop. Die übrige echte `Channel`-
Implementierung stammt unverändert aus `mod-player-worklet.js`.

Bei 1.536 Positionen mit Loopstarts 0/1/3 und Schritten 0,5/1/3,25/13,75 stimmt
der Prototyp exakt mit den aus `DSPChannel.swift` übernommenen, tatsächlich
in Swift ausgeführten Samplelesern überein (maximaler absoluter Float-Fehler 0).
Das belegt den untersuchten Lesealgorithmus, nicht die gesamte Mixerparität.

Ein quantisierter 8-Bit-Sinus mit 32 Samples pro Periode und Schritt 0,37
liefert bei 100.000 Ausgabeframes einen RMS-Fehler von 0,037303 beim bisherigen
Leser und 0,000898 mit linearer Interpolation, jeweils gegen den idealen Sinus.
Das entspricht 32,37 dB Fehlerreduktion in diesem synthetischen Fall.
Fünf warme Node-Läufe mit je einer Million Kanalframes benötigen im Median
5,18 ms beziehungsweise 6,44 ms. Das ist ein kleiner absoluter Mehraufwand
im isolierten Kanaltest; Browser-Worklet, mehrere Kanäle und Scheduling wurden
damit nicht gemessen.

Entscheidung: numerischer Nutzen belegt. Vor einer Produktänderung bleiben der
bereits verlangte hörbare A/B-Vergleich und Browser-Timing offen. Die Untersuchung
ersetzt diese Abnahme nicht. Ein eigener Umsetzungsschritt darf erst danach
den Klangdefault ändern; der Prototyp bleibt außerhalb des Produkts.

## Anti-Click

Der MOD-Samplepfad besitzt keine allgemeine Rampe bei Note/Cut/Volumensprung.
Ein kleines Signalexperiment vergleicht einen Sprung von 0 auf 0,5 mit linearen
Rampen bei 44.100 Hz. 16/32/64 Frames entsprechen 0,36/0,73/1,45 ms; der größte
Sprung fällt von 0,5 auf 0,03125/0,015625/0,0078125.

Die Gegenprobe ist ein Ein-Frame-Impuls am Notenanfang: Eine solche Rampe erhält
nur 0,391/0,098/0,024 Prozent seiner Energie. Die Sprungreduktion allein belegt
also keine bessere Tracker-Wiedergabe. Der Versuch ist ein Grenzsignalvergleich,
kein Nachweis eines störenden Klicks in einem konkreten Titel.

Entscheidung: kein pauschaler Anti-Click-Default. Ein eigener Korrekturschritt
braucht einen reproduzierbaren störenden Übergang, eine dafür passende
Crossfade-/Rampengrenze und A/B-Abnahme der Anschläge. Kein solcher Produktfehler
wurde in dieser begrenzten Untersuchung bestätigt.

## Gemeinsamer PCMSink

Die fünf Ausgabedateien umfassen 1.682 Zeilen im MOD- und 1.678 im verglichenen
SID-Stand. Der exakte Zeilenvergleich liegt je Datei zwischen 87,0 und 98,0 Prozent
Übereinstimmung; Kommentare und Projektnamen sind dabei enthalten. Das ist ein
Duplikationshinweis, keine semantische Gleichheitsmetrik.

Der öffentliche Vertrag ist formatfrei: `PCMFormat`, `PCMRenderBlock`,
`PCMSinkError`, `PCMSinkFinishReason`, Einweg-Lebenszyklus, Pause/Resume und
wiederholbares Warten. Pegelskalierung bleibt bei der Quelle. Die erhebliche
Gemeinsamkeit rechtfertigt grundsätzlich eine spätere Extraktion.
Die konkreten Apple-Implementierungen unterscheiden sich jedoch gerade bei
Drain/Endzeitpunkt und Serialisierung des Engine-Lebenszyklus. Der untersuchte
SID-Arbeitsstand war noch nicht abgeschlossen; darauf baut keine Migration auf.

Vor einer Extraktion müssen beide Implementierungen denselben geprüften Vertrag
für Start/Stop-Parallelität, mehrere Warter, Pause beim Auslaufen, Fehler und
Pointer-Lebensdauer erfüllen. Für eine spätere Umsetzung sind ein Eigentümer
für das Paket sowie je ein seriell arbeitender Eigentümer pro App-Migration
festzulegen. Der aktuelle Untersuchungsauftrag migriert keines der Projekte.

## Grenzen und Reproduktion

Die Proben sind synthetisch; kein Hörvergleich wurde als bestanden gemeldet.
Das Experiment verwendet den echten JavaScript-Kanal und die echten Swift-
Sampleleser, aber keine vollständige Browser-/Native-Audioaufnahme. Die privaten
Prüfbelege enthalten Prototyp, Messwerte, 1.536 Vergleichseingaben und Sink-Diffs.
Der Produktstand bleibt unverändert. Konkrete Defekte aus dem anschließenden
vollständigen Code-Review werden separat reproduziert und korrigiert.

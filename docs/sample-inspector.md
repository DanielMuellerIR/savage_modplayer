# Sample-Inspektor

Auf dem Mac liegt **Samples untersuchen…** im Instrumente-Tab der Seitenleiste.
Auf iPhone und iPad liegt derselbe Punkt im Info-Menü **Moduldetails** oben im Wiedergabe-Tab.
Der Inspektor hält das beim Öffnen gewählte Modul fest. Weiterlaufende Musik oder
ein Titelwechsel ersetzt die gerade untersuchten Daten nicht.

**Alle Samples** zeigt bei IT den globalen Samplepool, bei anderen Formaten die
Samples aller Instrumente. Die Instrumentauswahl grenzt die Liste ein; auch
ungenutzte XM-Samples und unzugeordnete IT-Samples bleiben über die Gesamtansicht
erreichbar. Leere oder nicht vorhandene Samples erhalten einen eigenen Zustand.

Die Wellenform zeigt bei Stereo beide Kanäle. Die Zeichnung fasst die kleinsten
und größten Werte jedes dargestellten Abschnitts zusammen; einzelne kurze
Impulse bleiben sichtbar. Zoom und Position wählen den Ausschnitt. **Gesamt**,
**Loop** und **Sustain** springen direkt in den jeweiligen Bereich. Der Maßstab
bleibt beim Zoomen gleich. Normaler Loop und Sustain-Loop haben unterschiedliche
Farben; die Beschriftung nennt Vorwärts- oder Ping-Pong-Wiedergabe.

Positionen und Längen sind **Frames**, keine Bytezahlen. Die obere Bereichsgrenze
liegt unmittelbar hinter dem letzten enthaltenen Frame. Bei Stereo enthält ein
Frame je einen Wert beider Kanäle. Aus den intern normalisierten PCM-Daten lässt
sich die ursprüngliche Bittiefe nicht zuverlässig ableiten; sie wird daher nicht
behauptet. Eine Referenzrate bezeichnet bei S3M C-4, bei IT C-5 und ist keine
feste Gesamtdauer des Samples bei allen gespielten Noten.

Die Tastenzuordnung zeigt die tatsächlich gespeicherten XM-/IT-Tabellen als
zusammenhängende Bereiche. Quellnote, Zielnote und Sample-Nummer bleiben getrennt;
IT kann Zielnoten transponieren und Tasten unbelegt lassen. Die Notennamen folgen
dem Tracker-Schema mit C-0 = 0. Finetune und Relative Note wirken zusätzlich.
Formate ohne eigene Tastentabelle erhalten einen Hinweis statt einer erfundenen
Zuordnung.

Die Ansicht liest vorhandene Daten. Sie verändert weder Samples noch Loopgrenzen
oder den Hörstatus. Die bisherige Instrumentvorschau bleibt separat verfügbar.
Berechnung und Abbruch der begrenzten Wellenform laufen außerhalb des UI- und
Audiothreads; unter Linux bleiben die Auswahl- und Auswertungsmodelle nutzbar.

# Songstellen und Bereichsauswahl

Auf dem Mac öffnet **Songstellen…** in der Seitenleiste oder im Notenregen die
Ansicht. Auf iPhone/iPad liegt derselbe Punkt im Info-Menü **Moduldetails** des
Wiedergabe-Tabs.

Songpositionen beginnen bei **1**, Tracker-Zeilen bei **0**. Eine Songstelle
speichert einen Namen und genau dieses Paar. Zwei Songpositionen bleiben
unterschiedliche Ziele, auch wenn sie dasselbe Pattern verwenden. **Aktuelle
Stelle** übernimmt die Transportposition; die Steuerelemente wählen ein anderes
Ziel. **Zum Ziel springen** nutzt den vorhandenen zeilengenauen Tracker-Sprung
und erhält Play/Pause/Stopp. Tempo, Speed und globale Lautstärke werden wie beim
Tracker-Zeilenklick rekonstruiert; laufende Stimmen und Effektverläufe bleiben
dabei näherungsweise.

**Songstelle hinzufügen** speichert das Ziel. Ein Klick auf eine vorhandene
Songstelle lädt Name und Ziel zum Bearbeiten; **Neu** kehrt zur Neuanlage zurück.
**Springen** navigiert direkt, **Löschen** entfernt nur den gespeicherten Marker.
Ungültig gewordene Ziele bleiben sichtbar und erhalten eine gesperrte
Sprungaktion. Zum Reparieren erst bewusst ein neues Ziel wählen.

**Anfang (A)** und **Ende (B)** übernehmen das gewählte Ziel als visuelle
Bereichsauswahl. Das Ende muss hinter oder auf dem Anfang liegen; beide Grenzen
sind eingeschlossen. Im Mac-Tracker zeigt ein Band die gewählten Zeilen und
Punkte markieren gespeicherte Songstellen. Das Kontextmenü einer Zeilennummer
setzt Anfang oder Ende direkt. Die Positionsleiste im Notenregen zeigt denselben
Bereich über der Abspielliste; sie ist keine Zeitachse und markiert keine
zukünftigen Notenstimmen. Der gewählte Wiedergabe-Loop-Modus bleibt unverändert.
Die Bereichsauswahl gehört zur aktuellen Sitzung und wird beim Titelwechsel
gelöst.

**A/B vorbereiten und abspielen** startet zusätzlich eine Audioschleife. Die App
rendert den tatsächlichen Songfluss vom normalen Anfang bis A im Hintergrund und
behält dessen vollständigen Tracker-Zustand. Laufende Samples, Effekt-Memory,
Hüllkurven, IT-Hintergrundstimmen und deren Filterhistorie bleiben damit erhalten.
B endet nach sämtlichen Ticks und Delays; erst dann beginnt A wieder. Wiederverwendete
Patterns werden anhand ihrer Songposition unterschieden. Sprünge können A oder B
unerreichbar machen: Die App meldet dies, statt eine andere Reihenfolge abzuspielen.
Die Vorbereitung endet spätestens nach zehn Minuten simuliertem Songverlauf und
lässt sich abbrechen; der Speicher wächst nicht mit der Songdauer.

Eine bestehende Wiedergabe läuft während der Vorbereitung weiter. Aktivierung
springt nach A; ein pausierter Zustand bleibt pausiert. **A/B ausschalten** setzt
an der aktuellen Stelle fort. Stop, Titel-/Bereichswechsel, ein manueller Sprung
oder geänderte Audioeinstellungen lösen die Schleife. Mute und Solo bleiben
unabhängige Bedienzustände. Der gewöhnliche Loop-Modus gilt anschließend weiter.
Der Mac-Notenregen verwendet denselben Zustand und dieselbe Framezahl; seine Uhr
zählt die Ausgabe kontinuierlich, während die Songposition nach A zurückspringt.
Der optionale LED-Ausgabefilter verarbeitet die kontinuierliche Ausgabe außerhalb
der Tracker-Engine; dessen Ausgabetail wird an A/B-Grenzen nicht zurückgesetzt.

Marker bleiben über Neustarts erhalten. Quellen-IDs entsprechen auf dem Mac der
Originaldatei einschließlich Archivmitglied und auf iOS dem relativen
Bibliothekspfad. Temporäre Wiedergabekopien werden nicht als neue Quellen
gespeichert. Eine Demo oder eine nicht mehr zuordenbare Temp-Quelle kann weiterhin
angesprungen/markiert werden, erhält aber keine dauerhaften Songstellen.

Der eigene versionierte Speicher ist keine Cache-Datei. Beschädigte, zu große oder
nicht unterstützte Daten bleiben erhalten und sperren Schreibzugriffe. Fehlgeschlagene
Schreibvorgänge erhalten den letzten Stand. Namen sind auf 200 Zeichen, der Bestand
auf 10.000 Marker begrenzt; zusätzlich gilt ein begrenztes Dateibudget. Die Ansicht
ändert weder Musikdateien noch Sample-/Pattern-Daten. Unter macOS isoliert
`SAVAGE_SONG_MARKER_STORE` den Speicher für Tests.

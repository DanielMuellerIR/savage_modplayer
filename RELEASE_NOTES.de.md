Ein Feinschliff-Release auf Basis von 1.3.0: überarbeitete Player-Oberfläche, ein eigener Wiedergabe-Pfad für die Instrument-Vorschau und die Fixes aus der Code-Review-Runde.

## Verbessert

- **Überarbeitete Oszilloskop- und Transport-Zeile**: Play/Pause liegt jetzt auf der rotierenden Disk im Transport-Balken (Stop/Zurück/Vor bleiben eigene Tasten); LED-Filter, Hi-Fi und Loop wandern in eine schmale Leiste unter die Oszis. Die **Kanal-Oszis sind jetzt adaptiv breit** (verfügbare Breite ÷ Kanalzahl, ab Mindestbreite wird gescrollt) — bis zu 16 Kanäle passen gleichzeitig nebeneinander, und das VU-Meter schrumpft bei vielen Kanälen mit.
- **Gestraffte Pattern-Ansicht**: kompakte Zeilenhöhe, 1-pt-Trennlinien zwischen den Kanälen, eng an den Inhalt gelegte Zellen und eine automatische Schrift-Verkleinerung um 1 Punkt, bevor eine horizontale Scrollbar nötig würde. Die **Zeilennummern-Spalte steht jetzt fest** (scrollt nicht mehr weg), und das Raster hat eine **eigene, dezent-graue horizontale Scrollbar** am unteren sichtbaren Rand.
- **Größere Klickflächen**: die ganze Instrument-Zeile (außer dem Download-Button) sowie die Tabs PLAYLIST/INSTRUMENTE sind jetzt vollständig anklickbar.
- **Rekursives Laden aus `audio/`**: Module in Unterordnern (z. B. `audio/Autor/song.mod`) werden automatisch gefunden, und übrig gebliebene Temp-Kopien früherer Läufe werden beim Start aufgeräumt.

## Behoben

- **Instrument-Vorschau** hat jetzt einen eigenen, vom Song getrennten Wiedergabe-Pfad (eigene Vorschau-Engine und eigener Kanal). Sie klingt auch im gestoppten Zustand und kapert nie mehr einen Song-Kanal — das hatte zuvor still Mute/Solo verloren.
- **Zuletzt gespielter Titel**: bei ausgeschaltetem Shuffle wird der zuletzt gespielte Titel nach einem Neustart wieder aufgenommen.

## Hinweise

- Der HTML5-Einzeldatei-Player bleibt bewusst ein kompakter 4-Kanal-ProTracker-Player.
- Das DMG enthält die App inklusive Quick-Look-Plugin; es sind keine Modul-Dateien enthalten. Musik wird per Drag & Drop oder aus einem lokalen `audio/`-Ordner geladen.

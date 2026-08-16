Savage Mod Player 1.6.8 behebt Fehler bei Nebenläufigkeit, Archivsicherheit und
abgeschnittenen Dateien, die im Folgereview des QA-Durchgangs für 1.6.7 gefunden
wurden.

## Wiedergabe

- Ein Sprung während der Live-Wiedergabe wird jetzt als vorab angelegter,
  lockfreier Auftrag im Audio-Callback ausgeführt. Position, Zeile, Timing,
  Effekte und Stimmen können nicht mehr in einem halb geänderten Zustand gelesen
  werden.
- Nach einer Titelwiederholung enthält die Anzeige- und Sperrbildschirmzeit auch
  die Audioframes, die seit dem exakten Loop-Übergang bereits gerendert wurden.
  Die Uhr hinkt nicht mehr bei jeder Runde um bis zu ein Abfrageintervall nach.

## Module

- MOD- und 15-Sample-Soundtracker-Dateien müssen alle deklarierten Pattern- und
  Samplebytes enthalten. Abgeschnittene Dateien werden abgelehnt, statt fehlende
  Noten mit Stille oder PCM-Daten gekürzt zu erfinden.
- S3M-Sampledaten werden vor dem Dekodieren gegen Framezahl, Bitbreite und
  Stereo-Aufbau geprüft. Abgeschnittene Samples erscheinen nicht mehr als
  verkürzte oder leere Instrumente.
- Der erste S3M-Endmarker beendet jetzt wirklich die Order-Liste. Einträge
  dahinter werden nicht mehr gespielt; Positionssprünge in diesen Rest führen
  zum Songende.
- Der Browserplayer lehnt ein signiertes MOD mit Songlänge null mit einer
  endlichen Parsermeldung ab, statt im Audio-Worklet fortlaufend zu scheitern.

## Archive und Bibliothek

- Der Desktop-Playlist-Scanner ignoriert symbolische Links, die beim Entpacken
  eines Archivs entstehen. Ein verlinktes Modul oder inneres Archiv kann den
  Scan nicht mehr aus seinem temporären Entpackverzeichnis führen.
- Der iOS-ZIP-Reader lehnt symbolische Links und verschlüsselte Einträge im
  gesamten Inhaltsverzeichnis ab, auch wenn ein Dateifilter sie sonst
  überspringen würde.
- Ein unvollständiger iOS-Dateisystemscan ergänzt neu gefundene Archive in der
  bekannten offenen Liste und behält ältere Einträge. Ein erreichbares Archiv
  bleibt nicht mehr unsichtbar, nur weil ein anderer Teilbaum unlesbar war.

## Prüfungen und Werkzeuge

- Ein benannter iOS-Simulator wird zu seiner UUID aufgelöst. Damit funktioniert
  auch ein gewähltes Gerät aus einer älteren installierten Laufzeit, statt
  fälschlich `OS:latest` zu verlangen.
- Die Kommandozeilentests erreichen und prüfen jetzt die echten
  Fehlwert-Zweige von `--seconds`, `--rate` und `--pattern`.
- Die Parser-Grenztests des Browserplayers laufen in CI, zusätzlich zur
  Worklet-Parität und zur Prüfung des erzeugten HTML-Bundles.

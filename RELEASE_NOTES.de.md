Savage Mod Player 1.6.18 begrenzt den Ressourcenbedarf beschädigter IT-Dateien
und schützt die Bibliothek vor bestehenden Symlinks im Zielpfad. Ping-Pong-Wiedergabe,
IT-Ordersprünge und Stereo-Sampleexport sind korrigiert. Pause und neuere Auswahlen
entwerten ausstehende Ladeaufträge; Favoritenlisten aktualisieren sich sofort.
Der Desktop-Tracker zeichnet neue Module neu. Der Webplayer setzt Stimmen beim
Titelwechsel zurück, erhält endliche Pattern-Loops und navigiert anhand der gewählten
Datei. Quick Look erneuert Audiocaches nach Updates. Linux-Desktop-Einträge verwenden
den installierten Programmpfad; die DMG-Bereinigung hängt nur ihr eigenes Volume aus.
Der DMG-Bau übernimmt den tatsächlichen Mountpunkt und wartet vor dem Einrichten
des Installationsfensters, bis Finder das Volume erkennt.

Der Referenzvergleich erhält die Stereoenergie und verwirft irreführende
Zeitverschiebungen mit nur zwei überlappenden Hüllkurvenwerten.

Savage Mod Player 1.6.17 zeigt auf breiten iPads bis zu acht Kanal-Oszilloskope nebeneinander. Die Höhenberechnung verwendet dieselbe verfügbare Breite wie die Wiedergabespalte.

Savage Mod Player 1.6.16 nutzt die freie Höhe der iPad-Wiedergabespalte
für das Master- und die Kanal-Oszilloskope. Auf dem iPhone bleiben die Größen
erhalten; Module mit vielen Kanälen lassen sich weiterhin scrollen. Der DMG-Bau
prüft außerdem, dass Finder die vorgesehene Fenstergröße beibehält, und setzt
die Icons oberhalb der Beschriftungen der Hintergrundgrafik.

Savage Mod Player 1.6.15 ist eine Korrekturausgabe. Sie erhält schnelle
Tempoänderungen, meldet unvollständige Bibliotheksläufe ehrlich und weist
Sonderdateien ab, bevor die CLI an ihnen hängen kann.

## Wiedergabe

- BPM und Speed gelangen jetzt über getrennte atomare Aufträge zum
  Audio-Callback. Eine spätere Änderung kann keinen veralteten Wert des anderen
  Reglers mehr mitführen; die Oberfläche behält jeden gewünschten Wert, bis der
  Audio-Callback seine Übernahme veröffentlicht hat. Auch die späte Bestätigung
  eines alten Audioblocks kann keinen bereits durch einen Seek überholten
  Tempoauftrag wieder aktivieren.
- Der Visualizer verbraucht den Spitzenpegel jedes Audioblocks genau einmal.
  Ein schnellerer Oberflächen-Poller lässt die letzte Wellenform stehen, wendet
  aber dieselbe VU-Attacke nicht mehrfach an.

## Dateien und Kommandozeile

- Scheitert die Dateityp-Abfrage, gilt ein Bibliotheks-Scan als unvollständig,
  statt einen bekannten und weiterhin vorhandenen Titel still zu entfernen.
  Rekursive Importe melden den betroffenen relativen Pfad, statt das Kind
  spurlos auszulassen. Lässt sich ein Modul nicht für seinen Fingerabdruck
  lesen, gilt der Abgleich ebenfalls ausdrücklich als unvollständig, statt
  einen veralteten Indexeintrag hinter einem scheinbaren Erfolg zu verbergen.
- Ein Abbruch während eines koordinierten iCloud- oder File-Provider-Lesewegs
  wird nach dem Hashen oder Kopieren als Abbruch gemeldet.
- Direkte CLI-Eingaben werden nichtblockierend geöffnet und vor dem Lesen mit
  `fstat` geprüft. Eine benannte Pipe wie `stream.mod` scheitert bei Analyse und
  Live-Wiedergabe sofort, statt unbegrenzt auf einen Schreiber zu warten.

## Bau und Prüfung

- Die Visualizer-CPU-Messung unterscheidet eine fehlende Voreinstellungs-Domain
  von einer gescheiterten Sicherung. Sie ändert nach einem Backupfehler nichts,
  erhält die Sicherung nach einem Wiederherstellungsfehler und beendet nur den
  selbst gestarteten Prozess.
- Der statische Linux-Bau behandelt Rootless- und User-Namespace-Docker
  ausdrücklich, verschluckt keine Besitzfehler mehr und prüft danach vom Host
  aus jedes Artefakt unter `.build`.
- Automatische Regressionstests decken jetzt Wiedergabe, Bibliothek, Import,
  iOS, CLI, Linux-Baulogik, weitere Bauskripte und den Browserpfad ab.

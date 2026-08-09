Savage Mod Player 1.6.6 härtet rekursive Archivimporte, beseitigt zwei
Nebenläufigkeitsfehler in der Wiedergabe und schließt die verbliebenen
XM-Abschneidepfade.

## Bibliothek und Archive

- Rekursive Importe teilen sich jetzt eine Obergrenze für entpackte Bytes,
  Archiveinträge und die Archivzahl über den gesamten Verschachtelungsbaum.
  Die Grenzen gelten für den eigenen ZIP-Reader ebenso wie für bsdtar auf
  macOS/Linux; innere Archive starten nicht mehr mit frischen 2 GiB und 50.000
  Einträgen.
- bsdtar-Archive werden vor dem Schreiben streamend vermessen. Symbolische
  Links werden vor der Verzeichnis- oder Endungsprüfung abgelehnt; ein
  `inner.zip` im Zwischenlager kann damit nicht aus dem Entpackordner zeigen.
- Versteckte unterstützte Module und innere Archive werden verarbeitet, statt
  still zu fehlen. Das Quellarchiv verschwindet weiterhin erst, wenn alle
  unterstützten Inhalte erfolgreich behandelt wurden.
- Ein unvollständiger Abgleich nach einem teilweise gescheiterten
  Bibliotheks-Reset bleibt als unvollständig erkennbar. Die iPhone-App vereinigt
  dessen Teilmenge mit der bekannten Liste offener Archive, statt die Liste
  durch fehlende Daten zu ersetzen.

## Wiedergabe-Korrektheit

- Der offene Auftrag zum Zurücksetzen der Spielzeit ist ein lockfreier
  C11-Atomik-Sentinel und wird per atomarem Austausch genau einmal verbraucht.
  Das funktioniert weiterhin ab macOS 13 und unter Linux.
- Frame, Position und Zeile eines Songendes werden als vollständiger atomarer
  Schnappschuss geschrieben, bevor das Bereitschaftssignal sichtbar wird. Die
  Oberfläche kann kein altes oder halb geschriebenes Loop-Ziel mehr lesen.
- Der Titel-Loop auf macOS setzt die sichtbare Spielzeit jetzt am tatsächlichen
  Loop-Punkt zurück und aktualisiert die systemweite Wiedergabeinformation
  sofort — wie bereits die iPhone-App.
- XM-Wiedergabe und Instrumentvorschau begrenzen Note plus Sample-Transpose
  gemeinsam auf 0...119, bevor lineare oder Amiga-Perioden berechnet werden.
  Das gilt auch für extreme vorzeichenbehaftete Transpositionen.

## Parser und Veröffentlichungshygiene

- Der XM-Parser verlangt den vollständigen festen 80-Byte-Header, jeden
  deklarierten Pattern-Kopf auch bei Datengröße null, jeden Instrument-Kopf,
  mindestens 40 Byte pro Sample-Kopf und das vollständige deklarierte
  PCM-Fenster. Ungerade Byte-Längen bei 16-Bit-Samples werden abgelehnt.
- Das Veröffentlichungs-Gate inventarisiert jede getrackte, als UTF-8 lesbare
  Textdatei einschließlich Swift, JavaScript, HTML, JSON und CI-YAML statt nur
  Markdown-, Shell- und Python-Dateien.
- Der optionale ZIP-Digital-Signature-Datensatz ist korrekt als Datensatz am
  Ende des ZIP-Inhaltsverzeichnisses dokumentiert.

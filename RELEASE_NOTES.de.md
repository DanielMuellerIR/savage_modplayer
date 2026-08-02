Savage Mod Player 1.6.5 ist ein Korrektheits- und Robustheits-Release über
alle Zielplattformen: ein hörbarer XM-Stimmungsfix, strengere Parser und
ZIP-Verarbeitung, ein sichererer Bibliotheks-Import sowie kleinere Fixes in
der iPhone-App, im CLI und in den Build-Skripten.

## Wiedergabe-Korrektheit

- XM-Module mit Amiga-Frequenztabelle spielen jetzt in der Tonhöhe, die
  FastTracker II definiert (Frequenz = 8363 × 1712 / Periode). Bisher wurden
  sie gegen die Amiga-PAL-Clock gerechnet und klangen rund zwei Oktaven zu
  tief. Module mit linearer Frequenztabelle sind nicht betroffen.
- Ein S3M-Header-Global-Volume von 0 gilt jetzt als bewusst stummer Start.
  Die einzige dokumentierte Realwelt-Ausnahme bleibt: Dateien aus Scream
  Tracker vor 3.20 speichern 0 oft als „nicht gesetzt" und behalten volle
  Lautstärke.
- Im Titel-Loop der iPhone-App springt die angezeigte Spielzeit (App und
  Sperrbildschirm) am Loop-Punkt zurück, statt die Titeldauer zu überholen.

## Strengere Parser und ZIP-Verarbeitung

- Der S3M-Parser validiert die deklarierte Länge jedes gepackten Patterns und
  lehnt abgeschnittene Patterns ab, statt stillschweigend Sampledaten als
  Noten-Events zu lesen.
- Der XM-Parser lehnt abgeschnittene Header und Dateien ab und behandelt
  Pattern-Zellen, die über die deklarierten Pattern-Daten hinausragen, als
  Korruption.
- Der ZIP-Reader erzwingt sein Eintragslimit bereits beim Einlesen des
  Inhaltsverzeichnisses, gleicht es gegen den EOCD-Datensatz ab und lehnt
  Einträge ab, die dieselbe Zieldatei treffen würden — auch Schreibweisen,
  die nur auf case-insensitiven Dateisystemen kollidieren. Zieldateien werden
  exklusiv angelegt, nie überschrieben.

## Bibliotheks-Import

- Ein Quellarchiv wird nur nach vollständig erfolgreicher Übernahme gelöscht:
  kein Abbruch, keine Fehler und mindestens eine übernommene Datei. Archive
  ohne spielbaren Inhalt, teilweise übernommene Archive und Einträge mit
  nicht unterstützter Kompressionsmethode lassen das Original nicht mehr
  verschwinden.
- Ein Abbruch wird über die gesamte Kette als solcher erkannt (auch beim
  Warten auf Cloud-Dateien) und nicht mehr als Dateifehler gemeldet.
- Unlesbare Quellordner erscheinen im Bericht statt still zu fehlen, ein
  unterbrochener Dateisystem-Abgleich entfernt keine bekannten Einträge mehr
  aus dem Index, und ein teilweise gescheitertes Zurücksetzen baut den Index
  aus dem tatsächlich verbliebenen Bestand neu auf.
- Das Entpacken auf macOS und Linux (bsdtar) lässt sich jetzt abbrechen.
- Archive, deren Name dem Amiga-Präfix `mod.` entspricht (etwa
  `mod.collection.zip`), gelten überall als Archiv und werden entpackt, statt
  als unspielbare „Moduldatei" importiert zu werden.

## Quick Look

- Der Vorschau-Cache-Schlüssel entsteht aus genau den Bytes, die gelesen und
  gerendert wurden. Eine an Ort und Stelle ersetzte Datei — selbst mit
  identischer Größe und Änderungszeit — kann nicht mehr die Audiodaten der
  Vorgängerdatei aus dem Cache liefern.

## CLI

- `--play` mit `--seconds 0` respektiert jetzt die dokumentierte
  600-Sekunden-Kappung, statt einen Loop endlos zu spielen.
- `--play` lehnt `--out`, `--stdout`, `--normalize` und `--rate` ab, statt
  sie still zu ignorieren.

## iPhone-App

- „Zurück" über eine defekte Datei sucht jetzt rückwärts weiter, statt wieder
  vorwärts zum aktuellen Titel zu springen.
- Ein pausierter Titel behält seine Position auch nach einem Neustart der
  Systemaudiodienste mit anschließendem App-Neustart.
- Fehler und offene Archive erscheinen auch bei leerer Bibliothek — ein
  gescheitertes Auspacken der einzigen ZIP-Datei ist damit sichtbar und
  wiederholbar.

## Build-Skripte und CI

- `release.sh`, `install.sh` und `ios/scripts/build-device.sh` parsen alle
  Argumente, bevor irgendetwas passiert: `--help` antwortet sofort, und
  unbekannte Optionen brechen ab, statt Builds, Notarisierung oder
  Installation anzustoßen.
- Der Notarisierungs-Helfer räumt sein Temp-Verzeichnis auf jedem Fehlerpfad
  auf, und `release.sh` entfernt ein altes DMG vor dem Lauf, damit die
  Erfolgsprüfung wirklich diesen Lauf belegt.
- CI baut zusätzlich das App-Bundle samt Quick-Look-Erweiterung (unsigniert),
  führt die UI-Quelltests aus und baut und testet die iPhone-App gegen das
  Simulator-SDK.

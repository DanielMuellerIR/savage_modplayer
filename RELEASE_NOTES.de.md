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
  Sie springt jetzt auf den Punkt, an dem wirklich weitergespielt wird — bei
  einem rückwärts gerichteten Bxx-Sprung also auf dessen Ziel und nicht auf
  den Neustartpunkt aus dem Modulkopf. Der Sperrbildschirm zeigt die neue Zeit
  sofort, nicht erst beim nächsten Anzeige-Takt.
- Die Instrument-Vorschau von XM-Modulen klingt jetzt genauso gestimmt wie
  dieselbe Note im abgespielten Modul. Sie lief bisher über die MOD-Rechnung
  (Periode 214 gegen die Amiga-Clock) und war deutlich verstimmt; beide
  XM-Frequenzmodi sind abgedeckt.

## Strengere Parser und ZIP-Verarbeitung

- Der S3M-Parser validiert die deklarierte Länge jedes gepackten Patterns und
  lehnt abgeschnittene Patterns ab, statt stillschweigend Sampledaten als
  Noten-Events zu lesen.
- Der XM-Parser lehnt abgeschnittene Header und Dateien ab und behandelt
  Pattern-Zellen, die über die deklarierten Pattern-Daten hinausragen, als
  Korruption. Auch Pattern-Köpfe und Pattern-Daten müssen vollständig in der
  Datei liegen, und nicht-leere Pattern-Daten müssen alle deklarierten Zellen
  enthalten — eine abgeschnittene Datei gilt damit nirgends mehr als gültiges,
  teilweise stummes Modul.
- Der ZIP-Reader erzwingt sein Eintragslimit bereits beim Einlesen des
  Inhaltsverzeichnisses, gleicht es gegen den EOCD-Datensatz ab und lehnt
  Einträge ab, die dieselbe Zieldatei treffen würden — auch Schreibweisen,
  die nur auf case-insensitiven Dateisystemen kollidieren. Zieldateien werden
  exklusiv angelegt, nie überschrieben.
- Der ZIP-Reader akzeptiert den optionalen Digital-Signature-Datensatz am Ende
  des Inhaltsverzeichnisses (ZIP-Spezifikation 6.3.10, Abschnitt 4.3.13);
  standardkonform signierte Archive galten bisher als beschädigt. Ungültige
  Obergrenzen (etwa eine negative Eintragszahl) liefern jetzt einen normalen
  Fehler, statt das Programm zu beenden.

## Bibliotheks-Import

- Ein Quellarchiv wird nur nach vollständig erfolgreicher Übernahme gelöscht:
  kein Abbruch, keine Fehler und mindestens eine übernommene Datei. Archive
  ohne spielbaren Inhalt, teilweise übernommene Archive und Einträge mit
  nicht unterstützter Kompressionsmethode lassen das Original nicht mehr
  verschwinden.
- Ein Archiv im Archiv wird bis zu drei Ebenen tief mit ausgepackt. Bisher
  blieb sein Inhalt liegen, während das äußere Quellarchiv als vollständig
  übernommen galt und gelöscht wurde — die letzte Kopie war damit weg.
- Ein Abbruch wird über die gesamte Kette als solcher erkannt (auch beim
  Warten auf Cloud-Dateien) und nicht mehr als Dateifehler gemeldet.
- Unlesbare Quellordner erscheinen im Bericht statt still zu fehlen, ein
  unterbrochener Dateisystem-Abgleich entfernt keine bekannten Einträge mehr
  aus dem Index, und ein teilweise gescheitertes Zurücksetzen baut den Index
  aus dem tatsächlich verbliebenen Bestand neu auf.
- Lässt sich der Verzeichnis-Abgleich gar nicht erst starten, gilt er als
  unvollständig; vorher wurde daraus ein leerer Bestand abgeleitet und der
  ganze Index gelöscht. Beim Zurücksetzen erscheint eine nicht auflistbare
  Bibliothekswurzel im Bericht, der bisherige Index bleibt bis zu einem
  nachweislich vollständigen Wiederaufbau erhalten, und ein Fehler in einem
  Temp-/Cache-Verzeichnis hebelt die Option „Indexdatei löschen" nicht mehr aus.
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
- `--play` läuft auch mit Ausgabegeräten über 192 kHz. Die Echtzeitausgabe
  streamt und braucht kein Offline-Speicherbudget; die dortige
  Sampleraten-Obergrenze beendete die Wiedergabe bisher vor dem ersten Ton.

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
  auf. Ein altes DMG entfernt `build_dmg.sh` vor jeder Erzeugung; die
  Erfolgsprüfung in `release.sh` belegt damit wirklich diesen Lauf.
- CI baut zusätzlich das App-Bundle samt Quick-Look-Erweiterung (unsigniert),
  führt die UI-Quelltests aus und baut und testet die iPhone-App gegen das
  Simulator-SDK.

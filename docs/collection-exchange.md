# Portables Sammlungsformat

Seit 1.6.47 stellt der gemeinsame Core das Austauschformat bereit; seit 1.6.48
sind Export und Import auf macOS und iPhone/iPad vorhanden. Das Format überträgt Metadaten zwischen
Sammlungen; es kopiert keine Musik und löst keine Pfade im Dateisystem auf.

## Native Bedienung

Am Mac öffnet **Sammlung → Sammlung übertragen…** oder die Schaltfläche neben
Playlists und Warteschlange den Dialog. Auf iPhone/iPad liegt **Sammlung übertragen**
im Bibliotheksmenü. **Sammlung exportieren…** verwendet den nativen Speicherdialog.
Die Datei kann separat kopiert oder geteilt und auf dem Zielgerät geöffnet werden.
**Austauschdatei importieren…** und das Öffnen einer `.savagecollection`-Datei
führen zuerst zur Vorschau, ohne Musik zu starten oder zu importieren.

Eindeutige Zuordnungen sind Vorschläge, keine Inhaltsbestätigung. Namen, relative
Pfade und Dateigrößen helfen bei der Auswahl; die Oberfläche berechnet keine
Audio-Fingerabdrücke. Fehlende oder mehrdeutige Titel einzeln auswählen oder
bewusst überspringen. Die lokale Suche zeigt höchstens 500 Treffer; bei größeren
Sammlungen die Suche eingrenzen. **Werte vergleichen** zeigt für Konflikte den
vorhandenen und den eingehenden Stand. **Übernehmen** ist erst bei vollständig
entschiedener Vorschau verfügbar. Lautstärke, laufende Timer, Warteschlange und
Musikdateien bleiben lokal. Globale Klangwerte und Titel-Overrides werden nur
entsprechend der bestätigten Vorschau geändert.

Ein geänderter Ausgangsstand verlangt eine neue Vorschau. Abbrechen verändert
keine Sammlungsdaten. Drei Metadatendateien und betroffene Voreinstellungen werden
mit einem begrenzten lokalen Journal übernommen; nach einer Unterbrechung erfolgt
die Wiederherstellung vor dem Aufbau der Bibliothek. Beschädigte oder fremd
veränderte Wiederherstellungsdaten bleiben erhalten und sperren weitere
Übernahmen, bis die Wiederherstellung gelingt.

## Datei und Grenzen

Die UTF-8-JSON-Datei verwendet die Endung `.savagecollection`, den Bezeichner
`org.savage-mod-player.collection` und `formatVersion: 1`. Datei-ID und
Erstellungszeit beschreiben den Export, nicht eine automatisch synchronisierte
Sammlung. Zeitangaben stehen als ISO-8601-UTC mit Sekundengenauigkeit in der Datei.
Unbekannte Versionen werden abgelehnt. Unbekannte JSON-Felder werden ignoriert
und nicht weiterexportiert; fehlende Pflichtfelder, falsche Typen, doppelte IDs
und nicht vorhandene Referenzziele machen die Datei ungültig.

Das Lesen ist auf reguläre Dateien und 32 MiB begrenzt, auch wenn die Datei beim
Lesen wächst. URLs zu Netzquellen, Verzeichnisse und benannte Pipes werden
abgelehnt. Zusätzlich gelten höchstens 20.000 Titel, 1.000 Playlists,
100.000 Playlist-Einträge insgesamt, 50.000 pro Liste, 10.000 Marker und je
20.000 Favoriten beziehungsweise Titel-Einstellungen. Ein konservatives
Text-/Strukturbudget begrenzt auch das Erzeugen großer Ausgaben. Beschädigte
Daten werden nicht als leere Sammlung behandelt.

## Inhalt und Titelidentität

- `tracks`: Titel mit eigenen UUIDs und einem `descriptor`. `fileName` ist ein
  einzelner Dateiname; `relativePath` ist ein optionaler bibliotheksrelativer
  Hinweis. `archiveMembers` beschreibt jede verschachtelte Archivebene separat.
  Optional enthalten `byteCount` und ein kleingeschriebener SHA-256-Hexwert einen
  Inhaltsnachweis. Diese Werte berechnet der Aufrufer; der Codec liest keine Musik.
- `playlists`: stabile Listen-UUIDs, Namen und geordnete Titel-UUIDs. Eine Liste
  enthält denselben Titel höchstens einmal. Die Reihenfolge bleibt unverändert.
- `favoriteTrackIDs`: eine Menge positiver Favoritenmarkierungen.
- `markers`: stabile Marker-UUIDs, Titel-UUID, Name, Erstellungszeit und
  `address` mit Songposition und Zeile. Unterschiedliche Orders desselben
  Patterns bleiben unterschiedliche Adressen. Die konkrete Erreichbarkeit
  lässt sich erst am zugeordneten Modul prüfen.
- `trackSettings`: Titel-UUIDs und partielle `overrides` für `palClock`,
  `stereoSeparation`, `useInterpolation` und `ledFilterActive`. Ein fehlender
  Wert erbt die globale Vorgabe; `false` bleibt ein ausdrücklicher Wert.
- `playbackDefaults`: optional alle vier globalen Klangwerte. Stereo-Separation
  liegt zwischen 0 und 1. Clock bleibt bei Formaten ohne wählbare Paula-Clock
  wirkungslos, wie bei den lokalen Titel-Einstellungen.

Lokale Quellen-IDs, absolute Pfade, Container-URLs, Audio, Metadaten-Caches,
Warteschlange, Lautstärke, aktive Timer und Geräte-/Oberflächeneinstellungen
gehören nicht zum Format. Exportreferenzen entstehen ausschließlich aus einer
ausdrücklich übergebenen portablen Zuordnung. Fehlt diese für einen verwendeten
Titel, scheitert der Export sichtbar. Relative Pfade verbieten leere Segmente,
`.`/`..`, absolute Wurzeln, Laufwerks-/URL-Präfixe, Backslashes und Steuerzeichen.
Ein Dateiname ist auf 1.024 UTF-8-Bytes, ein relativer Pfad auf 4.096 begrenzt;
Archivtiefe und Archivpfade folgen den Grenzen des vorhandenen Scanners.
Namen von Listen und Markern dürfen höchstens 200 Zeichen/800 UTF-8-Bytes haben.

## Zuordnung und Konflikte

Der Matcher liefert einen eindeutigen Kandidaten, mehrere Kandidaten oder
„fehlend“. Ein vorhandener SHA-256-Wert verlangt einen passenden Inhaltsnachweis;
ein Dateiname ersetzt diesen Nachweis nicht. Ohne Hash dienen zunächst exakter
relativer Pfad und Archivkette, danach der Dateiname als Vorschlag. Ein vorhandener
Byteumfang muss übereinstimmen. Namen und Pfade sind Hinweise, kein Beweis für
identischen Inhalt. Mehrere Kopien mit gleichem Hash bleiben mehrdeutig.
Gemeinsame Indizes begrenzen die Sucharbeit. Bei Mehrdeutigkeit enthält das
Ergebnis höchstens acht Vorschläge und die vollständige Trefferzahl; weitere
Zuordnungen kann die Oberfläche aus dem vorhandenen lokalen Katalog anbieten.

Eine Importvorschau verändert keinen Speicher. Jeder Titel braucht eine lokale
Zuordnung oder die ausdrückliche Entscheidung, ihn zu überspringen. Zwei
Austausch-Titel dürfen nicht auf dieselbe lokale Quelle zusammenfallen.
Überspringen entfernt nur die betreffenden eingehenden Referenzen aus diesem
Import; vorhandene Daten bleiben erhalten.

Favoriten werden ergänzt; eine fehlende Markierung löscht keinen lokalen
Favoriten. Gleiche Listen-/Marker-IDs mit geändertem Inhalt verlangen „Lokal
behalten“, „Übernehmen“ oder „Beide behalten“. Kopien erhalten neue IDs, und
Listen erhalten einen freien Namenszusatz. Gleiche Listennamen bei verschiedenen
IDs erlauben nur Behalten oder eine zusätzliche umbenannte Liste; der Name allein
rechtfertigt kein Ersetzen. Unterschiedliche Titel-Overrides und globale
Klangwerte verlangen Behalten oder Übernehmen. Zeitstempel wählen keinen Gewinner.
Gleiche Marker-ID, Quelle, Name und Adresse gelten unabhängig von der
Zeitauflösung als derselbe Marker. Wiederholter Import unveränderter Daten
erzeugt keine zusätzlichen Listen oder Marker.

Der fertige Vorschauplan hält den Ausgangsstand fest. `result(ifUnchanged:)`
prüft ihn vor der Übernahme vollständig; jede zwischenzeitliche Änderung verlangt
eine neue Vorschau. Offene Zuordnungen oder Konfliktentscheidungen verhindern
ein Ergebnis. Der Core liefert ausschließlich einen validierten neuen Snapshot;
die native Integration verlangt eine ausdrückliche Bestätigung und übernimmt
die lokalen Speicher gemeinsam mit den betroffenen Voreinstellungen über ein
Wiederherstellungsjournal. Es gibt keine automatischen Löschungen und keine Synchronisation.

## Prüfung

`swift test --filter CollectionExchangeTests` prüft den Hin-/Rückweg zwischen
synthetischen Mac- und iPhone-Quellen, Reihenfolge, Favoriten, Markeradressen (nullbasierte Order und Zeile),
explizite `false`-Overrides, Konflikte, unveränderte Wiederholungsimporte und
veraltete Vorschauen. Weitere Fälle decken Namenskollisionen, verschachtelte
Archive, Hashwidersprüche, fehlerhafte Referenzen, Grenzen, Daten-Slices,
benannte Pipes und zu große reguläre Dateien ab. Dieselben Tests laufen auf Linux;
eine Dateitransfer- oder Geräteabnahme ist damit noch nicht belegt.

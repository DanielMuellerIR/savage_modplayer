# Modul-Metadatenindex

Der gemeinsame Core stellt `ModuleMetadataIndex` für die native Bibliothek bereit.
Die Such-/Sortieroberflächen werden separat darauf aufgebaut. Ein Actor
serialisiert Datei-, Parser- und Cachearbeit außerhalb von UI und Audiothread.
Der Index enthält keine PCM-Daten und verändert keine Musikdateien.

Eingaben bestehen aus einer stabilen Quellen-ID und der aktuellen Datei-URL.
iOS verwendet die relativen Bibliotheksreferenzen; macOS kann Originalquellen
einschließlich Archivmitgliedern unterscheiden. Temporäre Dateikopien sind
keine dauerhaften IDs.

Pro Titel werden interner Name, exaktes Trackerformat, Kanalzahl, belegte
Instrumente, nicht leere PCM-Samples, Patternzahl, Instrumentnamen und Spieldauer
ermittelt. Instrumentnamen können auch Text-/Copyrightzeilen enthalten; sie
sind keine verlässlichen Künstlerangaben. IT-Instrumente mit Tastenzuordnung
oder Instrumenteigenschaften zählen unabhängig vom getrennten Samplepool.

Die Dauerprobe verwendet den bestehenden Sequencer-Probenpfad und endet spätestens
bei 600 Sekunden. `durationIsLimited` kennzeichnet ein Ergebnis an dieser Grenze;
es darf nicht als exakte Gesamtdauer angezeigt werden. Ein Abbruch wird vor und
nach Lesen/Parsen/Dauerprobe sowie zwischen Leseblöcken geprüft. Eine bereits
laufende einzelne Parser-/Dauerprobe wird noch beendet, ihr Ergebnis danach
verworfen. Teilfortschritt darf gespeichert werden; nicht besuchte Einträge
bleiben erhalten.

Unveränderte Dateien werden anhand von Größe, Gerät/Inode und nanosekundengenauer
Änderungszeit wiederverwendet. Nach dem Lesen wird derselbe Stand erneut am Pfad
geprüft. Ein Austausch währenddessen liefert ein erneut zu prüfendes Ergebnis.
Ändern sich Bytes unter absichtlich vollständig erhaltenen Dateiattributen, kann
der Cache dies nicht erkennen; ein Neuaufbau des Caches liest die Datei erneut.

Grenzen: 64 MiB pro Moduldatei, 50.000 Einträge und 32 MiB Cache. Überlange
Quellenangaben werden schon vor dem JSON-Encoding konservativ begrenzt. Erreichte
Grenzen und Speicherfehler sind im Ergebnis sichtbar. Fehlende, beschädigte und
zu große Dateien erhalten jeweils einen eigenen Zustand. Nicht reguläre Dateien
werden am geöffneten Deskriptor abgelehnt; benannte Pipes dürfen nicht blockieren.

Der versionierte JSON-Cache wird atomar ersetzt. Beschädigte oder anders
konfigurierte Caches sind rekonstruierbar und werden neu aufgebaut. Das unterscheidet
sie von gespeicherten Playlists: Dort bleibt die Datei bei Ladefehlern unangetastet.
`discardUnlisted` ist nur für vollständige Bestands-Snapshots gedacht und wirkt
bei Abbruch oder Kapazitätsüberschreitung nicht.

Prüfung: `swift test --filter ModuleMetadataIndexTests`, anschließend die vollständige
macOS-/Linux-Suite und der App-Build. Die synthetischen Fixtures durchlaufen die
echten MOD-, S3M-, XM- und IT-Parser.

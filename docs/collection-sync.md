# Automatischer Metadatenabgleich: Anbindung und Voraussetzungen

Stand: 2026-10-18. Seit 1.6.51 sind Core, lokale App-Speicheranbindung und
Status-/Zuordnungs-/Konfliktoberflächen für Mac und iPhone/iPad implementiert.
Seit 1.6.52 ist der gemeinsame Container bestätigt; optionale signierte Builds
prüfen die zugehörigen Entitlements und Profile. Standardbuilds lassen den
Cloud-Zugriff ausgeschaltet. Der manuelle
[Sammlungs-Austausch](collection-exchange.md) bleibt unabhängig davon nutzbar.

## Entscheidung und technische Grenze

Vorgesehen ist CloudKit mit einer eigenen Zone in der privaten Datenbank des
Nutzers. Mac und iPhone verwenden denselben ausdrücklich konfigurierten Container.
Es gibt keinen eigenen Server und keinen Zugriff auf die öffentliche Datenbank.
Private CloudKit-Daten setzen einen auf dem Gerät angemeldeten iCloud-Account
voraus. Die App muss ohne diesen Account weiter funktionieren.
[Apple: CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer).

Standardbuilds deklarieren keine CloudKit-Berechtigungen. Seit 1.6.52 können
beide App-Builds nach einer ausdrücklichen Profilprüfung CloudKit aktivieren.
Ein vorhandenes Signierzertifikat oder eine erfolgreiche Notarisierung ersetzt
die benötigten Entitlements und Profile nicht.
Auch außerhalb des Mac App Store kann eine Developer-ID-App CloudKit verwenden;
dafür sind passende Berechtigungen und ein Developer-ID-Provisioning-Profil
notwendig. [Apple: Developer-ID-Zertifikate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).

Vor dem Dienstlauf sind daher ein gemeinsamer Container, die zugehörigen
Berechtigungen für beide App-Targets und gültige Profile bereitzustellen.
Containerbestand und Mitgliedschaft im Entwicklerkonto müssen im Konto selbst
geprüft werden. Aus fehlenden lokalen Profilen folgt nicht, dass dort kein
Container existiert. Neue Container lassen sich nach ihrer Erstellung nicht
umbenennen oder löschen; die Kennung muss vorher feststehen.
[Apple: CloudKit aktivieren](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app).

Das macOS-Minimum bleibt 13. `CKSyncEngine` setzt macOS 14 voraus und ist daher
keine gemeinsame Basisschnittstelle. Der erprobte SDK-Vertrag verwendet stattdessen
`CKRecord`, `CKAsset` und `CKModifyRecordsOperation`, die für macOS 13 und iOS 17
kompilieren. Das ist ein lokaler API-Nachweis, kein erfolgreicher Cloud-Lauf.
[Apple-Beispiel zu CKSyncEngine](https://github.com/apple/sample-cloudkit-sync-engine).

## Übertragene und lokale Daten

Übertragen werden ausschließlich Playlists mit Reihenfolge, Favoriten,
Songstellen, globale Klang-Vorgaben und ausdrücklich gesetzte Titel-Overrides.
Titelbeschreibungen enthalten die begrenzten relativen Hinweise und optionalen
Fingerprints des vorhandenen Austauschformats. Keine Audio-, Sample-, WAV- oder
Videodateien werden übertragen.

Musikpfade, Security-Scoped-Bookmarks, lokale Quellen-IDs, Lautstärke,
Warteschlange, Verlauf, Einschlaftimer und aktuelle Abspielposition bleiben auf
dem Gerät. Die Zuordnung einer globalen Titel-UUID zu einer lokalen Quellen-ID
wird ausschließlich lokal gespeichert. Ein fehlender Musikdatenträger bedeutet
keine Löschung von Cloud-Metadaten. Mehrdeutige oder fehlende Zuordnungen brauchen
eine Entscheidung, bevor Klangwerte oder Songstellen einem lokalen Titel
zugewiesen werden.

Der Abgleich ist standardmäßig aus und wird bewusst aktiviert. Private CloudKit-
Daten liegen im iCloud-Konto des Nutzers; Metadaten wie Titel und Playlistnamen
können persönliche Informationen enthalten. Der Entwurf verspricht keine eigene
Ende-zu-Ende-Verschlüsselung. Die Oberfläche muss Datenumfang, Ausschalten und
Cloud-Löschung erklären. Ausschalten entfernt keine lokale Sammlung und ist
keine Cloud-Löschung.

## Datenmodell und konkurrierende Änderungen

Jede Playlist, Songstelle und jeder globale Titel erhält eine dauerhafte UUID.
Die zufälligen Export-IDs einer einzelnen manuellen Austauschdatei sind dafür
nicht geeignet. Bestehende Playlist-/Songstellen-IDs bleiben erhalten; eine
separate lokale Titelzuordnung verbindet Geräte mit denselben globalen Titeln.
Eine gemeinsame Sammlungs-ID und eine Generation unterscheiden Neueinrichtung,
normalen Abgleich und ausdrücklich bestätigten Cloud-Neustart.

Beim ersten Verbinden werden vorhandene lokale und Cloud-Daten zunächst
gegenübergestellt. Ein Gerät ohne gemeinsame Basis darf eine vorhandene
Cloud-Sammlung nicht als leer überschreiben. Titelzuordnung und Zusammenführung
werden einmal ausdrücklich bestätigt; danach werden die globalen IDs dauerhaft
wiederverwendet. Eine spätere manuelle Austauschdatei bleibt ein eigener Import
und setzt die gemeinsame Cloud-Basis nicht still zurück.

Der erste begrenzte Entwurf speichert einen Metadaten-Snapshot als `CKAsset`
mit Schema, Generation und Revision in einem `CollectionState`-Record. Die
bestehende 32-MiB-Grenze bleibt bestehen. Das verhindert, dass große Listen in
ein einzelnes normales Record-Feld gezwängt werden. Apples archivierte
Serverdokumentation nennt 1 MB je Record ohne Assets und 50 MB je Asset;
Dienstfehler und tatsächliche Grenzen müssen beim echten Lauf zusätzlich
geprüft werden. [Apple: Größenlimits](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html).

Der Client behält die zuletzt bestätigte gemeinsame Basis und vergleicht drei
Stände: Basis, lokale Sammlung und neu gelesene Cloud-Sammlung. Die Regel je
atomarer Einheit lautet:

| Vergleich | Ergebnis |
|---|---|
| Lokal und Cloud gleich | Diesen Wert behalten. |
| Lokal unverändert gegenüber der Basis | Cloud-Wert übernehmen. |
| Cloud unverändert gegenüber der Basis | Lokalen Wert übernehmen. |
| Beide unterschiedlich geändert | Konflikt anzeigen, nichts veröffentlichen. |

Eine Playlist einschließlich Name und Reihenfolge ist eine atomare Einheit;
ebenso eine Songstelle mit Name und Position. Gleichzeitiges Umbenennen und
Umordnen derselben Playlist braucht damit eine Entscheidung. Es entsteht keine
unbeabsichtigte Mischreihenfolge. Favoriten und einzelne Klangfelder können
unabhängig zusammengeführt werden. „Vorgabe erben“, fehlender Wert und bewusste
Löschung sind getrennte Zustände.

Löschungen bleiben als ausdrückliche Tombstones erhalten. Ein lange offline
gebliebenes Gerät darf einen unveränderten alten Eintrag nicht wiederherstellen.
Löschen gegen Bearbeiten wird als Konflikt gezeigt. Tombstones werden nicht
allein aufgrund ihres Alters entfernt. Eine spätere Bereinigung benötigt eine
bestätigte neue Generation und einen festgelegten Umgang mit alten Geräten.
Grenzen für Titel, Einträge, Songstellen und Bytes gelten auch für diese Zustände;
bei Überschreitung stoppt der Abgleich mit Erklärung.

Eine reine Uhrzeit entscheidet keinen Konflikt. Geräteuhren können falsch sein.
Vor jeder Veröffentlichung wird der gelesene Cloud-Change-Tag mit
`.ifServerRecordUnchanged` geprüft. Ändert ein anderes Gerät den Record
zwischen Lesen und Schreiben, meldet CloudKit `serverRecordChanged`; der Client
liest neu und berechnet den Merge erneut. Kein bedingungsloses Überschreiben.
[Apple: Save-Policy](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged).

## Offline, Neustart und Kontowechsel

Lokale Metadaten werden zuerst regulär gesichert. Basis, Generation und
Konto-Zuordnung bleiben dauerhaft gespeichert, damit lokale Änderungen auch
nach einem Neustart erneut erkennbar sind. Der Versand verwendet ein eigenes,
begrenztes Arbeitsverzeichnis; Asset-Dateien leben bis zum Abschluss der
Operation. Gleichzeitige lokale Dateiänderungen machen eine vorbereitete
Übernahme ungültig.

Nach erfolgreicher Cloud-Veröffentlichung wird die lokale Übernahme mit dem
vorhandenen Wiederherstellungsjournal durchgeführt. Erst danach wird die neue
gemeinsame Basis bestätigt. Ein Absturz zwischen Veröffentlichung und Bestätigung
führt beim nächsten Lauf erneut durch den idempotenten Merge. Ein defekter oder
unerwartet fehlender lokaler Metadatenspeicher darf nicht als leere Sammlung
hochgeladen werden. Dasselbe gilt für ein unerwartet verschwundenes Cloud-Record
nach bereits erfolgtem Abgleich: erst Wiederherstellung oder ausdrückliche
Neustartentscheidung.

Bei Abmeldung oder Kontowechsel stoppen laufende Übertragungen. Eine lokale
Konto-Generation verwirft spät eintreffende Ergebnisse. Ausstehende Änderungen
werden nicht still in ein anderes iCloud-Konto übertragen. Lokale Musik und
Metadaten bleiben erhalten; das Verknüpfen mit dem neuen Konto braucht eine
neue Vorschau und Bestätigung. Konto-Kennungen gehören nicht in normale Logs.

Automatischer Abgleich bedeutet zunächst Abgleich beim Aktivieren der App und
nach zusammengefassten lokalen Änderungen, ergänzt um „Jetzt abgleichen“.
Hintergrundzustellung ist ein eigener Dienst-/Gerätenachweis; eine bestimmte
Latenz oder Ausführung bei beendeter App wird nicht zugesagt. Netzwerk-, Quota-
und Drosselungsfehler behalten lokale Änderungen und respektieren
`retryAfterSeconds`. Kein enger Wiederholungsloop.

## Status und Abnahmekriterien

Die spätere Oberfläche unterscheidet „Aus“, „Einrichtung fehlt“, „Nicht
angemeldet“, „Offline – Änderungen warten“, „Wird abgeglichen“, „Konflikt braucht
Entscheidung“, „Aktuell“ und einen erklärten Fehler mit Wiederholungsmöglichkeit.
Während einer manuellen Sammlungs-Vorschau wird keine automatische Übernahme
in deren Grundlage geschrieben. Live-Wiedergabe, Timer und Warteschlange sind
vom Abgleich unabhängig.

Die lokale technische Erprobung besteht für 14 synthetische Szenarien mit 64
vollständig kombinierten Einzelwert-Vergleichen: unabhängige Änderungen,
gleichzeitige Reihenfolgen, Löschung, Löschen gegen Bearbeiten, Wiederholung,
veraltete Schreibversuche, Neustart, Absturz vor Bestätigung, Kontowechsel,
fehlende Musik, defekte/zukünftige Schemas, Vererbung und 20.000 Titel. Der native
SDK-Vertrag für Metadaten-Asset, bedingtes Schreiben und archivierte Systemfelder
besteht lokal; er wurde für macOS 13 und iOS 17 kompiliert. Ein echter
CloudKit-Leseversuch und die Einrichtungs-Vorschau bei noch fehlender privater
Zone bestehen. Die Vorschau darf weder die Zone anlegen noch Daten senden.
Der echte schreibende Entwicklungs-Rundweg Mac → iPhone → Mac besteht mit
synthetischen Daten: Playlistname, Favorit, Songstelle und Klang-Override werden
übernommen; globale IDs, Titelreihenfolge und lokale Lautstärke bleiben erhalten.
Der Mac-Neustart erhält die übernommenen Daten. Die ursprünglichen Apps und
Einstellungen wurden nach der Prüfung wiederhergestellt.

Das geprüfte `CollectionState`-Schema ist nach Production bereitgestellt. Der
korrekt konfigurierte, notarisierte Mac-Build 1.6.52 besteht die native Abnahme
ohne angemeldetes iCloud-Konto: Der Fehler wird erklärt, Wiederholung bleibt
möglich und lokale Speicher werden erhalten. Dateiübertragung, Konfliktansicht,
Wiedergabe, Timer, Neustart und Songstellen bleiben funktionsfähig. Dieser Lauf
ersetzt keinen schreibenden Production-Rundweg.

Der zusätzliche echte Zwei-Geräte-Lauf bestätigt parallele Playliständerungen,
eine ausdrückliche Konfliktentscheidung und das Weitergeben einer
Songstellen-Löschung. Ausgesetzter Abgleich sendet keine lokalen Änderungen.
Der gewählte Stand wird anschließend übernommen; ein Mac-Neustart stellt den
gelöschten Eintrag nicht wieder her. Development wurde nach zwei Fehlern im
Testablauf zusätzlich mit einem frischen iPhone-Client und dem Mac-Endstand
geprüft. Der abschließende Production-Lauf besteht durchgehend. Der Mac verwendet
dort das tatsächliche Speichermodell und SDK ohne Oberfläche; das iPhone verwendet
die App-Anbindung und die native Konfliktansicht. Die Testkorrekturen ändern
keinen Produktcode.

Der freigegebene Dienstblock ist damit abgeschlossen. Seine Abdeckung und Grenzen:

1. Development und Production bestehen mit demselben tatsächlich angemeldeten
   Konto für synthetische Metadaten. Sammlungs-, Generations-, Playlist- und
   Titel-IDs bleiben stabil; Musikdateien und lokale Lautstärke bleiben erhalten.
2. Parallele Änderungen, ausgesetzter Abgleich, Konflikte, Löschung und
   Mac-Neustart sind mit dem tatsächlichen Dienst geprüft. Reale Netztrennung
   und Kontowechsel wurden nicht ausgeführt. Ihre Fehler-/Wiederholungs- und
   Schutzlogik ist durch lokale Tests belegt; Konten und Netzwerkeinstellungen
   wurden bei der Geräteabnahme bewusst erhalten.
3. 20.000 Titel, Größenlimits und defekte Daten sind lokal geprüft. Fehlende
   Musik und geschützte Speicher sind nativ geprüft. Zusätzlich überträgt die
   private Production-Datenbank ein 6,4-MB-Asset mit 20.000 synthetischen
   Titelbeschreibungen bytegleich und weist einen veralteten bedingten
   Schreibzugriff zurück. Die eigene temporäre Prüfzone ist anschließend
   entfernt; der App-Snapshot bleibt unverändert. Der Zwei-Geräte-App-Lauf
   verwendet weiterhin zwei synthetische Titel. Quota, Drosselung und große
   Sammlungen in der Oberfläche auf zwei Geräten sind damit nicht belegt.
4. Das geprüfte Produktionsschema ist bereitgestellt. Development und Production
   wurden mit getrennt geprüften Entitlements ausgeführt.
   [Apple: Schema bereitstellen](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
5. Manuelle `.savagecollection`-Übertragung, Wiedergabe und Timer bestehen nativ
   auch ohne verfügbares iCloud-Konto. Apps und vollständige Einstellungen sind
   nach den temporären Prüfungen wiederhergestellt.

## Lokale Core-Grundlage seit 1.6.51

`CollectionSyncSnapshot` verwendet typisierte Schlüssel und Werte. Playlists und
Songstellen bleiben atomar; einzelne Klangfelder unterscheiden ausdrücklich
gesetzte Werte von Vererbung. Bekannte Schlüssel müssen erhalten oder durch einen
Tombstone ersetzt werden. Eine fehlende Datei oder eine unvollständige Projektion
kann dadurch keinen bekannten Eintrag als Löschung veröffentlichen. Die
Reihenfolge der Titel wird geteilt; die bestehende lokale Anzeige-Reihenfolge
der gespeicherten Listen kann beim Materialisieren ausdrücklich erhalten werden.

`CollectionSyncMergePlan` berechnet Vorschauen ohne Schreibzugriff. Jede
Konfliktentscheidung wird gegen den unveränderten lokalen Stand geprüft. Beim
Behalten beider Playlists oder Songstellen muss der Aufrufer eine neue feste
UUID liefern; Wiederholung oder Neustart erzeugen damit keine wechselnden
Kopien. Ein Merge mit widersprüchlichen Referenzen wird vor einer Übernahme
abgelehnt. Die Cloud-Seite benötigt zusätzlich weiterhin die bedingte
Veröffentlichung mit dem Change-Tag.

`CollectionSyncCheckpoint` hält Basis, lokale Änderungen, einen opaken
Konto-Scope, dessen Generation und optional den Server-Change-Tag. Ein spätes
Ergebnis aus einem anderen Scope oder einer alten Generation wird abgelehnt.
Der Codec verwendet eigene Formatkennungen und Schema-Versionen, 32 MiB je
Snapshot und 64 MiB zuzüglich 64 KiB Header-Reserve je lokalem Doppelstand. Zählergrenzen gelten auch für
Tombstones. Datumswerte werden intern als verlustfreie Date-Referenzsekunden
codiert; die manuelle Austauschdatei behält ihr vorhandenes Datumsformat. Der
Codec liest defekte, fehlende oder zukünftige Stände niemals als leere Sammlung.

Auch der lokale Songstellen-Speicher erhält Sekundenbruchteile. Das bisherige
ISO-Datum bleibt für ältere Leser bestehen; ein optionales Präzisionsfeld ergänzt
den genauen Zeitpunkt. Neue Leser nehmen alte Dateien weiter an und lehnen
widersprüchliche Zeitangaben ab. Dadurch verliert eine Projektion mit anschließendem
Dateijournal-Rundlauf keine Zeitstempelpräzision und erzeugt keine Scheinkonflikte.

`CollectionSyncProjection` bildet einen entschiedenen globalen Stand als
separate lokale Vorschau ab. Sie verlangt die bestätigte Sammlungs-Generation
und eindeutige Titelzuordnungen. Fehlende Zuordnungen blockieren jede Übernahme;
eine Änderung der lokalen Sammlung oder der Zuordnung verwirft die Vorschau.
Tombstones entfernen nur die ausdrücklich benannten lokalen Metadaten,
Vererbung setzt nur das betreffende Klangfeld zurück. Gerätelokale, nicht
benannte Einträge bleiben erhalten; Musikdateien werden nie gelöscht.

Der manuelle Import bleibt bewusst additiv und führt diese Löschungen nicht aus.
Eine automatische Integration darf ihn deshalb nicht einfach als Cloud-Abgleich
verwenden. Die lokale Projektion schreibt selbst nichts; ihre Übernahme muss
weiterhin über den geprüften Dateijournal-/Preferences-Pfad erfolgen.

Diese APIs führen keine Cloud-Aufrufe aus und verändern keine vorhandenen
App-Speicher. `CollectionSyncTrackRegistry` hält bestätigte lokale Titelzuordnungen
unter dem jeweiligen Konto und der Sammlungs-Generation. Wiederholte Exports und
Neustarts verwenden dieselben globalen Titel-IDs; gleichnamige Dateien bleiben
unterscheidbar. Das Register enthält lokale URLs und darf niemals hochgeladen
werden. Sein eigener begrenzter Codec ist vom portablen Snapshot getrennt.
Ein Dateiumzug wird nicht still als Neuzuordnung behandelt: Dafür fehlt noch die
gemeinsame Migration der vorhandenen lokalen Metadaten. Fehlende Musikdateien
löschen bestätigte Zuordnungen nicht. Export und Zuordnung liefern zunächst einen vorgeschlagenen Stand. Die App
sichert Register und Abgleich-Checkpoint vor einer Veröffentlichung gemeinsam
mit ihrem bisherigen Metadatenstand.

`CollectionSyncLocalState` bündelt Checkpoint und Titelregister in einem eigenen
gerätelokalen Format. Konto, Sammlung und Generation müssen zusammenpassen;
benötigte Zuordnungen dürfen nicht fehlen. Ausdrückliche Änderungszellen ersetzen
bekannte Werte, ohne bekannte Schlüssel aus dem Verlauf zu entfernen. Eine leere
Änderungsliste erzeugt deshalb keine Löschungen. Veraltete Ausgangsstände,
doppelte Änderungen, verlorene Zuordnungen und ungültige Referenzen werden vor
der Rückgabe eines neuen Standes abgelehnt. Der Codec begrenzt das Bundle auf
96 MiB zuzüglich 128 KiB Header-Reserve und prüft die Grenzen der enthaltenen
Stände zusätzlich einzeln. Die App verbindet diesen Stand mit den regulären Metadaten-/Preferences-
Transaktionen; die reine Wert-Operation schreibt selbst keine App-Dateien.

## App-Anbindung seit 1.6.51

Am Mac öffnet **Sammlung → Sammlung abgleichen…** die Oberfläche; auf
iPhone/iPad liegt **Sammlung abgleichen** in den Einstellungen. Sie zeigt
Einrichtung, offene Titelzuordnungen, Konflikte, Verbindungsfehler, ausstehende
Änderungen und den letzten erfolgreichen Abgleich. Ohne Dienstkonfiguration
erscheint eine entsprechende Erklärung. Es erfolgen dann keine Cloud-Aufrufe.

`CollectionSyncModel` erfasst regulär gespeicherte Playlists, Favoriten,
Songstellen und globale beziehungsweise titelbezogene Klangwerte. Lokale
Änderungen werden zusammengefasst; zusätzlich gibt es Abgleich beim Aktivieren
und eine manuelle Wiederholung. Lautstärke, Warteschlange, Timer, Darstellung und
Musikdateien gehören nicht dazu. Manuelle Sammlungsübertragungen pausieren den
Abgleich und behalten ihren eigenständigen Datei-Austausch.

Die Einrichtung und das Verknüpfen eines neuen Kontos verlangen eine Vorschau
mit ausdrücklicher Bestätigung. Noch nicht lokal übernommene Entscheidungen
blockieren einen Kontowechsel, bis sie im bisherigen Konto übernommen sind.
Titelzuordnungen sind eindeutig; eindeutige
Vorschläge lassen sich gemeinsam bestätigen. Alle Konflikte benötigen eine
Entscheidung. Kopien erhalten beim Entscheiden ihre feste UUID. Lokale Dateien
oder eine Kontokennung werden nicht in Cloud-Assets übernommen.

`CollectionSyncApplicationState` unterscheidet die tatsächlich beobachteten
App-Metadaten vom bereits vorgemerkten gemeinsamen Stand. Dadurch verwirft ein
Neustart zwischen Versand und lokaler Übernahme keine bestätigten Entscheidungen.
Neue lokale Änderungen verhindern eine veraltete Übernahme. Fehlende Speicher
oder unerwartet verschwundene einzelne Preferences-Schlüssel stoppen den
Abgleich. Der lokale Codec erlaubt höchstens 160 MiB zuzüglich 128 KiB Reserve;
die enthaltenen Snapshots und Register behalten ihre engeren Grenzen.

Playlists, Songstellen, Titel-Einstellungen und dieser lokale Stand bilden eine
vierteilige Dateitransaktion mit den ausgewählten Preferences. Das vorhandene
Journal stellt auch ältere dreiteilige Transaktionen wieder her. Der manuelle
Austausch kann einen defekten Abgleichstand unangetastet lassen. Erst nach
erfolgreicher lokaler Projektion wird die bestätigte Cloud-Basis fortgeschrieben.
Datenaufbereitung läuft außerhalb des Hauptthreads; die Übernahme bleibt mit den
regulären App-Schreibvorgängen koordiniert.

Die Anbieterfabrik bleibt standardmäßig deaktiviert. Sie benötigt ausdrücklich
`SAVAGE_CLOUDKIT_ENABLED` im jeweiligen App-Target und die bestätigte
Bundle-Konfiguration `CollectionSyncContainerIdentifier`. Diese Schalter ersetzen
keine passenden CloudKit-Entitlements, Profile oder Dienstabnahme. Sie dürfen erst
nach Prüfung dieser Voraussetzungen gesetzt werden. Standardbuilds setzen sie
nicht. Ein echter Zwei-Geräte-Dienstlauf bleibt erforderlich.

## Optionale CloudKit-Builds seit 1.6.52

Der bestätigte gemeinsame Container ist `iCloud.com.viben.SavageModPlayer`.
Die explizite App-Kennung lautet auf beiden Plattformen
`com.viben.SavageModPlayer`. Profile und private Schlüssel gehören nicht ins Repo.
Ein installiertes iOS-Profil muss bereits in Xcode verfügbar sein.

```sh
SAVAGE_CLOUDKIT_PROFILE="$HOME/Profiles/player-mac.provisionprofile" bash build_app.sh
SAVAGE_CLOUDKIT_PROFILE="$HOME/Profiles/player-ios.mobileprovision" bash ios/scripts/build-device.sh
```

Die Skripte prüfen die erlaubte Plattform, das Team, die explizite App-Kennung,
genau einen passenden Container, CloudKit, die gewünschte Umgebung und das
Ablaufdatum. Genau ein passender gültiger lokaler Signierschlüssel muss vorhanden
sein. Das App-Entitlement fordert nur CloudKit und den einzelnen Container an;
die weitergehenden Profil-Wildcards werden nicht übernommen. Der Mac bettet das
geprüfte Profil ein. Bei ungültiger Konfiguration bricht der Build ab, bevor das
vorhandene Mac-App-Bundle ersetzt wird. Es gibt keinen Ad-hoc-Ausweichpfad.

Ohne Profil bleibt der Anbieter deaktiviert. Mit Profil ist `Development` der
Standard; `SAVAGE_CLOUDKIT_ENVIRONMENT=Production` erfordert ein dazu passendes
Profil und ein separat geprüftes Produktionsschema. Ein Developer-ID-Profil
erlaubt ausschließlich `Production`; es ersetzt kein Mac-Entwicklungsprofil.
Die Build-Skripte legen keine Apple-Konten, Zertifikate, Geräte oder Profile an.
CloudKit-Entwicklungsbuilds bleiben im Projekt-/Buildverzeichnis; eine Installation
und Veröffentlichung setzen die passende Signatur und Abnahme voraus.

## Vorbereiteter Transport seit 1.6.51

`CollectionSyncTransportClient` verwendet ein injiziertes Asset-Backend und bindet
jeden Vorgang an Konto-Epoche, Sammlung und Generation. Ein fehlender Record ist
ein Fehler und keine leere Sammlung. Änderungen behalten bekannte Schlüssel;
gelöschte Werte bleiben ausdrücklich vermerkt. Der Client prüft die gelesene
Revision vor dem Versand. Das Backend muss zusätzlich serverseitig bedingt
schreiben, damit ein anderes Gerät auch zwischen Prüfung und Versand geschützt
bleibt. Eine Bestätigung trägt ihren Konto-Token; der Aufrufer muss ihn nach
jedem asynchronen Vorgang mit dem dann aktuellen Token vergleichen, bevor er
lokale Daten oder den Checkpoint bestätigt.

`CloudKitCollectionAssetBackend` liegt getrennt vom plattformneutralen
Bibliothekscode und wird nur auf Apple-Plattformen kompiliert. Seine Initialisierung
prüft lediglich die übergebene Containerkennung. Erst ein ausdrücklicher
Methodenaufruf erzeugt eine Containerinstanz. Er verwendet die private Datenbank,
eine eigene Zone und einen festen Snapshot-Record. Die Zone wird ausschließlich
durch eine getrennte Einrichtungsmethode angelegt. Lesen rekonstruiert keinen
gelöschten Cloud-Speicher automatisch. Eine beim ersten Zugriff noch fehlende
Zone liefert ebenso wie ein fehlender Snapshot keinen Record. Nur die ausdrückliche
Ersteinrichtung darf daraufhin eine neue Zone und Sammlung anlegen; mit einem
vorhandenen Checkpoint bleibt die Abwesenheit ein Fehler.

Vor jedem Schreiben liest das Backend den aktuellen Record erneut und vergleicht
den erwarteten Change-Tag. Der gelesene SDK-Record erhält anschließend das neue
Metadaten-Asset und wird mit `.ifServerRecordUnchanged` und atomarer Speicherung
gesendet. Ein zwischenzeitlich neuer Record verhindert auch den ersten Versand
mit leerem erwarteten Tag. Die zusätzliche Leseoperation erspart das dauerhafte
Archivieren von SDK-Systemfeldern. [Apple: Save-Policy](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged).

Uploads akzeptieren ausschließlich das portable Snapshot-Format, höchstens
32 MiB. Nach der Prüfung wird der bekannte Snapshot neu codiert; unbekannte
JSON-Zusatzfelder gelangen dadurch weder in den Upload noch in die Asset-Rückgabe.
Das lokale Titelregister und der gemeinsame Neustartstand werden vor
einer Containerinstanz abgelehnt. Die eigene Upload-Datei bleibt bis zum
SDK-Abschluss erhalten. Anfragen sind je SDK-Operation auf 30 Sekunden, Ressourcen
auf 60 Sekunden konfiguriert. Wiederholungshinweise sind begrenzt; rohe
Server- oder Kontodetails gelangen nicht in die öffentlichen Fehlertexte.

Ein Abbruch oder Fehler während eines Versands beweist keinen serverseitigen
Rollback. Eine spätere Wiederholung muss den Dienst neu lesen und den lokalen
Checkpoint erst nach einer gültigen Bestätigung fortschreiben. Der Transport
schreibt selbst keine App-Metadaten und bestätigt keinen lokalen Neustartstand.
Der Code ist mit synthetischem Backend und lokalen SDK-Records geprüft; ein
echter Dienstlauf und Container-/Profilkonfiguration stehen aus.

Savage Mod Player 1.6.52 ergänzt eine ausdrückliche CloudKit-Buildkonfiguration für Mac und iPhone. Optionale Builds prüfen Profil, App-Kennung, Container, Umgebung, Ablaufdatum und lokalen Signierschlüssel, bevor der Anbieter aktiviert wird. Standardbuilds lassen den Cloud-Zugriff ausgeschaltet. Entwicklung und Produktion bleiben getrennt; iOS-Builds verwenden vorhandene Profile, ohne automatisch Signiermaterial anzulegen. Der echte Entwicklungs-Rundweg Mac → iPhone → Mac besteht für Playlists, Favoriten, Songstellen und Klang-Overrides einschließlich stabiler IDs und Mac-Neustart. Das geprüfte CloudKit-Schema ist nach Production bereitgestellt. Der konfigurierte, notarisierte Mac-Build besteht die native Abnahme ohne iCloud-Konto einschließlich Wiederholung, geschütztem lokalem Speicher, Dateiübertragung und Songstellen nach Neustart. Der echte Production-Rundweg und ausdrückliche Zwei-Geräte-Konflikte mit Songstellen-Löschung bestehen; der entschiedene Stand bleibt nach Mac-Neustart erhalten. Eine zusätzliche Produktionsprüfung überträgt ein 6,4-MB-Asset mit 20.000 synthetischen Titelbeschreibungen und weist einen tatsächlich veralteten bedingten Schreibzugriff zurück. Die temporäre Prüfzone wird entfernt; der App-Snapshot bleibt unverändert. Reale Netztrennung, Kontowechsel, Dienstdrosselung und große Sammlungen in der Oberfläche auf zwei Geräten sind durch diese Prüfungen nicht belegt. Die erste Einrichtung erkennt jetzt eine noch fehlende private Zone; erst die ausdrückliche Bestätigung legt sie an. Bei bestehendem Checkpoint bleibt eine fehlende Cloud-Sammlung ein blockierender Fehler.

Savage Mod Player 1.6.51 ergänzt die lokale App-Anbindung für den Metadatenabgleich auf Mac und iPhone/iPad: Einrichtung, Status, Titelzuordnung, ausdrückliche Konfliktentscheidungen und Wiederholung. Ein dauerhaft beobachteter Stand erhält bestätigte Entscheidungen über unterbrochene Veröffentlichungen und Neustarts; Playlists, Songstellen, Klang-Overrides, Abgleichstand und ausgewählte Einstellungen teilen eine Wiederherstellungstransaktion. Fehlende Speicher oder verschwundene Einstellungsschlüssel dürfen keine Cloud-Löschungen erzeugen. Globale Titel-IDs, Konto-Generationen und bedingte Schreibvorgänge schützen lokale Änderungen vor verspäteten Ergebnissen. Der echte CloudKit-Anbieter bleibt bis zur bestätigten Containerkonfiguration, passenden Entitlements und Profilen sowie einem echten Zwei-Geräte-Dienstlauf ausgeschaltet. Der manuelle Sammlungs-Austausch bleibt nutzbar. Lokale Songstellen behalten Sekundenbruchteile; ältere Dateien bleiben lesbar.

Savage Mod Player 1.6.50 ergänzt den nativen Notenregen-Videoexport auf macOS. Eine pausierte Vorschau verwendet denselben Renderer wie die fertige MOV-Datei. Wählbar sind Auflösung bis Full HD, 24/25/30/60 Bilder pro Sekunde, hohe oder kompakte H.264-Kompression, Darstellung, Vorlauf und Dauergrenze. Titel und Klangoptionen werden beim Öffnen festgehalten; der Export läuft im Hintergrund mit Fortschritt und Abbruch. Vorhandene Ziele bleiben geschützt, fertige Videos lassen sich im Finder zeigen. Behebt einen Absturz beim Öffnen der Videovorschau in eigenständig gebauten App-Bundles. Die Buttons im Exportdialog bleiben auch bei größter Schrift lesbar.

Savage Mod Player 1.6.49 ergänzt den Offline-Notenregen-Video-Renderer im macOS-Core. H.264-Video und verlustfreies Stereo-Float32-Audio verwenden eine gemeinsame ganzzahlige Sample-Zeitbasis; das letzte Bild wird exakt am Audioende abgeschnitten. Begrenzte Audio-, Bild- und Notenpuffer, Klangoptionen, logische IT-Kanalzuordnung und Abbruch sind enthalten. Eine neue MOV-Datei wird erst nach erfolgreichem Abschluss veröffentlicht. Die native Exportoberfläche folgt getrennt.

Savage Mod Player 1.6.48 ergänzt den nativen Sammlungs-Export und -Import auf macOS und iPhone/iPad. Eine Vorschau zeigt Playlists, Favoriten, Songstellen und Klang-Einstellungen; lokale Titelzuordnungen werden geprüft, fehlende Titel zugeordnet oder übersprungen und Konflikte vor der Übernahme entschieden. Die versionierte `.savagecollection`-Datei enthält Metadaten ohne Musik oder lokale URLs. Ein Wiederherstellungsjournal schützt Sammlung und Voreinstellungen bei unterbrochenen Übernahmen. Lautstärke, laufende Timer und Warteschlange bleiben lokal. Beim manuellen Weiterblättern bleibt der nächste Warteschlangeneintrag außerdem erhalten, falls die Wiedergabe beim Ablauf des Einschlaftimers nicht startet. Mehrzeilige Mac-Zeilen halten Pfadhinweise und Zuordnungsstatus lesbar.

Savage Mod Player 1.6.47 ergänzt das gemeinsame portable Sammlungsformat für Playlists, Favoriten, Songstellen sowie globale Klang-Vorgaben und Titel-Overrides. Versioniertes JSON enthält relative Dateihinweise und optionale Inhaltsnachweise; Lesen und Referenzen sind begrenzt und validiert. Importvorschauen verlangen Titelzuordnung und ausdrückliche Konfliktentscheidungen, erhalten lokale Daten und erkennen veraltete Vorschauen. Das Format enthält weder Audio noch lokale Quellen-URLs; die nativen Import-/Export-Bedienelemente folgen als eigener Schritt.

Savage Mod Player 1.6.46 ergänzt Klang-Einstellungen pro Titel auf Mac und iPhone/iPad. Ausdrückliche Overrides für MOD-Clock, Stereo-Separation, Interpolation und LED-Ausgabefilter ersetzen jeweils nur die passende globale Vorgabe. Titelwechsel und Neustart erhalten die Zuordnung über stabile Quellen-IDs; Rücksetzen betrifft nur den gewählten Titel. Nicht anwendbare Clock-Optionen bleiben bei XM, S3M und IT ausgeblendet. Beschädigte Einstellungsdateien bleiben erhalten, während sichere globale Vorgaben gelten.

Savage Mod Player 1.6.45 ergänzt einen Einschlaftimer für die Mac- und iPhone/iPad-App. Die letzten zehn Sekunden blenden unabhängig von der Aktualisierung der Oberfläche aus. Abbruch und Verlängerung stellen den gewünschten Pegel sanft wieder her; der Ablauf beendet die Wiedergabe und verhindert automatisches Fortsetzen nach Unterbrechungen oder verspätetem Laden. Der Countdown läuft bei Pause, Titelwechsel und A/B-Wiedergabe weiter. Der Lautstärkewert bleibt erhalten; ein aktiver Timer wird nach einem App-Neustart nicht wiederhergestellt.

Savage Mod Player 1.6.44 ergänzt den WAV-Stapelexport auf macOS. Titel aus der aktuellen Playlist oder den Suchtreffern auswählen, Stereo-Mix oder Kanalspuren wählen und gespeicherte Audioeinstellungen wiederverwenden. Vorhandene Ziele werden übersprungen oder unter einem neuen Namen erhalten. Fortschritt, Abbruch und ein Stapelbericht mit Einzelergebnissen machen fertige Ausgaben sichtbar; der Export arbeitet seriell mit begrenzten Audiopuffern.

Savage Mod Player 1.6.43 ergänzt den Export tatsächlich gespielter Stereo-Kanalspuren auf macOS. IT-Hintergrundstimmen bleiben ihrem logischen Kanal zugeordnet. Float32-WAVs und Referenzmix haben denselben Anfang, dieselbe Länge und einen gemeinsamen Pegelfaktor. Eine Begleitdatei hält Audiooptionen und Mastergrenzen fest: Die Spuren liegen vor dem tanh-Limiter; Mixerlautstärke und externer LED-Ausgabefilter sind nicht enthalten. Zwei blockweise Renderdurchläufe begrenzen den Speicherbedarf. Die Oberfläche zeigt Fortschritt und Abbruch; bestehende Zielordner bleiben geschützt.

Savage Mod Player 1.6.42 ergänzt native A/B-Wiedergabe im Songstellenblatt.
Ein begrenzter Renderlauf im Hintergrund rekonstruiert den tatsächlich gespielten
Weg nach A einschließlich laufender Samples, Effekt-Memory und IT-Hintergrundstimmen.
Jede Wiederholung stellt diesen Zustand wieder her und schließt alle Ticks und
Delays von B ein. Abbruch, unerreichbare Grenzen, Pause und geänderte Einstellungen
haben eigene Zustände. Der Mac-Notenregen verwendet denselben Snapshot und
Framebereich. Der LED-Ausgabefilter verarbeitet den entstehenden Datenstrom weiter;
seine Ausgabehistorie liegt außerhalb des Replay-Snapshots.
Sample- und Modulinspektor erhalten das festgehaltene Modul direkt beim Öffnen;
der erste Aufruf erzeugt dadurch kein leeres Dialogblatt mehr.

Savage Mod Player 1.6.41 korrigiert Playlist- und Warteschlangenwechsel.
Eingeschobene Mac-Titel erhalten die ursprüngliche Liste; abgebrochene
iOS-Ladevorgänge behalten wartende Titel und Rückkehrpunkt. Während eines
Fehlversuchs ergänzte Titel behalten ihren Vorrang. Gespeicherte Playlists
öffnen mehr als 128 unabhängige Archive bei gemeinsamen Größenlimits;
Sicherheitsgrenzen werden getrennt von fehlenden Quellen gemeldet.
Native Drop- und Queue-Regressionen prüfen diese Fälle.

Savage Mod Player 1.6.40 ergänzt benannte Songstellen auf Mac, iPhone und iPad.
Position und Zeile bleiben über Neustarts pro Originalquelle erhalten, auch bei
wiederverwendeten Patterns. Ziele lassen sich bearbeiten, löschen und mit dem
vorhandenen zeilengenauen Sprung aufrufen. Eine getrennte visuelle Bereichsauswahl
markiert den Mac-Tracker und die Positionsleiste des Notenregens. Fehlende Ziele
und beschädigte Speicherdateien bleiben erhalten; die Musikdateien werden nicht
verändert. Der gewählte Wiedergabe-Loop-Modus bleibt unabhängig von der Auswahl.

Savage Mod Player 1.6.39 ergänzt den Modul-/Instrument-Inspektor auf Mac, iPhone
und iPad. Er zeigt Aufbau und tatsächliche Herkunftsfelder, Hüllkurven mit Loop,
Sustain und Carry sowie vorhandene IT-Kompatibilitätsdiagnosen. Ein Effektkatalog
unterscheidet Format und Spalte, erhält Nullparameter und erklärt erkannte
ignorierte Befehle. Statische Häufigkeiten sind keine Wiedergabezählung.
Auf iPhone/iPad sind beide Inspektoren über das Info-Menü im Wiedergabe-Tab erreichbar.

Savage Mod Player 1.6.38 ergänzt einen Sample-Inspektor auf Mac, iPhone und iPad.
Er zeigt Wellenformen mit Zoom und Ausschnitt, beide Stereo-Kanäle, Normal-/Sustain-
Loops und ihre Laufrichtung. Alle Instrument-Samples und der globale IT-Samplepool
bleiben zugänglich; gespeicherte XM-/IT-Tastenzuordnungen zeigen Transposition und
unbelegte Tasten. Die Anzeige liest vorhandene Daten und erhält die bisherige
Instrumentvorschau. Dialogtasten bedienen das Blatt statt die Wiedergabe.

Savage Mod Player 1.6.37 ergänzt Metadatensuche, Sortierung und gespeicherte
Filter auf Mac, iPhone und iPad. Die Suche findet interne Titel und Instrumentnamen
sowie Dateinamen und Ordner. Format, Kanalzahl, Favoriten, ungehörte und neu
erfasste Titel lassen sich kombinieren. Die Wiedergabe behält die ausdrücklich
gewählte Anzeigereihenfolge; Anzeigeänderungen ersetzen diese Auswahl nicht.
Tatsächliche Wiedergabe merkt den Hörstatus über stabile IDs, bloßes Laden oder
Wiederherstellen eines pausierten Titels nicht. Sammlungshinweise unterscheiden
gleiche Dateinamen von identischem Inhalt und zeigen Indexfehler.

Savage Mod Player 1.6.36 ergänzt einen gemeinsamen Hintergrund-Metadatenindex
für die folgende Bibliothekssuche und Sortierung. Er erfasst Modultitel, Formate,
Kanal-/Instrument-/Samplezahlen, Namen und begrenzte Spieldauern. Unveränderte
Dateien verwenden einen versionierten Cache; fehlende, ungültige oder zu große
Dateien erhalten eigene Zustände. Abbruch erhält Teilfortschritt. Größenlimits
und nicht blockierende Prüfung regulärer Dateien schützen vor übergroßen Daten
und benannten Pipes.

Savage Mod Player 1.6.35 ergänzt gespeicherte Playlists und eine Sitzungs-
warteschlange auf iPhone und iPad. Listen lassen sich anlegen, umbenennen, löschen
und umsortieren. Relative Bibliotheksreferenzen bleiben bei wechselndem App-
Container gültig; fehlende Titel bleiben gespeichert. Kontextmenüs füllen Listen
oder die Warteschlange, die anschließend die vorherige Auswahl fortsetzt und
gestoppte Wiedergabe erhält. Suchtreffer lassen sich ausdrücklich als
Wiedergabebereich festlegen. Neue Bedienelemente sind deutsch und englisch.

Savage Mod Player 1.6.34 ergänzt benannte Playlists in der macOS-Seitenleiste.
Reihenfolge und Originalquellen bleiben über Neustarts erhalten, auch bei Archiven;
fehlende Quellen bleiben vermerkt. Titelmenüs füllen gespeicherte Listen oder eine
umsortierbare Sitzungswarteschlange. Danach geht die vorherige Liste weiter.
Suchtreffer lassen sich ausdrücklich als Wiedergabebereich festlegen. Favoriten
nutzen Quellen-IDs; die Migration merkt ungesehene alte Namen vor und ordnet
mehrdeutige Namen nicht automatisch zu.

Savage Mod Player 1.6.33 ergänzt einen versionierten Speicher für benannte
Playlists und quellenbasierte Titelreferenzen. Sie überleben temporäre Kopien
und verschachtelte Archive; gleichnamige Dateien in verschiedenen Ordnern bleiben
unterscheidbar. Fehlende Quellen bleiben vermerkt, ungültige Playlist-Daten
überschreiben keinen gespeicherten Bestand. Die macOS-Oberfläche folgt im nächsten Update.

Savage Mod Player 1.6.32 ergänzt Sparkle-Updates in der macOS-App: manuelle
Prüfung im App-Menü und automatische Prüfungen über die Einstellungen.
Installationen brauchen eine Bestätigung; Update-Archive und Feed sind signiert.
Bestehende Versionen brauchen einmalig eine manuelle DMG-Installation.
Der Release-Workflow bereitet den signierten Feed für GitHub Pages vor;
die Ersteinrichtung steht in `docs/sparkle-release.md`.

Savage Mod Player 1.6.31 verwirft wartende Dateiimporte bei System-Play und
System-Pause. Im Browser lässt sich auch der erste Ordnerimport bereits
vor dem Laden eines Moduls mit Stop abbrechen.

Savage Mod Player 1.6.30 hält die Browser-Steuerung auch beim URL-Titelwechsel
während der ersten Audiovorbereitung mit dem aktiven Audiographen verbunden.
Abspielen/Pause und Stopp im Notenfenster nutzen die zentrale Transportsteuerung
und entwerten laufende Dateiimporte. Stereo- und Interpolationsänderungen erhalten
die Notenvorschau ohne Neuberechnung. Linux-Releases finden AppImage und Prüfsumme
am Standardpfad des Builders. Ein unerreichbarer ALSA-Selbst-Stop-Zweig entfällt.

Savage Mod Player 1.6.29 lässt den letzten macOS-Audiopuffer auch dann auslaufen,
wenn ein gültiger HAL-Zeitstempel bereits zurückliegt. Die Wartefrist beginnt
frühestens nach dem Rendern; künftige Ausgabezeitpunkte und ausdrücklicher Stop
behalten ihr Verhalten. Eine deterministische Regression prüft zurückliegende,
künftige und fehlende Zeitstempel. Die GitHub-CI deckte den Randfall auf.

Die iOS-Wächtertests trennen feste Zeit-/Abbruchentscheidungen von Start und Ende
des echten Hintergrundworkers; seine Einplanung wird ausdrücklich beobachtet.

Savage Mod Player 1.6.28 behebt Fehler aus einem vollständigen Quellcode-Review:
paralleles Starten/Stoppen der Audioausgabe, verzögerte Noten, kombiniertes
IT-Portamento, moderne Tempoänderungen, kurze explizite Sampleloops,
beschädigte S3M-PCM-Header und übergroße numerische IT-Erweiterungen.
macOS-Medientasten erreichen sicher den Hauptthread; der Sample-Export hält
das gewählte Stück auch bei Playlistwechsel fest. Verschachtelte Archive teilen
Entpackgrenzen, versteckte Musikdateien in Archiven bleiben enthalten.
Fehler beim Bibliotheksleeren werden gemeldet; der Restbestand bleibt im Index.
Browser-Pegel fallen bei Stop ab. Release- und Starttest-Skripte schützen
Zielrepository, Tags, Prozesse und gesicherte Voreinstellungen.

Savage Mod Player 1.6.27 ergänzt ein Linux-x86_64-AppImage mit festem
appimagetool 1.9.1 und geprüfter Runtime. Es enthält den Terminalplayer
samt Swift-Laufzeit, Icon, Dokumentation und Lizenzen.
Ausdrückliche CLI-Hilfe endet jetzt mit Erfolgscode 0.

Savage Mod Player 1.6.26 ergänzt MPRIS2 für die Linux-CLI-Wiedergabe über
libdbus-1. Desktop-Steuerungen können pausieren, fortsetzen, stoppen, neu
starten sowie Titel und Lautstärke wechseln und Titel/Position lesen.

Savage Mod Player 1.6.25 übernimmt die Pingpong-Umkehrpunkte von Original
Impulse Tracker 2.14, auch bei gebrochenen Sampleschritten. Zwei synthetische
Referenzaufnahmen belegten eine zu lange Loop-Periode im bisherigen Renderer.

Savage Mod Player 1.6.24 übernimmt die ProTracker-Vibrato-/Tremolotabelle
beim Aufbau der Wiedergabekanäle. Damit liegt ihre erste Initialisierung auch
im Debug-Build außerhalb des Audiothreads. Tabellenwerte und Audioausgabe
bleiben unverändert.

Savage Mod Player 1.6.23 lässt bei der macOS-CLI-Wiedergabe den letzten
Audiopuffer auslaufen, bevor das natürliche Ende gemeldet wird. Ein ausdrücklicher
Stop unterbricht weiterhin. Renderer und Audiosamples bleiben unverändert.

Savage Mod Player 1.6.22 verkleinert das Notenregen-Fenster bei **Tonumfang**
und erhält dabei exakt die Breite von Tasten und Notenbalken der Gesamtansicht.
**Klaviatur** stellt die vorherige Fensterbreite wieder her, auch nach einer
manuellen Größenänderung. In schmalen Fenstern stehen die Bedienelemente unter
dem Titel.

Savage Mod Player 1.6.21 zeigt im Notenregen standardmäßig eine Klaviatur mit
88 Tasten von A0 bis C8. Tracker-Noten außerhalb dieses Bereichs erweitern sie
automatisch. Über **Tonumfang** lässt sich bewusst auf das Stück zoomen;
**Klaviatur** kehrt zur Gesamtansicht zurück. Die Auswahl bleibt gespeichert.
Die Tasten behalten auch beim Zoom schlanke Proportionen, die Balken sind
schmaler und die Tastenbeleuchtung ist dezenter. Notennamen stehen waagerecht
oder gedreht im Balken, wenn genügend Platz vorhanden ist; beim Überfahren
bleiben Note, Kanal und Dauer ablesbar.

Savage Mod Player 1.6.20 ergänzt ein eigenes macOS-Fenster mit Klaviatur und
fallenden Notenbalken. **Darstellung → Notenregen öffnen** oder **Umschalt–⌘–N**
öffnet die Vorschau. Die Balken tragen Notennamen und sind nach Kanal gefärbt;
der Vorlauf lässt sich auf zwei, vier oder acht Sekunden einstellen. Klingende
Stimmen heben die zugehörigen Tasten hervor; Mute und Solo werden berücksichtigt.
Pause, Sprünge, Tempoänderungen, Pattern-Loops und überlappende IT-Stimmen folgen
demselben Sequencer wie die Audioausgabe. Die Vorschau rechnet nur bei geöffnetem
Fenster im Hintergrund.

Die Balken zeigen ausgelöste Tracker-Noten und die Laufzeit klingender Stimmen.
Sample-Inhalte werden nicht in Einzelnoten zerlegt; Pitch-Slides und Vibrato
verschieben die Balken nicht. Nach einem manuellen Sprung oder einer Tempoänderung
wird die Vorschau kurz neu berechnet.
Das App-Bauskript fragt Swift nach dem Binary-Verzeichnis und verpackt damit
auch beim neuen Swift-Buildsystem das frisch kompilierte Programm.

Savage Mod Player 1.6.19 spielt vorwärts gerichtete Bxx/Dxx-Sprünge innerhalb der
aktuellen MOD-Order bis zum tatsächlichen Songende weiter. Verzögerte Drops auf
Desktop und im Browser beachten Stop und neuere Auswahlen. Browser-Worklet-Meldungen
tragen die Identität ihrer Wiedergabe; verspätete Endereignisse starten keine
Wiedergabe neu und überspringen keinen neu gewählten Titel.

Savage Mod Player 1.6.18 begrenzt den Ressourcenbedarf beschädigter IT-Dateien
und schützt die Bibliothek vor bestehenden Symlinks im Zielpfad. Ping-Pong-Wiedergabe,
IT-Ordersprünge und Stereo-Sampleexport sind korrigiert. Pause und neuere Auswahlen
entwerten ausstehende Ladeaufträge; Favoritenlisten aktualisieren sich sofort.
Der Desktop-Tracker zeichnet neue Module neu. Der Webplayer setzt Stimmen beim
Titelwechsel zurück, erhält endliche Pattern-Loops und navigiert anhand der gewählten
Datei. Quick Look erneuert Audiocaches nach Updates. Linux-Desktop-Einträge verwenden
den installierten Programmpfad; die DMG-Bereinigung hängt nur ihr eigenes Volume aus.
Der DMG-Bau übernimmt den tatsächlichen Mountpunkt und wartet vor dem Einrichten
des Installationsfensters, bis Finder das Volume erkennt. Das Fenster lässt Platz
für Finders Tab- und Pfadleiste, damit die untere Beschriftung sichtbar bleibt.

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

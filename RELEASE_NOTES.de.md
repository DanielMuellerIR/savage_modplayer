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

Savage Mod Player 1.6.10 behebt den Start der Mac-App mit einem Dateiargument,
vervollständigt die Kommandozeile um Playlist-Wiedergabe und Tastatursteuerung
und macht die iPhone-App beim Laden und beim Öffnen fremder Dateien flüssiger.

## Mac-App

- `Savage Mod Player <song.mod>` und `open --args <song.mod>` öffnen wieder ein
  Fenster und spielen die übergebene Datei. Ursache war AppKit: Ein positionales
  Startargument galt dort als „diese Datei öffnen“, und auf diesem Startweg
  erzeugt SwiftUI sein Fenster nicht. Ohne Fenster konnte auch der Weg für
  „Öffnen mit“ die Datei nicht entgegennehmen — die App lief unsichtbar weiter.
  Gleiches galt für einen Ordner als Argument und für ein Argument, das gar
  keinem Pfad entspricht.
- Ein von macOS beim Start angehängtes `-Schlüssel Wert`-Paar wird samt Wert
  übersprungen. Ein Ordner namens `YES` im Arbeitsverzeichnis wird dadurch nicht
  mehr als Startordner missverstanden.
- Finder, Dock und „Öffnen mit“ bleiben unverändert: Dieser Weg läuft über ein
  Apple-Event, nicht über die Kommandozeile.
- Die Bildrate der Visualisierungen lässt sich in den Einstellungen (Cmd+,) auf
  30, 24, 15 oder 10 Hz stellen. Vorgabe bleibt 30 Hz und damit die volle
  Optik. Der Hebel ist groß: Auf einem Mac mit M5-Chip kostete dieselbe Wiedergabe bei 30 Hz
  rund 22 % eines Kerns, bei 15 Hz rund 18 % und bei 10 Hz rund 14 %. Die Änderung wirkt sofort; im
  kompakten Fenster bleibt es unabhängig davon bei 5 Hz.

## iPhone-App

- „Öffnen mit …" funktioniert. MOD, S3M, XM, IT und ZIP sind seit jeher als
  Dokumenttypen angemeldet, aber eine übergebene Datei startete nur die App und
  wurde verworfen. Jetzt wird sie in die Bibliothek übernommen — ein Archiv
  dabei ausgepackt — und anschließend abgespielt. Trifft sie während des
  Startabgleichs ein, wartet sie, bis die Bibliothek frei ist.
- Ein Titel wird nicht mehr auf dem Hauptthread eingelesen. Lesen, Parsen und
  das Ermitteln der Spieldauer laufen im Hintergrund; nur die Übergabe an die
  Engine bleibt vorn. Ein großes Modul oder eine Datei aus der Cloud friert die
  Oberfläche damit nicht mehr ein.
- Ein neuer Ladeauftrag überholt den alten. Wer mehrfach hintereinander auf
  „weiter" tippt, wartet nicht mehr darauf, dass alle übersprungenen Titel
  nacheinander eingelesen werden.
- Die Abspielliste behält ihre Auswahl. Wurde die Wiedergabe aus einer Suche
  oder aus den Favoriten gestartet, ersetzt eine Änderung der Bibliothek sie
  nicht mehr durch den Gesamtbestand — schon ein einzelner neuer Favorit
  reichte dafür.
- Die Namen der Dateitypen erscheinen auf englischen Geräten englisch. In der
  Dateien-App, im Teilen-Menü und unter „Öffnen mit …" stand bisher überall
  Deutsch.
- Die Audio-Session verwaltet nur noch die App. Der Player-Kern setzte sie beim
  Start ein zweites Mal, mit einer Konsolenmeldung als einziger
  Fehlerbehandlung.
- Freigegebene Sperrbildschirm-Steuerungen melden ihre Empfänger jetzt
  garantiert wieder ab, statt sie im systemweiten Befehlszentrum liegen zu
  lassen.
- Ein hängender Cloud-Anbieter blockiert den Import nicht mehr dauerhaft. Das
  koordinierte Lesen einer Datei hatte kein Zeitlimit und bemerkte auch
  „Abbrechen" nicht mehr; beides greift jetzt während des Lesevorgangs.
  Fortschritt verlängert dabei die Frist, ein langsamer Anbieter läuft also
  weiterhin durch.

## iPad

- Auf breiten Bildschirmen zeigt die App zwei Spalten: links die Bibliothek,
  rechts die laufende Wiedergabe. Man sucht einen Titel und sieht dabei weiter,
  was gerade spielt; eine Mini-Player-Leiste braucht es dort nicht mehr. Die
  Einstellungen erreicht man über ein Zahnrad in der Bibliotheks-Leiste.
- Entscheidend ist die Fensterbreite, nicht das Gerät: Ein iPad in Slide Over
  zeigt weiterhin das iPhone-Layout mit drei Tabs, und am iPhone ändert sich
  nichts.
- Der Hinweistext der leeren Bibliothek wird nicht mehr abgeschnitten. In der
  schmalen Spalte stand er vorher an beiden Seiten über dem Rand.

## Kommandozeile

- `savage-cli --list <ordner> --play` spielt einen Ordner als Playlist, in
  Pfadreihenfolge. Ein unlesbares oder kaputtes Modul wird gemeldet und
  übersprungen; bleibt kein spielbares übrig, endet der Aufruf mit Exit-Code 1.
- An einem Terminal steuern einzelne Tasten die laufende Wiedergabe:
  Leertaste oder `p` pausiert und setzt fort, `n` oder Pfeil rechts springt zum
  nächsten Titel, `b` oder Pfeil links zurück, `q` beendet. Ohne Terminal
  (Pipe, Cron, CI) läuft die Wiedergabe unverändert durch.
- Ctrl-C beendet `--play` wieder. Bisher spielte die Wiedergabe trotz Signal
  bis zum Ende weiter, obwohl die Meldung etwas anderes versprach. Jetzt wird
  die Audio-Ausgabe geschlossen und der Prozess endet mit Exit-Code 130.
- `--list` zusammen mit einer Eingabedatei wird abgelehnt statt halb ausgeführt.
  Vorher gewann `--list`, und die angegebene Datei verschwand kommentarlos.

## Archive

- `.zip` entpackt jetzt auf allen Plattformen der projekteigene Leser, nicht
  mehr das System-`bsdtar`. Damit gilt sein Sicherheitsfilter auch auf Mac und
  Linux: Zip-Slip, symbolische Links, verschlüsselte Einträge, Zip64 und
  unplausible Kompressionsverhältnisse machen das **ganze** Archiv ungültig,
  statt teilweise entpackt zu werden. Nebenbei landen nur noch Moduldateien und
  verschachtelte Archive auf der Platte statt des kompletten Inhalts.
- **Verhaltensänderung:** Ein ZIP mit einem symbolischen Link darin wird
  vollständig abgelehnt. Vorher entpackte `bsdtar` auf Mac und Linux den Rest
  und ließ nur den Link aus.
- `bsdtar` ist damit optional geworden: Es wird nur noch für `.7z` gebraucht.
  Unter Linux braucht der Bau dafür `zlib1g-dev`.
- Eine benannte Pipe mit der Endung `.zip` lässt den Leser nicht mehr hängen.
  Er öffnet ohne Blockieren und weist alles ab, was keine gewöhnliche Datei ist.

## Module

- XM: `P00` setzt einen laufenden Panning-Slide fort, statt ihn abzubrechen.
  FastTracker 2 merkt sich den letzten `Pxy`-Parameter; dieses Effekt-Memory
  fehlte als einziges der XM-Effekte.

## Linux

- Der Player lässt sich auf dem Desktop installieren: `bash linux/install.sh`
  legt `savage-cli` und einen Menü-Eintrag nach `~/.local` (ohne root,
  `--uninstall` räumt wieder auf). Damit erscheint er als Anwendung für MOD-,
  S3M-, XM- und IT-Dateien. Der Eintrag startet im Terminal, weil die
  Tastensteuerung eines braucht.
- `bash linux/build-static.sh` baut ein statisch gelinktes `savage-cli` im
  Container. Es läuft ohne installierte Swift-Laufzeit auf dem Zielrechner.

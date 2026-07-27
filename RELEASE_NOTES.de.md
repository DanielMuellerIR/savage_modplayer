Savage Mod Player 1.6.2 repariert die Viewport-Aktivierung der Visualisierungen
in der nativen iPhone-App und behält die automatische ZIP-Verarbeitung, das
lesbare mehrzeilige Kanalraster und die ruhige Gestaltung der Mac-App bei.

## iPhone-App

- Die native SwiftUI-App liegt unter `ios/` und bindet dasselbe
  `SavageModPlayerCore` ein wie die macOS-App, die Quick-Look-Erweiterung und der
  Kommandozeilen-Renderer. Es gibt keine zweite Wiedergabe-Implementierung.
- Die Wiedergabe läuft im Hintergrund und bei gesperrtem Gerät weiter. Titel,
  Format, Ordner, Titelbild und verstrichene Zeit erscheinen auf dem
  Sperrbildschirm; Play, Pause, Weiter, Zurück, der Positionsregler sowie
  −15 s / +30 s funktionieren von dort und über die Kopfhörersteuerung.
- Die Audiositzung behandelt die Fälle, die auf einem Telefon wirklich
  vorkommen: ein eingehender Anruf pausiert und setzt danach fort, das Abziehen
  der Kopfhörer pausiert statt auf den Lautsprecher zu wechseln, und ein Neustart
  der Systemaudiodienste baut die Engine samt Tiefpass des LED-Filters neu auf.
- Die Visualizer-Aktivierung auf echten iPhones hängt nicht mehr an
  unzuverlässigen Lifecycle-Rückrufen einer Lazy-Liste. Die Tab-Auswahl wird
  explizit verfolgt; die Scroll-Sichtbarkeit kommt auf iOS 18 vom System und auf
  iOS 17 aus einer Geometrie-Abfrage.
- Die Bibliothek ist ein echter Ordnerbaum, keine flache Liste. Ordner starten
  zugeklappt, der Pfad zum laufenden Titel klappt automatisch auf, und Wiedergabe
  wie Zufallswiedergabe laufen über alle Ordner. Live-Suche, Favoriten,
  Loop-Modi und Sitzungswiederherstellung arbeiten wie auf dem Desktop.
- Visualisierungen brauchen keinen Ein-/Aus-Schalter mehr. Sie starten, sobald
  ihr Abschnitt in den Scrollbereich kommt, und stoppen beim Herausscrollen,
  Tabwechsel oder Sperren. Canvas-Views und Wellenform-Caches werden im
  unsichtbaren Zustand freigegeben. Bis zu 32 Kanal-Oszilloskope stehen auf dem
  iPhone in vier, auf breiten Layouts in acht Spalten statt gequetscht in einer
  Zeile.
- PAL/NTSC-Takt, LED-Filter, Hi-Fi-Interpolation und Stereo-Separation sind
  vorhanden. Das Erscheinungsbild nutzt nun die Blau-/Cyan-/Graphit-Palette der
  Mac-App; das iOS-Asset ist als echtes PNG aus derselben Icon-Quelle verpackt.
  Es folgt dem System und lässt sich fest auf hell oder dunkel stellen.

## Musik auf das Gerät bekommen

- **Ordner-Import in der App:** einen Ordner auswählen, und alles Spielbare
  darin wird mitsamt Struktur in die Bibliothek kopiert. Archive werden
  ausgepackt, Doppelte übersprungen, der Fortschritt angezeigt, und der Import
  lässt sich abbrechen, ohne eine halbfertige Bibliothek zu hinterlassen.
  Dateien aus einem Cloud-Dateianbieter werden zuvor geladen und koordiniert
  gelesen.
- **Finder-Dateifreigabe:** iPhone anschließen, im Finder „Dateien" öffnen und
  ganze Ordner auf die App ziehen. Dieselbe Bibliothek erscheint in der
  iOS-Dateien-App unter „Auf meinem iPhone". Die App gleicht ihren Index bei
  jedem Start mit dem Dateisystem ab, sodass von außen abgelegte oder gelöschte
  Dateien richtig ankommen. Dort gefundene ZIP-Archive werden automatisch
  ausgepackt statt auf einen separaten Knopf zu warten; nur fehlgeschlagene oder
  abgebrochene Archive bleiben zum erneuten Versuch stehen.
- **Bibliothek zurücksetzen:** eine zweistufige Bestätigung löscht Titel, Index
  und zwischengespeicherte Extrakte; Favoriten können erhalten bleiben.

## ZIP ohne fremde Werkzeuge

- Der Core hat einen eigenen ZIP-Reader bekommen. Er streamt jeden Eintrag
  blockweise direkt in seine Zieldatei, der Speicherbedarf wächst also nicht mit
  der Archivgröße — ein 120-MB-Archiv braucht jetzt rund 7 MB statt 122 MB.
- Entpackt werden ausschließlich spielbare Moduldateien. Bei einem großen
  Sammlungsarchiv spart das den Löwenanteil an Zeit und Platz.
- Einträge, die aus dem Zielordner herausführen, symbolische Links,
  verschlüsselte Einträge, ZIP64-Archive und unplausible Kompressionsverhältnisse
  werden abgelehnt statt bereinigt; die CRC32-Prüfsumme jedes Eintrags wird
  verifiziert.
- macOS und Linux nutzen weiterhin das System-`bsdtar`, das auch 7-Zip liest.
  Auf iOS wird 7-Zip nicht unterstützt und genau so gemeldet.

## Verifikation und bekannte Grenzen

- Die vollständige Swift-Suite, der Linux-Container-Lauf, der macOS-App- und
  Quick-Look-Build, byteidentische Kommandozeilen-WAV-Ausgabe gegen die vorherige
  Baseline über den lokalen Modulbestand sowie Build und Testlauf im
  iOS-Simulator decken das Release ab.
- Hintergrundwiedergabe, Sperrbildschirm-Steuerung, Kopfhörerverhalten und der
  Speicherbedarf beim Import eines großen Archivs sind nur auf einem echten Gerät
  belegbar und werden nicht auf Basis eines Simulatorlaufs behauptet.
- Die iPhone-App hat keinen WAV-Export; der bleibt eine Desktop-Funktion.
- MPTM, VST-/AudioUnit-Plugin-Wiedergabe und externe MIDI-Ausgabe bleiben
  außerhalb der nativen Engine. Der HTML5-Player bleibt bewusst auf klassische
  vierkanalige ProTracker-MOD-Dateien begrenzt.
- Das DMG ist mit Developer ID signiert, von Apple notarisiert und enthält App
  und Quick-Look-Erweiterung. Moduldateien werden nicht mitgeliefert.

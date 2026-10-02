# Bestätigte Fallen

Aus realen Fehlern dieses Projekts gelernte Regeln. Vor Änderungen an Parsern,
Library, App-Start, Combine-Abonnenten oder dem Dreifachpuffer hier nachlesen.
Ausgelagert aus `AGENTS.md` am 2026-09-11 (Kontext-Hygiene); Wortlaut erhalten.

## Parser

- **Deklarierte Längen vollständig erzwingen.** Ein Binärparser darf ein
  deklariertes Datenfenster nicht still am Dateiende kürzen; `min(…, data.count)`
  ersetzt keine Prüfung. Liegt der Bereich nicht vollständig in der Eingabe, gilt
  sonst das Präfix einer abgeschnittenen Datei — etwa eines XM — als gültig.
- **`Data`-Slices nie als nullbasiert behandeln.** Ihr `startIndex` kann ungleich
  null sein. Öffentliche Parser-Eingaben umbasieren oder durchgehend relativ zum
  `startIndex` adressieren; echte Slices testen.

## Library und Import

- **Ein fehlgeschlagener Dateisystem-Scan leert keinen Index.** Liefert ein
  Verzeichnis-Enumerator `nil` oder unvollständige Ergebnisse, ist das kein
  leerer Bestand. Den alten Index bis zum vollständigen Neuaufbau behalten oder
  fehlgeschlagene Teilbäume mit dem bekannten Bestand zusammenführen.
- **Ein Quellarchiv erst nach vollständiger Übernahme löschen** — samt
  verschachtelter Archive. Ein einzelner importierter Direkteintrag belegt nicht,
  dass das gesamte Staging verarbeitet wurde.

## App-Start und SwiftUI

- **Ein positionales Startargument kostet der Mac-App ihr Fenster.** AppKit
  deutet es als Dateiöffnung; ohne SwiftUI-Fenster greift `.onOpenURL` nicht.
  `SavageModPlayerApp.init()` setzt `NSTreatUnknownArgumentsAsOpen`; eigene
  Schalter bleiben besser `-Schlüssel Wert`. Beleg ist ein Startlauf:
  `bash Tests/launch_argument_smoke.sh`.
- **`@Published` meldet in `willSet`.** Der Sink-Parameter ist neu, Objekt und
  abgeleitete Caches noch alt. Muss ein Abonnent zurücklesen, nach der Zuweisung
  ein eigenes `PassthroughSubject` senden.
- **Swift-6-Isolation auf iOS kann SIGTRAP auslösen.** Combine-Sinks auf
  Systembenachrichtigungen und `MPRemoteCommand`-Handler bleiben deshalb
  ausdrücklich entkoppelt (`.receive(on:)` beziehungsweise `@Sendable`).

## Audio und Nebenläufigkeit

- **Zwei getrennte Atomics brauchen im Dreifachpuffer seq_cst-Barrieren.**
  Acquire/Release auf zwei verschiedenen Atomics (Leseranspruch und
  veröffentlichte Generation) erzwingt nicht, dass eine Seite die Schreibung
  der anderen sieht — der klassische Store-Buffering-Fall. Unter Linux
  kombinierte ein Leser so einen veröffentlichten Block mit uninitialisierten
  Daten. Zueinander passende sequentiell konsistente Barrieren
  (`CSavageAtomics.c`, `LockFreeAtomicUInt64.swift`) beheben das; Beleg waren
  je 100 Release-Stressläufe auf macOS und Linux (2026-08-29).

## iOS-Dauersemantik

- Finder-ZIPs werden beim Dateisystemabgleich automatisch streamend ausgepackt.
- Visualisierungen laufen nur im sichtbaren Abschnitt. Beim Herausscrollen,
  Tabwechsel oder Sperren verschwinden Views und Caches, der Core sinkt auf etwa
  5 Hz. Höchstens 32 Oszilloskope, im 4-/8-spaltigen Raster.

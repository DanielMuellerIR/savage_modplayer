# Vollständiges Quellcode-Review vom 2026-10-07

Stand: Version 1.6.28. Das Review umfasst den gesamten Produktbereich, nicht nur
die Änderungen seit 1.6.22. Alle nachfolgend bestätigten Funde sind korrigiert.
Ein Review ist kein Beweis für Fehlerfreiheit; die Grenzen stehen unten.

## Abdeckung

| Bereich | Gelesener und geprüfter Umfang |
| --- | --- |
| Parser | Alle neun Parserdateien, ModuleModels, Formatgrenzen und synthetische Format-/Erweiterungsfixtures. |
| DSP | RenderEngine, DSPChannel, SequencerCore, IT-Patternzustand/Voice-Pool, Renderer, Notenvorschau, Atomics, Visualizer und Coordinator. |
| Audio und CLI | Alle fünf Audio-Abstraktions-/Sink-Dateien, CLI-Transport, MPRIS/C-Brücke und zugehörige Verträge. |
| Archive und Bibliothek | ZIP-Reader, Entpack-/Importgrenzen, LibraryReset, MusicLibrary, PlaylistScanner, Pfad- und Symlinkschutz. |
| Native Apps | macOS-Start, Eingabe, Export, Transport, Playlist und Notenfenster; iOS-Appmodell, Wiedergabe, Session/NowPlaying, Import, File Provider, Reset und Ansichten; komplette Quick-Look-Extension. |
| Web und Lieferung | Parser/App/Worklet, build.py, Build-/Install-/Notary-/DMG-/Linux-/Publish-Skripte, Package.swift und CI. |

Sechs getrennte Lesedurchgänge wurden zusammengeführt. Layout-/Theme-Definitionen
wurden gezielt durchsucht; relevante Zustandswechsel und Datenwege wurden im
Zusammenhang gelesen. Testdateien wurden nach dem jeweiligen Risiko ausgewählt,
nicht jede Testzeile einzeln erneut bewertet. Änderungen blieben bei bestätigten
Fehlern; keine pauschale Umstrukturierung und keine zusätzliche Audiobearbeitung.

## Korrigierte Funde

P1 bezeichnet mögliche Abstürze, Ressourcen-/Datenrisiken oder eine falsche
Veröffentlichung; P2 bezeichnet fehlerhaftes Produkt-/Testverhalten.

| Priorität | Stelle der Korrektur | Auslöser und Änderung | Beleg |
| --- | --- | --- | --- |
| P1 | [Sources/SavageModPlayerCore/Audio/AVAudioEnginePCMSink.swift:195](../../Sources/SavageModPlayerCore/Audio/AVAudioEnginePCMSink.swift#L195) | Parallele Start-/Stop-Aufrufe konnten Graph und Puffer gleichzeitig aufbauen oder freigeben. Ein Kontroll-Lock schützt den gesamten Lebenszyklus, außerhalb des Renderblocks. | PCMSinkConcurrencyTests; macOS ohne Skip. |
| P1 | [Sources/SavageModPlayerCore/Audio/ALSAPCMSink.swift:179](../../Sources/SavageModPlayerCore/Audio/ALSAPCMSink.swift#L179) | Zwei Starts konnten dasselbe ALSA-Handle beanspruchen; Stop konnte vor Veröffentlichung des Wiedergabe-Threads zurückkehren. Reservierter Startzustand und serialisierte Kontrolle; Selbst-Stop wartet nicht auf sich selbst. | PCMSinkConcurrencyTests unter Linux mit ALSA-Nullausgabe ohne Skip. |
| P2 | [Sources/SavageModPlayerCore/DSP/DSPChannel.swift:1926](../../Sources/SavageModPlayerCore/DSP/DSPChannel.swift#L1926) | MOD-EDx ohne neue Instrumentnummer löschte das laufende Sample beim verzögerten Trigger. Nur ausdrücklich vorgemerkte Instrument-/Sampleänderungen werden angewendet. Derselbe Fehler wurde im JS-Worklet korrigiert. | Native ED2-Regression und worklet-timing.mjs; alte JS-Fassung scheitert an zwei Assertions. |
| P2 | [Sources/SavageModPlayerCore/DSP/ITPlaybackVoicePool.swift:220](../../Sources/SavageModPlayerCore/DSP/ITPlaybackVoicePool.swift#L220) | IT-SDx wendete DCT/NNA schon an Tick 0 an und schnitt die bisherige Voice zu früh ab. Der neue Ton und seine Voice-Übergabe warten bis zum Ziel-Tick. | ITVoicePoolTests mit NNA Cut/Continue und Voice-Generation. |
| P2 | [Sources/SavageModPlayerCore/DSP/ITPlaybackVoicePool.swift:333](../../Sources/SavageModPlayerCore/DSP/ITPlaybackVoicePool.swift#L333) | IT-Lxy wurde im Voice-Pool nicht wie Gxx als Portamento erkannt. Lxy erhält nun die laufende Voice und Sampleposition. | ITVoicePoolTests: Gxx-Speicher gefolgt von L00. |
| P2 | [Sources/SavageModPlayerCore/DSP/SequencerCore.swift:301](../../Sources/SavageModPlayerCore/DSP/SequencerCore.swift#L301) | IT-Axx änderte im modernen Tempomodus die Tickzahl, aber nicht deren Dauer. Die Dauer wird nach der Speedänderung neu berechnet. | Bei 48 kHz, 125 BPM, vier Reihen/Beat und A03: 1.920 Frames/Tick, 5.760 Frames/Reihe. |
| P2 | [Sources/SavageModPlayerCore/Parser/S3MParser.swift:234](../../Sources/SavageModPlayerCore/Parser/S3MParser.swift#L234) | Ein PCM-Instrument ohne SCRS-Signatur wurde still als leeres Instrument akzeptiert. Strukturell beschädigte PCM-Header werden abgelehnt; leere/AdLib-Platzhalter bleiben möglich. | MultiFormatTests: beschädigter PCM-Header. |
| P2 | [Sources/SavageModPlayerCore/Parser/ModuleModels.swift:361](../../Sources/SavageModPlayerCore/Parser/ModuleModels.swift#L361) | Explizite Ein- und Zwei-Frame-Loops wurden global unterdrückt. Positive explizite Loops bleiben erhalten; der MOD-Parser behält seine eigene Sentinelregel. | MultiFormatTests: S3M-Loops mit einem und zwei Frames; bestehende IT-/XM-Suiten. |
| P1 | [Sources/SavageModPlayerCore/Parser/ITOpenMPTExtensionParser.swift:373](../../Sources/SavageModPlayerCore/Parser/ITOpenMPTExtensionParser.swift#L373) | Übergroße numerische Erweiterungsfelder konnten beim Int-Cast negative Werte erzeugen und nachfolgende Berechnungen gefährden. Betroffene UInt32-Felder akzeptieren nur ein bis vier Bytes. | ITOpenMPTCompatibilityTests mit acht Byte großen Feldern; Größenabgleich mit OpenMPT. |
| P1 | [Sources/SavageModPlayerApp/UI/MainView+Input.swift:64](../../Sources/SavageModPlayerApp/UI/MainView+Input.swift#L64) | MediaPlayer kann Handler außerhalb des Hauptthreads aufrufen. Explizit sendbare Handler übergeben Benachrichtigungen an den MainActor; die UI-Abonnenten empfangen auf der Hauptqueue. | Swift-6-App-Build und Prüfung aller sechs Handler/Abonnenten; keine physische Medientaste behauptet. |
| P2 | [Sources/SavageModPlayerApp/UI/MainView+Export.swift:65](../../Sources/SavageModPlayerApp/UI/MainView+Export.swift#L65) | Während des Exportdialogs konnte ein Playlistwechsel das exportierte Sample austauschen. Der Export hält das beim Öffnen ausgewählte Modul fest und meldet fehlende Samples als Fehler. | InstrumentExportTests wechseln vor dem Export das aktive Modul und prüfen die PCM-Ausgabe. |
| P1 | [Sources/SavageModPlayerCore/Playlist/PlaylistScanner.swift:162](../../Sources/SavageModPlayerCore/Playlist/PlaylistScanner.swift#L162) | Verschachtelte Archive konnten pro Ebene erneut das volle Entpackbudget verbrauchen. Ein Scan teilt Byte-, Eintrags- und Archivgrenzen; entpackte Zwischenbäume werden nach dem Scan entfernt. | PlaylistScannerTests mit kleinen gemeinsamen Budgets und Kontrolle der Zwischenverzeichnisse. |
| P2 | [Sources/SavageModPlayerCore/Playlist/PlaylistScanner.swift:251](../../Sources/SavageModPlayerCore/Playlist/PlaylistScanner.swift#L251) | Versteckte Musikdateien und Unterarchive wurden nach erfolgreichem Entpacken übersprungen. Innerhalb geprüfter Archive werden sie einbezogen. | PlaylistScannerTests mit versteckter Datei, Ordner und verschachteltem ZIP. |
| P2 | [Sources/SavageModPlayerCore/Library/MusicLibrary.swift:469](../../Sources/SavageModPlayerCore/Library/MusicLibrary.swift#L469) | Fehlgeschlagene Dateilöschungen wurden verschluckt, während der Index geleert wurde. Fehler werden weitergereicht und der verbleibende Bestand nach Möglichkeit neu gescannt. | MusicLibraryTests: verweigerte Verzeichnisberechtigung; unter Linux als root bewusst übersprungen. |
| P2 | [src/app.js:510](../../src/app.js#L510) | Stop ließ die letzten Browser-Pegelziele stehen. Die Ziele werden jetzt auf null gesetzt, die vorhandene Anzeigeanimation fällt ab. | playback-state.mjs und echter WebKit-Drop-/Stop-Lauf mit Sichtprüfung. |
| P1 | [publish_github.sh:120](../../publish_github.sh#L120) | Git-URL-Umschreibungen, automatische Zusatz-Tags, ein anderes gh-Ziel und mehrdeutige Tags konnten eine falsche Veröffentlichung erzeugen. Ein geprüftes Ziel, vollständige Refs, --no-follow-tags, Commitvergleich und --verify-tag binden den Release; Assets werden vor dem Push geprüft. | Vier Publish-Vertragstests (davon eine echte Git-Probe), einschließlich absichtlich umgebogener URL und falscher Tags; die echte Git-Probe deckt zusätzlich einen mit reinen Mocks verdeckten Fehler der Remote-Abfrage auf. |
| P1 | [Tests/launch_argument_smoke.sh:88](../../Tests/launch_argument_smoke.sh#L88) | Ein fehlgeschlagenes Preference-Backup konnte beim Aufräumen gültige Einstellungen löschen. Vor Änderungen ist ein gültiger Export Pflicht; misslungene Wiederherstellung bewahrt die Sicherung. | Launch-Smoke-Vertragstests für Export- und Restorefehler. |
| P1 | [Tests/launch_argument_smoke.sh:50](../../Tests/launch_argument_smoke.sh#L50) | Breites pkill konnte eine unabhängig gestartete Player-Instanz beenden. Der Smoke-Lauf beendet nur seine markierten Prozesse nach erneutem PID-/Kommandoabgleich. | Vertragstest mit unabhängigem Prozess sowie sechs echte Start-/LaunchServices-Fälle. |

Die UInt32-Grenze folgt den numerischen Songfeldern im
[OpenMPT-Loader](https://github.com/OpenMPT/openmpt/blob/master/soundlib/Load_it.cpp).
Andere, unbekannte Metadatenchunks bleiben nach dem bestehenden Vertrag erhalten.

## Ausgeführte Prüfung

- Neun gezielte Fälle gegen die vorherigen Produktionsdateien: neun Tests mit 25 fehlgeschlagenen Assertions; anschließend grün. Die JS-ED2-Gegenprobe scheiterte vorher an zwei Assertions.
- macOS: vollständige Debug- und Release-Suite, jeweils 473 Tests, zwei Fixture-Skips, null Fehler. App/Appex gebaut und Signaturen geprüft; CLI-Release gebaut, 14 CLI-Vertrags- und acht Wiedergabetests bestanden.
- Linux: 449 Swift-Tests, acht Skips, null Fehler; der Sink-Nebenläufigkeitstest lief mit ALSA-Nullausgabe ohne Skip. Statisches Release-CLI, 14 CLI-Vertrags-, acht Wiedergabe- und vier Desktop-MPRIS-Tests bestanden.
- 22 lokale MODs jeweils acht Sekunden gerendert: alle WAVs byteidentisch zur Baseline vor den Arbeitspaketen.
- iOS: Simulator-Build erfolgreich; 73 Unit-Tests, null Fehler, TEST SUCCEEDED und Exit 0. Das anschließende Sammeln der Simulator-Diagnostik meldete nach 600 Sekunden einen Timeout; der Testlauf selbst war erfolgreich.
- Web: Pattern-Bounds, Worklet-Timing und Wiedergabezustand bestanden; echter WebKit-Lauf mit Drop-Autoplay und Stop, Stop-Ansicht visuell geprüft.
- Skripte: 15 Build-, vier Publish- und drei Launch-Smoke-Vertragstests bestanden; sechs echte App-Startfälle einschließlich LaunchServices bestanden. Kontext-, Desktop-, Drop-, UI-Vertrags- und Referenzvergleichstests ebenfalls ausgeführt; zwei Desktop-Fixture-Skips.
- Erzeugtes HTML und EN/DE-Release-Notes geprüft; git diff --check ohne Befund.

## Grenzen und verbleibende Abnahmen

Es gibt hier keinen lokalen Realweltkorpus für IT, XM und S3M; synthetische Tests
und die beiden Original-IT-Referenzen ersetzen diesen nicht. Physische
Medientasten, Bluetooth-/Lautsprecheraufnahme, iPhone-Hintergrundverhalten und
persönliche Hörabnahme wurden nicht als bestanden gewertet. Linux wurde auf
Ubuntu 24.04 x86_64 geprüft; keine Aussage für andere Distributionen.

[Interpolation, Anti-Click und gemeinsames PCMSink-Paket](2026-10-07-audio-ideas.md)
bleiben getrennte Untersuchungen. Der nachgewiesene ED2-Fehler wurde in Swift
und JavaScript korrigiert; Sampleinterpolation und Anti-Click wurden nicht als
neuer Klangstandard eingeführt. Offene Geräte-/A/B-Abnahmen stehen im
[Backlog](../../tasks/backlog.md). Release-Signaturen, Notary-Tickets und die
Download-Dateien werden zusätzlich am fertig gepackten Release geprüft.

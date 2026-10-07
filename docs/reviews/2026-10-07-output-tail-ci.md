# Zusätzlicher Ausgabetail-Fall aus der GitHub-CI

Stand: Version 1.6.29, 2026-10-07.

Der [macOS-CI-Lauf für 1.6.28](https://github.com/DanielMuellerIR/savage_modplayer/actions/runs/37637894675)
meldete das natürliche Ende eines letzten Teilpuffers nach 0,1378 ms,
obwohl dessen gültige Frames 10,6576 ms umfassen. Lokal bestand derselbe
Hardwaretest; der CI-Befund begrenzt daher die frühere lokale Aussage.

Die Deadline verwendete einen als gültig markierten HAL-Zeitstempel ohne
Untergrenze. Liegt dieser bereits zurück, kann die daraus errechnete Frist
beim Fertigstellen des Puffers schon abgelaufen sein. Die Korrektur verwendet
`max(HAL-Zeit, Zeitpunkt des fertig gerenderten Puffers)` als Beginn und addiert
wie zuvor die gültigen Frames sowie außerhalb des Audiocallbacks die
Pipeline-Latenz. Zukünftige HAL-Zeitstempel bleiben erhalten, fehlende verwenden
den Fertigstellungszeitpunkt. Stop kann das Warten weiterhin unterbrechen.
Es kommen weder Heap-Allokationen noch Locks in den Renderblock.

Eine reine Zeitstempel-Gegenprobe mit zurückliegender Zeit scheiterte vor der
Korrektur (1.288 statt mindestens 2.278 Host-Ticks); die Korrektur besteht sie.
Zwei weitere Eingaben sichern künftige und fehlende Zeitstempel ab. Der bestehende
Hardwaretest und das Freigeben aller Warter bleiben aktiv. Eine akustische
Lautsprecher- oder Bluetooth-Aufnahme wird damit weiterhin nicht behauptet.

Ausgeführte Prüfungen der Korrektur:

- Vier gezielte Audio-Sink-Tests bestanden, ohne Skip; die neue Gegenprobe war vorher rot.
- macOS Debug und Release jeweils 475 Tests, zwei Fixture-Skips, null Fehler.
- Linux Release-Suite: 449 Tests, acht Skips, null Fehler; statisches CLI gebaut.
- macOS und Linux jeweils 14 CLI-Vertrags- und acht Wiedergabetests bestanden.
- 22 lokale MOD-WAVs mit je acht Sekunden bleiben byteidentisch zur Baseline.
- App/Quick-Look gebaut und signiert; JS-Pattern-/Timing- und vier Publish-Vertragstests bestanden; HTML-Diff nur Version, git diff --check ohne Befund.

Die öffentliche CI wird zusätzlich am neuen Release-Commit geprüft. Der iOS-CI-Lauf
zeigte unabhängig davon einen Timeout im Watchdog-Test; das ist kein Beleg für
einen Fehler des realen File Providers. 1.6.28 und dessen Tag bleiben unverändert.

## iOS-Testwarteweg

Im selben CI-Lauf scheiterte der Stillstandstest des Koordinationswächters.
Die Testhilfe blockierte ihren Thread mit Sleep-Polling. Sie wartet jetzt mit
`XCTNSPredicateExpectation`, sodass XCTest seinen Runloop weiter betreibt.
Das Limit von fünf Sekunden, die Bedingung und die Prüfung von `.stalled`
bleiben erhalten; der Produktionswächter wurde dadurch nicht geändert.

Simulator-Build und vollständige Suite mit 73 Tests bestanden lokal ohne Fehler,
mit TEST SUCCEEDED und Exit 0. Die anschließende Simulator-Diagnostiksammlung
wurde separat beendet. Die Entscheidung am synthetischen Test ersetzt weiterhin
keinen echten, hängenden File Provider; diese Geräteabnahme bleibt offen.

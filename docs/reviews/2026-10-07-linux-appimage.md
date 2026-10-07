# Linux-AppImage, 2026-10-07

Version 1.6.27 liefert ein zusätzliches x86_64-AppImage für den Terminalplayer.
Der [AppImage-Handbuchvertrag](https://docs.appimage.org/packaging-guide/manual.html)
bleibt erhalten: AppRun, Terminal-Desktop-Eintrag, Icon und ausführbares CLI.
Die vorhandene Swift-Laufzeit ist statisch eingebunden; ALSA, D-Bus, zlib,
libstdc++ und glibc sind Systembibliotheken. Geprüft wurde Ubuntu 24.04; das
konkrete Binary referenziert glibc-Symbole bis 2.38. Andere Distributionen
werden daraus nicht pauschal als geprüft bezeichnet.

`linux/build-appimage.sh` verwendet ausschließlich das offizielle
[appimagetool-Releaseasset 1.9.1](https://github.com/AppImage/appimagetool/releases/tag/1.9.1),
SHA-256 `ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0`.
Die unveränderte Runtime wird aus diesem Asset extrahiert (944.632 Bytes,
Commit `caf24f9`, SHA-256
`d30a3ba1388ef57be73faabf606e0d326682f48c87f666106a3c8d6b35b58b4f`).
`--runtime-file` verhindert einen wechselnden Runtime-Download.
Das Tool meldet intern Git-Version `8c8c91f`, Build 296.

AppRun erhält das Arbeitsverzeichnis, damit relative Modulpfade weiterhin
auflösbar sind. Vorhandene Eingabebinaries können nicht als Ausgabe ersetzt
werden; falsche Cache-Prüfsummen brechen vor dem Ausführen des Werkzeugs ab.
Dokumentation, Produktversion sowie Swift-/Runtime-Lizenztexte liegen im Paket.
Ein SHA-256-Sidecar enthält nur den Dateinamen, keine lokalen Pfade.

Der echte Starttest fand einen vorhandenen CLI-Fehler: ausdrücklich angeforderte
Hilfe endete mit Fehlercode 2. `--help` und `-h` liefern nun Hilfe auf stdout
mit Exit-Code 0; fehlende Eingaben bleiben Argumentfehler mit Exit-Code 2.
Die neue Regression scheiterte vor dieser Korrektur.

Ausgeführte Prüfungen:

- `linux/build-static.sh` einschließlich Rückgabe der Build-Eigentümerschaft;
  AppImage-Bau, Desktop-Dateiprüfung und SHA-256-Kontrolle.
- Vier AppImage-Vertragstests ohne Skip: echter FUSE-Start, Fallback über
  Extraktion, relative Pfade mit Leerzeichen, byteidentisches WAV gegenüber
  dem direkten Linux-CLI, Ressourcen/Version/Icon/Lizenzen, beschädigter
  Toolcache und Schutz des Eingabebinarys.
- Vier MPRIS-Vertragstests ohne Skip mit dem gepackten Player auf dem
  echten Desktopbus; zwei Instanzen, Stop/Play und Busausfall eingeschlossen.
- Zwei Paketläufe mit gleichem `SOURCE_DATE_EPOCH` waren byteidentisch.
- Linux und macOS jeweils 14 CLI-Vertragstests und 8 Wiedergabetests bestanden.
- macOS: 462 Swift-Tests, 2 Fixture-Skips, 0 Fehler; Release-CLI und
  App-/Quick-Look-Build mit gültigen Signaturen.
- 15 Skripttests, JavaScript-Pattern-Bounds, HTML nur Version,
  `git diff --check` bestanden. Keine Linux-GUI und keine Hörabnahme.

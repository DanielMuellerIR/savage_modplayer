# Linux-MPRIS2, 2026-10-07

Version 1.6.26 ergänzt MPRIS2 ausschließlich in `savage-cli` unter Linux.
Die [MPRIS-Spezifikation](https://specifications.freedesktop.org/mpris/latest/)
ist der Vertrag; libdbus-1 ist die zusätzliche Systembibliothek.

`org.mpris.MediaPlayer2.savage.instance<PID>` exportiert das Standardobjekt
`/org/mpris/MediaPlayer2`. Play/Pause, Stop mit anschließendem Neustart,
Vor/Zurück und Quit gehen durch dieselbe Kontrollschleife wie die Tastatur.
Pausierte oder gestoppte Titelwechsel erhalten diesen Zustand. Metadaten,
Wiedergabestatus, Position und Lautstärke (0–1) sind verfügbar. Seek wird mit
`CanSeek=false` kenntlich gemacht, URI-Öffnen und grafisches Raise werden
abgelehnt. Die optionalen Repeat-/Shuffle-/Fullscreen-Properties fehlen.
Es entsteht keine Linux-Oberfläche.

Die C-Brücke verarbeitet den Bus ausschließlich auf dem Kontrollthread.
Der Audiocallback verwendet daraus nur statisch als lockfrei geprüfte
64-Bit-Atomics für Pegel und Framezähler. Er allokiert dafür keinen Speicher
und ruft weder D-Bus noch Locks auf. Eine fehlende oder beendete Busverbindung
beendet die normale CLI-Wiedergabe nicht.

Ausgeführte Prüfungen:

- `Tests/mpris_contract_tests.py`: vier Tests auf einem realen Linux-Desktopbus
  und dieselben vier unter `dbus-run-session`, jeweils ohne Skip.
- Geprüft: Play/Pause, idempotentes Pause/Stop, Stop → Play ab Position 0,
  Next unter Pause, Previous, Quit, Position unter Pause, Metadaten,
  PropertiesChanged, Introspection/GetAll, unbekannte Properties/Interfaces,
  falsche Typen, schreibgeschützte Properties, Rate 0, zwei unabhängige
  Instanzen und Wiedergabe bei unerreichbarem Bus.
- Ausschließlich synthetische Nullsamples; keine akustische Abnahme behauptet.
- Statischer Linux-Release-CLI-Build; C-Brücke zusätzlich mit
  `-std=c11 -Wall -Wextra -Werror` geprüft. `ldd` bestätigt libdbus-1 und
  keinen Bedarf an einer installierten Swift-Laufzeit.
- Linux: 438 Swift-Release-Tests, 7 Skips, 0 Fehler.
- macOS: 462 Swift-Tests, 2 Fixture-Skips, 0 Fehler; Release-CLI,
  13 CLI-Vertrags- und 8 Wiedergabetests bestanden.
- App-/Quick-Look-Build und Signaturen gültig; 15 Skripttests, 7 Desktop-
  Eintragstests (2 mangels Linux-Werkzeug übersprungen), 6 Kontexttests bestanden.
- HTML neu erzeugt, ausschließlich Versionsdiff; JavaScript-Pattern-Bounds
  und `git diff --check` bestanden.

Die Tests belegen den D-Bus-Vertrag und den CLI-Zustandswechsel. Eine bestimmte
Desktop-Shell, physische Medientasten oder hörbare Lautstärkeverhältnisse sind
keine eigenständigen Prüfergebnisse dieses Laufs.

# Linux-Desktop-App

Seit 1.6.55 besitzt Savage Mod Player eine Qt-6-Oberfläche für Linux.
`linux/gui/` zeichnet die Oberfläche; `savage-desktop-engine` verwendet den
bestehenden Swift-Wiedergabekoordinator, die Speicherformate und den Renderkern.
Der Audiothread arbeitet unabhängig vom JSON-Nachrichtenkanal der Oberfläche.
Die CLI und ihr AppImage bleiben eigenständige Ausgaben.

## Bau und Installation

Voraussetzungen: CMake ≥ 3.21, C++17-Compiler, Docker, Python 3, Qt ≥ 6.4 mit Quick,
Quick Controls, Widgets, DBus, Network, Multimedia sowie den QML-Modulen für
Controls, Layouts, Window und Multimedia. Der Swift-Bau läuft im offiziellen
`swift:6.2.1-noble`-Container; ALSA-, DBus- und zlib-Entwicklungsdateien werden
darin installiert. Der Host braucht keine Swift-Laufzeit. Zur Laufzeit werden
ALSA, libdbus, zlib und die passenden Qt-Systembibliotheken benötigt.
FFmpeg wird für den Videoexport und die Vorschau verwendet; `.7z` benötigt
zusätzlich `bsdtar` aus libarchive.

```bash
./build.sh
./install.sh
~/.local/bin/savage-mod-player
~/.local/bin/savage-mod-player song.mod other.xm music-folder
```

Auf Debian/Ubuntu heißen die Qt-Baupakete typischerweise `qt6-base-dev`,
`qt6-declarative-dev`, `qt6-multimedia-dev`; die QML-Laufzeitmodule müssen ebenfalls
installiert sein. Auf Arch sind dies `qt6-base`, `qt6-declarative` und
`qt6-multimedia`. Der CMake-Bau meldet fehlende Entwicklungskomponenten.

`linux/build-gui.sh --image <Image>` wählt die Swift-Werkzeugkette.
`linux/install-gui.sh --prefix <Pfad> --build-dir <Pfad>` installiert einen
vorhandenen Bau ohne erhöhte Rechte. Die Programme werden versioniert abgelegt;
der Starter wechselt atomar auf die neue Version. Eine vorhandene CLI-Desktopdatei
wird gesichert, ausgeblendet und zur GUI weitergeführt, damit alte Dateizuordnungen
funktionieren. `./install.sh --uninstall` entfernt GUI-Starteinträge und stellt den
alten CLI-Eintrag wieder her. Sammlungsdaten und versionierte Programme bleiben
erhalten.

## Bedienung und Funktionsumfang

Die Hauptansicht folgt dem macOS-Fenster bei gleichem Inhalt und gleicher Größe:
260-Pixel-Sidebar, Kopfzeile, Positionsleiste, Kanalpegel/-oszilloskope, Tracker,
Master-Oszilloskop und Transport. Schmale Fenster verwenden die Kompaktansicht.
Hell/Dunkel, Schriftzoom und Sidebarbreite sind einstellbar.

Dateien, rekursive Ordner und Archive lassen sich öffnen oder hineinziehen.
Weitere Aufrufe liefern ihre Dateien an die laufende Instanz. Die Bibliothek
bietet Baumansicht, Metadatensuche/-filter, Favoriten, gespeicherte Filter,
Playlists, Warteschlange und Verlauf. Die Instrumentansicht bietet Vorhören und
Sample-WAVs. Modul- und Sample-Inspektoren verwenden die gemeinsamen
Diagnosemodelle, einschließlich Hüllkurven, Tastenzuordnung und Loop-Bereichen.

Wiedergabe, Zeilen-/Zeit-Sprünge, Tempo/Speed, Mute/Solo, Schleifen/Zufallsfolge,
Titelklang, Einschlaftimer und A/B benutzen denselben Koordinator. Der separate
Notenregen verwendet die gemeinsame Sequencer-Vorschau. Stereo-WAVs, Kanalspuren,
Stapel- und Sample-Exporte sowie H.264/MOV mit verlustfreiem Float32-Audio sind
verfügbar. Bestätigtes Ersetzen von Stereo- und Sample-WAVs veröffentlicht erst
nach erfolgreichem Export; fehlgeschlagene Exporte erhalten das alte Ziel.
Sample-Exporte behalten den vor dem Speicherdialog gewählten Titel fest.
`.savagecollection` überträgt Playlists, Favoriten, Songstellen und
Klangwerte mit Zuordnungs-/Konfliktprüfung und Wiederherstellungsjournal.

Leertaste schaltet Play/Pause; Pfeile wechseln Titel. Unter Linux ersetzen
Ctrl-Tastenkürzel die Command-Tastenkürzel: Ctrl+O, Ctrl+F, Ctrl+, sowie
Ctrl+Shift+N für Notenregen. Die Mediensteuerung nutzt MPRIS2 einschließlich
Position, Seek, Lautstärke, Wiederholung und Zufallsfolge.

## Konkrete Plattformunterschiede

| Bereich | Linux-Verhalten und technischer Grund |
|---|---|
| Oberfläche | Qt Quick statt SwiftUI, da SwiftUI nicht für Linux verfügbar ist. Systemschriften, Schrift-Rasterung, Fensterrahmen, Dateidialoge und Desktop-Menüs folgen Linux; SF-Schriften werden nicht mitgeliefert; die Apple-Systemsymbole sind als geometrische Icons nachgezeichnet. Maße, Farben, Zustände und Anordnung orientieren sich an der Mac-App. Eine völlige Pixelidentität wird dadurch nicht zugesichert. |
| Ausgabe | ALSA statt AVAudioEngine. Der externe 3,2-kHz-LED-Ausgabefilter wird als zweipoliger Tiefpass berechnet; Apples interne EQ-Implementierung steht nicht zur Verfügung. Der gemeinsame Tracker-DSP bleibt identisch. |
| Sammlungssync | CloudKit benötigt Apples Framework, Accountzugriff und signierte Apple-App. Unter Linux steht der geprüfte Dateiaustausch zur Verfügung; es gibt keine CloudKit-Nachbildung. |
| Dateivorschau | Quick Look und Finder-Integration sind macOS-Dienste. Linux registriert Dateitypen und öffnet sie in der GUI; eine Dateimanager-Vorschauextension ist nicht enthalten. |
| Updates | Sparkle ist macOS-spezifisch. Linux wird durch erneutes Bauen/Installieren aktualisiert; es besteht kein signierter Linux-Updatefeed. |
| Video | FFmpeg übernimmt H.264/Float32-MOV statt AVFoundation. Audio und Video verwenden dieselbe ganzzahlige 48-kHz-Sampleuhr; das letzte Bild endet am Audioende. |

Die GUI wird gegen synthetische Module ohne mitgelieferte Musik geprüft.
Prüfbefehle und Grenzen stehen im [Test-Runbook](testing.md#linux-gui).

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

## GitHub-Updates und fertige Linux-Pakete

Ab 1.6.58 enthält jedes Release `savage-mod-player-<Version>-linux-x86_64.tar.gz`
und die zugehörige SHA-256-Datei. Dieses Archiv enthält die Qt-App, die statische
Swift-Engine und den Installer; es benötigt weder Docker noch Swift zum Installieren.
Das CLI-AppImage ist eine gesonderte Ausgabe und besitzt keinen GUI-Updater.

Auf Ubuntu 24.04 werden folgende Laufzeitpakete benötigt:

```bash
sudo apt install python3 openssl libasound2t64 libdbus-1-3 libqt6widgets6t64 \
  qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
  qml6-module-qtquick-window qml6-module-qtmultimedia \
  qml6-module-qtqml-workerscript qml6-module-qtquick-templates
```

Archiv und Prüfsumme von derselben GitHub-Release-Seite herunterladen, die
Prüfsumme mit `sha256sum -c <Archivname>.sha256` prüfen und das Archiv entpacken.
Im entpackten Verzeichnis `savage-mod-player-linux` dann `bash install.sh`
ausführen. `--prefix <Pfad>` wählt optional eine andere Benutzerinstallation.
Vorhandene Sammlungen und die bisherige Version bleiben erhalten. Die
Startfähigkeitsprüfung bricht bei fehlenden Bibliotheken ab, bevor sie die
aktive Version ersetzt. Bereits laufende Player können ihre Wiedergabe fortsetzen.

Der Player prüft beim Start und während des Betriebs höchstens einmal täglich
auf Updates. **Einstellungen → Automatisch nach Updates suchen** schaltet die
Hintergrundprüfung aus. **Hilfe → Nach Updates suchen…** und derselbe Button in
den Einstellungen prüfen manuell. Neue Versionen werden angezeigt und erst nach
Bestätigung geladen und installiert. Die neue Version gilt ab dem nächsten
Start. Der Player startet nach der Installation nicht selbst neu.

Der Feed liegt unter
`https://danielmuellerir.github.io/savage_modplayer/linux/stable.json`.
Ed25519-Signaturen verwenden denselben öffentlichen Schlüssel wie der Mac-
Updater. OpenSSL 3 prüft die Signatur der unveränderten Manifestbytes. Das Paket
muss zu Produkt, Architektur und höherer Version passen und die signierte Größe
sowie SHA-256-Prüfsumme erfüllen. Umleitungen bleiben auf GitHub-HTTPS-Endpunkte
beschränkt. Unsichere Archivpfade, Links und spezielle Dateien werden abgewiesen.
Der bereits installierte Installer prüft und aktiviert das Paket; parallele
Installationen, Abbruch und Fehler erhalten die alte aktive Version.

**Einmaliger Umstieg:** 1.6.57 und ältere Linux-Versionen besitzen diesen Updater
noch nicht. Die erste Installation von 1.6.58 erfolgt deshalb manuell aus dem
Archiv oder mit dem vorhandenen Quellbau. Anschließend sind Updates aus dem
Player möglich. Nicht aktive Quell-/Testbauten dürfen keine bestehende
Benutzerinstallation aktualisieren. Automatische Prüfungen kontaktieren GitHub
Pages, bestätigte Downloads GitHub Releases. Musik- und Bibliotheksdaten werden
nicht übertragen.

## Bedienung und Funktionsumfang

Die Hauptansicht folgt dem macOS-Fenster bei gleichem Inhalt und gleicher Größe:
260-Pixel-Sidebar, Kopfzeile, Positionsleiste, Kanalpegel/-oszilloskope, Tracker,
Master-Oszilloskop und Transport. Schmale Fenster verwenden die Kompaktansicht.
Hell/Dunkel, Schriftzoom und Sidebarbreite sind einstellbar. Visualizer laufen
standardmäßig mit 60 Bildern/s; die Einstellungen bieten 15 Bilder/s als
Sparmodus. Ein kompaktes, ausgeblendetes oder minimiertes Hauptfenster stoppt
die Scope-/Pegelerfassung und die Übertragung der Visualizer-Bilder. Transport
und Spielzeit bleiben aktiv. Der separate Notenregen folgt der gewählten Bildrate.

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
| Updates | Linux verwendet einen signierten GitHub-Feed und atomare Benutzerinstallationen; macOS behält Sparkle. Download und Installation benötigen auf beiden Plattformen eine Bestätigung. |
| Video | FFmpeg übernimmt H.264/Float32-MOV statt AVFoundation. Audio und Video verwenden dieselbe ganzzahlige 48-kHz-Sampleuhr; das letzte Bild endet am Audioende. |

Die GUI wird gegen synthetische Module ohne mitgelieferte Musik geprüft.
Prüfbefehle und Grenzen stehen im [Test-Runbook](testing.md#linux-gui).

<p align="center">
  <img src="src/AppIcon.png" width="128" alt="Savage Mod Player Icon">
</p>

<h1 align="center">Savage Mod Player</h1>

**🌐 Sprache / Language:** [English](README.md) · [Deutsch](README.de.md)

<p align="center">
  <strong>Nativer macOS- und iPhone-Tracker-Player für MOD, S3M, XM und IT — mit unabhängiger Swift-Replay-Engine.</strong>
</p>

Ein eigenständiger Tracker-Modul-Player mit den nativen macOS- und iOS-Apps im Mittelpunkt:

1. **Native macOS App (`Savage Mod Player.app`)** — SwiftUI-Desktop-Anwendung mit `AVAudioEngine`, `AVAudioSourceNode`, echten Echtzeit-Oszilloskopen und Pegel-Metern. Sie spielt ProTracker- und Multichannel-MODs (6/8/… Kanäle, u. a. `6CHN`/`8CHN`/`FLT8`), 15-Sample-Soundtracker-Module, **ScreamTracker 3 (`.s3m`)**, **FastTracker II (`.xm`)** und **Impulse Tracker (`.it`)** — und bringt ein **Quick-Look-Plugin** mit: Leertaste auf einer `.mod`/`.s3m`/`.xm`/`.it` im Finder öffnet eine abspielbare Audio-Vorschau.
2. **Native iPhone-App (`ios/`)** — SwiftUI-App auf derselben Replay-Engine. Sie spielt bei gesperrtem Bildschirm weiter, lässt sich über Sperrbildschirm und Kopfhörer bedienen, zeigt die Bibliothek als echten Ordnerbaum und nimmt ganze Sammlungsordner auf einen Rutsch auf — ZIP-Archive inklusive, die sie selbst auspackt. Verteilt wird sie per Sideload mit eigenem Developer-Team.
3. **HTML5-Bonusplayer (`savage-mod-player.html`)** — Eine winzige einzelne HTML-Datei (unter 60 KB), die ohne Webserver direkt per Doppelklick aus dem Dateisystem funktioniert. Sie konzentriert sich bewusst auf klassische 4-Kanal-ProTracker-MODs.

**Kein libopenmpt-Wrapper:** Die nativen Apps parsen, sequenzieren, synthetisieren und mischen MOD/S3M/XM/IT selbst in Swift. Sie binden weder `libopenmpt`, `libxmp`, `libmodplug`, DUMB noch eine andere Modul-Replay-Library ein. `openmpt123` dient ausschließlich als optionale externe Referenz bei Entwicklung und Tests.

Keine Variante enthält Moduldateien. Musikstücke werden per Drag & Drop, Datei-Dialog oder — auf dem iPhone — durch Import eines Ordners geladen.

<p align="center">
  <img src="docs/screenshot-dark.png" width="900" alt="Savage Mod Player (Dark Mode) spielt ein 32-Kanal-FastTracker-II-Modul">
</p>

---

## Download

Fertige Builds der macOS-App stehen als notarisierte DMGs auf der [Releases-Seite](https://github.com/DanielMuellerIR/savage_modplayer/releases) bereit. DMG herunterladen, öffnen und die App in den Programme-Ordner ziehen.

Ab 1.6.32 enthält die macOS-App Sparkle-Updates: **Savage Mod Player → Nach Updates suchen…** prüft manuell, unter **Einstellungen → Updates** lassen sich automatische Prüfungen steuern. Jede Installation braucht eine Bestätigung. Downloads und Update-Feed sind signiert; Systemprofildaten werden nicht übertragen. Ältere Versionen brauchen einmalig eine manuelle DMG-Installation. Die Release-Einrichtung steht unter [Sparkle-Releases](docs/sparkle-release.md).

Der HTML5-Player benötigt keinen Download über die Releases hinaus: Die Datei `savage-mod-player.html` lässt sich direkt im Browser öffnen.

Die iPhone-App wird nicht als fertiger Build verteilt. Sie wird per Sideload mit dem eigenen Apple-Developer-Team installiert — siehe [iPhone-App](#iphone-app-1) unter Build.

---

## Quick-Look-Plugin installieren

Das Quick-Look-Plugin steckt bereits im App-Bundle (`Contents/PlugIns/`) — es gibt nichts separat zu installieren:

1. App aus dem DMG nach **`/Applications`** ziehen.
2. Die App **einmal starten** (dabei registriert macOS die enthaltene Quick-Look-Extension).
3. Im Finder eine `.mod`-, `.s3m`-, `.xm`- oder `.it`-Datei markieren und die **Leertaste** drücken — die Vorschau zeigt den macOS-Audio-Player mit Play, Scrubbing und Lautstärke. Sie rendert bis zu den ersten 60 Sekunden und cached diese Vorschau anhand kanonischer Dateiidentität und Subsekunden-Änderungszeit; weitere Aufrufe sind dadurch sofort da, ohne Kollisionen gleichnamiger Dateien. Nicht unterstützte Dateien zeigen den Parsergrund statt eines endlosen Ladeindikators.

Falls keine Vorschau erscheint:

- Quick-Look-Dienst neu laden: `qlmanage -r` im Terminal, dann die Vorschau erneut öffnen.
- Registrierung prüfen: `pluginkit -m -p com.apple.quicklook.preview | grep -i savage` muss einen Eintrag zeigen; falls nicht, App einmal starten oder neu nach `/Applications` kopieren.
- **Hinweis zu `.mod` und VLC**: Ist VLC (oder eine andere App, die `.mod` als Audio-/Video-Typ registriert) installiert, kann macOS `.mod`-Dateien mit seiner eingebauten Medien-Vorschau abfangen, bevor Drittanbieter-Plugins gefragt werden — eine Systembeschränkung von Quick Look. Die Extension claimt zusätzlich die verifizierten VLC-Identifier für `.s3m`, `.xm` und `.it`.

---

## Funktionsumfang

- **Unabhängige native Replay-Engine**: projekteigene Swift-Parser, Sequencer, Instrument-/Voice-Engines, Effekte, Filter, Resampling und Mixer. Hinter der Oberfläche steckt kein fremder Modul-Decoder.
- **Formatvielfalt (macOS-App)**: ProTracker-MOD, Multichannel-MOD (`xCHN`/`xxCH`/`CD81`/`OKTA`/`FLT8`), 15-Sample-Soundtracker, ScreamTracker 3 (`.s3m`), FastTracker II (`.xm`) und Impulse-Tracker-Dateien bis `cmwt=0x0216` (`.it`) im Sample- oder Instrument-Modus. IT unterstützt 64 Pattern-Kanäle, einen vorallozierten 256-Voice-NNA-Pool, komprimierte 8-/16-Bit-Mono-/Stereo-Samples, Hüllkurven, Filter, Effekte und Sustain-Loops. Der HTML5-Player bleibt bewusst kompakt und spielt 4-Kanal-MODs.
- **Quick-Look-Vorschau (macOS-App)**: Das mitgelieferte Quick-Look-Plugin rendert und cached bis zu den ersten 60 Sekunden von `.mod`/`.s3m`/`.xm`/`.it` mit der Player-Engine und zeigt im Finder (Leertaste) den nativen Audio-Player mit Play und Scrubbing. Nicht unterstützte Dateien zeigen einen lesbaren Grund.
- **Drag & Drop**: Einzelne `.mod`-/`.s3m`-/`.xm`-/`.it`-Dateien, ganze Ordner (rekursiv) oder Zip-/7-Zip-Archive können auf den Player gezogen werden.
- **Automatische Playlist**: Ein konfigurierbarer Autoplay-Ordner (macOS-App: Einstellungen, Cmd+,) wird beim Start gescannt und als Playlist geladen; ohne Konfiguration wird ein `audio/`-Unterordner neben dem Player bzw. der App verwendet.
- **Hierarchische Playlist**: Ordner und Archive erscheinen als auf- und zuklappbarer Baum. Ordner starten zugeklappt, der Pfad zum laufenden Titel klappt automatisch auf, und Wiedergabe wie Shuffle laufen über alle Ordner hinweg.
- **Archive wie Ordner (macOS-App)**: Zip- und 7-Zip-Archive werden unsichtbar in ein temporäres Verzeichnis entpackt (aufgeräumt beim Beenden) und in der Playlist wie normale Ordner angezeigt.
- **Playlist-Bedienung**: Einzelklick auf einen Playlist-Eintrag lädt und startet den Titel direkt. Nach dem Songende kann die Playlist automatisch weiterlaufen.
- **Echtzeit-Oszilloskope**:
  - Ein echtes Stereo-Master-Mischungs-Oszilloskop direkt aus dem Audio-Renderpfad.
  - Separate Spur-Oszilloskope für jeden Kanal (dynamische Kanalzahl), die die tatsächlichen Schwingungsformen direkt aus dem Synthesizer-Render-Block visualisieren.
- **Fallende Noten mit Klaviatur (macOS-App)**: **Darstellung → Notenregen öffnen** oder **Umschalt–⌘–N** öffnet ein eigenes, skalierbares Fenster mit Notennamen und Kanalfarben. Standardmäßig zeigt es 88 Tasten von A0 bis C8 und erweitert sich für Tracker-Noten außerhalb dieses Bereichs; **Tonumfang** verkleinert das Fenster auf den Bereich des Stücks und erhält dabei die Breite von Tasten und Balken; **Klaviatur** stellt die Gesamtansicht und die vorherige Fensterbreite wieder her. Zwei, vier oder acht Sekunden Vorlauf folgen dem Audio-Sequencer, einschließlich Loops, Notenverzögerungen und überlappender IT-Stimmen. Die Balken zeigen ausgelöste Tracker-Noten und die Laufzeit klingender Stimmen; Sample-Inhalte und kontinuierliche Pitch-Effekte werden nicht in Einzelnoten zerlegt. Nach manuellen Sprüngen und Tempoänderungen wird die Vorschau kurz neu berechnet.
- **Multi-Theme**:
  - **Dark**: Graphit-/Schwarzpalette mit gutem Kontrast und gedämpften Akzentfarben.
  - **Light**: klassischer, heller macOS-naher Stil mit nüchternem Kontrast.
- **PAL- & NTSC-Taktfrequenzen**: Umschaltbare Paula-Taktung (3,546 MHz PAL vs. 3,580 MHz NTSC) für Paula-basierte MOD-Formate; bei Formaten mit eigenem Frequenzmodell ist die Steuerung ausgeblendet.
- **Lautstärke & Stereo-Separation**: Psychoakustische (quadratische) Lautstärkeskalierung und einstellbare Stereo-Separation (Bleed von 0% Mono bis 100% Hard-Panning).
- **Hi-Fi Resampling**: Umschaltbares linear-interpoliertes Sample-Playback für weicheren Sound (deaktivierbar für originalen 8-Bit-Crunch).
- **WAV- & Kanalspuren-Export (macOS-App)**: Stereo-Mix, tatsächlich gespielte Stereo-Kanalspuren als Float32-WAV mit gemeinsamem Pegel und Referenzmix sowie einzelne Instrumentensamples. Der [Kanalspuren-Export](docs/channel-stem-export.md) übernimmt Mute/Solo und Audiooptionen; Fortschritt, Abbruch und neue Zielordner schützen vorhandene Dateien. Der [Stapel-Export](docs/batch-wav-export.md) rendert ausgewählte Listentitel oder Suchtreffer mit gespeicherten Einstellungen, Fortschritt, Abbruch und Zielkonfliktbehandlung. Die iPhone-App hat bewusst keinen WAV-Export.
- **Einschlaftimer (Mac und iPhone/iPad)**: 1–720 Minuten, sanftes Ausblenden in den letzten zehn Sekunden, Verlängerung um 15 Minuten und Abbruch bei unverändertem Lautstärkewert. Der Countdown läuft bei Pause und Titelwechsel weiter. [Details zum Einschlaftimer](docs/sleep-timer.md).
- **Klang pro Titel (Mac und iPhone/iPad)**: Globale Vorgaben und ausdrückliche Titel-Overrides für MOD-Clock, Stereo-Separation, Interpolation und LED-Ausgabefilter; einzelne Werte erben oder den Titel zurücksetzen. [Details zu Titel-Einstellungen](docs/track-playback-settings.md).
- **Notenregen als Video exportieren (macOS)**: **Export → Notenregen als Video…** öffnet eine pausierte Fünf-Sekunden-Vorschau, Auflösung/Bildrate/Kompression und geschützte Zielwahl. H.264-Bild und verlustfreies Stereo-Float32-Audio verwenden dieselbe Sample-Zeitbasis. Fortschritt, Abbruch und Finder-Zugriff sind enthalten. [Videoexport-Details](docs/note-rain-video.md).
- **Sammlungen übertragen**: macOS und iPhone/iPad exportieren und importieren Playlists, Favoriten, Songstellen und Klang-Einstellungen als `.savagecollection`-Dateien. Am Mac öffnet **Sammlung → Sammlung übertragen…** den Dialog, auf iPhone/iPad **Sammlung übertragen** im Bibliotheksmenü. Lokale Titelzuordnungen prüfen, fehlende Titel zuordnen oder überspringen und Konflikte vor der Übernahme entscheiden. Musik, Lautstärke, laufende Timer und Warteschlange bleiben lokal. Unterbrochene Übernahmen werden vor dem Öffnen der Sammlung wiederhergestellt. [Formatdetails](docs/collection-exchange.md). **Sammlung → Sammlung abgleichen…** am Mac beziehungsweise **Sammlung abgleichen** in den iPhone/iPad-Einstellungen öffnet Einrichtung, Status, Titelzuordnung und Konfliktentscheidungen. Das macOS-Release 1.6.52 enthält CloudKit-Unterstützung; der Abgleich beginnt erst nach dem Einschalten und Bestätigen der ersten Titelzuordnung. Playlists, Favoriten, Songstellen und Klang-Einstellungen nutzen deine private iCloud-Datenbank. Musikdateien und Lautstärke bleiben auf dem jeweiligen Gerät. Synthetische Mac-/iPhone-Rundwege sowie Konflikt- und Löschprüfungen bestehen in Entwicklung und Produktion. Selbst gebaute Versionen lassen den Cloud-Zugriff ausgeschaltet, solange kein geprüftes CloudKit-Profil angegeben wird. [Abgleich und Voraussetzungen](docs/collection-sync.md).
- **Komplette Tastatursteuerung (macOS-App)**: Leertaste für Play/Pause, Pfeiltasten links/rechts für Song-Positionen, Pfeiltasten oben/unten für Song-Wechsel in der Playlist.

### Gespeicherte Playlists und Als Nächstes (macOS)

**Playlists…** in der Seitenleiste speichert die aktuell sichtbaren Titel als
benannte Liste. Der Dialog öffnet Listen und erlaubt Umbenennen, Umsortieren und
Löschen. Das Kontextmenü eines Titels fügt ihn einer bestehenden Liste hinzu,
spielt ihn als Nächstes oder hängt ihn an die Sitzungswarteschlange an. **Als
Nächstes** öffnet die Warteschlange zum Verschieben und Entfernen. Weiter verwendet
sie vor der bisherigen Liste; ein pausierter Titelwechsel bleibt pausiert.

Suche und Favoritenfilter ändern die Anzeige. **Diese Ergebnisse abspielen**
begrenzt Wiedergabe und Shuffle ausdrücklich auf die Treffer; **Alle** gibt wieder
die ganze Liste frei. Gespeicherte Listen verweisen auf Originaldateien und
Archivmitglieder, auch in verschachtelten Archiven. Diese Quellen müssen verfügbar
bleiben. Fehlende Titel bleiben gespeichert und werden beim Öffnen gemeldet.
Gleichnamige Dateien in verschiedenen Ordnern haben getrennte Favoriten. Alte
Favoriten werden beim Auffinden übernommen; mehrdeutige Namen brauchen einen neuen
Stern. Diese Oberfläche gibt es zunächst auf macOS.

### Sample-Inspektor (Mac/iPhone/iPad)

**Samples untersuchen…** öffnet Wellenform, Zoom, Stereo-Kanäle und getrennte
Loop-/Sustain-Bereiche. Alle XM-Instrument-Samples und der globale IT-Samplepool
bleiben erreichbar; vorhandene Tastenzuordnungen zeigen Quell-/Zielnoten und
Sample-Nummern. Der Inspektor verändert keine Daten. Details:
[Sample-Inspektor](docs/sample-inspector.md).

**Modul untersuchen…** ergänzt Aufbau und Herkunft, Instrument-Hüllkurven und
vorhandene Kompatibilitätsdiagnosen. Die Effektansicht erklärt übernommene
formatabhängige Befehle samt Volume-Spalte. Auf iPhone/iPad liegen beide
Inspektoren im Info-Menü der Wiedergabeansicht. Details:
[Modul-Inspektor](docs/module-inspector.md).

### Songstellen und Bereichsauswahl (Mac/iPhone/iPad)

**Songstellen…** speichert benannte Position-/Zeilenpaare pro Originalquelle.
Die Ziele bleiben über Neustarts erhalten; fehlende Ziele bleiben vermerkt.
Eine getrennte Bereichsauswahl markiert Zeilen im Mac-Tracker und in der
Positionsleiste des Notenregens. Der vorhandene zeilengenaue Sprung erhält den
Transportzustand. **A/B vorbereiten und abspielen** rekonstruiert den tatsächlichen
Wiedergabezustand bei A und wiederholt bis zum letzten Tick von B. Die Vorbereitung
ist abbrechbar und auf zehn Minuten Songverlauf begrenzt. Ausschalten spielt an der
aktuellen Stelle weiter; Sprünge oder Audioeinstellungen lösen die Schleife.
Der Mac-Notenregen folgt denselben Samplegrenzen. Details: [Songstellen](docs/song-markers.md).

### Metadatensuche und gespeicherte Filter (Mac/iPhone/iPad)

Die Suche findet Dateinamen, Ordner, interne Titel und Instrumentnamen. **Anzeige und Filter**
kombiniert Format, Kanalzahl, Favoriten, ungehörte und neu erfasste Titel mit
Sortierung und benannten Filtern. Ausdrückliche Wiedergabe folgt der Anzeigereihenfolge.
Tatsächliche Wiedergabe merkt den Hörstatus, Auswahl und Indexierung nicht.
Sammlungshinweise zeigen ungültige Dateien und unterscheiden gleiche Namen von
identischem Inhalt. `≥` kennzeichnet begrenzte Dauern. Details: [Filterbedienung](docs/library-filters.md).

### iPhone-App

- **Gespeicherte Playlists und Warteschlange**: Das Listenmenü in der Bibliotheks-Werkzeugleiste öffnet benannte Listen und die Sitzungswarteschlange. Listen anlegen/umbenennen, Titel über ihr Kontextmenü hinzufügen und mit „Titel bearbeiten“ im Optionenmenü entfernen/umsortieren. „Als Nächstes“ hat Vorrang, danach geht die vorherige Liste weiter. Fehlende Titel bleiben gespeichert; Referenzen verwenden relative Bibliothekspfade. Suchtreffer lassen sich ausdrücklich abspielen.

- **Hintergrundwiedergabe und Sperrbildschirm-Steuerung**: Die Wiedergabe läuft bei gesperrtem Bildschirm weiter. Titel, Format, Ordner, Titelbild und verstrichene Zeit erscheinen auf dem Sperrbildschirm; Play, Pause, Weiter, Zurück, Positionsregler sowie −15 s / +30 s funktionieren von dort und über die Kopfhörersteuerung. Ein eingehender Anruf pausiert und setzt danach fort; das Abziehen der Kopfhörer pausiert, statt auf den Lautsprecher zu wechseln.
- **Bibliothek als Ordnerbaum**: Ordner starten zugeklappt, der Pfad zum laufenden Titel klappt automatisch auf, und Wiedergabe wie Zufallswiedergabe laufen über alle Ordner. Live-Suche, Favoriten, Loop-Modi und Sitzungswiederherstellung sind dabei.
- **Ordner-Import**: Einen Ordner auswählen, und alles Spielbare darin wird mitsamt Struktur in die Bibliothek kopiert. ZIP-Archive werden ausgepackt, Doppelte übersprungen, der Fortschritt angezeigt, und der Import lässt sich abbrechen. Verschachtelte Archive teilen sich eine Sicherheitsgrenze für Bytes, Einträge und Archivzahl; Links werden abgelehnt, und bei unvollständiger Übernahme bleibt die Quelle erhalten. Dateien aus einem Cloud-Dateianbieter werden zuvor geladen und koordiniert gelesen.
- **Finder-Dateifreigabe**: iPhone anschließen, im Finder „Dateien" öffnen und ganze Ordner oder ZIP-Archive auf die App ziehen; dieselbe Bibliothek erscheint in der iOS-Dateien-App unter „Auf meinem iPhone". Der Index wird bei jedem Start mit dem Dateisystem abgeglichen, ZIPs werden automatisch ausgepackt.
- **Visualisierungen nach Sichtbarkeit**: nach unten scrollen, und Master-Oszilloskop, VU-Meter sowie Kanal-Oszilloskope starten sofort; wegscrollen, Tab wechseln oder Bildschirm sperren, und Views wie Wellenform-Caches werden freigegeben. Bis zu 32 Kanal-Oszilloskope stehen lesbar in vier Spalten auf dem iPhone beziehungsweise acht auf breiten Layouts.
- **iPad**: Auf breiten Bildschirmen steht die Bibliothek links und die laufende Wiedergabe rechts. Master- und Kanal-Oszilloskope wachsen in die freie Höhe der Wiedergabespalte. Module und ZIP-Archive lassen sich aus der Dateien-App direkt in die Bibliothek ziehen — sie werden übernommen und Archive ausgepackt, ohne die laufende Wiedergabe zu unterbrechen. Mit angeschlossener Tastatur schaltet die Leertaste zwischen Abspielen und Pause, Cmd+← und Cmd+→ wechseln den Titel, Cmd+Umschalt+← und Cmd+Umschalt+→ springen zehn Sekunden. Während das Suchfeld aktiv ist, tippt die Leertaste ein Leerzeichen. Alle Kürzel erscheinen beim Halten von Cmd.
- **Erscheinungsbild**: verwendet dieselbe ruhige Blau-/Cyan-/Graphit-Palette und dasselbe App-Icon wie die Mac-App. Es folgt dem System und lässt sich fest auf hell oder dunkel stellen. Deutsch und Englisch.

---

## Bedienelemente & Anzeigen erklärt

Die Transport-Tasten erklären sich von selbst, doch die tracker-typischen Anzeigen und Schalter tragen ein Stück Amiga-Geschichte in sich. Jeder Punkt hier ist in der App auch als **Tooltip** hinterlegt — einfach mit dem Mauszeiger auf einem Bedienelement verweilen, bis die Erklärung erscheint. Weil Tooltips ein paar Sekunden brauchen und leicht zu übersehen sind, sind sie hier zusätzlich gesammelt.

**Kopfzeilen-Anzeigen**

- **CH** (genutzte Kanäle): zählt Pattern-Kanäle, die tatsächlich Noten, Instrumente, Lautstärkeangaben oder Effekte enthalten; reservierte, leere Kanäle zählen nicht mit. Tracker-Grid und Kanal-Oszilloskope zeigen genau diese Kanäle unter ihrer ursprünglichen Kanalnummer, sodass weder ITs reservierte 64-Kanal-Kapazität noch Lücken leere Spalten oder eine unnötige Scrollbar erzeugen.
- **BPM** (Beats per Minute): Wiedergabe-Tempo. Der Amiga-Standard ist 125. Mit −/+ veränderbar; ein Song kann sein Tempo per Effekt auch selbst umstellen. Bei Songwechsel wird der Header-Wert des neuen Moduls gesetzt.
- **SPD** (Speed): Ticks pro Pattern-Zeile (Amiga-Standard 6). Kleiner = die Zeilen laufen schneller durch, größer = langsamer. Zusammen mit BPM ergibt das die effektive Geschwindigkeit.
- **PAT** (Pattern-Position): aktuelles Pattern und Gesamtzahl in der Abspielreihenfolge des Songs. Ein Pattern ist ein Notenblock (meist 64 Zeilen); der Song spielt sie in dieser Reihenfolge ab.

**Taktfrequenz** (neben dem Master-Oszilloskop, nur bei Paula-basierten MOD-Formaten)

- **PAL** (3,546 MHz Paula-Takt): wie bei europäischen Amigas — die Referenz-Tonhöhe und -Geschwindigkeit der meisten Module.
- **NTSC** (3,580 MHz Paula-Takt): wie bei US-Amigas — Module klingen minimal höher und laufen etwas schneller als mit PAL.

**Klang-Optionen**

- **LED-Filter**: der zuschaltbare Amiga-Tiefpass bei ~3,2 kHz, der die Höhen kappt — der dumpfere Originalklang, wie wenn am echten Amiga die Power-LED leuchtete.
- **Hi-Fi-Interpolation**: glättet die Samples beim Resampling (weicherer Klang). Ausgeschaltet klingt es wie die Original-Hardware — roher 8-Bit-Sound mit hörbarem Aliasing.
- **Stereo-Separation**: 100 % = hartes Amiga-Panning (Kanäle ganz links/rechts), 0 % = Mono. Dazwischen wird Übersprechen beigemischt, das Kopfhörer-Ermüdung vermeidet. Am deutlichsten mit Kopfhörern hörbar; über Laptop-Lautsprecher kaum.
- **Loop-Modus**: was nach dem Songende passiert — Playlist fortsetzen, den Song wiederholen oder stoppen.

**Transport & Navigation**

- **Shuffle** (Zufallswiedergabe): eingeschaltet springen Titelwechsel und Songende zufällig durch die Playlist; ausgeschaltet spielt die Playlist der Reihe nach. Der Schalter bleibt auch im kompakten Mac-Player sichtbar.
- **−30 s / +30 s**: zurück-/vorspringen (zeilengenau; bei Tempo-Wechseln näherungsweise). Diese beiden Sprünge bleiben auch im kompakten Mac-Player sichtbar; der Vollmodus bietet zusätzlich −10 s / +10 s.
- **Positions-Schieberegler**: eine Stelle im Song wählen — funktioniert auch bei gestoppter Wiedergabe: Play startet dann ab dieser Stelle.

---

## Technischer Hintergrund

### Synthese & Paula-Emulation

Die Audio-Engine simuliert das Amiga Paula-Hardwareverhalten:
- **Taktung**: Der Taktgeber rechnet mit der PAL-Paula-Frequenz von `3.546.894,6 Hz`. Der Pitch-Faktor ergibt sich aus dem Frequenzverhältnis zur aktuellen Audio-Ausgaberate.
- **Stereo-Panning**: Amiga-typisches Hardware-Panning (Kanäle 1 und 4 links, Kanäle 2 und 3 rechts) mit einstellbarer Software-Mischung zur Vermeidung von Kopfhörer-Ermüdung.
- **Effekte**: Vollständige Wiedergabetreue für alle Standard-ProTracker-Befehle, einschließlich Arpeggio (`0x0`), Slides (`0x1`/`0x2`), Tone Portamento (`0x3`), Vibrato (`0x4`), Volume Slides (`0xA`), Position Jump (`0xB`), Volume Set (`0xC`), Pattern Break (`0xD`), Extended Effects (`0xE` wie Loop, Cut, Note Delay, Retrigger) und Tempo-Steuerung (`0xF`).

Für ScreamTracker 3 rechnet die Engine im ST3-Periodenmodell (C2Spd-basierte Perioden gegen die ST3-Clock 14,3 MHz) statt in Amiga-Paula-Perioden; die ProTracker-Effekte werden um S3M-Spezifika (Fine-/Extra-Fine-Slides mit Effekt-Memory, Tremor, Fine-Vibrato, Global Volume) ergänzt.

Für FastTracker II fährt die Engine ein eigenes Instrument-Voice-Modell: Der Modul-Header wählt zwischen FT2s linearer Frequenztabelle und seiner Amiga-Periodentabelle; Multi-Sample-Instrumente mit Keymaps, Lautstärke- und Panning-Hüllkurven (Sustain und Loop, pro Tick interpoliert), Key-Off mit Volume-Fadeout, Auto-Vibrato mit Sweep und Ping-Pong-Sample-Loops funktionieren in beiden Modi. Der XM-Effektsatz inklusive Volume-Column und Per-Kanal-Effekt-Memory wird auf den gemeinsamen DSP-Kern übersetzt.

Für Impulse Tracker trennt die Engine 64 logische Pattern-Kanäle von einem vorallozierten Pool mit 256 Wiedergabe-Voices. Implementiert sind Sample- und Instrument-Modus, NNA/DCT/DCA, 120er Sample-Maps, IT-2.14-/2.15-Kompression, Stereo- und Sustain-Loops, Pitch-/Pan-/Filter-Hüllkurven, resonante Filter pro Voice, Sample-Vibrato, Surround, IT-Effekt-Memory sowie die Profile `Old Effects` und `Compatible Gxx`. Von OpenMPT erzeugte IT-Dateien verwenden zusätzlich strukturiertes XTPM-/STPM-Parsing, klassische/alternative/moderne Tempoformeln, gespeicherte Preamp-/Mix-Werte, Restart-Position, erweiterten Filterbereich und die jeweils zutreffenden PCM-`PlayBehaviour`-Flags.

Version 1.6.53 reduziert den CPU-Aufwand des gemeinsamen Sample-Renderers bei unveränderter Audioausgabe und strenger Echtzeitgrenze im Stresstest. [Performance-Prüfungen](docs/testing.md#performance-abnahme-und-geteilte-ci-runner).

Kompatibilitätsmeldungen entstehen aus einer Capability-Analyse. `cwtv` identifiziert den erstellenden Tracker, `cmwt` steuert dagegen die erforderliche IT-Semantik; eine neuere OpenMPT-Erstellerversion ist allein kein Warnungsgrund. Metadaten, inaktive MIDI-Flags, unbenutzte Plugin-Definitionen und markerähnliche Bytes im PCM bleiben still. Eine Warnung erscheint nur, wenn ein Pattern der abgespielten Order-Liste tatsächlich ein nicht unterstütztes klangrelevantes Merkmal erreicht, soweit möglich mit Instrument, Kanal, Plugin-Slot oder Chunk-ID. `savage-cli --info` zeigt die vollständige strukturierte Diagnose.

### Bekannte Impulse-Tracker-Einschränkungen

- IT-Strukturen bis `cmwt=0x0216` und bekannte PCM-relevante OpenMPT-IT-Erweiterungen werden unterstützt. MPTM wird sicher erkannt, bleibt aber ein separates nicht unterstütztes Format.
- Der Player ist bewusst kein VST-/AudioUnit-Host und gibt kein externes MIDI aus. Eingebettete MIDI-Makros sind auf gebräuchliche Cutoff-/Resonance-Filtermakros beschränkt. Diese Pfade warnen nur, wenn sie tatsächlich getriggert werden.
- Veraltete OpenMPT-Bugemulationen für Swing vor 1.17, die abgelöste alte Pattern-Loop-/Jump-Regel, ungenauen historischen Ping-Pong-Überschuss und proprietäre Envelope-Release-Knoten werden nicht emuliert. Nur die tatsächliche Nutzung erzeugt eine merkmalsspezifische Warnung.
- Erweiterte IT-Patterns mit 1 bis 1.024 Zeilen und bis zu 240 Patterns werden akzeptiert. Gelöschte Pattern-Referenzen in der Order-Liste werden wie in OpenMPT übersprungen.

Pro IT-Modul gelten Grenzen von 33.554.432 dekodierten PCM-Werten (beide
Stereokanäle zusammen) und 4.194.304 expandierten Pattern-Zellen. Größere Dateien
werden vor der entsprechenden Pufferallokation abgelehnt.

### Architektur

| Schicht | macOS und iOS (Swift) | HTML5-Bonusplayer |
|---|---|---|
| Parser | `ModuleLoader` plus projekteigene MOD-/S3M-/XM-/IT-Parser (`SavageModPlayerCore`) | `modplayer.js` |
| DSP / Mixer | Projekteigener Sequencer und DSP via `AVAudioSourceNode`, bis 64 logische Kanäle / 256 IT-Voices | `mod-player-worklet.js` (AudioWorklet) |
| UI | SwiftUI + Canvas (`Sources/SavageModPlayerApp` auf macOS, `ios/SavageModPlayer` auf iOS) | Vanilla JS + CSS Grid |
| Archive | `.zip` überall über den projekteigenen `ZipArchiveReader`; `.7z` nur auf macOS und Linux über `bsdtar` | — |
| Bibliothek | `SavageModPlayerCore/Library` (Index, Import, Zurücksetzen) — von der iPhone-App genutzt | — |
| Quick Look | `quicklook/PreviewProvider.swift` (Appex, WAV-Offline-Render) | — |

---

## Build

### macOS App

```bash
./build.sh                        # → "Savage Mod Player.app" (inkl. Quick-Look-Appex; Wrapper auf build_app.sh)
```

`build_app.sh` kompiliert neben der App auch die Quick-Look-Extension
(`quicklook/`) und legt sie im App-Bundle unter `Contents/PlugIns/` ab.

Die App befüllt die Playlist beim Start aus dem Autoplay-Ordner, der im Einstellungs-Fenster (Cmd+,) konfiguriert ist. Ist keiner gesetzt, sucht sie nach einem `audio/`-Verzeichnis neben der Anwendung und lädt dort gefundene `.mod`-/`.s3m`-/`.xm`-/`.it`-Dateien (oder `mod.*`-Dateien) automatisch in die Playlist. Diese Dateien sind nur lokale Testdaten und gehören nicht ins Git-Repository.

Im selben Fenster steht die Bildrate der Visualisierungen: 30 Hz (Vorgabe, volle
Optik), 24, 15 oder 10 Hz. Daran hängt nicht der Klang, sondern die Rechenlast
der Oberfläche — auf einem Mac mit M5-Chip kostete dieselbe Wiedergabe bei 30 Hz rund 22 %
eines Kerns und bei 10 Hz rund 14 %. Die Änderung wirkt sofort; im kompakten
Fenster bleibt es unabhängig davon bei 5 Hz, weil dort keine Oszilloskope zu
sehen sind.

Für Release-Builds signiert `build_app.sh` automatisch mit der Developer-ID
`Developer ID Application: Daniel Mueller (9QSWKSR4NQ)`, sofern sie im
Schlüsselbund verfügbar ist. Lokale unsignierte Builds sind mit
`SIGN_APP=0 bash build_app.sh` möglich.

### iPhone-App

Das Xcode-Projekt ist eingecheckt und nutzt eine dateisystem-synchronisierte
Wurzelgruppe: neue Swift-Dateien unter `ios/SavageModPlayer/` landen ohne
Projektdatei-Edit im Target. Vorausgesetzt wird Xcode 16 oder neuer.

```bash
bash ios/scripts/build-simulator.sh      # Build für den Simulator, ohne Signatur
bash ios/scripts/run-tests.sh            # XCTest im Simulator
bash ios/scripts/build-device.sh --install   # Build für ein echtes iPhone und Installation
SAVAGE_DEVICE='<Name oder ID>' bash ios/scripts/build-device.sh --install  # mehrere iPhones
```

`build-simulator.sh` bricht ab, sobald der Build Warnungen im projekteigenen
Quellcode meldet — ein grüner Lauf ist also wirklich warnungsfrei. Protokolle
landen unter `ios/build/` und sind nicht getrackt.

Das Signatur-Team steht im Projekt (`DEVELOPMENT_TEAM`). Wer mit einem anderen
Team baut, ändert es in Xcode unter „Signing & Capabilities" oder übergibt dem
Skript `SAVAGE_DEVELOPMENT_TEAM=<eigene Team-ID>`.

Die Team-ID ist kein Geheimnis. Apple bettet sie in die Signatur jeder
ausgelieferten App ein — `codesign -dv --verbose=4` liest sie aus jedem
heruntergeladenen DMG heraus — und sie steht für die macOS-Signatur ohnehin
schon in `build_app.sh`. Zu schützen sind der private Schlüssel des
Signaturzertifikats und die Notarisierungs-Zugangsdaten; beides liegt nicht in
diesem Repository.

**Für den ersten Lauf auf einem neuen Gerät ist Xcode das richtige Werkzeug.**
Gerät beim Team registrieren, Provisioning-Profil anlegen und das
Entwicklerzertifikat auf dem iPhone bestätigen sind einmalige Schritte, durch die
die Oberfläche führt. `ios/SavageModPlayer.xcodeproj` öffnen, Gerät auswählen,
Run drücken. Die gemeinsame Scheme verwendet für Run bewusst Release:
unoptimierter Swift-DSP kann bei anspruchsvollen Modulen langsamer als Echtzeit
sein und dann kratzen; Simulator-Tests bleiben Debug. Danach läuft
`build-device.sh` headless für jeden weiteren Build; es übergibt
`-allowProvisioningUpdates`, damit `xcodebuild` das Profil selbst auffrischen
darf.

Simulator-Build und Simulator-Tests laufen ganz ohne Signatur.

### Kommandozeile (`savage-cli`)

Ein kopfloser Renderer, der exakt dieselbe DSP-Engine nutzt wie App und Quick
Look — gedacht für A/B-Vergleiche gegen Referenz-Renderer und für skriptbare
Prüfungen ohne GUI.

```bash
swift build                                  # → .build/debug/savage-cli
savage-cli song.it --info                    # strukturierte Moduldiagnose, kein Render
savage-cli song.mod -o out.wav -s 30         # 30 s als WAV rendern
savage-cli song.mod --play                   # Echtzeit-Wiedergabe (CoreAudio / ALSA)
savage-cli song.mod --stdout | aplay -f S16_LE -c2 -r44100   # rohes PCM in einen Player
savage-cli --list audio/                     # spielbare Module eines Ordners auflisten
savage-cli --list audio/ --play              # den ganzen Ordner als Playlist abspielen
```

`--stdout` streamt rohes 16-Bit-Stereo-PCM (Little Endian) in begrenzten Blöcken
nach stdout, während Statusmeldungen auf stderr bleiben. Die Wiedergabe kann
sofort beginnen, ohne den ganzen Song zu puffern. Streaming lässt sich nicht mit
`--normalize` kombinieren, weil dessen Peak-Suche die Gesamtausgabe braucht.
`--seconds` akzeptiert 0...600 Sekunden (0 bedeutet Songende mit 600-Sekunden-
Kappung), `--rate` 8.000...192.000 Hz; nicht-endliche oder außerhalb liegende
Werte enden mit Exit-Code 2. `--list` gibt einen Pfad je Zeile aus und endet mit Exit-Code 1,
wenn nichts Spielbares gefunden wurde; zusammen mit `--play` wird der Ordner
stattdessen als Playlist abgespielt — in Pfadreihenfolge, unlesbare Module
werden übersprungen. `--normalize` hebt den Pegel wie Quick Look an; für rohe
Vergleiche weglassen.

Läuft `--play` an einem Terminal, steuern einzelne Tasten die Wiedergabe:
Leertaste oder `p` pausiert und setzt fort, `n` oder Pfeil rechts springt zum
nächsten Titel, `b` oder Pfeil links zurück, `q` beendet. Ohne Terminal (Pipe,
Cron, CI) läuft die Wiedergabe durch, sofern keine Linux-Mediensteuerung genutzt
wird. Ctrl-C schließt die Audio-Ausgabe
und endet mit Exit-Code 130.

#### Linux

Die Core-Bibliothek und `savage-cli` bauen und laufen unter Linux; die SwiftUI-App
und die Quick-Look-Extension sind macOS-only und werden dort aus dem Paket
ausgeblendet.

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.0 \
  bash -c "apt-get update -qq && apt-get install -y -qq libasound2-dev libdbus-1-dev zlib1g-dev libarchive-tools && swift build && swift test"
```

`libasound2-dev` liefert die ALSA-Header für die Linux-Audioausgabe;
`zlib1g-dev` liefert die zlib, mit der der eigene `ZipArchiveReader` unter Linux
`.zip` entpackt (auf Apple-Plattformen übernimmt das Framework `Compression`).
`libarchive-tools` liefert `bsdtar` — seit 1.6.10 nur noch für `.7z` nötig. Ohne
das Paket läuft alles weiter, nur `.7z` wird übersprungen.

`--play` nutzt die Audio-Ausgabe der Plattform — AVAudioEngine auf macOS, ALSA
unter Linux (braucht `libasound2-dev` zum Bauen). Der Wiedergabepfad liefert
sample-identisch dasselbe wie der Offline-Renderer; beide holen aus derselben
Engine.

`libdbus-1-dev` liefert die Anbindung an die Linux-Mediensteuerung; das Binary
benötigt zur Laufzeit `libdbus-1.so.3`. Während `--play` bietet MPRIS2
Play/Pause, Stop, Vor/Zurück, Titel, Position und Lautstärke (0–1), auch ohne
Terminal. Nach Stop bleibt der Prozess erreichbar; Play beginnt den aktuellen
Titel von vorn. Quit beendet ihn. Titelwechsel erhalten Pause/Stop. Jeder
Prozess nutzt `org.mpris.MediaPlayer2.savage.instance<PID>`. Ohne Sitzungsbus
bleibt die normale CLI-Wiedergabe nutzbar. Seek, URI-Öffnen, Wiederholung und
Zufallsfolge werden nicht angeboten; Desktop-Clients erhalten die passenden
Fähigkeitsangaben.

##### Auf dem Desktop installieren

```bash
bash linux/build-static.sh            # statisches savage-cli im Container bauen
bash linux/install.sh                 # nach ~/.local, ohne root
bash linux/install.sh --uninstall     # wieder entfernen
```

`install.sh` legt `savage-cli` in `~/.local/bin` und den Eintrag
`savage-cli.desktop` in `~/.local/share/applications` ab; ein anderes Ziel geht
über `--prefix`. Damit taucht der Player im Menü auf und lässt sich als
Anwendung für MOD-, S3M-, XM- und IT-Dateien wählen. Der Eintrag startet im
Terminal — das ist Absicht, denn die Tastensteuerung braucht eines. Die vier
Dateitypen sind bei freedesktop.org bereits definiert; der Eintrag meldet sich
nur dafür an, statt eigene zu erfinden.

Das statische Binary ist rund 70 MB groß und läuft ohne installierte
Swift-Laufzeit. Zusätzlich gibt es ein AppImage für Linux x86_64
(geprüft auf Ubuntu 24.04):

```bash
bash linux/build-appimage.sh
chmod +x build/Savage-Mod-Player-*.AppImage
./build/Savage-Mod-Player-*.AppImage track.mod --play
```

Das Bauskript verpackt das vorhandene statische CLI nach `build/`, mit
geprüftem appimagetool 1.9.1 und festgelegter Runtime. ALSA, libdbus-1, zlib,
libstdc++ und glibc bleiben Systembibliotheken; eine installierte Swift-Laufzeit
ist unnötig. Die tatsächliche minimale glibc-Version steht in der enthaltenen
`build-info.txt`. Terminalsteuerung und MPRIS bleiben nutzbar. Fehlt FUSE:
`./build/Savage-Mod-Player-*.AppImage --appimage-extract-and-run track.mod --play`.
Es handelt sich um eine Terminalanwendung.

Der Render ist je Plattform deterministisch, aber **nicht** bitgleich *zwischen*
den Plattformen: `tanh` im Limiter rundet in glibc und Darwin-libm
unterschiedlich, wodurch rund 0,01 % der Samples um ein einzelnes LSB abweichen —
etwa 115 dB unter dem Signal und damit weit unter der Hörschwelle.

### HTML5-Bonusplayer

```bash
python3 build.py                  # → savage-mod-player.html (unter 60 KB)
python3 build.py --no-min         # ohne Minifizierung
```

Die erzeugte Single-File-Variante `savage-mod-player.html` ist Teil des
Repositories, damit der kompakte Player auch ohne lokalen Build direkt genutzt
werden kann.

### DMG (für Releases)

```bash
bash build_dmg.sh                 # → build/Savage Mod Player.dmg
bash build_dmg.sh --notarize      # DMG signieren, notarisieren und stapeln
```

Das DMG enthält ein Retina-kompatibles Hintergrundbild (1x/2x TIFF via `tiffutil`).
Für die Notarisierung wird ein Keychain-Profil erwartet, standardmäßig
`SavageModPlayerNotary`. Es kann einmalig interaktiv angelegt werden:

```bash
xcrun notarytool store-credentials SavageModPlayerNotary
```

### Tests

```bash
swift test
swift test --filter MultiFormatTests
node Tests/js/worklet-timing.mjs
python3 tools/reference_compare.py --output-dir /tmp/savage-it-reference audio/example.it
```

Die Suite deckt Parser (alle MOD-Varianten, S3M, XM, IT, synthetische und echte Dateien),
DSP-Timing, Sequenzierung, den Offline-WAV-Renderer des Quick-Look-Plugins und
die Parität zwischen Swift- und Browser-DSP ab. Das optionale Referenz-Harness
vergleicht den nativen Renderer mit dem festgeschriebenen `openmpt123`-Build und
meldet Dauer, Signalpegel, Hüllkurvenkorrelation, Lag, Onset-Zuordnung und
spektrale Ähnlichkeit, ohne libopenmpt als Produktions-Backend zu verwenden.

Die iOS-Gates laufen getrennt, headless im Simulator:

```bash
bash ios/scripts/build-simulator.sh
bash ios/scripts/run-tests.sh
```

Der Kern der iPhone-App — ZIP-Reader, Bibliotheks-Index, Importer,
Zurücksetzen — steckt in der normalen `swift test`-Suite und braucht keinen
Simulator. Dort läuft nur, was ohne iOS nicht prüfbar ist. Hintergrundwiedergabe,
Sperrbildschirm-Steuerung und das Speicherverhalten beim Import eines großen
Archivs lassen sich im Simulator nicht belegen und müssen an einem echten Gerät
geprüft werden; die Prüfliste steht in [docs/testing.md](docs/testing.md).

---

## GitHub-Veröffentlichung

```bash
bash publish_github.sh --dry-run --release
bash publish_github.sh --release
```

Das Veröffentlichungsskript setzt `origin` auf
`https://github.com/DanielMuellerIR/savage_modplayer.git`, blockt
versehentlich getrackte Audio- und Release-Artefakte und erzeugt bei
`--release` den passenden GitHub-Release-Eintrag mit DMG-Asset.

## Herkunft

Die ProTracker-Engine entstand zuerst im Schwesterprojekt
[FraktalLab](https://github.com/DanielMuellerIR/FraktalLab) als eigene
TypeScript-/AudioWorklet-Implementierung (`AmiModPanel` / `utils/modplayer`,
kein `libopenmpt`). Für dieses Projekt wurde sie als native Swift-Engine mit
`AVAudioSourceNode` portiert und anschließend um projekteigene S3M-, XM- und
IT-Parser, Sequenzierung, Effekte und Voice-Verwaltung erweitert. Die ursprüngliche
Web-Implementierung bleibt als kompakter Single-File-Bonusplayer erhalten.
Mitgelieferte Moduldateien sind nicht Teil dieses Repositories.

## Lizenz

**WTFPL** (Do What The Fuck You Want To Public License) — siehe [LICENSE](LICENSE).

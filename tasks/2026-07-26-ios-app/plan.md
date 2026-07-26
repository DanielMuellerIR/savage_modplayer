# iOS-App für Savage Mod Player — Plan

Stand: 2026-07-26. Ziel: eine native iPhone-App im selben Repo, funktional so nah
an der macOS-App wie sinnvoll, mit Wiedergabe im gesperrten Zustand, einer
Playlist mit echten Unterordnern und einem Weg, ganze Modul-Sammlungen bequem
aufs Gerät zu bekommen.

## Bestätigte Entscheidungen (2026-07-26)

| Thema | Entscheidung |
|---|---|
| Distribution | Sideload mit eigenem Developer-Team. App Store bleibt offen: keine privaten APIs, Privacy-Manifest, saubere UTIs, Bundle-ID universal-purchase-fähig. |
| Projektformat | Eingechecktes `.xcodeproj`, aber mit `PBXFileSystemSynchronizedRootGroup` — neue Swift-Dateien landen ohne pbxproj-Edit im Target. |
| Import-Wege | (A) rekursiver Ordner-Import in der App, (B) Finder-Dateifreigabe. Kein CLI-Push, kein Wi-Fi-Server. |
| iOS-Minimum | 17.0 |
| Bundle-ID | `com.viben.SavageModPlayer` (identisch zur Mac-App, hält Universal Purchase offen) |

## Nicht verhandelbar

- **Keine Musikdateien im Repo.** Keine `.mod`/`.s3m`/`.xm`/`.it`, keine Archive,
  keine Referenz-WAVs. Tests arbeiten mit synthetischen Fixtures; vorhandene
  lokale Korpora bleiben ungetrackt.
- **Keine privaten Pfade.** Der lokale Sammlungsordner erscheint nirgends — nicht
  im Code, nicht in Doku, nicht in Tests, nicht in Screenshots, nicht in
  Commit-Nachrichten.
- **Team-ID nicht eingecheckt.** `DEVELOPMENT_TEAM` kommt aus einer gitignorierten
  `.env`; eine `.env.example` dokumentiert das Format.
- **Kein GitHub-Push, kein Release** ohne ausdrücklichen weiteren Auftrag.
- **`RenderEngine.swift` bleibt plattformneutral.** Kein AVFoundation, kein
  Combine, keine CoreAudio-Typen. Diese Invariante gilt für die iOS-Arbeit
  unverändert; der Linux-Build ist der Nachweis.

## Ausgangslage (verifiziert 2026-07-26)

- `Package.swift` deklariert `.iOS(.v16)` bereits — anzuheben auf `.iOS(.v17)`.
  Ein iOS-Target oder verifizierter iOS-Buildpfad existiert bisher nicht.
- `ModPlayerCoordinator.swift:351` hat bereits einen `#if os(iOS)`-Zweig, der die
  `AVAudioSession` auf `.playback` setzt. Es fehlen Interruption-, Route-Change-
  und `mediaServicesWereReset`-Behandlung.
- `Audio/PCMSink*` und `DSP/RenderEngine` sind plattformneutral und nutzbar.
- **Blocker:** `Playlist/PlaylistScanner.swift` entpackt Archive über `Process`
  und `/usr/bin/bsdtar` (Zeilen 144–185). Beides gibt es auf iOS nicht. Der reale
  Bestand besteht überwiegend aus ZIP-Archiven (einzelne über 100 MB), also ist
  das kein Randfall, sondern der Hauptpfad.
- Der hierarchische Playlist-Baum (`PlaylistScanner.FolderNode`, `Entry` mit
  `folderPath`) existiert im Core bereits — die geforderte „Playlist mit
  Unterordnern“ ist damit größtenteils vorhandene Substanz, nicht Neubau.
- Die Wiedergabelogik der Mac-App verteilt sich auf `MainView*.swift`
  (~40 `@State`/`@AppStorage`). Sie wird **nicht** komplett umgebaut; siehe
  „Scope-Grenze“.

## Architektur

### Repo-Layout (neu)

```
ios/
  SavageModPlayer.xcodeproj/             # eingecheckt, synchronized groups
  SavageModPlayer/                       # synchronized root group
    SavageModPlayerApp.swift
    Library/                             # Import-UI, Ordnerbrowser
    Player/                              # AudioSession, Now Playing, Session
    UI/                                  # Views, Themes, Visualizer
    Resources/                           # Assets.xcassets, Localizable.xcstrings
    Info.plist
    PrivacyInfo.xcprivacy
  SavageModPlayerTests/                  # iOS-Glue-Tests (Simulator)
  scripts/
    build-simulator.sh
    run-tests.sh
    build-device.sh
  .env.example
```

`ios/build/`, `xcuserdata/`, `*.xcuserstate` und `ios/.env` kommen in `.gitignore`.

### ZIP ohne bsdtar — eigener Reader im Core

Neu: `Sources/SavageModPlayerCore/Archive/ZipArchiveReader.swift`, reines Swift,
hinter `canImport(Compression)` geguardet.

- EOCD in den letzten 64 KB suchen, Central Directory parsen, pro Eintrag den
  Local File Header lesen. Methoden 0 (stored) und 8 (deflate).
- Inflate über das `Compression`-Framework mit `COMPRESSION_ZLIB` im
  Raw-Deflate-Modus, gestreamt in Blöcken direkt in die Zieldatei. Kein
  Vollpuffer — ein 100-MB-Archiv darf nicht als Ganzes in den Speicher.
- **Vorfilter vor dem Entpacken:** nur Einträge extrahieren, die
  `PlaylistScanner.isModFile` erfüllen. Das spart bei großen Archiven den
  Löwenanteil an Platz und Zeit.
- **Zip-Slip-Schutz:** Zielpfade normalisieren und erzwingen, dass sie unterhalb
  der Extraktionswurzel bleiben. Absolute Pfade, `..`-Komponenten und Symlink-
  Einträge werden abgelehnt, nicht „bereinigt“.
- **Zip-Bomben-Schutz:** Obergrenze für entpackte Gesamtgröße und für das
  Kompressionsverhältnis je Eintrag; bei Überschreitung sauber abbrechen.
- CRC32 je Eintrag verifizieren; verschlüsselte Einträge ablehnen.
- Dateinamen: UTF-8, wenn Flag-Bit 11 gesetzt ist, sonst CP437.
- Zip64 erkennen und, solange nicht unterstützt, mit klarer Meldung ablehnen
  statt falsche Offsets zu lesen.

Integration: `PlaylistScanner` bekommt eine Weiche. macOS und Linux behalten
`bsdtar` (dort kommt auch `.7z` weiter durch), iOS nutzt den Swift-Reader. `.7z`
ist auf iOS nicht unterstützt und meldet das dem Nutzer verständlich. Die
`Process`-Nutzung wandert hinter `#if !os(iOS)`, damit der Core überhaupt für iOS
übersetzt. Ein späterer Umstieg auch auf macOS/Linux ist Backlog, nicht Scope.

Tests headless im vorhandenen SwiftPM-Testtarget: im Test erzeugte ZIPs (stored
und deflate), Zip-Slip-Versuch, Bomben-Grenze, CRC-Fehler, CP437-Name,
Vorfilter-Wirkung.

### Weitere Core-Erweiterungen

Neu unter `Sources/SavageModPlayerCore/Library/`:

- `MusicLibrary.swift` — Bibliothekswurzel, rekursiver Scan, Codable-Index.
  **Stabile IDs sind relative Pfade**, keine absoluten URLs: der App-Container
  wechselt bei jeder Neuinstallation seine UUID. Der Index liegt in
  `Application Support`, nicht in `Documents`.
- `LibraryImporter.swift` — rekursiver Import mit Fortschritt und Abbruch,
  Struktur-Erhalt, Dedupe, Archiv-Auspacken über den ZIP-Reader.
- `LibraryReset.swift` — Wipe: Dateien, Index, Caches, Temp-Extrakte; Favoriten
  optional. Idempotent und headless testbar.

Änderungen an vorhandenem Core-Code, bewusst klein: `Package.swift` auf
`.iOS(.v17)`, `PlaylistScanner`-Weiche, sonst nichts.

### Scope-Grenze für den Mac-Refactor

Es wird **nicht** die gesamte `MainView`-Logik nach Core gezogen. Erlaubt ist
nur, was 1:1 austauschbar und durch Tests abgedeckt ist: Playlist-Ordnung,
Shuffle, Dedupe, Suchfilter, Favoriten-Schlüssel, Loop-Modus-Semantik. Alles
Größere geht in `tasks/backlog.md`. Nach jeder Extraktion müssen `swift test`
vollständig und `bash build_app.sh` grün sein; die byteidentische WAV-Ausgabe des
Renderpfads ist unverhandelbar.

### iOS-Audio und Sperrbildschirm

- `Info.plist`: `UIBackgroundModes = [audio]`.
- Eigener `AudioSessionController`: Kategorie `.playback`,
  `setPreferredIOBufferDuration` (Startwert 10 ms, danach messen — IT mit 64
  Kanälen und großem Voice-Pool ist deutlich teurer als ein 4-Kanal-MOD),
  Interruption (Anruf → pausieren, `.shouldResume` → fortsetzen), Route-Change
  (`.oldDeviceUnavailable` → pausieren), `mediaServicesWereReset` (Engine neu
  aufbauen, inklusive des Low-Pass-Knotens für den LED-Filter).
- `MPRemoteCommandCenter`: play, pause, togglePlayPause, nextTrack,
  previousTrack, changePlaybackPosition, skipForward/skipBackward passend zu
  −15 s / +30 s.
- `MPNowPlayingInfoCenter`: Songname, Format, Ordner, Dauer, Elapsed, Rate,
  Artwork. Elapsed höchstens im Sekundentakt schreiben.

### Performance

Der kritische Punkt dieser App, nicht Beiwerk:

- Alle Visualisierungen (Master-Oszilloskop, Kanal-Scopes, VU-Meter,
  Tracker-Grid) laufen ausschließlich bei `scenePhase == .active`.
- Kanal-Scopes: Anzahl gleichzeitig gezeichneter Kanäle hart begrenzen. 64
  IT-Kanäle als Einzel-Canvas auf einem iPhone-Display sind weder lesbar noch
  bezahlbar. Vorschlag: sichtbare Auswahl plus reduzierte Bildrate.
- Tracker-Grid: nur sichtbare Zeilen rendern; auf dem iPhone als optionale,
  kompakte Ansicht, nicht als Layout-Träger.
- Erst messen, dann optimieren. Belegt wird über Dauerlauf mit einem
  anspruchsvollen IT-Modul: keine Dropouts über mindestens 10 Minuten inklusive
  Bildschirmsperre.
- Import großer Archive darf den Speicher nicht sprengen; iOS beendet Prozesse
  ohne Vorwarnung. Streaming plus Vorfilter sind deshalb Pflicht, nicht Kür.

### UI (iPhone, Hochformat zuerst)

- `TabView`: **Bibliothek**, **Now Playing**, **Einstellungen**, plus persistente
  Mini-Player-Leiste über der Tab-Bar.
- **Bibliothek**: hierarchischer Ordnerbaum aus `FolderNode` — Ordner starten
  zugeklappt, der Pfad zum laufenden Titel klappt automatisch auf, Wiedergabe und
  Shuffle laufen über alle Ordner. Genau das ist die geforderte Navigation durch
  gemischte Sammlungen. Dazu Live-Suche, Favoriten-Filter, Swipe-Aktionen.
- **Now Playing**: Master-Oszilloskop, Kanal-Scopes (begrenzt), VU, BPM/SPD/PAT,
  Transport, Positionsslider, −15 s / +30 s, Loop-Modus, Shuffle.
- **Klang**: PAL/NTSC, LED-Filter, Hi-Fi-Interpolation, Stereo-Separation,
  Lautstärke.
- **Einstellungen**: Theme (Dark/Light), Bibliothek zurücksetzen,
  Visualizer-Bildrate, Über/Lizenzen.
- Lokalisierung Deutsch und Englisch über `Localizable.xcstrings`.

### Import — der eigentliche Knackpunkt

**A — Ordner-Import in der App.**
`fileImporter(allowedContentTypes: [.folder], allowsMultipleSelection: true)`.
Der Nutzer wählt *einen* Ordner, die App läuft rekursiv durch, packt gefundene
Archive aus und kopiert alles Spielbare samt Struktur in ihre Bibliothek.

- `startAccessingSecurityScopedResource()` / `stopAccessing…` sauber paaren.
- **Risiko File Provider:** Nextcloud liefert Einträge unter Umständen als
  Platzhalter. Vor dem Kopieren `ubiquitousItemDownloadingStatus` prüfen und über
  `NSFileCoordinator` koordiniert lesen. Bei 100-MB-Archiven kann das dauern —
  Fortschritt anzeigen, Abbruch anbieten, Fehler pro Datei sammeln.
- Abschlussbericht: importiert / übersprungen / fehlgeschlagen, mit Grund.

**B — Finder-Dateifreigabe.**
`UIFileSharingEnabled = YES` und `LSSupportsOpeningDocumentsInPlace = YES`, die
Bibliothek liegt direkt in `Documents/`. Damit: iPhone am Kabel → Finder →
Dateien → App, ganze Ordner per Drag & Drop; und dieselbe Bibliothek erscheint in
der iOS-Dateien-App unter „Auf meinem iPhone“. Die App gleicht beim Start
Fremdablagen und Fremdlöschungen mit dem Index ab — sonst fühlt sich Weg B kaputt
an. Per Finder abgelegte Archive werden beim Abgleich ausgepackt.

**Zurücksetzen.** Einstellungen → „Bibliothek zurücksetzen“, zweistufig bestätigt:
Bibliotheksinhalt, Index, Temp-Extrakte und Caches; Favoriten optional. Danach
über A oder B neu befüllen.

## Umsetzungsphasen

**Phase 0 — Spike (blockierend, zuerst).** `platforms:` auf `.iOS(.v17)`,
`PlaylistScanner`-Weiche setzen und beweisen, dass `SavageModPlayerCore` für
`iphonesimulator` baut. Ohne diesen Nachweis ist jede weitere Planung Spekulation.

**Phase 1 — Projektgerüst.** `.xcodeproj` mit synchronized groups, lokale
Package-Referenz, drei Skripte, `.env.example`, `.gitignore`-Ergänzung.
Erfolgskriterium: leere App startet im Simulator.

**Phase 2 — ZIP-Reader im Core.** Inklusive Sicherheits- und Grenztests. Muss vor
der Import-UX fertig sein, weil der Bestand überwiegend aus Archiven besteht.

**Phase 3 — Core-Bibliothek.** `MusicLibrary`, `LibraryImporter`, `LibraryReset`
mit Tests.

**Phase 4 — Wiedergabe und Sperrbildschirm.** Coordinator anbinden,
`AudioSessionController`, Now Playing, Remote Commands, Hintergrund-Audio.

**Phase 5 — Import-UX.** Ordner-Picker, Fortschritt, File-Provider-Behandlung,
Archiv-Import, Finder-Freigabe, Fremdablage-Abgleich, Zurücksetzen.

**Phase 6 — Feature-Parität.** Ordnerbaum, alle vier Formate, Visualisierungen,
PAL/NTSC, LED-Filter, Interpolation, Stereo-Separation, Loop-Modi, Suche,
Favoriten, Shuffle, Session-Restore, Themes, WAV-Export ins Share-Sheet.

**Phase 7 — Härtung.** Performance messen, Lokalisierung, Über/Lizenzen,
Privacy-Manifest, App-Icon, Doku (README.md und README.de.md synchron), VERSION,
RELEASE_NOTES, AGENTS.md (iOS von „Option“ auf „Ist-Zustand“), `tasks/backlog.md`.

## Prüfgates

| Bereich | Gate |
|---|---|
| Core-Änderung | `swift test` vollständig grün |
| `PlaylistScanner`, `Package.swift`, `Audio/`, Renderkern | zusätzlich Linux-Lauf (Docker) — der einzige Beleg für Plattformneutralität |
| Renderpfad berührt | `savage-cli`-WAVs über den lokalen Korpus byteidentisch zur vorher erzeugten Baseline |
| Mac-App berührt | zusätzlich `bash build_app.sh` |
| iOS-Build | `ios/scripts/build-simulator.sh` ohne Warnungen im eigenen Code |
| iOS-Logik | `ios/scripts/run-tests.sh` (Simulator, headless) |
| Import | Simulator-Durchlauf mit synthetischem Ordnerbaum inklusive Archiv: Struktur, Dedupe, Abbruch, Reset |
| Sperrbildschirm | **Nur auf echtem Gerät belegbar** — Daniels Schritt: Wiedergabe bei gesperrtem Display, Steuerung über Sperrbildschirm und AirPods, Verhalten bei Anruf und beim Abziehen der Kopfhörer |
| Öffentlichkeit | getrackter Diff frei von Moduldateien, privaten Pfaden, Team-ID und Assistentenformulierungen |

## Risiken

- **ZIP-Reader ist der größte Einzelbrocken** und sicherheitsrelevant
  (Zip-Slip, Zip-Bomben). Nicht nebenbei erledigen.
- **Speicher beim Import.** Große Archive plus IT-Module mit fetten Samples auf
  einem Telefon — Streaming und Vorfilter sind Pflicht.
- **DSP-Last.** IT mit 64 Kanälen und 256 Voices ist die Messlatte, nicht ein
  4-Kanal-MOD.
- **Linux-Regression** durch die `PlaylistScanner`-Weiche. Der Docker-Lauf ist
  Pflichtgate, kein Bonus.
- **`objectVersion 77`** setzt Xcode 16 oder neuer voraus.
- **Bibliothek in `Documents/`** heißt: der Nutzer sieht und verändert sie. Der
  Index darf nie die einzige Wahrheit sein.

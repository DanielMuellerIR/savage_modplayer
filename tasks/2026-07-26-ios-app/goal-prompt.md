# Goal-Prompt — iOS-App für Savage Mod Player

Dieser Text ist zum Einfügen in eine frische Session im Repo-Wurzelverzeichnis
gedacht. Er ist absichtlich selbsttragend.

---

Baue im Repo `savage_modplayer` eine native iOS-App für iPhone, zusätzlich zur
bestehenden macOS-App. Der vollständige Plan steht in
`tasks/2026-07-26-ios-app/plan.md` — lies ihn zuerst, zusammen mit `AGENTS.md`.
Der Plan ist verbindlich; wo er schweigt, gilt „wie in der Mac-App“.

**Ziel in einem Satz:** eine iPhone-App, die Tracker-Module spielt, im gesperrten
Zustand weiterläuft und dort bedienbar ist, eine Playlist mit echten
Unterordnern zum Navigieren bietet und in die man ganze Sammlungsordner auf einen
Rutsch hineinbekommt.

## Bereits entschieden — nicht neu aufrollen

- Sideload mit eigenem Developer-Team; App Store bleibt offen (keine privaten
  APIs, Privacy-Manifest, saubere UTIs).
- Eingechecktes `.xcodeproj`, aber mit `PBXFileSystemSynchronizedRootGroup`
  (`objectVersion 77`), damit neue Swift-Dateien ohne pbxproj-Edit erfasst werden.
- Import ausschließlich über (A) rekursiven Ordner-Import in der App und
  (B) Finder-Dateifreigabe. Kein CLI-Push-Skript, kein Wi-Fi-Server.
- iOS-Minimum 17.0. Bundle-ID `com.viben.SavageModPlayer`.
- Layout unter `ios/`, Skripte unter `ios/scripts/`.

## Harte Grenzen

- **Keine Moduldateien und keine Archive ins Repo**, keine Referenz-WAVs.
  Tests nutzen synthetisch erzeugte Fixtures; lokale Korpora bleiben ungetrackt.
- **Keine privaten Pfade** in Code, Doku, Tests, Screenshots oder
  Commit-Nachrichten. Import-Quellen sind reine Laufzeit-Auswahl.
- **Team-ID** nur über gitignorierte `ios/.env`, dazu eine `.env.example`.
- **`RenderEngine.swift` bleibt plattformneutral** — kein AVFoundation, kein
  Combine, keine CoreAudio-Typen. Der Linux-Build ist der Nachweis.
- **Kein Push zu `github`, kein Release, keine Notarisierung.** Commits gehen
  ausschließlich zum privaten Fleet-Remote `minipc`, und nur mit
  aufgabenbezogenen Pfaden im Index. Kein `git add .`, kein Reset, kein Clean.
- Fremdes WIP und andere Worktrees bleiben unangetastet.

## Reihenfolge

Arbeite die Phasen 0 bis 7 aus dem Plan in dieser Reihenfolge ab.

**Phase 0 ist blockierend:** hebe `platforms:` in `Package.swift` auf
`.iOS(.v17)`, setze die `PlaylistScanner`-Weiche (der `Process`/`bsdtar`-Pfad
existiert auf iOS nicht) und beweise, dass `SavageModPlayerCore` für
`iphonesimulator` baut. Erst danach weiterbauen.

**Phase 2 (ZIP-Reader) ist der größte und heikelste Brocken.** Der reale Bestand
besteht überwiegend aus ZIP-Archiven, einzelne über 100 MB. Der Reader muss
streamen statt zu puffern, vor dem Entpacken auf Moduldateien vorfiltern und
gegen Zip-Slip und Zip-Bomben abgesichert sein. Behandle ihn als eigenständige
Aufgabe mit eigenen Sicherheitstests, nicht als Nebenprodukt der Import-UX.

Melde dich bei mir, bevor du Phase 6 (Feature-Parität) beginnst, mit einem
kurzen Stand: was läuft im Simulator, was ist offen. Ansonsten arbeite durch.

## Subagenten

Du darfst Opus-Subagenten parallel einsetzen — das ist hiermit ausdrücklich
beauftragt. Sinnvolle Aufteilung, jeweils ein Schreiber pro Dateibereich:

- **ZIP-Reader:** `Sources/SavageModPlayerCore/Archive/` plus Sicherheitstests.
- **Core/Bibliothek:** `Sources/SavageModPlayerCore/Library/` plus Tests.
- **Audio/Now Playing:** `ios/SavageModPlayer/Player/`.
- **UI:** `ios/SavageModPlayer/UI/` und `ios/SavageModPlayer/Library/`.
- **Build/Skripte/Doku:** `ios/scripts/`, `.gitignore`, READMEs, VERSION.

Das `.xcodeproj`, `Package.swift` und `PlaylistScanner.swift` sind serielle
Engpässe — dort schreibt immer nur einer, nie parallel. Subagenten committen
nicht; das machst du zentral.

## Erfolgskriterien

1. `swift test` vollständig grün; `bash build_app.sh` baut weiterhin; der
   Linux-Lauf im Docker-Container ist erbracht, weil `PlaylistScanner` und
   `Package.swift` angefasst wurden.
2. Renderpfad unverändert: `savage-cli`-WAVs über den lokalen Korpus
   byteidentisch zur vorher erzeugten Baseline.
3. `ios/scripts/build-simulator.sh` und `ios/scripts/run-tests.sh` laufen
   headless durch.
4. Im Simulator nachweisbar: Ordner-Import eines synthetischen, verschachtelten
   Testbaums inklusive eines im Test erzeugten ZIP-Archivs erhält die Struktur,
   dedupliziert, ist abbrechbar; „Bibliothek zurücksetzen“ leert sauber; danach
   funktioniert ein erneuter Import.
5. Der Bibliotheksbrowser zeigt echte Unterordner, zugeklappt startend, mit
   automatischem Aufklappen zum laufenden Titel; Wiedergabe und Shuffle laufen
   über alle Ordner.
6. Wiedergabe aller vier Formate, Visualisierungen, PAL/NTSC, LED-Filter,
   Interpolation, Stereo-Separation, Loop-Modi, Suche, Favoriten, Shuffle,
   Session-Restore, Themes und WAV-Export sind vorhanden und bedienbar.
7. Visualisierung steht bei inaktiver Szene still, Audio läuft weiter. Ein
   anspruchsvolles IT-Modul spielt ohne Dropouts.
8. Der getrackte Diff enthält keine Moduldateien, keine privaten Pfade, keine
   Team-ID.
9. `VERSION`, `README.md`, `README.de.md`, `RELEASE_NOTES*`, `AGENTS.md` (iOS von
   „Option“ auf „Ist-Zustand“) und `tasks/backlog.md` sind auf dem neuen Stand;
   die beiden READMEs bleiben inhaltlich synchron.

**Was du nicht abnehmen kannst:** Hintergrundwiedergabe und Sperrbildschirm-
Steuerung sind nur auf echtem Gerät belegbar. Bereite `ios/scripts/build-device.sh`
vor, schreibe mir eine kurze Prüfliste (Sperrbildschirm-Steuerung, AirPods,
eingehender Anruf, Kopfhörer abziehen, Speicherverhalten beim Import eines großen
Archivs) und übergib diesen Test an mich. Behaupte niemals, das sei verifiziert,
wenn nur der Simulator lief.

## Berichten

Am Ende: was gebaut wurde, welche Gates mit welchem Ergebnis liefen, was bewusst
offen blieb und warum, und was ich am Gerät prüfen muss. Fehlgeschlagene Tests
nennst du mit Ausgabe, nicht als Randnotiz.

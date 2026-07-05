# Linux-Port: Savage Mod Player

Stand: 2026-07-05 · Ziel: Repo läuft zusätzlich unter Linux — zuerst als CLI-Player.
Kein separates Repo: `SavageModPlayerCore` ist der plattformübergreifende Teil, die
macOS-App bleibt unverändert. Dieser Plan folgt der Blaupause aus dem
vicious_sidplayer-Port (dort `tasks/2026-07-05-linux-port/plan.md`) — **den zuerst
umsetzen**, Erkenntnisse hier einfließen lassen.

## Ausgangslage (verifiziert 2026-07-05)

- `Sources/SavageModPlayerCore/`: nur **zwei Dateien** importieren AVFoundation —
  `DSP/ModPlayerCoordinator.swift` (+ Combine) und `DSP/ModuleRenderer.swift`.
  Plattformneutral sind: `DSPChannel.swift` (Paula-Emulation), `ModParser.swift`,
  `S3MParser.swift`, `ModuleLoader.swift`, `PlaylistScanner.swift`.
- `Package.swift` mit getrennten Targets (Core-Library, App, Quick-Look, Tests);
  CI existiert bereits (`.github/workflows/ci.yml`) → nur um Ubuntu-Job erweitern.
- 5 Testsuiten hängen am Core (Parser, DSP-Timing, Sequencing, Multiformat, Playlist).
- HTML5-Variante (`savage-mod-player.html`) deckt „GUI auf Linux" übergangsweise ab —
  natives Linux-GUI ist NICHT Teil dieses Plans.

## Phasen

### Phase 0 — Core kompiliert auf Linux (~0,5 PT)
- `ModPlayerCoordinator.swift` datei-weit in `#if canImport(AVFoundation)` hüllen.
- `ModuleRenderer.swift` prüfen: Der Offline-Renderer ist für das CLI wertvoll —
  wenn er AVFoundation nur für AVAudioFile/WAV nutzt, den WAV-Teil abtrennen
  (eigener Mini-WAV-Writer, plattformneutral) und nur den Rest guarden. Wenn die
  Verflechtung tiefer ist: komplett guarden und den CLI-Renderpfad direkt auf
  `DSPChannel`-Ebene bauen (wie beim SID-Player).
- Betroffene Tests ebenso guarden.
- **Erfolgskriterium:** `swift build` + `swift test` grün im `swift:6.0`-Docker-Container.

### Phase 1 — CLI mit PCM-Ausgabe (~1 PT, mit Blaupause)
- Neues Executable-Target `savage-mod` :
  `savage-mod <datei.mod|s3m> [--seconds S] [--wav out.wav] [--stdout] [--list]`
  (`--list`: Playlist-Scan eines Ordners via `PlaylistScanner`).
- PCM-s16le auf stdout (→ `aplay`), Metadaten (Titel, Format, Kanäle, Pattern-Zahl)
  auf stderr. Exit-Codes wie beim SID-CLI.
- **PCMSink-Abstraktion aus dem vicious_sidplayer-Port kopieren** (bewusst Copy statt
  gemeinsames Package — erst nach Bewährung in beiden Repos extrahieren).
- **Erfolgskriterium:** Referenz-MOD und -S3M spielen hörbar korrekt via aplay;
  `--wav` byteident zwischen macOS- und Linux-Build (Determinismus-Test).

### Phase 2 — Echtzeit-Playback + Steuerung (~1 PT, mit Blaupause)
- ALSA-`systemLibrary`-Anbindung aus dem SID-Port übernehmen; Tastatursteuerung
  (Pause, nächster Titel in Playlist, Quit).
- **Erfolgskriterium:** Playlist-Wiedergabe eines Ordners auf Linux ohne Aussetzer.

### Phase 3 (optional) — Desktop-Integration
- MPRIS2, .desktop-Datei, statisches Binary/AppImage — analog SID-Plan, erst bei Bedarf.

## Rahmenbedingungen

- CI: Ubuntu-Job in `.github/workflows/ci.yml` (Build + Tests), erst wenn lokal grün.
- README.md/README.de.md: Linux-Abschnitt nach Phase 1; RELEASE_NOTES pflegen,
  `VERSION`-Bump pro Phase.
- Chirurgisch: App-, Quick-Look- und JS/HTML5-Code nicht anfassen.
- Phasen als Junior-Dev-Briefs delegierbar; Diff-Review vor Merge obligatorisch.

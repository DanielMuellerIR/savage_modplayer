# Sparkle-Updates für macOS

Die macOS-App bindet Sparkle 2.10.0 exakt gepinnt ein. Der Update-Feed liegt unter
`https://danielmuellerir.github.io/savage_modplayer/appcast.xml`, die DMGs bei
GitHub Releases. Automatische Prüfungen lassen sich unter **Einstellungen →
Updates** abschalten; **Nach Updates suchen…** im App-Menü prüft jederzeit
manuell. Jede Installation braucht eine Bestätigung. Systemprofiling ist aus.

1.6.32 ist die erste Sparkle-Version. Ältere Installationen müssen sie einmal
manuell per DMG installieren, bevor spätere Updates aus der App möglich sind.
CLI, Linux, Quick Look und iPhone enthalten keinen Updater.

## Einmalige Einrichtung

GitHub Pages, Tag-Deployments und das Actions-Secret sind seit 2026-10-16
eingerichtet. Der Schlüssel wurde zusätzlich verschlüsselt gesichert.
Die folgenden Schritte beschreiben die Einrichtung für eine neue Umgebung:

1. **Pages → Source: GitHub Actions** wählen. Im Environment `github-pages`
   Deployments für `main` und Tags vom Typ `v*` zulassen.
2. Einen eigenen Ed25519-Schlüssel für `com.viben.SavageModPlayer` verwenden.
   Sparkles `generate_keys --account com.viben.SavageModPlayer` legt ihn im
   Login-Schlüsselbund an und zeigt ausschließlich den öffentlichen Teil.
   Dieser muss mit `SUPublicEDKey` in `build_app.sh` übereinstimmen.
3. Den privaten Schlüssel als Actions-Secret `SPARKLE_PRIVATE_KEY` hinterlegen.
   Für den Transfer kann `generate_keys --account com.viben.SavageModPlayer -x`
   in eine geschützte temporäre Datei exportieren; `gh secret set
   SPARKLE_PRIVATE_KEY < datei` liest über stdin. Die Klartextdatei anschließend
   entfernen und den Schlüssel zusätzlich verschlüsselt sichern. Private
   Schlüssel gehören nie in Git, Logs oder Kommandozeilenargumente.

Apple-Signaturen und Notarisierung sowie Sparkle-Signaturen erfüllen getrennte
Aufgaben: Erstere bestätigen die App-Identität gegenüber macOS, letztere sichern
Update-Archiv und Feed. Beide sind erforderlich.

## Pro Release

1. `VERSION`, EN/DE-Release Notes und eingebettetes HTML aktualisieren.
   `CFBundleVersion` und `CFBundleShortVersionString` stammen beide aus `VERSION`
   und müssen gegenüber der ausgelieferten Version steigen.
2. Tests aus `docs/testing.md` ausführen und `bash release.sh` für das
   notarisierte DMG nutzen. Die innere Signierreihenfolge lautet Sparkle-Helfer,
   Sparkle-Framework, Quick-Look-Extension, App. Nur die Extension ist sandboxed.
3. Nach Freigabe mit `bash publish_github.sh --release` veröffentlichen.
   Das Release muss genau ein fertiges DMG enthalten. Bei bestehendem Release
   wird der Feed anschließend manuell über **Actions → Publish Sparkle appcast →
   Run workflow** mit dem Tag aktualisiert; ein Asset-Upload löst `published`
   nicht erneut aus.
4. `.github/workflows/publish-appcast.yml` akzeptiert nur das neueste stabile
   Release. Er prüft DMG/App, Developer-Team, Notary-Tickets, Bundle-ID,
   Versionsnummer und Update-Konfiguration, bevor der private Schlüssel in
   einem einzelnen Schritt verwendet wird. `generate_appcast` erzeugt genau
   ein Vollupdate ohne Deltas. Feed und Archiv werden anschließend unabhängig
   gegen den öffentlichen Schlüssel aus dem ausgelieferten Bundle geprüft.
5. Workflow und öffentliche Feed-URL prüfen. Auf einem Test-Mac muss eine ältere,
   bereits Sparkle-fähige, notarisiert installierte Fassung das Update finden,
   installieren und mit der neuen Version starten. Gültiges XML und erfolgreiche
   Signaturprüfungen allein belegen keinen vollständigen App-Austausch.

Ein lokaler Generatorlauf mit einem Test-DMG kann ohne Veröffentlichung erfolgen:

```bash
swift package resolve
# Werkzeuge liegen unter .build/artifacts/sparkle/Sparkle/bin/.
generate_appcast --account com.viben.SavageModPlayer \
  --embed-release-notes --maximum-versions 1 --maximum-deltas 0 \
  --download-url-prefix 'https://github.com/DanielMuellerIR/savage_modplayer/releases/download/v1.6.32/' \
  -o /tmp/savage-update/appcast.xml /tmp/savage-update
swift scripts/verify-sparkle-feed.swift /tmp/savage-update/appcast.xml \
  'Savage Mod Player.app/Contents/Info.plist' '/tmp/savage-update/Savage Mod Player.dmg'
```

Dabei muss `/tmp/savage-update` vorher genau das Test-DMG und optional Release
Notes mit gleichem Basisnamen enthalten. Der Lauf veröffentlicht nichts und
ersetzt weder Notarisierung noch den abschließenden Installationsversuch.

## Verifizierter Update-Lauf

Am 2026-10-16 fand eine separat installierte, Developer-ID-signierte und
notarisierte Testkopie mit zurückgesetzter Versions- und Buildnummer 1.6.31
über den öffentlichen Feed die Version 1.6.32. **Install Update** lud das
Release-DMG; **Install and Relaunch** ersetzte die App und startete 1.6.32
mit einer neuen Prozess-ID. Das gestartete Binary war bytegleich mit dem
Release-Bundle. Verschachtelte Signaturen, angeheftetes Notary-Ticket und
Gatekeeper wurden nach dem Austausch erneut erfolgreich geprüft.

Vorhandene Installationen blieben erhalten. Die Test-App wurde anschließend
beendet und entfernt, die vorher gesicherten Einstellungen wurden vollständig
wiederhergestellt. Das DMG-Layout wurde visuell mit 600 × 600 Punkten und den
vorgesehenen Icon-Positionen geprüft.

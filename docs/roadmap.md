# Geplante Erweiterungen

Stand: 2026-10-18. Reihenfolge nach Abhängigkeiten; keine Veröffentlichungstermine.
Die Wiedergabe bleibt auf MOD, S3M, XM und IT konzentriert. Der kompakte
Browserplayer erhält keine automatische Funktionsparität mit den nativen Apps.

1. **Playlists und Warteschlange:** eindeutige Titelreferenzen, benannte Listen,
   Als Nächstes, umsortierbare Warteschlange und explizite Wiedergabe von Suchtreffern.
   Der versionierte Speicher und Referenzen für verschachtelte Archive sind seit
   1.6.33 vorhanden; die macOS-Oberfläche ist seit 1.6.34 und iOS seit 1.6.35 vorhanden.
2. **Metadatenbibliothek:** interner Songtitel, Format, Kanalzahl, Instrumente,
   begrenzte Dauerermittlung, inkrementeller Hintergrundindex und gespeicherte Filter.
   Der [gemeinsame Index](metadata-index.md) ist seit 1.6.36 vorhanden; Such-/Sortieroberflächen und gespeicherte Filter sind seit 1.6.37 vorhanden.
3. **Inspektoren:** Sample-Wellenformen, Loop-/Sustain-Bereiche, Tastenzuordnungen,
   Hüllkurven, formatspezifische Effekt-Erklärungen und Kompatibilitätsdetails.
   Der [Sample-Inspektor](sample-inspector.md) ist seit 1.6.38 vorhanden.
   Der [Modul-/Instrument-Inspektor](module-inspector.md) ist seit 1.6.39 vorhanden.
4. **Songstellen und A/B:** benannte Positionen, Zeilenauswahl und Schleifen mit
   korrektem Wiedergabezustand beim Einstieg in eine Passage.
   [Songstellen und visuelle Bereichsauswahl](song-markers.md) sind seit 1.6.40 vorhanden;
   zustandskorrekte native A/B-Audioschleifen sind seit 1.6.42 implementiert; offene Abnahmen stehen im Backlog.
5. **Audioexport:** tatsächlich gespielte Kanalspuren, gemeinsame Pegelskalierung,
   Float-WAV und Stapel-Export mit Fortschritt, Abbruch und Zielkonfliktbehandlung.
   [Stereo-Kanalspuren](channel-stem-export.md) sind seit 1.6.43 implementiert; die echte GUI-Abnahme ist bestanden. Der [Stapel-Export](batch-wav-export.md) ist seit 1.6.44 vorhanden und nativ abgenommen.
6. **Hörkomfort:** Einschlaftimer mit Ausblenden und Wiedergabeeinstellungen pro Titel.
   Der [Einschlaftimer](sleep-timer.md) ist seit 1.6.45 implementiert und am Mac nativ abgenommen; die offene iPhone-Geräteabnahme steht im Backlog.
   [Klang-Einstellungen pro Titel](track-playback-settings.md) sind seit 1.6.46 implementiert und am Mac nativ abgenommen; Telefon-/Tablet-Darstellung und iOS-Ladepfade sind geprüft.
7. **Datenaustausch:** portabler Austausch von Favoriten, Playlists, Songstellen
   und Einstellungen zwischen Mac und iPhone; später automatischer Metadatenabgleich.
   Das [portable Format](collection-exchange.md) ist seit 1.6.47 im gemeinsamen Core vorhanden; die nativen Export-/Import-Oberflächen mit Titelzuordnung, Vorschau und Konfliktentscheidung sind seit 1.6.48 vorhanden. Lokale Musikdateien bleiben davon getrennt. Der [automatische Metadatenabgleich](collection-sync.md) ist seit 1.6.52 mit geprüfter CloudKit-Konfiguration und synthetischen Development-/Production-Rundwegen zwischen Mac und iPhone abgenommen. Konflikte brauchen eine ausdrückliche Entscheidung; Musikdateien bleiben lokal. Weitere Geräte- und Dienstgrenzen stehen im [Backlog](../tasks/backlog.md).
8. **Notenregen-Video:** der [Offline-Renderer](note-rain-video.md) ist seit 1.6.49 im macOS-Core vorhanden. Seit 1.6.50 gibt es Exportoberfläche, Vorschau und Zielwahl; die zusammenhängende native Abnahme einschließlich Audio-/Video-Gegenprobe ist bestanden.

Neue Modulformate und auswählbare Teilstücke innerhalb einer Datei werden erst
anhand konkreter Referenzdateien bewertet. Vor iPhone-Abnahmen bleiben die offenen
Geräteprüfungen in [der aktiven Projektliste](../tasks/backlog.md) maßgeblich.

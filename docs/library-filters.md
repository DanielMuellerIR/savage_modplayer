# Metadatensuche und gespeicherte Filter

Auf macOS öffnet **Anzeige und Filter…** in der Seitenleiste die Auswahl.
Auf iPhone/iPad liegt derselbe Punkt im Listenmenü der Bibliotheks-Werkzeugleiste.
Die Suche berücksichtigt Dateinamen, Ordner, interne Modultitel und Instrumentnamen.
Mehrere Wörter dürfen in unterschiedlichen Feldern vorkommen. Instrumentnamen
enthalten mitunter Copyright-/Textzeilen und sind keine verlässlichen Künstlerdaten.

Format, Mindestkanalzahl, Favoriten, ungehörte und neu erfasste Titel lassen sich
kombinieren. Die ursprüngliche Ordnerreihenfolge bleibt der Standard. Alternativ
sortieren Dateiname, interner Titel, Format, Kanäle, Dauer oder neueste Aufnahme;
die Reihenfolge lässt sich umkehren. Unbekannte Metadaten stehen zuletzt.
Dauerwerte mit `≥` sind begrenzte Ergebnisse, keine exakten Gesamtdauern.

**Diese Ergebnisse abspielen** übernimmt die angezeigte Reihenfolge als
Wiedergabeauswahl. Spätere Such-/Filteränderungen ersetzen sie nicht. Auf iOS
übernimmt auch das Antippen eines Treffers seine angezeigte Auswahl. Weiter,
Zurück und Shuffle bleiben in dieser Auswahl; der gewählte Loop-Modus gilt weiter.

Ein Filtername speichert die aktuellen Such-, Filter- und Sortiereinstellungen.
Gespeicherte Filter lassen sich erneut anwenden oder löschen. **Anzeige zurücksetzen**
kehrt zur vollständigen Ordneransicht zurück, ohne Musikdateien zu verändern.

Der Hörstatus wird erst bei tatsächlich gestarteter Modulwiedergabe gesetzt.
Bloße Auswahl, Wiederherstellung im gestoppten Zustand und Indexierung zählen nicht.
**Als ungehört markieren** im Titel-Kontextmenü setzt diesen Status zurück.
Die ID ist auf dem Mac die Originalquelle einschließlich Archivmitglied; auf iOS
der relative Bibliothekspfad. Ersetzen von Bytes unter derselben Quelle behält
diesen Status bei. Die erste Erfassung bleibt über erneutes Indexieren erhalten;
iOS übernimmt ein bereits bekanntes Importdatum.

Die Sammlungsübersicht zeigt indizierte Formate, Indexfehler und Gruppen gleicher
Dateinamen. Gleiche Namen bedeuten nicht, dass die Inhalte identisch sind.
Fehlende/ungültige Dateien und Indexgrenzen sind sichtbar; Musikdateien bleiben erhalten.
Beschädigte Filter-/Hörstatusdaten werden nicht still geleert oder überschrieben.

Technik: plattformneutrale Query-/Präferenztypen liegen in `Library/`; die optionale
native Combine-Bindung in `Presentation/`. Datei-, Parser-, Cache- und Sortierarbeit
laufen außerhalb der UI und des Audiothreads. Fertige, gegen veraltete Aufträge
geschützte Ergebnisse werden an die Ansichten übergeben. Fortschrittsanzeigen
beobachten einen getrennten Zustand und lösen keine regelmäßige Neusortierung aus.

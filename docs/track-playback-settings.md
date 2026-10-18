# Klang-Einstellungen pro Titel

Seit 1.6.46 öffnet **Klang** in der Mac-Kopfzeile beziehungsweise das
Regler-Symbol in der iPhone-/iPad-Wiedergabe die Klang-Einstellungen.
Der Quellpfad unter dem Titel unterscheidet gleichnamige Dateien und Archivmitglieder.
**Dieser Titel** bearbeitet den beim Öffnen ausgewählten Titel. Ein automatischer
Titelwechsel im Hintergrund verändert den bearbeiteten Titel nicht.

Jede Option verwendet zunächst die globale Vorgabe. Ausdrücklich PAL/NTSC,
Interpolation oder LED-Ausgabefilter wählen beziehungsweise die eigene
Stereo-Separation einschalten, um nur diesen Wert zu überschreiben.
**Titel zurücksetzen** entfernt alle Overrides dieses Titels. Andere Titel
und die globalen Vorgaben bleiben erhalten.

**Globale Vorgaben** gelten für alle nicht überschriebenen Werte. Auf dem Mac
bearbeiten die vorhandenen Schnellregler den wirksamen Wert: bei einem
ausdrücklichen Override dessen Titelwert, sonst die globale Vorgabe.
Die globalen Mac-Klangvorgaben werden jetzt über Neustarts gespeichert.
Die allgemeinen iPhone-/iPad-Einstellungen bleiben globale Vorgaben.

PAL/NTSC ist nur für MOD, Soundtracker und Mehrkanal-MOD anwendbar.
XM, S3M und IT verwenden ihr festes Frequenzmodell. Separation und Interpolation
gelten für alle Formate; der LED-Filter ist ein externer Ausgabefilter.
Änderungen an wirksamen Klangwerten beenden eine aktive A/B-Schleife.
Der Einschlaftimer und der gewünschte Lautstärkewert bleiben erhalten.

Einstellungen folgen der stabilen Quelle, einschließlich Archivmitgliedern;
gleiche Dateinamen in unterschiedlichen Ordnern bleiben getrennt. iOS verwendet
weiter relative Bibliotheks-IDs. Verschieben einer Quelle kann deren Identität
ändern. Lautstärke, Tempo, Mute/Solo und Timer sind keine Titel-Overrides.

Reglerbewegungen wirken sofort und werden nach einer kurzen Ruhephase gesichert;
Titelwechsel und Schließen sichern den letzten Wert. Eine beschädigte,
unbekannt versionierte oder zu große Datei bleibt unverändert. Es gelten dann
globale Vorgaben, und der Dialog erklärt den gesperrten Titel-Speicher.
Bei einem Schreibfehler bleibt der zuletzt gesicherte Titelwert erhalten.

Der normale Einzel-WAV-/Kanalspurenexport übernimmt die wirksamen Optionen,
soweit der jeweilige Export sie unterstützt. Der Stapel-Export verwendet seine
eigenen ausdrücklich gewählten Audioeinstellungen. Der externe LED-Filter ist
wie bisher kein Bestandteil des WAV-Renderpfads.

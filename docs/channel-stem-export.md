# Stereo-Kanalspuren exportieren

Seit 1.6.43 bietet die macOS-App im WAV-Export die Auswahl **Stereo-Mix** oder
**Kanalspuren**. Für Kanalspuren einen neuen Ordnernamen eingeben und dessen
übergeordnetes Zielverzeichnis wählen. Der Export beginnt am Songanfang und
endet gemeinsam am natürlichen Songende oder an der gewählten Dauergrenze.
Die aktuelle Abspielposition und eine aktive A/B-Schleife begrenzen ihn nicht.
Fortschritt und Abbruch stehen im Exportdialog; danach lässt sich der Ordner
im Finder zeigen. iPhone/iPad bieten weiterhin keinen WAV-Export.

## Dateien und Wiedergaberegeln

- `Channel-01.wav` bis zur Anzahl logischer Kanäle: je eine Stereo-Float32-WAV,
  einschließlich gleich langer Stummspuren für ungespielte oder stumme Kanäle.
- `Reference-Mix.wav`: gemeinsamer Stereo-Mix vor dem Master-Limiter, mit
  demselben Pegelfaktor wie die Spuren.
- `manifest.json`: Schema, Modulname/-format, Audiooptionen, Framezahl,
  natürliches Ende/Dauergrenze, Rohpeaks und gemeinsamer Pegelfaktor.

Globale Lautstärke, Header-Mix-Gain, Panning, Surround, IT-Stimmenfilter und
Mute/Solo fließen ein. Alle IT-NNA-Hintergrundstimmen bleiben dem ursprünglichen
logischen Kanal zugeordnet. Ein Stereo-Sample behält beide Seiten; auch
gegenphasiges Material bleibt erhalten. Clock, Interpolation und Separation
werden beim Öffnen des Exportdialogs zusammen mit dem angezeigten Titel aus
dem Player übernommen und bleiben für beide Durchläufe fest. Ein inzwischen
weitergeschalteter Player verändert diese Auswahl nicht. Währenddessen kann
die normale Wiedergabe unabhängig weiterlaufen.

Die Spuren liegen vor dem `tanh`-Limiter. Mixerlautstärke und externer
LED-Ausgabefilter sind nicht enthalten. Die Summe der WAV-Spuren ergibt den
Referenzmix bis auf Float-Rundung; bei anders gruppierten IT-Stimmen sind geringe
Abweichungen möglich. Für die gewöhnliche ungefilterte Engine-Ausgabe zuerst
durch `commonGain` teilen und dann `tanh` auf die gemeinsame Summe anwenden.
Ein Limiter auf jeder einzelnen Spur ergibt einen anderen Mix.

## Gemeinsamer Pegel und Speicher

Der erste vollständige Renderdurchlauf bestimmt den höchsten absoluten Peak
über alle Stereo-Spuren und den Referenzmix. Der Faktor ist
`min(1, 0.98 / peak)` beziehungsweise 1 bei Stille. Leise Spuren werden somit
nicht einzeln angehoben. Der zweite identische Durchlauf schreibt alle Dateien
mit diesem gemeinsamen Faktor. Das Float-Format bewahrt die Stereodaten ohne
16-Bit-Quantisierung; die WAVs enthalten ein IEEE-Float-Format- und Fact-Chunk.

Die zusätzlichen Audiopuffer umfassen `(2 * Kanalzahl + 4) * 1024` Floats.
WAV-Blöcke werden unmittelbar geschrieben; die Songdauer vergrößert die Dateien,
nicht diese Puffer. Die gemeinsame Sequencer-Endtransition schneidet auch den
letzten Teilblock für sämtliche Dateien auf dieselbe Framezahl.

Der Renderer schreibt zunächst einen eigenen temporären Ordner neben dem Ziel.
Nach vollständigem Schreiben und Schließen veröffentlicht ein exklusives
Umbenennen den Ordner. Ein auch erst während des Exports neu angelegtes Ziel
bleibt erhalten. Abbruch und Fehler räumen ausschließlich den eigenen
Zwischenstand auf. Linux benötigt für diese Veröffentlichung `renameat2` mit
`RENAME_NOREPLACE`; fehlt die Unterstützung, scheitert der Export ohne Ersatz
durch ein überschreibendes Umbenennen.

## Core-API und Prüfung

`ChannelStemRenderer.export(mod:to:options:progress:)` läuft synchron außerhalb
des MainActors und des Audiothreads. Raten von 8.000 bis 192.000 Hz müssen
ganzzahlig sein; das Dauerlimit beträgt höchstens 600 Sekunden. Abbruch erfolgt
über Task-Cancellation zwischen Blöcken. `mutedChannels: nil` erhält die
Header-Defaults; eine explizite Liste setzt den Playerzustand einschließlich
manuell freigegebener Headerkanäle. Kanalindizes in den Optionen sind nullbasiert,
WAV-Dateinamen beginnen mit 1.

`ChannelStemRendererTests` vergleicht die Spurensumme mit dem Referenzmix und
rekonstruiert die gewöhnliche limitierte WAV-Ausgabe. Die synthetischen Fälle
umfassen vier Formate, Stereo-Gegenphase, Mute/Solo/Header-Defaults, IT-NNA mit
256 Stimmen und 64 Besitzern, Zufallspanning/Surround, Loops/Delays/Tempo,
Teilblöcke, Abbruch, Dateisystemfehler und späte Zielkonflikte. Die native macOS-Bedienabnahme für 1.6.43 ist bestanden. Der spätere
[Stapel-Export](batch-wav-export.md) hat eine eigene Abnahme im Projektbacklog.

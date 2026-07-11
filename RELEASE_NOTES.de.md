## 1.5.27 — 2026-07-11

- Pauschale IT-/OpenMPT-Warnungen wurden durch einen strukturierten Capability-Bericht ersetzt. `cwtv` identifiziert jetzt den erstellenden Tracker, `cmwt` steuert die Formatkompatibilität und vollständige OpenMPT-Versionen kommen aus ihren eigenen Erweiterungsfeldern. Eine neuere OpenMPT-Erstellerversion warnt nicht mehr allein.
- XTPM, STPM, alte ModPlug-Chunks, MIDI-/Plugin-Routing und alle aktuellen OpenMPT-`PlayBehaviour`-Bits werden an ihren strukturellen Grenzen geparst. Markerbytes in Patterns oder komprimiertem beziehungsweise unkomprimiertem PCM können nicht mehr mit Erweiterungen verwechselt werden.
- Bekannte Kanal-, Timing-, Mix-, Preamp-, Restart-, Filter- und PCM-Kompatibilitätswerte werden von der Engine angewandt. Klassischer, alternativer und moderner OpenMPT-Tempo-Modus sowie erweiterte IT-Patterns mit 1 bis 1.024 Zeilen werden unterstützt.
- Warnungen setzen jetzt tatsächliche Nutzung im abgespielten Order-Pfad voraus. Inaktive MIDI-Flags, Default-Makros, unbenutzte Plugin-Definitionen, Metadaten und nicht unterstützte Eigenschaften unbenutzter Instrumente bleiben still; verwendete externe Pfade nennen Instrument, Kanal oder Plugin-Slot.
- Der Start erweiterter Patterns und gelöschte Order-Referenzen wurden korrigiert. Patterns mit mehr als 64 Zeilen spielen nicht mehr erst ihren hinteren Teil und starten dann nochmals bei Zeile null; Referenzen auf gelöschte Patterns werden wie in OpenMPT übersprungen.
- Der Offline-Renderer schneidet den letzten Block jetzt am exakten Sequencer-Endframe. Die UI-Dauer nutzt dieselbe Jump-/Loop-/Delay-/Tempo-bewusste Sequencer-Probe statt einer statischen Zeilenschätzung; die primäre OpenMPT-Referenz zeigt und rendert jetzt exakt 46,080 Sekunden.
- `savage-cli --info` zeigt jetzt Tracker-Identität, `cwtv`/`cmwt`, vollständige OpenMPT-Versionen, jeden strukturierten Erweiterungs-Chunk, `PlayBehaviour`-Zustände und konkrete Capability-Ergebnisse.
- Deterministische Fixtures für OpenMPT-Erweiterungen, Warnungen, Kompatibilitätsbits, variable Pattern-Längen und MIDI-/Plugin-Pfade wurden ergänzt. Der reproduzierbare A/B-Bericht enthält nun die deklarierte Songdauer und trennt OpenMPTs abschließendes WAV-Padding von der musikalischen Dauer.

### Bewusste Grenzen

- Savage Mod Player bleibt eine native PCM-Tracker-Engine, kein VST-/AudioUnit-Host und kein externer MIDI-Renderer. Diese Pfade warnen nur, wenn sie getriggert werden.
- Veralteter OpenMPT-Swing vor 1.17, die abgelöste alte Loop-/Jump-Regel, ungenauer historischer Ping-Pong-Überschuss und proprietäre Envelope-Release-Knoten bleiben merkmalsspezifische Kompatibilitätsgrenzen.

## 1.5.25 — 2026-07-11

- Die Kopfzeile zeigt vor BPM die Anzahl der tatsächlich verwendeten Pattern-Kanäle.
- PAL/NTSC liegt jetzt neben dem Master-Oszilloskop und ist nur bei Paula-basierten MOD-Formaten verfügbar.
- Quick Look rendert und cached jetzt eine schnelle 60-Sekunden-Audiovorschau; nicht unterstützte Dateien zeigen einen lesbaren Fehler statt eines endlosen Ladeindikators.

Die macOS-App spielt jetzt **Impulse-Tracker-Module (`.it`)** im Sample- und Instrument-Modus. Die neue Engine deckt native IT-2.14-/2.15-Wiedergabe vom Parser über Echtzeit-Audio bis CLI-Rendering, Drag & Drop und Quick Look ab.

## Neu

- **Impulse Tracker (`.it`)**: bis zu 64 logische Kanäle, ein vorallozierter 256-Voice-NNA-Pool, NNA/DCT/DCA, 120er Sample-Maps, Hüllkurven, Fadeout, Sustain-Loops, Stereo-Samples, Surround, Sample-Vibrato, Pitch-Pan, Volume-/Pan-Swing und resonante Filter pro Voice.
- **IT-2.14-/2.15-Samples**: unkomprimiertes und komprimiertes 8-/16-Bit-Mono-/Stereo-PCM, Signed-/Unsigned- und Delta-Varianten, Forward-/Ping-Pong-Loops sowie getrennte Sustain-Loops.
- **IT-Effektsemantik**: Effekt- und Volume-Column-Memory, `Old Effects`, `Compatible Gxx`, Pattern-/Row-Delays und Loops, Tempo, Global-/Channel-Volume, Retrigger, Tremor, Vibrato, Panbrello und gebräuchliche Filtermakros.
- **Öffentliche Integration**: `.it` funktioniert im Loader, Playlist-Scanner, Datei-Dialog, Drag & Drop, Finder-„Öffnen mit“, in `savage-cli` und in der Quick-Look-Extension. Die App zeigt ein Impulse-Tracker-Format-Badge und rendert alle Pattern-Zeilen sowie bis zu 64 Kanäle.
- **Kompatibilitätsmeldungen**: nicht unterstütztes MIDI-/Plugin-Routing, eingeschränkte Custom-MIDI-Makros, neuere Tracker-Versionen und unbekannte MPTM-/IT-Erweiterungen erzeugen sichtbare, nicht-fatale Warnungen.

## Verifikation

- Die vollständige Swift-Suite, gezielte Filter-/NNA-/Stereo-Fixtures, der 64-Kanal-/256-Voice-Release-Stresstest, die JS↔Swift-MOD-Parität, der signierte App-Build und die Quick-Look-Extension sind grün.
- Die Wiedergabe wurde gegen die festgeschriebene `openmpt123`-/libopenmpt-Referenz und bei Filter-/Kompatibilitätsdetails zusätzlich gegen die OpenMPT- und Schism-Tracker-Implementierungen geprüft.

## Bekannte Einschränkungen

- MPTM, proprietäre OpenMPT-Erweiterungen, VST-/Plugin-Wiedergabe und externe MIDI-Ausgabe werden nicht unterstützt.
- Eingebettete MIDI-Makros sind auf gebräuchliche Cutoff-/Resonance-Filtermakros begrenzt.
- Pattern-Längen von 32 bis 200 Zeilen werden unterstützt; kürzere oder längere Erweiterungs-Patterns werden mit einem Parserfehler abgelehnt.
- Der HTML5-Player bleibt bewusst auf klassische 4-Kanal-ProTracker-MODs beschränkt.

## Hinweise

- Das DMG ist signiert und notarisiert und enthält App und Quick-Look-Extension; Moduldateien werden nicht mitgeliefert.

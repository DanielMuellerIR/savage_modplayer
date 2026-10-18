# Einschlaftimer

Seit 1.6.45 öffnet das Timer-Symbol in der Mac-Kopfzeile beziehungsweise in der
Wiedergabe-Navigation auf iPhone/iPad den Einschlaftimer. Eine Dauer zwischen
1 und 720 Minuten wählen oder die Schnellwahl für 15, 30 oder 60 Minuten nutzen.
**Timer starten** beginnt den Countdown für die aktuelle oder nächste Wiedergabe.
Die Restzeit steht im Dialog und am Timer-Symbol.

Der Countdown läuft als verstrichene Zeit: Pause, Titelwechsel, A/B-Wiedergabe
und Unterbrechungen halten ihn nicht an. Die letzten zehn Sekunden blenden die
Ausgabe sanft aus. **15 Minuten hinzufügen** verlängert die noch laufende Frist;
**Timer abbrechen** beendet den Countdown. Beide Aktionen stellen den momentan
gewünschten Pegel sanft wieder her. Der Lautstärkeregler bleibt unverändert und
kann weiterhin benutzt werden.

**Schließen** schließt den Dialog; der Countdown läuft weiter. **Neu starten**
setzt die Frist ab dem aktuellen Zeitpunkt auf die ausgewählte Dauer.
Der ausdrückliche Stopp der Wiedergabe schaltet den Timer aus. Ein natürliches
Songende erhält den Countdown, auch wenn die gewählte Abspielreihenfolge endet.

Nach Ablauf endet die Wiedergabe. Automatisches Fortsetzen nach einer
Unterbrechung oder einem verspäteten Ladevorgang bleibt gesperrt. Bewusstes
Wiedergeben startet mit dem erhaltenen Lautstärkewert. Ein abgelaufener Timer
lässt sich zurücksetzen oder neu setzen; dabei bleibt die Wiedergabe angehalten.

Die zuletzt gewählte Dauer wird gespeichert. Ein aktiver Countdown wird nach
einem App-Neustart nicht wiederhergestellt. Audioexporte erhalten die normalen
Exportpegel und werden vom Timer nicht beeinflusst.

Die Prüfverfahren stehen in [testing.md](testing.md), offene Geräteabnahmen
in [der aktiven Projektliste](../tasks/backlog.md).

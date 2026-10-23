OpenASPI 0.1 - freie ASPI-Geraetetreiber fuer DOS
================================================

Dieser deutsche Installationsdiskettensatz enthaelt:

  ASPIDSK.SYS  Festplatten und plattenaehnliche Geraete
  ASPIFDD.SYS  LS-120/240, ZIP, Clik! und Wechselmedien
  ASPICDA.SYS  CD/DVD und digitales CD-Audio
  ASPITAP.SYS  SCSI-Bandlaufwerke, ASPITAPE-kompatibel

Laden Sie einen ASPI-Manager wie AHCIASPI, EUSBASPI oder einen Adaptec-
Manager in CONFIG.SYS vor den OpenASPI-Treibern. Der Manager ist nicht auf
dieser Diskette enthalten. Die Diskette enthaelt auch kein bootfaehiges DOS.

Starten Sie A:\INSTALL.EXE aus DOS oder Windows 3.1/95/98/ME. Dieselbe EXE
enthaelt die DOS-Installation und die native Win16-Oberflaeche. Die Texte
dieses Pakets sind auf Deutsch eingestellt. Die Treiber werden nach
C:\OPENASPI installiert; INSTALL /U in C:\OPENASPI\ASPI entfernt OpenASPI.
Die automatische Geraeteauswahl kann vor der Installation geaendert werden.
Starten Sie danach den Rechner neu, damit die Treiber geladen werden.

ASPISCAN.COM zeigt ASPI-Adapter und Geraete. ASPIMGR.EXE bietet die gemeinsame
DOS-Oberflaeche von Open386MAX; Pfeiltasten waehlen ein Geraet, R sucht neu,
Esc beendet. ASPIMGR /TEXT gibt die Liste als Text aus.

ASPICTL EJECT|CLOSE|LOCK|UNLOCK|STATUS X: steuert Laufwerke. Jeder Befehl
funktioniert auch direkt als gleichnamige EXE, etwa EJECT F: oder LOCK F:.
EJECT F: /FORCE hebt die vom Treiber gemeldeten Sperren vor dem Auswerfen
auf. Hardwarefehler fuehren weiterhin zum Abbruch. CLOSE gilt nur fuer CD.

ASPIFMT D: zeigt den vorgesehenen FAT-Aufbau eines ASPIFDD-Wechselmediums.
Mit /YES wird es formatiert; dabei gehen vorhandene Dateien verloren.
Die Datenbereiche werden gelesen und wiederholt unlesbare Cluster in beiden
FAT-Kopien als defekt markiert. /FAT:32 setzt ein FAT32-faehiges DOS voraus;
dieser Pfad ist mit FreeDOS 1.4 getestet. Das ist keine physische Low-Level-
Formatierung. /WHOLE ersetzt ausdruecklich auch eine vorhandene Partitionierung.

ASPIDD D: E: kopiert gleich grosse Medien; ASPIDD D: verwendet eine temporaere
Abbilddatei und fordert zum Medienwechsel auf. Diese Datei muss auf einem
anderen physischen Datentraeger liegen; TEMP/TMP oder /TEMP:C:\COPY.IMG
waehlen ihren Speicherort. Schreibzugriffe werden durch Lesen geprueft.
ASPIDD READ D: C:\DISK.IMG sichert das gesamte Medium in eine neue Datei.
ASPIDD WRITE D: C:\DISK.IMG /YES schreibt ein genau passendes Abbild zurueck.
Auch lange Dateinamen innerhalb des Abbilds bleiben bei der Sektorkopie erhalten.

/RESCUE setzt bei Lesefehlern fort, fuellt unlesbare Sektoren mit Nullen und
schreibt eine separate CSV-Fehlerkarte. /MAP:C:\BAD.MAP waehlt eine neue Karte
auf einem anderen Laufwerk. Rueckgabewert 3 bedeutet: beendet mit Leseluecken,
nicht fehlerfrei wiederhergestellt. Schreib- und Prueffehler werden nicht
uebergangen. ASPIDDG.EXE bietet dieselben Funktionen mit deutscher DOS-GUI.
Ohne Argumente: Quelle/Ziel mit A-Z und Tab, F2 fuer Rescue, Enter bestaetigt.
Esc bricht zwischen abgeschlossenen Treiberaufrufen ab. Normale BIOS/FDC-
Diskettenlaufwerke ohne ASPIFDD-Rohzugriff werden von diesen Tools nicht bedient.

SHSUCDX.COM und CDAUDIO.COM sind fuer CD/DVD und die Audio-Moduswahl enthalten.
SHSUCD.LIC und SHSUCD.TXT enthalten Lizenz und Originaldokumentation.
TAPECTL.COM fragt den Bandstatus ueber NRMT0 ab; /READY prueft die Bereitschaft.
OTAPINFO.EXE nutzt die neue native Tape-API. Ohne Optionen erfolgt kein
SCSI-Zugriff; /REFRESH fragt Identitaet, Blockgrenzen und optionale Mode Pages
ohne Bandbewegung oder Bandschreiben ab. Unbekannte Faehigkeiten bleiben
unbekannt. Exit 0: Abfrage fertig; 1: Aufruf-/DOS-/API-Fehler; 2: unvollstaendig,
belegt oder gespeicherter Schreibfehler. Details im Quellbaum:
docs/native-tape-query.md.
Der Band-Schreibpfad ist emuliert getestet, aber noch nicht fuer produktive
Sicherungen auf echten Baendern qualifiziert. Es wird ein Laufwerk angeboten;
Bandwechsler gehoeren noch nicht zu diesem Stand.

WINCHECK.COM und WINCHECK.EXE erkennen die DOS-/Windows-Umgebung fuer Setup.
Die Kommandozeilenprogramme und Treiberdiagnosen verwenden derzeit gemeinsame
englische Texte. Installer, ASPIMGR und ASPIDDG dieses Satzes sind deutsch.

Installer: https://github.com/geosone/gdi
Lizenz: GNU General Public License Version 3, siehe LICENSE.TXT.
Quellcode: https://github.com/geosone/OpenASPI

OpenASPI exFAT 0.4 - exFAT-Laufwerke fuer DOS
==============================================

  EXFAT.SYS  exFAT-Datentraeger als DOS-Laufwerke
  EXFMT.EXE  formatiert exFAT
  EXCHK.EXE  prueft und repariert exFAT

EXFAT.SYS ist ein Redirector: es laeuft mit jedem DOS, das einen kennt
(MS-DOS 5 und neuer, FreeDOS, EDR-DOS). Es findet exFAT-Datentraeger auf
den BIOS-Festplatten (Superfloppy oder MBR-Partition vom Typ 07h) und, mit
OpenASPI, die exFAT-Medien von ASPIDSK.SYS und ASPIFDD.SYS, auch nach einem
Medienwechsel. Es braucht etwa 24 KB (34 KB mit langen Dateinamen) und
kann hoch geladen werden:

  DEVICE=C:\EXFAT\EXFAT.SYS [/L:x] [/Q] [/C] [/R]

  /L:x  erster zu verwendender Laufwerksbuchstabe (sonst der erste freie)
  /Q    keine Meldungen
  /C    BIOS-Festplatten nur ueber CHS, ohne die INT-13h-Erweiterungen
  /R    nur lesen: Schreiben, Anlegen, Loeschen und Umbenennen abgelehnt

Mit OpenASPI muss EXFAT.SYS nach ASPIDSK.SYS und ASPIFDD.SYS stehen. DOS
zeigt lange Namen als 8.3-Namen (LETTER~1.TXT) in Codepage 437 oder 850.
Mit der Option "Lange Dateinamen" (EXFATL.SYS, als EXFAT.SYS installiert)
sehen Programme fuer lange Dateinamen (INT 21h AX=71xxh, wie mit DOSLFN
oder Windows 95: das DIR von MS-DOS 7, Dateimanager) die langen Namen;
DOSLFN kann fuer die anderen Laufwerke nach EXFAT.SYS geladen werden.
Dateien und Verzeichnisse koennen geschrieben, angelegt, geloescht und
umbenannt werden, auch auf TexFAT. Waehrend einer Aenderung ist der
Datentraeger als unsauber markiert; nach einem Absturz gibt EXCHK /F
verlorene Cluster frei. Dateien ab 4 GB zeigen die Groesse FFFFFFFFh. CHKDSK, SCANDISK und DEFRAG
arbeiten nicht auf diesen Laufwerken; dafuer gibt es EXFMT und EXCHK.

EXFMT d: | /D:nn [/P:n | /WHOLE] [/V:Name] [/A:Groesse] [/TEXFAT] [/Q] [/YES]
formatiert ein Laufwerk von EXFAT.SYS, ASPIDSK oder ASPIFDD oder die
BIOS-Festplatte nn (80 = die erste). Ohne /YES wird nur der Aufbau
gezeigt. Formatiert wird die Partition des Laufwerks, mit /P:n Partition
n, mit /WHOLE das ganze Medium. Vorher wird der Datenbereich gelesen (nicht
mit /Q) und unlesbare Cluster werden als defekt markiert. /TEXFAT schreibt
zwei FATs und Belegungstabellen: sinnvoll fuer alte ZIP- und SuperDisk-
Medien, EXCHK /F repariert eine beschaedigte Kette aus der zweiten Kopie.
Auf einer BIOS-Festplatte muss eine FAT-Partition mit /P:n genannt werden.

EXCHK d: [/F] prueft ein Laufwerk von EXFAT.SYS: Bootbereich und seine
Sicherung, Pruefsummen und Namens-Hashes aller Verzeichniseintraege,
Clusterketten gegen die Belegungstabelle. /F repariert, was sich
reparieren laesst, und zeigt jede Reparatur. Rueckgabewerte: 0 keine
Fehler, 1 Fehler, 2 falscher Aufruf, 3 Lesefehler.

Dieses Paket und die exFAT-Option von OpenASPI installieren dieselben
Dateien. Ist OpenASPI installiert, nehmen Sie dessen exFAT-Option (dieses
Setup warnt). Fuer den Wechsel zu OpenASPI entfernen Sie dieses Paket
vorher mit INSTALL /U in C:\EXFAT: INSTALL /U entfernt jede EXFAT.SYS-
Zeile aus CONFIG.SYS, auch eine von OpenASPIs Setup (dann dieses Setup
erneut ausfuehren).

Der Installer ist der GeosOne DOS Installer: https://github.com/geosone/gdi
Lizenz: GNU General Public License Version 3.
Quelle: https://github.com/geosone/OpenASPI

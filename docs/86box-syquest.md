# SyQuest ATA cartridge drives in 86Box

The SyQuest EZ135 and EZFlyer 230 are plain ATA drives, not ATAPI. Their
cartridges are read and written with ordinary ATA sector commands, and
IDENTIFY DEVICE sets the removable bit. 86Box master (since PR #8698,
2026-11-04) runs its removable disk types EZ135A (31) and EZ230A (32) as
such on the bus `ide`; on `atapi` they stay an ATAPI approximation. The
older geosone/86Box branch `lpt-zip` had them as types 9 and 10
(`TYPES="9 10"` for the test):

```ini
[Other removable devices]
rdisk_01_parameters = 32, ide
rdisk_01_ide_channel = 1:0
rdisk_01_image_path = cart.img
```

The geometry comes from SyQuest Technical Bulletin 5040 and the EZFlyer manual.
The EZFlyer also reads and writes EZ135 cartridges.

| Drive       | CHS         | Sectors | LBA |
|-------------|-------------|---------|-----|
| EZ135       | 512/16/32   | 262 144 | no  |
| EZFlyer 230 | 880/16/32   | 450 560 | no  |

`tests/dos_86box_syquest.sh` checks access through the BIOS and through
SQATDRVR.SYS; see [building](building.md).

## AHCIASPI, ASPIFDD and EXFAT.SYS

With its ATA cartridge support, AHCIASPI offers the drive as
a SCSI direct access device. Its INQUIRY gives vendor `ATA` and product
`SyQuest EZFlyer`, and ASPIFDD takes SyQuest products like ZIP and Jaz.

With `ASPI=1`, the test puts the drive on 86Box's tertiary ISA channel
(1E8h/3EEh, IRQ 11). The BIOS does not look there, so the drive is
AHCIASPI's:

```text
DEVICE=AHCIASPI.SYS /V /P:1E8,3EE
DEVICE=ASPIFDD.SYS /V
```

DOS reads and writes the FAT16 partition, both without and with `VERIFY ON`.
`EXFAT=1` uses an exFAT partition (type 07h) for EXFAT.SYS on ASPIFDD's drive
letter instead.

On the BIOS channel (`ASPI=bios`), the BIOS has the drive as hard disk 80h.
AHCIASPI finds that through EDD and reports it in GET DISK INFO, so ASPIFDD
takes the letter DOS has over (`C: (BIOS drive taken over)`, see
[ownership](block-ownership.md)): one letter, reached through ASPI.

Without a cartridge, ASPIFDD registers the drive as `(no disk)`, and an access
gives `C: - READ FAILURE`.

## SQATDRVR.SYS 1.75 as observed

SyQuest's DOS driver (Windows 98 driver library) was not disassembled; its
license forbids that. Its behaviour below was taken from the ATA commands
86Box received from the emulated EZFlyer, without and with a cartridge, and
from what DOS showed. 86Box now emulates that behaviour.

Commands seen during BIOS POST and driver init. The trace does not separate
the BIOS from the driver.

- EC IDENTIFY DEVICE
- 90 EXECUTE DIAGNOSTICS
- 10 RECALIBRATE
- 91 INITIALIZE DEVICE PARAMETERS (32 sectors, 16 heads)
- C6 SET MULTIPLE (16)
- 40 VERIFY of sector 0
- EF SET FEATURES 03 (transfer mode 0Ch)
- E3 IDLE
- DB ACKNOWLEDGE MEDIA CHANGE
- DC POST-BOOT, sent once after the driver loads
- DE DOOR LOCK, only with `/a:0`

A cartridge is read with C4 READ MULTIPLE and written with C5 WRITE MULTIPLE.
Before an access, the driver often sends IDENTIFY DEVICE again.

With a cartridge, the driver takes over the BIOS volume:
`DOS VOLUME C: SYQUEST has been taken over`.

Without a cartridge, the driver adds a placeholder volume instead:
`DUMMY VOLUME C: Added on Master Device of ports 17Xh`. An access to it runs:

1. IDENTIFY, then READ MULTIPLE of one sector, which fails.
2. IDENTIFY and READ again, which fail again.
3. ACKNOWLEDGE MEDIA CHANGE, SET MULTIPLE and IDENTIFY, then a third READ,
   which fails.
4. DOS shows `C: - READ FAILURE` and `(A)bort, (R)etry, (F)ail?`. Enhanced
   DR-DOS shows that for any empty removable drive. ASPIFDD with an empty
   ATAPI LS-120 gets the same prompt.

The driver therefore repeats the read itself. The emulated drive answers each
command only once.

The driver output stays the same for each of these answers to a command without
a cartridge:

- error NM (02h), the ATA-4 "no media"
- ABRT (04h)
- IDNF (10h)
- the same error without DRDY in the status
- DRDY cleared in every status read

So the driver does not tell these cases apart. 86Box uses NM, which also gives
ATA-4 hosts the right answer.

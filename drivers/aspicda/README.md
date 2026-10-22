# ASPICDA.SYS

ASPI CD/DVD driver: a DOS CD-ROM device driver (the MSCDEX driver interface)
for SCSI multimedia devices (peripheral type 05h) behind an ASPI manager
such as AHCIASPI (SATA/IDE) or EUSBASPI (USB).

    DEVICE=C:\OPENASPI\AHCIASPI.SYS
    DEVICE=C:\OPENASPI\ASPICDA.SYS /D:ASPICDA0
    C:\OPENASPI\SHSUCDX.COM /D:ASPICDA0        (or MSCDEX /D:ASPICDA0)

Options: `/D:name` device name (default `ASPICDA0`), `/V` list the drives.
Up to 8 drives, one subunit each.

Version 0.1:

- READ LONG cooked (2048 bytes, READ(10)) and raw (2352 bytes, READ CD),
  HSG and Red Book addresses.  Raw reads of audio sectors give the
  CD-audio SHSUCDX (`deps/shsucd`, `/A:1`) the digital audio for VSBHDA.
- IOCTL input: device header, device status, sector size, volume size
  (READ CAPACITY), media changed (TEST UNIT READY), audio disk and track
  info (READ TOC).
- IOCTL output: eject, close tray, lock/unlock, reset.
- PLAY AUDIO (PLAY AUDIO MSF), STOP/RESUME (PAUSE/RESUME) for analog audio.
- A private stack for the ASPI manager.

What Adaptec ASPICD.SYS has beyond that, and what follows, is listed in
[ASPICD compatibility](../../docs/aspicd-compat.md).  Tested in QEMU with
AHCIASPI on AHCI and IDE and SHSUCDX (`make dos-cda-smoke`).

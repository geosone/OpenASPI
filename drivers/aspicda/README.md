# ASPICDA.SYS

CD eject, close and lock/unlock use the shared media-control transport.
The command-line frontend is `ASPICTL`, also usable as `EJECT.EXE` and
`CLOSE.EXE`; see [media controls](../../docs/media-control.md) for semantics,
tests and qualification limits.

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
  CD-audio SHSUCDX (`deps/shsucd`, `/A:ON` or `/A:AUTO`) the digital audio
  for VSBHDA.
- SEEK and READ LONG PREFETCH perform SEEK(10), checking the target against
  the current medium's capacity. Prefetch is a positioning hint, not a
  guarantee of cached sectors. HSG/MSF addresses are validated.
- IOCTL input: device header, device status, sector size, volume size
  (READ CAPACITY), media changed (TEST UNIT READY), audio disk and track
  info (READ TOC), current head position (HSG/MSF) and audio Q-channel
  information (READ SUB-CHANNEL, including BCD track conversion), audio
  pause status and the saved MSF start/end range, UPC/EAN media catalog
  number (packed BCD, with explicit missing-code/error handling).
- IOCTL output: eject, close tray, lock/unlock. Reset is currently only a
  success-only placeholder, not a hardware reset.
- Four-port volume/routing IOCTLs read current Audio Control page 0Eh and
  use its changeable mask before MODE SELECT(10). Failed changes are not
  cached as success; unrelated page fields and muted ports are preserved.
  Device-status bit 8 is enabled only after verified channel-control support.
- PLAY AUDIO (PLAY AUDIO MSF), STOP/RESUME (PAUSE/RESUME) for analog audio.
- Per-unit playback state: successful pause saves the resume position;
  failed commands do not fake transitions. Active status/open/close/flush
  calls poll the drive; playing audio sets busy and device-status bit 10.
- The audio capabilities from MODE SENSE page 2Ah, listed by `/V`:
  "analog audio" (Audio Play: the drive plays audio itself, to its
  analog output) and "digital audio" (CD-DA: audio sectors can be read
  for VSBHDA; "inexact" when the stream is not accurate).
- A private stack for the ASPI manager.

### Analog or digital CD audio

Whether the analog output of a drive reaches the speakers no driver can
tell: Audio Play only says the drive has one.  SATA and USB drives and HDA
sound without a CD input usually have no working analog path even when
the bit is set.  So SHSUCDX picks the path:

    SHSUCDX /D:ASPICDA0 /A:AUTO     digital while VSBHDA /CDA1 is loaded
    CDAUDIO ON                      digital (VSBHDA) from now on
    CDAUDIO OFF                     analog (the drive plays)
    CDAUDIO                         show the mode and the current path

VSBHDA registers when it loads with `/CDA1` and unregisters when it is
unloaded; switching away from digital stops a digital play.  The device
status (IOCTL input 6) always reports audio play, since programs that
check it would otherwise not play CD audio on the digital path either.

What Adaptec ASPICD.SYS has beyond that, and what follows, is listed in
[ASPICD compatibility](../../docs/aspicd-compat.md).  Tested in QEMU with
AHCIASPI on AHCI and IDE and SHSUCDX (`make dos-cda-smoke`).
The test also checks the real driver against a memory ASPI callback and
positions the emulated drive at sector zero and its capacity boundaries.
Head/Q packet layouts and malformed/unsupported responses are covered by
memory-backed tests; physical audio-disc qualification remains outstanding.
Two-unit memory tests also cover audio state/busy flags, failed commands,
completion, pause/resume ranges and lost/replaced media.
Channel tests cover routing/volume readback, changeability masks, muted ports,
mode-page preservation and capability flags. Physical analog volume and
legacy/vendor command sets remain unqualified.
UPC tests also check SHSUCDX forwarding in analog and digital modes; no
SHSUCDX change is needed for this IOCTL. A physical disc with a catalog
number remains unqualified.

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
  CD-audio SHSUCDX (`deps/shsucd`, `/A:ON` or `/A:AUTO`) the digital audio
  for VSBHDA.
- IOCTL input: device header, device status, sector size, volume size
  (READ CAPACITY), media changed (TEST UNIT READY), audio disk and track
  info (READ TOC).
- IOCTL output: eject, close tray, lock/unlock, reset.
- PLAY AUDIO (PLAY AUDIO MSF), STOP/RESUME (PAUSE/RESUME) for analog audio.
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

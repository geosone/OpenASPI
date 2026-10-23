# CD image with a media catalog number

`make dos-cda-smoke` creates these fixtures under `build/dos-cda/`:

- `cd.iso`: ISO-9660 data track, including the existing read-test files;
- `cd.cue`: one MODE1/2048 track plus catalog number `0123456789012`.

The catalog has a valid EAN-13 check digit and leading zero, matching the
positive memory-backed UPC test. The CUE references `cd.iso` relative to its
own directory. The image is padded beyond the four-second minimum track
length so cdrdao can validate it without forcing warnings. These are data-only
test images; no physical CD is written.

To parse and validate the image metadata using installed cdrdao tools:

```sh
cd build/dos-cda
cue2toc -o cd.toc cd.cue
cdrdao toc-info cd.toc
```

Neither command opens a physical drive. The generated TOC retains CATALOG.

## Native QEMU limitation

The tested QEMU 10.2.3 AHCI and IDE boots attach `cd.iso` as `ide-cd`, read
its files and exercise SHSUCDX. Native `ide-cd` does not load the CUE metadata.
An ISO contains the data sectors, not the Q-subchannel catalog number; putting
a barcode text file or a volume identifier inside the ISO cannot supply MCN.

More importantly, the version-pinned [ATAPI command table](https://github.com/qemu/qemu/blob/v10.2.3/hw/ide/atapi.c)
does not implement opcode 42h (READ SUB-CHANNEL). Thus current installed-driver
UPC checks exercise **unsupported-command propagation**, not a positive MCN
read and not a proof that a catalog-capable drive reports a missing code.
The image format alone cannot fix this. The installed `ide-cd,help` options
also provide no catalog-number property.

The CUE/ISO pair is prepared for a CD backend that understands the catalog
metadata. A positive end-to-end test needs one of:

- a CUE-capable virtual SCSI CD backend, passed into QEMU using `scsi-generic`
  and a DOS-supported SCSI controller/manager; or
- a QEMU CD-emulation extension that implements READ SUB-CHANNEL and obtains
  catalog metadata from a defined image/backend interface.

Neither is silently substituted here. CDEmu/vhba is not installed/loaded on
the inspected host; installing its daemon/kernel module or building a custom
QEMU is a separate environment change. The existing tape libraries and
physical optical drives are not used by this fixture.

Until such a backend exists, positive UPC conversion remains covered by
`tests/cda_upc.asm` against memory ASPI. Successful data-image boots must not
be described as successful image-backed catalog reads.

## Unpatched 86Box and VirtualBox checks

At initial inspection, both alternatives were installed: stock 86Box 6.0 and
VirtualBox 7.2.18. Their image-backed paths were inspected before attempting
to create/register another VM. No existing VM or its media was modified.

86Box supports CUE images and CD audio, but that alone is not MCN support.
Its version-pinned [CUE parser](https://github.com/86Box/86Box/blob/v6.0/src/cdrom/cdrom_image.c)
explicitly treats CATALOG as an ignored command. Its
[current-subchannel formatter](https://github.com/86Box/86Box/blob/v6.0/src/cdrom/cdrom.c)
marks UPC reporting TODO and returns zero catalog data rather than obtaining
the real number from an image. Changing to another supported image type
does not resolve that formatter limitation. Thus a normal 86Box 6.0 boot
cannot supply the positive image-backed MCN test either.

VirtualBox's installed version was checked against the matching local source
archive `/var/cache/distfiles/VirtualBox-7.2.18.tar.bz2`: neither the emulated
IDE packet command handler in `DevATA.cpp` nor the emulated SCSI MMC handler
in `Storage/VSCSI/VSCSILunMmc.cpp` implements READ SUB-CHANNEL. Unknown commands
return ILLEGAL REQUEST. The corresponding upstream
[IDE](https://github.com/mirror/vbox/blob/master/src/VBox/Devices/Storage/DevATA.cpp)
and [SCSI MMC](https://github.com/mirror/vbox/blob/master/src/VBox/Devices/Storage/VSCSI/VSCSILunMmc.cpp)
paths show the same limitation. Host-drive passthrough is a different path,
not proof that a virtual image carries its catalog to the guest.

These are source-level capability checks, not claimed 86Box/VirtualBox DOS
boot results. Native QEMU AHCI/IDE data-image boots passed with the generated
image. `cue2toc` and `cdrdao toc-info` validated the catalog manifest and
640-block track without forcing consistency warnings. Those checks motivated
the separate local emulator variant described below; no host kernel-module
installation was needed.

## Local patched 86Box and Portage integration

The local test build now reads CUE CATALOG and reports it through MCN
READ SUB-CHANNEL, without replacing the system emulator:

```text
/home/mario/mars/86Box/build-upc/src/86Box
```

Upstream change: [86Box pull request #8478](https://github.com/86Box/86Box/pull/8478),
branch `geosone:cdrom-cue-mcn`, commit `90c644da3`. The optional backend callback
keeps absent catalogs invalid and stores metadata per image. Seven unit tests
cover parsing, leading zeros, absent/invalid catalogs, replacement images,
format 0, BCD-drive frames and output boundaries. The patch also fixes the
existing formatter's fallthrough and uninitialized reserved byte.

A source-compatible backport was compiled for installed version 6.0 and is
placed at:

```text
/etc/portage/patches/app-emulation/86Box-6.0/0001-cdrom-expose-CUE-media-catalog-numbers-through-READ-.patch
```

Portage applies it on the next merge of that version, for example:

```sh
emerge -1av =app-emulation/86Box-6.0
```

This command has **not** been run by the test harness; the installed system
binary is unchanged. The versioned directory avoids blindly applying the
6.0 backport to a future release. When upstream includes the feature, remove
the local backport before merging a version that already contains it.

## Positive guest tests

The local build uses `AUTOMATION=ON`. With the existing local ROM set:

```sh
bash tests/dos_86box_upc.sh
HIGH=1 bash tests/dos_86box_upc.sh
```

Override `BOX`, `ROMDIR`, `OUT` and `JEMMEX` as needed. The system 6.0 binary
does not acquire the newer automation interface from the small backport;
these scripted runs use the local development build. They create isolated
VM directories and a private Xvfb, leaving existing registered VMs untouched.
ROMs and JEMMEX are local prerequisites, not distributed with this project.

On an ASUS P/I-P55T2P4 with an emulated ATAPI CD-ROM, both analog and digital
SHSUCDX modes read catalog `0123456789012` from the mounted CUE. The check
uses actual AHCIASPI/ASPICDA and validates packed BCD, CONTROL/ADR and output
guards; it is not the memory-only ASPI callback fixture. The ISO's README is
also read through the installed driver. Logs remain in each VM directory.

The HIGH variant loads JEMMEX with DOS=HIGH,UMB and uses DEVICEHIGH for
AHCIASPI and ASPICDA. It verifies the manager's returned entry segment and
the CD driver's header segment are both at least A000h, then runs the same
positive catalog checks. This confirms upper-memory operation for that CD
stack, **not** DEVICEHIGH qualification of ASPIDSK, ASPIFDD or ASPITAP.

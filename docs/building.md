# Building OpenASPI

## Checkout and requirements

Clone with `git clone --recursive`, or initialize an existing checkout with:

```sh
git submodule update --init --recursive
```

The build uses GNU make, a host C compiler, the pinned JWasm/JWlink
submodules and OpenWatcom. The default OpenWatcom location is `/opt/watcom`;
override `WATCOM` when necessary. JWasm and JWlink are built locally without
writing generated files into their checkouts:

```text
build/tools/jwasm/jwasm
build/tools/jwlink/jwlink
```

Override `JWASM`, `JWLINK` or `CC` on the make command line when required.
All build products are written below `build/`.

## Build and local checks

```sh
make
make test
make check
```

`make` builds the DOS driver, diagnostic tools, Win16 environment probe and
host test programs. `make test` runs the host protocol/SRB tests and checks
the DOS device-header layout. `make check` also builds the tools and compiles
the portable C modules and tape ABI checks as 16-bit DOS objects with
OpenWatcom. These local checks do not access tape media.

## Emulator and integration tests

- `make dos-smoke` boots the local SvarDOS fixture in QEMU, loads the sibling
  AHCIASPI manager, verifies clean rejection when no tape is present and runs
  the scanner and installer probes against an emulated ATAPI CD-ROM.
- `make dos-tape-smoke` boots a test-only ASPI manager exposing an emulated
  tape. Driver scenarios and focused runs are documented in
  [ASPITAP testing](../drivers/aspitap/TESTING.md).
- `make dos-mhvtl-smoke` uses QEMU's Tekram-compatible DC-390 controller and
  `scsi-generic` passthrough to an mhVTL tape. It requires an external DOS ASPI
  manager and explicitly selected `/dev/sgN` nodes. Follow the separate
  [mhVTL setup and safety instructions](qemu-mhvtl.md).

The boot tests require external tools and local test media described in
[reference material](reference-material.md) and the test scripts. They are
not part of `make check`. Do not substitute a physical tape device for the
virtual test target without reviewing the integration instructions.

## Distribution

`make dist` creates an installable directory under `build/dist/` using the
existing GeosOne DOS Installer. Component choices cover all four OpenASPI
drivers; drivers not present in the distribution remain unavailable to the
installer. See [installation](../installer/README.md).

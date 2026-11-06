# Native ASPI layer

The ASPI model in C for 32- and 64-bit kernels: GDOS, the DOS-like start
environment of [GonWare](https://gitea.disconnected-by-peer.at/GonSoft/GonWare),
uses it polled; GonWare's server executive takes it over as `ASPI.GLM` and
adds interrupts and DMA. It needs no C library.

| File | Content |
| --- | --- |
| [`aspi.h`](../../include/openaspi/native/aspi.h), `aspi.c` | host adapters, SCSI request blocks (`struct oa_srb`), sense decoding, INQUIRY bus scan |
| [`disk.h`](../../include/openaspi/native/disk.h), `disk.c` | block device class: disks, removable media (floppy, LS-120, ZIP, sticks), CD/DVD data |
| [`sat.h`](../../include/openaspi/native/sat.h), `sat.c` | SCSI/ATA translation for transports that drive ATA disks (AHCI, IDE, ATA bridges) |
| [`host.h`](../../include/openaspi/native/host.h) | services the embedding system provides: log, time, DMA memory, MMIO, PCI, port I/O |

Transports live with their DOS managers and are built with CMake there:
AHCI and IDE in [AHCIASPI](https://github.com/geosone/ahciaspi), USB in
[EUSBASPI](https://github.com/geosone/eusbaspi), NVMe in
[NVMEASPI](https://github.com/geosone/nvmeaspi), parallel port and floppy
controller in [PORTASPI](https://github.com/geosone/portaspi) (later). Each
registers a `struct oa_hba` and answers `execute()`.

## Build and test

```sh
cmake -S . -B build/native -G Ninja
ninja -C build/native && ctest --test-dir build/native
```

As a subproject (`add_subdirectory`) the top-level `CMakeLists.txt` only
defines the static library `OpenASPI::native`; the parent chooses compiler
and flags. The host test runs an in-memory ATA disk through the translation,
the bus scan and the block class.

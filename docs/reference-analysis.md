# Reproducing Adaptec driver analysis

`tools/reference/InspectAspiDriver.java` is a local Ghidra post-script for
the documented ASPIDISK 4.01b and ASPICD 4.01 binaries. It checks the imported
file's SHA-256, requires a raw real-mode import at `0000:0000`, reads dispatch
tables from the image, seeds their nonzero handlers, runs analysis, and
exports discovered functions to a local report. It never executes the
original driver or accesses a storage device through it.

The vendor files remain external [reference material](reference-material.md).
Generated reports contain vendor disassembly/decompiler output: keep them
under ignored `build/` or outside the checkout, never in source releases.
Only behavioral notes, offsets and our analysis tooling belong in the repo.

Example using the installed Ghidra (its launcher is invoked with bash):

```sh
mkdir -p build/reference-ghidra
bash /usr/share/ghidra/support/analyzeHeadless \
  "$PWD/build/reference-ghidra" aspidisk-reference \
  -import /home/mario/Iso/Dos/ez-scsi/ASPIDISK.SYS \
  -loader BinaryLoader -processor x86:LE:16:Real\ Mode \
  -scriptPath "$PWD/tools/reference" \
  -postScript InspectAspiDriver.java "$PWD/build/reference-ghidra/aspidisk.c"
bash /usr/share/ghidra/support/analyzeHeadless \
  "$PWD/build/reference-ghidra" aspicd-reference \
  -import /home/mario/Iso/Dos/ez-scsi/ASPICD.SYS \
  -loader BinaryLoader -processor x86:LE:16:Real\ Mode \
  -scriptPath "$PWD/tools/reference" \
  -postScript InspectAspiDriver.java "$PWD/build/reference-ghidra/aspicd.c"
```

Use fresh project names for fresh imports; use Ghidra's `-process` when
revisiting an existing imported program instead. The local 2026-10-23 runs
used Ghidra 12.1.4 DEV and exported 94 discovered functions from each driver.
That count is **not** proof that every code path or vendor-specific command
table has been recovered, understood or runtime-tested. Real-mode register
arguments, segment state and flags need disassembly checks; missing or
incorrect decompiler types cannot serve as an application ABI.

Analysis and implementation ledgers:

- [ASPIDISK / ASPIDSK](aspidisk-compat.md).
- [ASPICD / ASPICDA](aspicd-compat.md).
- [GUEST / MKELS120 and ASPIFDD](aspifdd-reference.md).
- [NT tape drivers and common device cases](nt-tape-analysis.md).
- [DOS tape APIs and the Colorado Win3.x VxD](dos-tape-api-analysis.md).

Driver-replacement acceptance requires tests of the actual OpenASPI code,
not compilation of vendor decompiler output. Hardware-specific destructive
operations require separate scratch-media qualification, even after static
analysis and memory-only protocol tests pass.

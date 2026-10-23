# Static reference inspection

These tools inspect known reference binaries to document compatibility/API
behavior. They do not execute vendor drivers or supply production implementations.
Findings and pinned provenance are recorded in
[reference material](../../docs/reference-material.md),
[analysis notes](../../docs/reference-analysis.md) and the tape manifests.
Generated disassembly/decompiler reports stay in ignored local output directories.

| Tool | Input/analysis convention |
| --- | --- |
| [`inspect_guest.sh`](inspect_guest.sh) | Documented GUEST 6.0/8.5 executable, checked by SHA-256 and expected bytes before selected 16-bit disassembly ranges. |
| [`InspectAspiDriver.java`](InspectAspiDriver.java) | Pinned ASPIDISK/ASPICD raw real-mode import at `0000:0000`; seed known entry/dispatch targets and report functions. |
| [`InspectDosTapeApi.java`](InspectDosTapeApi.java) | Pinned raw DOS tape module, real-mode import at `0000:0000`; use the module's callback table or device-header entries. |
| [`InspectNtTapeDriver.java`](InspectNtTapeDriver.java) | Pinned x86 32-bit PE import; report strings/xrefs, callers, decompiled functions and disassembly. |

## Running and interpreting reports

The shell helper takes one local binary path:

```sh
bash tools/reference/inspect_guest.sh /path/to/GUEST.EXE
```

It requires `sha256sum`, `od`, `tr`, `dd` and `ndisasm`. Offsets are load-image
relative; extraction accounts for the pinned MZ header. An unknown hash is
rejected rather than applying offsets to another version.

Run Java scripts inside Ghidra with one output-report-path argument, using the
matching raw/PE import convention. The scripts use Ghidra APIs and are not
standalone Java programs. They check pinned hashes and relevant import properties;
read their individual checks before reusing an existing analysis project.
Choose an ignored `build/` report path: that location is caller policy, not a
path restriction enforced by the Java scripts. Existing report paths are opened
for writing, so choose the intended destination.

Raw DOS imports set DS context for analysis; this does not establish actual
runtime segment/register arguments. Inferred C types and function boundaries
need review against instructions and dispatch structure. NT imports retain PE
image-base semantics and cannot use DOS raw-image assumptions.

A string or a decompiled branch alone does not establish an API guarantee or
firmware bug. Separate a supported device function, an emulatable capability
and a version-specific workaround; qualify behavior before adding it to the
native API or a quirk. See [tape profiles](../../docs/tape-device-profiles.md),
[DOS/Win3.x findings](../../docs/dos-tape-api-analysis.md) and
[NT findings](../../docs/nt-tape-analysis.md).

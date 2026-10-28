# Native TapeAlert retrieval

TapeAlert supplies drive-reported diagnostic flags through LOG SENSE page
`2Eh`. Retrieval is explicit: some drives clear their alert log when it is
read, so this operation requires caller acknowledgment and is never part of
QUERY/REFRESH, READY, backup startup or automatic UI polling.

The [HPE LTO-7 TapeAlert reference](https://support.hpe.com/hpesc/public/docDisplay?docId=sd00006909en_us&docLocale=en_US&page=GUID-D7147C7F-2016-0901-0922-0000000005A5.html)
describes the binary parameters and clear-on-read behavior. The
[HPE LOG SENSE reference](https://support.hpe.com/hpesc/public/docDisplay?docId=sd00001234en_us&page=GUID-D7147C7F-2016-0901-0922-0000000005C5.html)
defines current-value selection, allocation and parameter ordering. The
[IBM 3592 TapeAlert guide](https://www.ibm.com/docs/en/3592-rackmount?topic=troubleshooting-tapealert-error-reporting)
lists drive diagnostic meanings; not every flag is supported by every drive.
This binding retains numeric codes, rather than imposing vendor-specific
severity or recovery actions. It operates on the selected tape drive, not a
library/changer.

## Caller and wire contract

Category `80h`, function `07h`, version `0100h`, packed size 64, format 0.
Flags must be exactly `OT_TAPE_ALERTS_ACKNOWLEDGE=1`; missing or unknown flags
are rejected before a command. The provider capability is
`OT_TAPE_OP_ALERTS=10000000h`; the complete current mask is `3FFFFFFFh`.
A provider bit advertises the binding, not attached-drive support.

| Offset | Bytes | Field |
| --- | --- | --- |
| `00h..1Bh` | 28 | Shared native envelope and observation diagnostics/completion |
| `1Ch` | 4 | Valid fields: bit 1 means a complete parsed alert page |
| `20h` | 4+4 | Reported flags, low/high DWORDs |
| `28h` | 4+4 | Active flags, low/high DWORDs |
| `30h` | 4 | Probe flags: UNVERIFIED_LENGTH bit 1 |
| `34h` | 12 | Reserved zero |

Bit 0 of the low DWORD is alert 1; bit 31 is alert 32. High DWORD bits 0 and
31 denote alerts 33 and 64. Active bits must be a subset of reported bits.
A missing reported bit means unknown, not clear or unsupported. A reported
zero value means only that the drive returned zero: it does not prove support
for that diagnostic condition or overall drive health. An empty valid page
has no known flag states. No masks are published for PARTIAL, BUSY or ERROR.

`ot_tape_alerts_init` rejects invalid acknowledgment before changing its
output. `ot_tape_alerts_validate` checks the returned packet, including result,
completion, diagnostic and mask consistency. `ot_tape_alert_state` returns
-1 for unknown/invalid, 0 for reported inactive, 1 for reported active.
These helpers perform no I/O and use separate 32-bit words on the DOS compiler.

## One submission and bounded parsing

One synchronous ten-byte CDB is issued:
`4D 00 6E 00 00 00 00 02 00 00`.
It requests current values, page `2Eh`, subpage zero, parameter pointer zero,
512 bytes and 32 sense bytes. PPC, SP and remaining fields are zero. The
resident buffer can hold the usual 324-byte page without a header-only probe
followed by another read that might consume cleared flags.

A negotiated residual must prove transferred length: retained residual flag,
zero high word, residual in `0..512`. The parser checks the header, declared
extent, subpage form and every parameter extent. DS in the page header is
ignored. Parameters must be unique and ascending; code zero is invalid.
Known codes 1..64 require length 1, numeric format and boolean value 0 or 1.
Complete future codes above 64 are skipped after structural validation.
Masks are staged separately and copied only after the entire page passes.
Truncation, duplicates, wrong format/value or malformed trailing data discard
all masks. No partial successful-looking warning list escapes.

A valid complete page returns OK, SUBMITTED|DONE, opcode `4Dh` and validity 1.
A manager without length proof returns PARTIAL/INCOMPLETE/UNVERIFIED_LENGTH
without parsing flag states. A malformed completed page returns ERROR/MALFORMED
and SUBMITTED|DONE. Hardware errors retain their checked diagnostics with
SUBMITTED but no DONE. BUSY submits nothing. No failed or malformed retrieval
is retried: its first read may already have acknowledged device warnings.

Active writers, legacy activity, pending rewind, buffered aliases/data or
competing handles prevent submission. Native FAILED and DIRTY|FAILED can be
observed; legacy diagnostics, queued EOF and native session state are preserved.
Retrieval does not recover abandoned output, move tape or issue LOG SELECT.
The acknowledgement permits device-defined read side effects, not a log-reset
command. It cannot coordinate other applications' concurrent log readers.

## OpenTape consumer

The SDK exposes `ot_native_alerts` / `ot_dos_native_alerts` with the mandatory
acknowledgment argument and guarded reply validation. It opens once, checks
device identity, provider capability and ownership, submits once, and closes
once with first-error precedence. A close error preserves a validated report.

```dos
OPENTAPE --native-alerts --allow-clear --device NRMT0
```

The CLI rejects missing/duplicate acknowledgment, extra arguments, refresh and
rewinding aliases before opening. It prints the acknowledgment notice and
flushes output before retrieval, then prints reported/active counts and active
flag numbers. Exit 0 means successful retrieval, not healthy media; active flags
do not automatically change the exit code. Missing states remain explicit.
Existing stdout redirection can retain the report; automatic history is not
implemented. Older SDK headers reject the verb without device I/O.

In the native DOS tape controls, **A** displays the selected drive and the
acknowledgment notice before the existing Y/J confirmation. Canceling consumes
the key without another action. Results display all active numeric codes,
including all 64 in the existing QUILIB data window, and retained session/
diagnostic status. Leaving the view does not request another page. Ordinary
status screens never acknowledge the log implicitly.

## Tests and limits

`tests/mockalerts.inc` checks the exact CDB, sizes and flags in memory only.
The sibling OpenTape `tests/dos_native_alerts.sh` runs installed DOS provider,
SDK and CLI tests for sparse/all/clear/empty pages, flag boundaries 1/32/33/64,
unknown parameters, DS, malformed bounds/ordering/values, residual provenance,
legacy managers, transport/target failures and preservation of diagnostics,
queued EOF and retained writer uncertainty. Exact counters reject extra reads.
GUI tests check confirmation/cancellation, full 64-code display, unknown/clear
states, failures and older SDK behavior in both languages. No physical tape
is attached; device support and warning-reset behavior remain hardware
qualification work.

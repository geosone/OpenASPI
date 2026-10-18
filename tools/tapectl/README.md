# TAPECTL

`TAPECTL.COM` is the small DOS diagnostic used before OpenTape exists. It opens
`RMT0`, enables DOS raw mode, obtains the complete fourteen-byte `mtget` block
through the ASPITAPE-compatible category `07h` interface, and reports:

- the ASPI host-adapter, target and LUN address;
- driver flags;
- the last SCSI status, sense key and operation code;
- the residual byte count.

Running it without arguments is read-only and does not send a SCSI command to
the tape:

```dos
TAPECTL
```

`TAPECTL /READY` additionally sends `TEST UNIT READY`, which is also
non-destructive. An empty drive returns a failure, followed by the recorded
SCSI status and sense key. No writing or tape-positioning operation is exposed
by this utility yet.

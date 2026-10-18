# TAPECTL

This directory will contain the small DOS control and diagnostic utility used
before OpenTape exists.  It will open an ASPITAPE-compatible device, enable raw
mode, issue category `07h` IOCTL calls, and report the complete `mtget` block.

No executable is built yet because the driver currently advertises no working
I/O interface.
